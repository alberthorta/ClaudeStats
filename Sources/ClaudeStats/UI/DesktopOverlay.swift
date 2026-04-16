import SwiftUI
import AppKit

// MARK: - Overlay Manager

final class DesktopOverlayManager {
    static let shared = DesktopOverlayManager()
    private var windows: [UInt32: NSWindow] = [:]   // screenNumber → window
    private var screenMap: [UInt32: NSScreen] = [:]  // screenNumber → screen
    private var frameObservations: [UInt32: NSKeyValueObservation] = [:]
    private weak var currentStore: StatsStore?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        guard let store = currentStore else { return }
        DispatchQueue.main.async { [self] in
            self.update(store: store)
        }
    }

    func update(store: StatsStore) {
        currentStore = store
        guard store.showDesktopOverlay else {
            removeAll()
            return
        }

        let screens = targetScreens(for: store.overlayScreen)
        let activeNumbers = Set(screens.map { $0.screenNumber })

        // Remove windows for screens no longer targeted
        for num in windows.keys where !activeNumbers.contains(num) {
            windows[num]?.orderOut(nil)
            windows.removeValue(forKey: num)
            screenMap.removeValue(forKey: num)
            frameObservations.removeValue(forKey: num)
        }

        // Create or update windows for each target screen
        for screen in screens {
            let num = screen.screenNumber
            screenMap[num] = screen
            if let win = windows[num] {
                repositionWindow(win, on: screen, position: store.overlayPosition)
            } else {
                let win = makeOverlayWindow(for: screen, store: store)
                windows[num] = win
                // Observe content view frame changes to reposition when SwiftUI resizes
                frameObservations[num] = win.observe(\.frame, options: [.new]) { [weak self] win, _ in
                    guard let self, let store = self.currentStore,
                          let screen = self.screenMap[num] else { return }
                    self.repositionWindow(win, on: screen, position: store.overlayPosition)
                }
                win.orderFront(nil)
            }
        }
    }

    func removeAll() {
        for (_, win) in windows { win.orderOut(nil) }
        windows.removeAll()
        screenMap.removeAll()
        frameObservations.removeAll()
    }

    private func targetScreens(for choice: OverlayScreen) -> [NSScreen] {
        let all = NSScreen.screens
        switch choice {
        case .all:
            return all
        case .screen(let num):
            return all.filter { $0.screenNumber == num }
        }
    }

    private func makeOverlayWindow(for screen: NSScreen, store: StatsStore) -> NSWindow {
        let view = DesktopOverlayView(store: store)
        let hosting = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.borderless]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Just above the desktop icons
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        win.isReleasedWhenClosed = false

        repositionWindow(win, on: screen, position: store.overlayPosition)
        return win
    }

    private func repositionWindow(_ window: NSWindow, on screen: NSScreen, position: OverlayPosition) {
        let margin: CGFloat = 24
        let frame = screen.visibleFrame
        let winSize = window.frame.size

        let x: CGFloat
        let y: CGFloat

        switch position {
        case .topLeft:
            x = frame.minX + margin
            y = frame.maxY - winSize.height - margin
        case .topRight:
            x = frame.maxX - winSize.width - margin
            y = frame.maxY - winSize.height - margin
        case .bottomLeft:
            x = frame.minX + margin
            y = frame.minY + margin
        case .bottomRight:
            x = frame.maxX - winSize.width - margin
            y = frame.minY + margin
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Overlay position

enum OverlayPosition: String, CaseIterable, Identifiable {
    case topLeft = "Top-left"
    case topRight = "Top-right"
    case bottomLeft = "Bottom-left"
    case bottomRight = "Bottom-right"
    var id: String { rawValue }
}

// MARK: - Screen identifier

enum OverlayScreen: Equatable, Hashable {
    case all
    case screen(UInt32)

    var rawValue: String {
        switch self {
        case .all: return "all"
        case .screen(let n): return "screen:\(n)"
        }
    }

    init(rawValue: String) {
        if rawValue.hasPrefix("screen:"), let n = UInt32(rawValue.dropFirst(7)) {
            self = .screen(n)
        } else {
            self = .all
        }
    }
}

extension NSScreen {
    var screenNumber: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var displayName: String {
        localizedName
    }
}

// MARK: - Overlay View

struct DesktopOverlayView: View {
    @Bindable var store: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pace = store.effectiveFiveHourPace {
                overlaySection(title: "5-hour window", pace: pace,
                               resetText: store.windowResetText)
            }
            if let pace = store.effectiveWeeklyPace {
                overlaySection(title: "Weekly", pace: pace,
                               resetText: store.weeklyResetText ?? "—")
            }
            if store.effectiveFiveHourPace == nil && store.effectiveWeeklyPace == nil {
                Text(store.effectiveSignedIn ? "Loading…" : "Not signed in")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }

    private func overlaySection(title: String, pace: StatsStore.Pace, resetText: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(pace.label)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(paceColor(pace))
            }
            overlayPaceBar(pace: pace)
                .frame(height: 8)
            HStack(spacing: 8) {
                Text("Used \(pctText(pace.used))")
                    .foregroundStyle(paceColor(pace))
                Text("Resets in \(resetText)")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(.caption2, design: .rounded))
            .monospacedDigit()
        }
    }

    private func overlayPaceBar(pace: StatsStore.Pace) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(paceColor(pace).gradient)
                    .frame(width: geo.size.width * CGFloat(min(1, pace.used)))
                // Elapsed marker
                ZStack {
                    Capsule().fill(Color.black.opacity(0.5)).frame(width: 4)
                    Capsule().fill(Color.white).frame(width: 2)
                }
                .frame(height: 14)
                .offset(x: geo.size.width * CGFloat(min(1, pace.elapsed)) - 2)
            }
        }
    }

    private func paceColor(_ pace: StatsStore.Pace) -> Color {
        switch pace.ratio {
        case ..<0.75:  return .green
        case ..<0.95:  return .mint
        case ..<1.10:  return .yellow
        case ..<1.35:  return .orange
        default:       return .red
        }
    }

    private func pctText(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }
}
