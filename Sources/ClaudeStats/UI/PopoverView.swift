import SwiftUI

struct PopoverView: View {
    @Bindable var store: StatsStore

    static let width: CGFloat = 360
    private static let outerPadding: CGFloat = 12
    private static let cardInnerWidth = width - outerPadding * 2 - 28

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroCard
                .entrance(0)
            weeklyCard
                .entrance(1)
            if store.showCodex && store.codexConnected {
                codexCard
                    .entrance(2)
            }
            if store.showHistory {
                activityCard
                    .entrance(3)
            }
            footer
                .padding(.top, 2)
        }
        .padding(Self.outerPadding)
        .frame(width: Self.width)
        .onAppear {
            if !store.effectiveSignedIn {
                NSApp.activate(ignoringOtherApps: true)
                openAppSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    PopoverToggle.toggle()
                }
            }
        }
    }

    private func openAppSettings() {
        SettingsWindowController.present(store: store)
    }

    // MARK: Cards

    @ViewBuilder
    private var heroCard: some View {
        let stats = store.stats(for: .window5h)
        VStack(alignment: .leading, spacing: 14) {
            if let pace = store.effectiveFiveHourPace {
                HStack(alignment: .center, spacing: 14) {
                    PaceRing(pace: pace)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("5-hour window")
                            .font(.system(.headline, design: .rounded))
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(percentText(pace.used))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: pace.used))
                                .animation(Theme.springy, value: pace.used)
                            Text("used")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        PacePill(pace: pace)
                        VStack(alignment: .leading, spacing: 3) {
                            MetricRow(symbol: "clock", text: "Resets in \(store.windowResetText)")
                            MetricRow(symbol: "timer", text: "\(percentText(pace.elapsed)) of window elapsed")
                            MetricRow(symbol: "arrow.up.forward",
                                      text: "Projecting \(percentText(pace.projectedAtReset)) at reset")
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                placeholder(title: "5-hour window")
            }
            ModelBreakdownBar(tokensByModel: stats.tokensByModel)
        }
        .card()
    }

    @ViewBuilder
    private var weeklyCard: some View {
        let stats = store.stats(for: .week)
        let rings = store.weeklyRings
        if !rings.isEmpty {
            let sameReset = Set(rings.map(\.resetText)).count == 1
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    PaceRing(paces: rings.map(\.pace), symbol: "calendar")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weekly")
                            .font(.system(.headline, design: .rounded))
                        ForEach(Array(rings.enumerated()), id: \.element.id) { i, ring in
                            WeeklyRingRow(
                                name: ring.name,
                                pace: ring.pace,
                                resetText: sameReset ? nil : ring.resetText,
                                legend: rings.count > 1
                                    ? RingIndexIcon(count: rings.count, index: i, color: ring.pace.color)
                                    : nil
                            )
                        }
                        if sameReset, let first = rings.first {
                            VStack(alignment: .leading, spacing: 3) {
                                MetricRow(symbol: "clock", text: "Resets in \(first.resetText)")
                                MetricRow(symbol: "timer", text: "\(percentText(first.pace.elapsed)) of week elapsed")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                ModelBreakdownBar(tokensByModel: stats.tokensByModel)
            }
            .card()
        } else if store.effectiveFiveHourPace != nil {
            VStack(alignment: .leading, spacing: 12) {
                placeholder(title: "Weekly")
                ModelBreakdownBar(tokensByModel: stats.tokensByModel)
            }
            .card()
        }
    }

    @ViewBuilder
    private var codexCard: some View {
        let windows = store.codexWindows
        VStack(alignment: .leading, spacing: 14) {
            if !windows.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    PaceRing(paces: windows.map(\.pace), logo: "openai")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(codexTitle)
                            .font(.system(.headline, design: .rounded))
                        ForEach(Array(windows.enumerated()), id: \.element.id) { i, window in
                            WeeklyRingRow(
                                name: window.name,
                                pace: window.pace,
                                resetText: window.resetText,
                                legend: windows.count > 1
                                    ? RingIndexIcon(count: windows.count, index: i, color: window.pace.color)
                                    : nil
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: store.codexError == nil ? "hourglass" : "exclamationmark.triangle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .symbolEffect(.pulse, options: .repeating, isActive: store.codexError == nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(codexTitle)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Text(store.codexError ?? "Loading from chatgpt.com…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .card()
    }

    private var codexTitle: String {
        store.codexPlanName.map { "Codex · \($0)" } ?? "Codex"
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if store.cachedStreak > 0 {
                    Label("\(store.cachedStreak) day\(store.cachedStreak == 1 ? "" : "s") streak",
                          systemImage: "flame.fill")
                        .labelStyle(TintedIconLabelStyle(tint: Theme.accent))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(store.cachedStreak)))
                }
            }
            ActivityHeatmap(data: Array(store.cachedSummaries.suffix(91)), weeks: 13,
                            width: Self.cardInnerWidth, cellAspect: 0.7)
        }
        .card()
    }

    private func placeholder(title: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.06), in: Circle())
                .symbolEffect(.pulse, options: .repeating, isActive: isLoading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var isLoading: Bool {
        store.effectiveSignedIn && store.remoteError == nil
    }

    private var statusIcon: String {
        if !store.effectiveSignedIn { return "person.crop.circle.badge.questionmark" }
        if store.remoteError != nil { return "exclamationmark.triangle" }
        return "hourglass"
    }

    private var statusMessage: String {
        if !store.effectiveSignedIn { return "Sign in via Settings to see pace data" }
        if let err = store.remoteError { return "claude.ai error: \(err)" }
        return "Loading from claude.ai…"
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            RefreshCountdown(seconds: store.secondsUntilRefresh, total: store.refreshInterval)
            Text("v\(UpdateChecker.currentVersion)")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .padding(.leading, 6)
            Spacer()
            RefreshButton { store.reload() }
            IconButton(symbol: "chart.bar.xaxis", help: "History") {
                HistoryWindowController.present(store: store)
            }
            IconButton(symbol: "gearshape", help: "Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openAppSettings()
            }
            IconButton(symbol: "info.circle", help: "About") { AboutWindowController.present() }
            IconButton(symbol: "power", help: "Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Pieces

/// One ring of the weekly gauge: which ring it is, its share used, status and projection.
struct WeeklyRingRow: View {
    let name: String
    let pace: StatsStore.Pace
    let resetText: String?
    let legend: RingIndexIcon?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let legend {
                    legend.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                }
                Text(name)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(percentText(pace.used))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: pace.used))
                    .animation(Theme.springy, value: pace.used)
            }
            HStack(spacing: 6) {
                PacePill(pace: pace)
                Text(resetText.map { "→ \(percentText(pace.projectedAtReset)) · \($0)" }
                     ?? "→ \(percentText(pace.projectedAtReset))")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .help("Projected usage at reset if you keep this pace")
            }
        }
    }
}

private struct MetricRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

/// A tiny ring that drains towards the next automatic refresh.
private struct RefreshCountdown: View {
    let seconds: Int
    let total: Double

    var body: some View {
        let fraction = total > 0 ? Double(seconds) / total : 0
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: seconds == Int(total) ? 0.3 : 1), value: fraction)
        }
        .frame(width: 12, height: 12)
        .padding(.leading, 4)
        .help(seconds > 0 ? "Refresh in \(seconds)s" : "Refreshing…")
    }
}

private struct RefreshButton: View {
    let action: () -> Void
    @State private var turns = 0.0

    var body: some View {
        IconButton(symbol: "arrow.clockwise", help: "Refresh now") {
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) { turns += 1 }
            action()
        }
        .rotationEffect(.degrees(turns * 360))
    }
}
