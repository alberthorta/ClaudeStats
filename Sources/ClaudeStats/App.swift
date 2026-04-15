import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: StatsStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("ClaudeStats: did finish launching")

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
            Image(systemName: symbol)
            if let pace = store.effectiveFiveHourPace {
                Text(percentText(used: pace.used))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else if !store.effectiveSignedIn {
                Text("ClaudeStats")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            } else if let weekly = store.effectiveWeeklyPace {
                Text(percentText(used: weekly.used))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private func percentText(used: Double) -> String {
        let value = store.displayMode == .used ? used : (1 - used)
        return "\(Int((value * 100).rounded()))%"
    }

    private var symbol: String {
        guard let r = store.effectiveFiveHourPace?.ratio else {
            return store.effectiveSignedIn ? "hourglass" : "person.crop.circle.badge.questionmark"
        }
        switch r {
        case ..<0.95: return "tortoise.fill"
        case ..<1.10: return "equal.circle.fill"
        default:      return "hare.fill"
        }
    }
}
