import ChangeNotifyCore
import Observation
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var events: [ChangeEvent] = []
    private(set) var lastChecked: Date?
    private(set) var lastError: String?
    private(set) var signedIn: Bool

    private static let tokenAccount = "github-token"
    private static let seenKey = "seenEventIDs"
    private static let primedKey = "trackerPrimed"
    static let popupKey = "popupEnabled"
    private let pollInterval: Duration = .seconds(120)

    private let tracker: EventTracker
    private let notificationDelegate = NotificationDelegate()
    private var loop: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.popupKey: true])
        let seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        tracker = EventTracker(seen: seen, primed: defaults.bool(forKey: Self.primedKey))
        signedIn = KeychainStore.load(account: Self.tokenAccount) != nil
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    func start() {
        guard loop == nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(120))
            }
        }
    }

    func signIn(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(trimmed, account: Self.tokenAccount)
        signedIn = true
        Task { await refresh() }
    }

    func signOut() {
        KeychainStore.delete(account: Self.tokenAccount)
        signedIn = false
        events = []
    }

    func refresh() async {
        guard let token = KeychainStore.load(account: Self.tokenAccount) else { return }
        do {
            let fetched = try await GitHubSource(token: token).fetchEvents()
            events = fetched
            lastError = nil
            lastChecked = .now
            let fresh = await tracker.ingest(fetched)
            fresh.forEach(notify)
            let snap = await tracker.snapshot()
            UserDefaults.standard.set(Array(snap.seen), forKey: Self.seenKey)
            UserDefaults.standard.set(snap.primed, forKey: Self.primedKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Fires a sample toast so notification permission and click-through can be verified without GitHub.
    func sendTestToast() {
        notify(ChangeEvent(
            id: "test:\(UUID().uuidString)",
            source: "test",
            project: "JimGBritt/claude-usage-widget",
            title: "Test: Add usage widget (#6)",
            url: URL(string: "https://github.com/JimGBritt/claude-usage-widget/pull/6")!,
            reason: .mention,
            updatedAt: .now,
            nextStep: "Ready to merge"))
    }

    private func notify(_ event: ChangeEvent) {
        let content = UNMutableNotificationContent()
        content.title = "\(event.reason.label) · \(event.project)"
        content.subtitle = event.title
        content.body = event.nextStep ?? ""
        content.sound = .default
        // Breaks through Focus once the Time Sensitive capability is enabled; harmless until then.
        content.interruptionLevel = .timeSensitive
        #if os(macOS)
        if UserDefaults.standard.bool(forKey: Self.popupKey) {
            AlertPanelController.shared.show(event)
        }
        #endif
        content.userInfo = ["url": event.url.absoluteString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
    }
}

/// Shows toasts while the app is "foreground" (menu bar apps always are) and opens the link on click.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: s) {
            await MainActor.run { openExternally(url) }
        }
    }
}

/// Opens a link in the default browser on either platform.
@MainActor
func openExternally(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}
