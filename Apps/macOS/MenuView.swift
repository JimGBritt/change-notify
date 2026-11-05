import ChangeNotifyCore
import SwiftUI

struct MenuView: View {
    let model: AppModel
    @State private var tokenInput = ""
    @AppStorage(AppModel.popupKey) private var popupEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.signedIn {
                signIn
            } else if model.events.isEmpty {
                Text("Nothing needs you right now.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.events) { EventRow(event: $0) }
                    }
                }
                .frame(maxHeight: 360)
            }

            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            Toggle("Pop-up window until dismissed", isOn: $popupEnabled)
                .font(.caption)
            if let checked = model.lastChecked {
                Text("Checked \(checked, style: .relative) ago")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if model.signedIn {
                    Button("Refresh") { Task { await model.refresh() } }
                }
                Menu("More") {
                    Button("Send test toast") { model.sendTestToast() }
                    if model.signedIn {
                        Button("Sign out") { model.signOut() }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign in to GitHub").font(.headline)
            Text("Paste a personal access token (classic) with the “notifications” scope. "
                 + "It is stored in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("ghp_…", text: $tokenInput)
            Button("Save token") { model.signIn(token: tokenInput); tokenInput = "" }
                .disabled(tokenInput.isEmpty)
            Link("Create a token", destination: URL(
                string: "https://github.com/settings/tokens/new?scopes=notifications&description=ChangeNotify")!)
                .font(.caption)
        }
    }
}

struct EventRow: View {
    let event: ChangeEvent

    var body: some View {
        Button {
            NSWorkspace.shared.open(event.url)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).fontWeight(.medium).lineLimit(2)
                Text("\(event.project) · \(event.reason.label)")
                    .font(.caption).foregroundStyle(.secondary)
                if let step = event.nextStep {
                    Label(step, systemImage: "arrow.right.circle")
                        .font(.caption).foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
