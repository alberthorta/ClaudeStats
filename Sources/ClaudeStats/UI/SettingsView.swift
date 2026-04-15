import SwiftUI

struct SettingsView: View {
    @Bindable var store: StatsStore
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var updateStatus: UpdateStatus = .idle
    @State private var installing: Bool = false
    @State private var installError: String?

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

            if Self.debugEnabled {
                Section("Debug (temporary)") {
                    Picker("Simulate state", selection: $store.simulation) {
                        ForEach(StatsStore.SimulationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Text("Forces the UI into a placeholder state without actually signing out or waiting for the window to drain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                HStack {
                    Text("Version \(UpdateChecker.currentVersion)")
                        .font(.callout)
                    Spacer()
                    Button(updateStatus == .checking ? "Checking…" : "Check for updates") {
                        Task {
                            updateStatus = .checking
                            updateStatus = await UpdateChecker.check()
                        }
                    }
                    .disabled(updateStatus == .checking)
                }
                updateStatusView
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            Text("Contacting GitHub…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate(_, let latest):
            Label("You're on the latest version (\(latest))", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .updateAvailable(let release):
            VStack(alignment: .leading, spacing: 6) {
                Label("Update available: \(release.normalizedVersion)", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                HStack(spacing: 10) {
                    Button(installing ? "Installing…" : "Install & restart") {
                        Task { await installUpdate(release: release) }
                    }
                    .disabled(installing || release.downloadURL == nil)
                    Link("Release notes", destination: release.htmlURL)
                        .font(.caption)
                }
                if let installError {
                    Text(installError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    static var debugEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--debug") { return true }
        if ProcessInfo.processInfo.environment["CLAUDESTATS_DEBUG"] == "1" { return true }
        return false
    }

    @MainActor
    private func installUpdate(release: LatestRelease) async {
        installing = true
        installError = nil
        do {
            try await UpdateInstaller.installAndRestart(release: release)
            // App will quit before this point on success.
        } catch {
            installError = error.localizedDescription
            installing = false
        }
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
