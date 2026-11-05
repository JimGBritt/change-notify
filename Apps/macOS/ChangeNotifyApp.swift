import SwiftUI

@main
struct ChangeNotifyApp: App {
    init() {
        // MenuBarExtra content is lazy, so start polling at launch.
        AppModel.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: AppModel.shared)
        } label: {
            Image(systemName: AppModel.shared.events.isEmpty ? "bell" : "bell.badge")
        }
        .menuBarExtraStyle(.window)
    }
}
