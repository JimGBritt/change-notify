import ChangeNotifyCore
import SwiftUI

struct ContentView: View {
    let model: AppModel
    @State private var tokenInput = ""

    var body: some View {
        NavigationStack {
            Group {
                if !model.signedIn {
                    signIn
                } else {
                    list
                }
            }
            .navigationTitle("ChangeNotify")
            .toolbar {
                if model.signedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Send test notification", systemImage: "bell.badge") {
                                model.sendTestToast()
                            }
                            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right",
                                   role: .destructive) { model.signOut() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            if model.events.isEmpty {
                ContentUnavailableView("Nothing needs you right now",
                                       systemImage: "checkmark.circle",
                                       description: Text("Mentions, review requests and assignments will show up here."))
                    .listRowBackground(Color.clear)
            }
            ForEach(model.events) { event in
                Link(destination: event.url) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.headline).foregroundStyle(.primary)
                        Text("\(event.project) · \(event.reason.label)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let step = event.nextStep {
                            Label(step, systemImage: "arrow.right.circle")
                                .font(.subheadline).foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let checked = model.lastChecked {
                Text("Checked \(checked, style: .relative) ago")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .refreshable { await model.refresh() }
    }

    private var signIn: some View {
        Form {
            Section {
                Text("Paste a personal access token (classic) with the “notifications” scope. "
                     + "It is stored in your Keychain.")
                    .font(.footnote).foregroundStyle(.secondary)
                SecureField("ghp_…", text: $tokenInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save token") { model.signIn(token: tokenInput); tokenInput = "" }
                    .disabled(tokenInput.isEmpty)
                Link("Create a token", destination: URL(
                    string: "https://github.com/settings/tokens/new?scopes=notifications&description=ChangeNotify")!)
            } header: {
                Text("Sign in to GitHub")
            }
        }
    }
}
