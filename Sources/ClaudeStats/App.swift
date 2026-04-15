import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("ClaudeStats: did finish launching")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct ClaudeStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = StatsStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarIconLabel(store: store)
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
