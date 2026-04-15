import SwiftUI

struct SettingsView: View {
    @Bindable var store: StatsStore
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var updateStatus: UpdateStatus = .idle
    @State private var installing: Bool = false
    @State private var installError: String?
    @State private var showPasteField: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                claudeAccountSection
                generalSection
                if Self.debugEnabled { debugSection }
                updatesSection
            }
            .padding(24)
            .frame(width: 460, alignment: .leading)
        }
        .frame(width: 460, height: 600)
    }

    // MARK: - Sections

    private var claudeAccountSection: some View {
        section("Claude.ai account") {
            HStack(spacing: 8) {
                Image(systemName: store.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                    .foregroundStyle(store.isSignedIn ? .green : .secondary)
                Text(store.isSignedIn
                     ? "Signed in — using server-side usage"
                     : "Not signed in — pace data unavailable")
                    .font(.callout)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(store.isSignedIn ? "Re-authenticate" : "Sign in to Claude.ai") {
                    SignInWindowController.present {
                        store.isSignedIn = ClaudeAIClient.hasSession
                        Task { await store.refreshRemote() }
                    }
                }
                if store.isSignedIn {
                    Button("Sign out") { store.signOut() }
                }
                Spacer(minLength: 0)
            }

            if let err = store.remoteError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Opens a login window. Your session cookie is stored locally.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\u{201C}Continue with Google\u{201D} isn't supported. Google blocks sign-in inside embedded web views — use email login or paste the sessionKey manually below.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showPasteField.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showPasteField ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("Paste sessionKey manually")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)

                if showPasteField {
                    Text("1. Open claude.ai in Safari/Chrome (logged in)\n2. DevTools \u{2192} Application \u{2192} Cookies \u{2192} claude.ai\n3. Copy the value of the sessionKey cookie and paste below")
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
            }
        }
    }

    private var generalSection: some View {
        section("General") {
            Toggle("Show remaining percentage in menu bar", isOn: Binding(
                get: { store.displayMode == .remaining },
                set: { store.displayMode = $0 ? .remaining : .used }
            ))
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    let ok = LaunchAtLogin.setEnabled(newValue)
                    if !ok { launchAtLogin = LaunchAtLogin.isEnabled }
                }
        }
    }

    private var debugSection: some View {
        section("Debug (temporary)") {
            Picker("Simulate state", selection: $store.simulation) {
                ForEach(StatsStore.SimulationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Text("Forces the UI into a placeholder state without actually signing out or waiting for the window to drain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var updatesSection: some View {
        section("Updates") {
            HStack {
                Text("Version \(UpdateChecker.currentVersion)")
                    .font(.callout)
                Spacer()
                Button(updateStatus == .checking ? "Checking\u{2026}" : "Check for updates") {
                    Task {
                        updateStatus = .checking
                        updateStatus = await UpdateChecker.check()
                    }
                }
                .disabled(updateStatus == .checking)
            }
            Toggle("Check for updates automatically at startup", isOn: $store.autoCheckUpdates)
            updateStatusView
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            Text("Contacting GitHub\u{2026}")
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
                    Button(installing ? "Installing\u{2026}" : "Install & restart") {
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
