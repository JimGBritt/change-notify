import BackgroundTasks
import SwiftUI

private let refreshTaskID = "com.jimbritt.changenotify.refresh"

/// BGTask isn't Sendable; the system guarantees we only touch it to complete it.
private final class TaskBox: @unchecked Sendable {
    let task: BGAppRefreshTask
    init(_ task: BGAppRefreshTask) { self.task = task }
}

@main
struct ChangeNotifyiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            let box = TaskBox(task)
            let work = Task { @MainActor in
                scheduleRefresh()
                await AppModel.shared.refresh()
                box.task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        AppModel.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: AppModel.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await AppModel.shared.refresh() }
            case .background: scheduleRefresh()
            default: break
            }
        }
    }
}

/// iOS decides when (and whether) this runs; expect roughly 15+ minutes at best.
func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
}
