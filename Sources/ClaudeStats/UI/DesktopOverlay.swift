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
        ZStack {
            // Watermark glyph — 80% of height, centered, behind all content
            GeometryReader { geo in
                Image(systemName: watermarkSymbol)
                    .font(.system(size: geo.size.height * 0.9))
                    .foregroundStyle(.black.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

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
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                if store.showHistoryAtLaunch && !store.cachedSummaries.isEmpty {
                    overlayHeatmap
                }
                Text(store.secondsUntilRefresh > 0 ? "Refresh in \(store.secondsUntilRefresh)s" : "Refreshing…")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: 310)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var overlayHeatmap: some View {
        let cal = Calendar.current
        let data = Array(store.cachedSummaries.suffix(56))
        let grid = buildHeatmapGrid(data: data, cal: cal)
        let spacing: CGFloat = 2
        // 310 - 2*14 padding = 282 inner width
        let columns = CGFloat(max(grid.count, 1))
        let cellSize = floor((282 - spacing * (columns - 1)) / columns)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Activity")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(store.cachedStreak)d streak")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<grid.count, id: \.self) { col in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            if let summary = grid[col][row] {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(overlayHeatColor(summary.intensity))
                                    .frame(width: cellSize, height: cellSize / 4)
                            } else {
                                Color.clear.frame(width: cellSize, height: cellSize / 4)
                            }
                        }
                    }
                }
            }
        }
    }

    private var watermarkSymbol: String {
        guard let r = store.effectiveFiveHourPace?.ratio else {
            return store.effectiveSignedIn ? "hourglass" : "person.crop.circle.badge.questionmark"
        }
        switch r {
        case ..<0.95: return "tortoise.fill"
        case ..<1.10: return "gauge.medium"
        default:      return "hare.fill"
        }
    }

    private func buildHeatmapGrid(data: [DailySummary], cal: Calendar) -> [[DailySummary?]] {
        let lookup = Dictionary(uniqueKeysWithValues: data.map { (cal.startOfDay(for: $0.date), $0) })
        let today = cal.startOfDay(for: Date())
        let todayWeekday = cal.component(.weekday, from: today)
        let firstWeekday = cal.firstWeekday
        let rowOffset = (todayWeekday - firstWeekday + 7) % 7

        let weeksBack = (data.count + rowOffset) / 7
        let startDate = cal.date(byAdding: .day, value: -(weeksBack * 7 + rowOffset), to: today)!

        var grid: [[DailySummary?]] = []
        var current = startDate
        while current <= today {
            var week: [DailySummary?] = []
            for _ in 0..<7 {
                week.append(current <= today ? lookup[current] : nil)
                current = cal.date(byAdding: .day, value: 1, to: current)!
            }
            grid.append(week)
        }
        return grid
    }

    private func overlayHeatColor(_ intensity: Double) -> Color {
        switch intensity {
        case 0:       return .white.opacity(0.06)
        case ..<0.15: return .green.opacity(0.3)
        case ..<0.4:  return .green.opacity(0.45)
        case ..<0.7:  return .green.opacity(0.65)
        default:      return .green.opacity(0.9)
        }
    }

    private func overlaySection(title: String, pace: StatsStore.Pace, resetText: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(pace.label)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(paceColor(pace))
            }
            overlayPaceBar(pace: pace)
                .frame(height: 10)
            HStack(spacing: 8) {
                Text("Used \(pctText(pace.used))")
                    .foregroundStyle(paceColor(pace))
                Text("Resets in \(resetText)")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(.caption, design: .rounded))
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
