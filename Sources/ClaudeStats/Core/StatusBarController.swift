import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    let statusItem: NSStatusItem
    let popover: NSPopover
    private let store: StatsStore
    private var observationTask: Task<Void, Never>?

    init(store: StatsStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateButton(store: store)
        startObserving(store: store)
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(store: store)
        } else {
            togglePopover()
        }
    }

    private func showContextMenu(store: StatsStore) {
        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: "Launch at login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About ClaudeStats", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ClaudeStats", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear the menu so left-click goes back to the popover
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !LaunchAtLogin.isEnabled
        _ = LaunchAtLogin.setEnabled(newValue)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.present(store: store)
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        AboutWindowController.present()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring the popover window to front
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateButton(store: StatsStore) {
        guard let button = statusItem.button else { return }

        let symbolName = currentSymbol(store: store)
        let titleText = currentTitle(store: store)

        if !store.compactMenuBar {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "pace indicator"),
               let configured = base.withSymbolConfiguration(config) {
                configured.isTemplate = true
                button.image = configured
            }
            button.imagePosition = titleText.isEmpty ? .imageOnly : .imageLeading
        } else {
            button.image = nil
        }

        // Use attributed string so the text also gets native template rendering
        if !titleText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            ]
            button.attributedTitle = NSAttributedString(string: titleText, attributes: attrs)
        } else {
            button.title = ""
        }
    }

    private func currentSymbol(store: StatsStore) -> String {
        guard let r = store.effectiveFiveHourPace?.ratio else {
            return store.effectiveSignedIn ? "hourglass" : "person.crop.circle.badge.questionmark"
        }
        switch r {
        case ..<0.95: return store.glyphUnderPace
        case ..<1.10: return store.glyphOnPace
        default:      return store.glyphOverPace
        }
    }

    private func currentTitle(store: StatsStore) -> String {
        guard store.displayMode != .glyphOnly else { return "" }

        if let pace = store.effectiveFiveHourPace {
            return labelText(store: store, pace: pace, resetText: store.windowResetText)
        } else if !store.effectiveSignedIn {
            return "ClaudeStats"
        } else if let weekly = store.effectiveWeeklyPace {
            return labelText(store: store, pace: weekly, resetText: store.weeklyResetText ?? "—")
        }
        return ""
    }

    private func labelText(store: StatsStore, pace: StatsStore.Pace, resetText: String) -> String {
        switch store.displayMode {
        case .used:      return "\(Int((pace.used * 100).rounded()))%"
        case .remaining: return "\(Int(((1 - pace.used) * 100).rounded()))%"
        case .timeToReset: return resetText
        case .glyphOnly: return ""
        }
    }

    private func startObserving(store: StatsStore) {
        // Use a 1-second timer to sync store state → button.
        // This is simple, reliable, and matches the countdown timer cadence.
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.updateButton(store: store)
            }
        }
    }
}
