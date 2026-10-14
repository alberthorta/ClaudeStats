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
                if let hosting = win.contentViewController as? NSHostingController<DesktopOverlayView> {
                    let fittingSize = hosting.view.fittingSize
                    win.setContentSize(fittingSize)
                }
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

    private static let width: CGFloat = 300
    private static let padding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let rings = store.weeklyRings
            if store.effectiveFiveHourPace != nil || !rings.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    if let pace = store.effectiveFiveHourPace {
                        fiveHourColumn(pace)
                    }
                    if !rings.isEmpty {
                        weeklyColumn(rings)
                    }
                }
                // Both columns take the taller one's height, so the "Resets in" lines share a baseline.
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(store.effectiveSignedIn ? "Loading…" : "Not signed in",
                      systemImage: store.effectiveSignedIn ? "hourglass" : "person.crop.circle.badge.questionmark")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            let codexWindows = store.codexWindows
            if !codexWindows.isEmpty {
                codexSection(codexWindows)
            }
            if store.showHistory && !store.cachedSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Activity")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        if store.cachedStreak > 0 {
                            Label("\(store.cachedStreak)d streak", systemImage: "flame.fill")
                                .font(.system(size: 10.5, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    ActivityHeatmap(data: Array(store.cachedSummaries.suffix(70)), weeks: 10,
                                    width: Self.width - Self.padding * 2,
                                    showLabels: false, cellAspect: 0.35, onDark: true, spacing: 2)
                }
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .background(alignment: .bottomTrailing) {
            Image(systemName: watermarkSymbol)
                .font(.system(size: 120, weight: .regular))
                .foregroundStyle(.white.opacity(0.035))
                .offset(x: 18, y: 18)
                .contentTransition(.symbolEffect(.replace))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .darkGlass(cornerRadius: 18, tint: Color(rgba: store.overlayTint), frost: glassFrost)
        .environment(\.colorScheme, .dark)
    }

    // Full glass from the default opacity up; below it the glass fades with the color, so 0% hides the box.
    private var glassFrost: Double {
        min(1, store.overlayTint[3] / StatsStore.defaultOverlayTint[3])
    }

    private var watermarkSymbol: String {
        guard let r = store.effectiveFiveHourPace?.ratio else {
            return store.effectiveSignedIn ? "hourglass" : "person.crop.circle.badge.questionmark"
        }
        switch r {
        case ..<0.95: return store.glyphUnderPace
        case ..<1.10: return store.glyphOnPace
        default:      return store.glyphOverPace
        }
    }

    private func fiveHourColumn(_ pace: StatsStore.Pace) -> some View {
        VStack(spacing: 6) {
            PaceRing(pace: pace, size: 84)
                .padding(.bottom, 2)
            columnTitle("5-hour window")
            Text(percentText(pace.used))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText(value: pace.used))
                .animation(Theme.springy, value: pace.used)
            statusLabel(pace)
            Spacer(minLength: 0)
            footnote("Resets in \(store.windowResetText)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func weeklyColumn(_ rings: [WeeklyRing]) -> some View {
        let sameReset = Set(rings.map(\.resetText)).count == 1
        return VStack(spacing: 6) {
            PaceRing(paces: rings.map(\.pace), symbol: "calendar", size: 84)
                .padding(.bottom, 2)
            columnTitle("Weekly")
            VStack(spacing: 4) {
                ForEach(Array(rings.enumerated()), id: \.element.id) { i, ring in
                    HStack(spacing: 5) {
                        if rings.count > 1 {
                            RingIndexIcon(count: rings.count, index: i, color: ring.pace.color, size: 11)
                        }
                        Text(ring.name)
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(percentText(ring.pace.used))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: ring.pace.used))
                        Image(systemName: ring.pace.symbol)
                            .font(.system(size: 9.5))
                            .foregroundStyle(ring.pace.color)
                            .help(ring.pace.label)
                    }
                    .animation(Theme.springy, value: ring.pace.used)
                    if !sameReset {
                        footnote("Resets in \(ring.resetText)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
            if sameReset, let first = rings.first {
                footnote("Resets in \(first.resetText)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func codexSection(_ windows: [StatsStore.CodexWindow]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PaceRing(paces: windows.map(\.pace), logo: "openai", size: 84)
            VStack(alignment: .leading, spacing: 6) {
                columnTitle(store.codexPlanName.map { "Codex · \($0)" } ?? "Codex")
                ForEach(Array(windows.enumerated()), id: \.element.id) { i, window in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            if windows.count > 1 {
                                RingIndexIcon(count: windows.count, index: i, color: window.pace.color, size: 11)
                            }
                            Text(window.name)
                                .font(.system(size: 10.5, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(percentText(window.pace.used))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: window.pace.used))
                            Image(systemName: window.pace.symbol)
                                .font(.system(size: 9.5))
                                .foregroundStyle(window.pace.color)
                                .help(window.pace.label)
                        }
                        footnote("Resets in \(window.resetText)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .animation(Theme.springy, value: window.pace.used)
                }
            }
        }
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
    }

    private func statusLabel(_ pace: StatsStore.Pace) -> some View {
        Label(pace.label, systemImage: pace.symbol)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(pace.color)
            .lineLimit(1)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.white.opacity(0.45))
            .monospacedDigit()
            .lineLimit(1)
    }
}
