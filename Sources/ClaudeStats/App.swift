import SwiftUI
import AppKit

enum PopoverToggle {
    static weak var popoverWindow: NSWindow?

    static func toggle() {
        let isOpen = popoverWindow?.isVisible == true

        // Always toggle by clicking the status bar button — this properly
        // handles both opening and closing, including the button highlight state.
        for window in NSApp.windows where window.className == "NSStatusBarWindow" {
            if let button = findButton(in: window.contentView) {
                if !isOpen {
                    let before = Set(NSApp.windows.map { ObjectIdentifier($0) })
                    button.sendAction(button.action, to: button.target)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        for w in NSApp.windows {
                            if !before.contains(ObjectIdentifier(w)), w.isVisible {
                                popoverWindow = w
                            }
                        }
                    }
                } else {
                    button.sendAction(button.action, to: button.target)
                    popoverWindow = nil
                }
                return
            }
        }
    }

    private static func findButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.action != nil {
            return button
        }
        for subview in view.subviews {
            if let button = findButton(in: subview) {
                return button
            }
        }
        return nil
    }

    static func registerHotkey(combo: KeyCombo) {
        HotkeyManager.shared.register(combo: combo) {
            DispatchQueue.main.async { toggle() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: StatsStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("ClaudeStats: did finish launching")

        // Restore saved hotkey
        if let combo = KeyCombo.load() {
            PopoverToggle.registerHotkey(combo: combo)
        }

        // Auto-check for updates a few seconds after launch so we don't
        // race with the initial UI / claude.ai fetch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.maybeAutoCheckForUpdates()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func maybeAutoCheckForUpdates() {
        guard let store, store.autoCheckUpdates else { return }
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
    @State private var store = StatsStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
                .onAppear { appDelegate.store = store }
        } label: {
            MenuBarIconLabel(store: store)
                .onAppear { appDelegate.store = store }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

struct MenuBarIconLabel: View {
    let store: StatsStore
    var body: some View {
        HStack(spacing: 4) {
            if !store.compactMenuBar {
                Image(systemName: symbol)
            }
            if store.displayMode != .glyphOnly {
                if let pace = store.effectiveFiveHourPace {
                    Text(labelText(pace: pace, resetText: store.windowResetText))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else if !store.effectiveSignedIn {
                    Text("ClaudeStats")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                } else if let weekly = store.effectiveWeeklyPace {
                    Text(labelText(pace: weekly, resetText: store.weeklyResetText ?? "—"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }

    private func labelText(pace: StatsStore.Pace, resetText: String) -> String {
        switch store.displayMode {
        case .used:
            return "\(Int((pace.used * 100).rounded()))%"
        case .remaining:
            return "\(Int(((1 - pace.used) * 100).rounded()))%"
        case .timeToReset:
            return resetText
        case .glyphOnly:
            return ""
        }
    }

    private var symbol: String {
        guard let r = store.effectiveFiveHourPace?.ratio else {
            return store.effectiveSignedIn ? "hourglass" : "person.crop.circle.badge.questionmark"
        }
        switch r {
        case ..<0.95: return "tortoise.fill"
        case ..<1.10: return "gauge.medium"
        default:      return "hare.fill"
        }
    }
}
