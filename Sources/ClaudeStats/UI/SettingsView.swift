import SwiftUI

struct SettingsView: View {
    @Bindable var store: StatsStore
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Claude.ai account") {
                HStack {
                    Image(systemName: store.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                        .foregroundStyle(store.isSignedIn ? .green : .secondary)
                    Text(store.isSignedIn ? "Signed in — using server-side usage" : "Not signed in — falls back to local estimates")
                        .font(.callout)
                    Spacer()
                }
                HStack {
                    Button(store.isSignedIn ? "Re-authenticate" : "Sign in to Claude.ai") {
                        SignInWindowController.present {
                            store.isSignedIn = ClaudeAIClient.hasSession
                            Task { await store.refreshRemote() }
                        }
                    }
                    if store.isSignedIn {
                        Button("Sign out") { store.signOut() }
                    }
                }
                if let err = store.remoteError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Opens a login window. Your session cookie is stored in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label {
                    Text("“Continue with Google” isn't supported — Google blocks sign-in inside embedded web views. Use email login or paste the sessionKey manually.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup("Paste sessionKey manually") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Open claude.ai in Safari/Chrome (logged in)\n2. DevTools → Application → Cookies → claude.ai\n3. Copy the value of the `sessionKey` cookie and paste below")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SessionPasteField { key in
                            Task { @MainActor in
                                ClaudeAIClient.storeSessionKey(key)
                                do {
                                    let orgId = try await ClaudeAIClient.fetchOrgId()
                                    ClaudeAIClient.storeOrgId(orgId)
                                    store.isSignedIn = true
                                    await store.refreshRemote()
                                } catch {
                                    store.remoteError = error.localizedDescription
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        let ok = LaunchAtLogin.setEnabled(newValue)
                        if !ok { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    struct SessionPasteField: View {
        let onSubmit: (String) -> Void
        @State private var text: String = ""
        var body: some View {
            HStack {
                SecureField("sessionKey value", text: $text)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                    text = ""
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

}
