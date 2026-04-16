import SwiftUI
import AppKit

enum SettingsWindowController {
    private static var window: NSWindow?

    @MainActor
    static func present(store: StatsStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(store: store)
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "ClaudeStats Settings"
        win.setContentSize(NSSize(width: 460, height: 600))
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

struct SettingsView: View {
    @Bindable var store: StatsStore
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var updateStatus: UpdateStatus = .idle
    @State private var installing: Bool = false
    @State private var installError: String?
    @State private var showPasteField: Bool = false
    @State private var googleSignInStatus: String?
    @State private var currentShortcut: KeyCombo? = KeyCombo.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                claudeAccountSection
                generalSection
                desktopOverlaySection
                if Self.debugEnabled { debugSection }
                updatesSection
            }
            .padding(24)
            .frame(width: 460, alignment: .leading)
        }
        .frame(width: 460, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = LaunchAtLogin.isEnabled
        }
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
                Button(store.isSignedIn ? "Re-authenticate (email)" : "Sign in with email") {
                    SignInWindowController.present {
                        store.isSignedIn = ClaudeAIClient.hasSession
                        Task { await store.refreshRemote() }
                    }
                }
                Button("Sign in with Google") {
                    googleSignInStatus = nil
                    GoogleSignInHelper.shared.start { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let key):
                                ClaudeAIClient.storeSessionKey(key)
                                googleSignInStatus = "Captured — fetching organization…"
                                do {
                                    let orgId = try await ClaudeAIClient.fetchOrgId()
                                    ClaudeAIClient.storeOrgId(orgId)
                                    store.isSignedIn = true
                                    await store.refreshRemote()
                                    googleSignInStatus = nil
                                } catch {
                                    store.remoteError = error.localizedDescription
                                    googleSignInStatus = nil
                                }
                            case .failure(let error):
                                googleSignInStatus = error.localizedDescription
                                showPasteField = true
                            }
                        }
                    }
                }
                if store.isSignedIn {
                    Button("Sign out") { store.signOut() }
                }
                Spacer(minLength: 0)
            }

            if let status = googleSignInStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let err = store.remoteError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Email opens an embedded window. Google opens your default browser for OAuth compatibility.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
            Picker("Menu bar display", selection: $store.displayMode) {
                ForEach(StatsStore.DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Toggle("Compact menu bar (text only, no icon)", isOn: $store.compactMenuBar)
                .disabled(store.displayMode == .glyphOnly)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pace icons")
                    .font(.callout.weight(.medium))
                HStack(spacing: 12) {
                    glyphPicker("Under", selection: $store.glyphUnderPace)
                    glyphPicker("On", selection: $store.glyphOnPace)
                    glyphPicker("Over", selection: $store.glyphOverPace)
                }
            }
            Toggle("Show activity heatmap in popover and desktop overlay", isOn: $store.showHistory)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    let ok = LaunchAtLogin.setEnabled(newValue)
                    if !ok { launchAtLogin = LaunchAtLogin.isEnabled }
                }
            HStack {
                Text("Toggle popover shortcut")
                Spacer()
                ShortcutRecorderView(combo: $currentShortcut)
                    .frame(width: 140)
                if currentShortcut != nil {
                    Button("Clear") {
                        currentShortcut = nil
                        KeyCombo.clear()
                        HotkeyManager.shared.unregister()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var desktopOverlaySection: some View {
        section("Desktop overlay") {
            Toggle("Show usage on desktop", isOn: $store.showDesktopOverlay)

            if store.showDesktopOverlay {
                Picker("Display on", selection: $store.overlayScreen) {
                    Text("All monitors").tag(OverlayScreen.all)
                    ForEach(NSScreen.screens, id: \.screenNumber) { screen in
                        Text(screen.displayName).tag(OverlayScreen.screen(screen.screenNumber))
                    }
                }
                .pickerStyle(.menu)
                Picker("Position", selection: $store.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { pos in
                        Text(pos.rawValue).tag(pos)
                    }
                }
                .pickerStyle(.menu)
                Text("A translucent widget with your pace data is pinned to the top-left corner of the desktop. It's non-interactive and stays behind all windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func glyphPicker(_ label: String, selection: Binding<String>) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(StatsStore.availableGlyphs, id: \.0) { (name, title) in
                    Label(title, systemImage: name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity)
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

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var combo: KeyCombo?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.combo = combo
        view.onRecord = { newCombo in
            combo = newCombo
            newCombo.save()
            PopoverToggle.registerHotkey(combo: newCombo)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.combo = combo
        nsView.needsDisplay = true
    }
}

final class ShortcutRecorderNSView: NSView {
    var combo: KeyCombo?
    var onRecord: ((KeyCombo) -> Void)?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = recording ? .controlAccentColor.withAlphaComponent(0.15) : .controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()

        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).stroke()

        let text: String
        if recording {
            text = "Press shortcut\u{2026}"
        } else {
            text = combo?.displayString ?? "Click to record"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2,
                            y: (bounds.height - size.height) / 2)
        str.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        recording = true
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require at least one modifier (Cmd, Option, Control, or Shift)
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            return
        }

        // Escape cancels recording
        if event.keyCode == 53 {
            recording = false
            needsDisplay = true
            return
        }

        let newCombo = KeyCombo.from(event: event)
        combo = newCombo
        recording = false
        needsDisplay = true
        onRecord?(newCombo)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 140, height: 24)
    }
}

