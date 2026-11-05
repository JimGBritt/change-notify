import AppKit
import ChangeNotifyCore
import Observation
import SwiftUI

/// A floating pop-up that stays on screen (on every Space) until the user acts on each event.
/// Unlike a system notification banner, the app fully controls this window.
@MainActor
@Observable
final class AlertPanelController {
    static let shared = AlertPanelController()

    private(set) var items: [ChangeEvent] = []
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hosting: NSHostingView<AlertStackView>?

    func show(_ event: ChangeEvent) {
        guard !items.contains(where: { $0.id == event.id }) else { return }
        items.append(event)
        presentPanel()
    }

    func open(_ event: ChangeEvent) {
        NSWorkspace.shared.open(event.url)
        dismiss(event)
    }

    func dismiss(_ event: ChangeEvent) {
        items.removeAll { $0.id == event.id }
        if items.isEmpty { panel?.orderOut(nil) } else { resizeAndPosition() }
    }

    func dismissAll() {
        items.removeAll()
        panel?.orderOut(nil)
    }

    private func presentPanel() {
        if panel == nil {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: AlertStackView(controller: self))
            p.contentView = host
            panel = p
            hosting = host
        }
        resizeAndPosition()
        panel?.orderFrontRegardless()
    }

    private func resizeAndPosition() {
        guard let panel, let hosting else { return }
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let origin = NSPoint(x: area.maxX - size.width - 16, y: area.maxY - size.height - 16)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

struct AlertStackView: View {
    let controller: AlertPanelController

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if controller.items.count > 1 {
                Button("Dismiss all (\(controller.items.count))") { controller.dismissAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(controller.items) { event in
                AlertCard(event: event, controller: controller)
            }
        }
        .padding(8)
        .frame(width: 356)
    }
}

struct AlertCard: View {
    let event: ChangeEvent
    let controller: AlertPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(event.reason.label) · \(event.project)")
                .font(.caption).foregroundStyle(.secondary)
            Text(event.title).font(.headline).lineLimit(3)
            if let step = event.nextStep {
                Label(step, systemImage: "arrow.right.circle")
                    .font(.subheadline).foregroundStyle(.tint)
            }
            HStack {
                Spacer()
                Button("Dismiss") { controller.dismiss(event) }
                Button("Open") { controller.open(event) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}
