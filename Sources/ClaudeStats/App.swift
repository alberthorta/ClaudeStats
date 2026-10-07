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

// Plain AppKit entry point. A SwiftUI `App` needs at least one scene, and the empty `Settings` scene
// it used to declare was opened at launch on macOS 27 as a blank "ClaudeStats Settings" window.
@main
enum ClaudeStatsMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = makeMainMenu()
        app.run()
    }

    // Never shown (LSUIElement), but its key equivalents are what make ⌘C / ⌘V / ⌘A work in
    // text fields and in the sign-in web view.
    @MainActor
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ClaudeStats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)

        return main
    }
}
