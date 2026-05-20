import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(HomeDashAPI.serverURLKey) private var serverURL: String = HomeDashAPI.defaultBaseURL
    @AppStorage("biometricLock") private var biometricLock = false
    @State private var draftURL: String = ""
    @State private var saved = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL", text: $draftURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Text("Use the LAN address while you're home, or a Tailscale URL when you're away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        save()
                    } label: {
                        if saved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(draftURL == serverURL || URL(string: draftURL) == nil)
                }

                Section("Security") {
                    Toggle(isOn: $biometricLock) {
                        Label("Require Face ID to open", systemImage: "faceid")
                    }
                    Text("HomeDash will lock when you leave the app and ask for Face ID (or your passcode) to reopen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Account") {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "HomeDash")
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .onAppear { draftURL = serverURL }
            .confirmationDialog("Sign out of HomeDash?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await state.logout() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        serverURL = draftURL
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            saved = false
        }
        // URL changed → cookies belong to old host; sign out so they re-auth.
        Task { await state.logout() }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
