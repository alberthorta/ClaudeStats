import SwiftUI
import AppKit

@MainActor
enum PopoverToggle {
    static weak var controller: StatusBarController?

    static func toggle() {
        controller?.togglePopover()
    }

    nonisolated static func registerHotkey(combo: KeyCombo) {
        HotkeyManager.shared.register(combo: combo) {
            DispatchQueue.main.async { @MainActor in
                toggle()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: StatsStore!
    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = StatsStore()
        statusBarController = StatusBarController(store: store)
        PopoverToggle.controller = statusBarController

        // Restore saved hotkey
        if let combo = KeyCombo.load() {
            PopoverToggle.registerHotkey(combo: combo)
        }

        // Auto-check for updates a few seconds after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.maybeAutoCheckForUpdates()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func maybeAutoCheckForUpdates() {
        guard store.autoCheckUpdates else { return }
        Task {
            let status = await UpdateChecker.check()
            if case let .updateAvailable(release) = status {
                await MainActor.run { promptForUpdate(release: release) }
            }
        }
    }

    @MainActor
    private func promptForUpdate(release: LatestRelease) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ClaudeStats \(release.normalizedVersion) is available"
        alert.informativeText = "You're on \(UpdateChecker.currentVersion). Update now? The app will restart automatically."
        alert.addButton(withTitle: "Update now")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do { try await UpdateInstaller.installAndRestart(release: release) }
                catch {
                    let err = NSAlert()
                    err.messageText = "Update failed"
                    err.informativeText = error.localizedDescription
                    err.alertStyle = .warning
                    _ = err.runModal()
                }
            }
        }
    }
}

@main
struct ClaudeStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible scenes — the status item and popover are managed by
        // StatusBarController. Settings opens as a standalone NSWindow.
        // A WindowGroup is required to satisfy the Scene protocol.
        Settings {
            EmptyView()
        }
    }
}
