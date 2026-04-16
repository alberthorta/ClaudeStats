import SwiftUI

struct PopoverView: View {
    @Bindable var store: StatsStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(scope: .window5h)
            Divider()
            section(scope: .week)
            if store.showHistoryAtLaunch {
                Divider()
                miniHeatmap
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            if !store.effectiveSignedIn {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    closeMenuBarPopover()
                }
            }
        }
    }

    private func closeMenuBarPopover() {
        for window in NSApp.windows
            where String(describing: type(of: window)).contains("MenuBarExtra") {
            window.close()
        }
    }

    @ViewBuilder
    private func section(scope: UsageScope) -> some View {
        let stats = store.stats(for: scope)
        let pace: StatsStore.Pace? = scope == .window5h ? store.effectiveFiveHourPace : store.effectiveWeeklyPace
        let resetText: String = scope == .window5h
            ? store.windowResetText
            : (store.weeklyResetText ?? "—")
        let title: String = scope == .window5h ? "5-hour window" : "Weekly"
        VStack(alignment: .leading, spacing: 10) {
            if let pace {
                PaceView(pace: pace, title: title, resetText: resetText)
            } else {
                fallbackHeader(title: title, stats: stats)
            }
            breakdown(stats: stats)
        }
    }

    private func fallbackHeader(title: String, stats: ScopeStats) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: statusIcon)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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

    @ViewBuilder
    private func breakdown(stats: ScopeStats) -> some View {
        if !stats.tokensByModel.isEmpty {
            let total = stats.tokensByModel.reduce(0) { $0 + $1.1 }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(stats.tokensByModel, id: \.0) { (name, tokens) in
                    HStack {
                        Text(prettify(name))
                            .font(.system(.caption, design: .rounded))
                        Spacer()
                        Text("\(percent(tokens, of: total))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var miniHeatmap: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Activity")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Spacer()
                Text("\(store.cachedStreak) day\(store.cachedStreak == 1 ? "" : "s") streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            MiniHeatmapGrid(data: Array(store.cachedSummaries.suffix(56)))
        }
    }

    private var footer: some View {
        HStack {
            Text("v\(UpdateChecker.currentVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Text(store.secondsUntilRefresh > 0 ? "Refresh in \(store.secondsUntilRefresh)s" : "Refreshing…")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer()
            Button("Refresh") { store.reload() }
                .buttonStyle(.borderless)
                .font(.caption)
            Button("History") { HistoryWindowController.present(store: store) }
                .buttonStyle(.borderless)
                .font(.caption)
            Button("About") { AboutWindowController.present() }
                .buttonStyle(.borderless)
                .font(.caption)
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func prettify(_ name: String) -> String {
        name.replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }
}

struct PaceView: View {
    let pace: StatsStore.Pace
    let title: String
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text(pace.label)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(paceColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Resets in \(resetText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("projecting \(Int((pace.projectedAtReset * 100).rounded()))% at reset")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            paceBar
                .frame(height: 14)
            HStack(spacing: 12) {
                legendDot(paceColor, "used \(pctText(pace.used))")
                legendDot(.primary.opacity(0.85), "elapsed \(pctText(pace.elapsed))")
            }
            .font(.caption2)
        }
    }

    private var paceColor: Color {
        switch pace.ratio {
        case ..<0.75:  return .green
        case ..<0.95:  return .mint
        case ..<1.10:  return .yellow
        case ..<1.35:  return .orange
        default:       return .red
        }
    }

    private var paceBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(paceColor.gradient)
                    .frame(width: geo.size.width * CGFloat(min(1, pace.used)))
                marker
                    .offset(x: geo.size.width * CGFloat(min(1, pace.elapsed)) - 3)
            }
        }
    }

    private var marker: some View {
        // Pure white bar with a strong dark outline so it stays readable over any fill color.
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: 6)
            Capsule()
                .fill(Color.white)
                .frame(width: 3)
        }
        .frame(height: 22)
        .shadow(color: .black.opacity(0.5), radius: 1.5, x: 0, y: 0.5)
    }

    private func pctText(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct MiniHeatmapGrid: View {
    let data: [DailySummary]
    private let spacing: CGFloat = 3
    private let dayLabelWidth: CGFloat = 24

    var body: some View {
        let cal = Calendar.current
        let grid = buildGrid(cal: cal)
        let labels = buildMonthLabels(grid: grid, cal: cal)
        // Popover is 360px with 16px padding = 328px inner width
        let columns = CGFloat(max(grid.count, 1))
        let gridWidth: CGFloat = 328 - dayLabelWidth - spacing
        let cellSize = floor((gridWidth - spacing * (columns - 1)) / columns)

        VStack(alignment: .leading, spacing: 3) {
            // Month labels
            HStack(spacing: 0) {
                Color.clear.frame(width: dayLabelWidth + spacing, height: 12)
                ForEach(labels, id: \.offset) { item in
                    Text(item.label)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: CGFloat(item.span) * (cellSize + spacing), alignment: .leading)
                }
                Spacer(minLength: 0)
            }

            // Grid with weekday labels
            HStack(alignment: .top, spacing: spacing) {
                // Weekday labels
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        let label = weekdayLabel(row, cal: cal)
                        if !label.isEmpty {
                            Text(label)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: dayLabelWidth, height: cellSize, alignment: .trailing)
                        } else {
                            Color.clear.frame(width: dayLabelWidth, height: cellSize)
                        }
                    }
                }

                // Cells
                ForEach(0..<grid.count, id: \.self) { col in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            if let summary = grid[col][row] {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(heatColor(summary.intensity))
                                    .frame(width: cellSize, height: cellSize)
                            } else {
                                Color.clear.frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func buildGrid(cal: Calendar) -> [[DailySummary?]] {
        let lookup = Dictionary(uniqueKeysWithValues: data.map { (cal.startOfDay(for: $0.date), $0) })
        let today = cal.startOfDay(for: Date())
        // Row offset: how many rows down from the first weekday is today
        let todayWeekday = cal.component(.weekday, from: today) // 1=Sun
        let firstWeekday = cal.firstWeekday // 1=Sun or 2=Mon per locale
        let rowOffset = (todayWeekday - firstWeekday + 7) % 7

        let totalDays = data.count
        let weeksBack = (totalDays + rowOffset) / 7
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

    private func weekdayLabel(_ row: Int, cal: Calendar) -> String {
        // Row 0 is the first day of the week per locale
        let firstWeekday = cal.firstWeekday // 1=Sun, 2=Mon
        let weekday = ((firstWeekday - 1 + row) % 7) + 1 // 1-based weekday
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        let name = f.shortWeekdaySymbols[weekday - 1] // Sun, Mon, ...
        // Only show every other row
        return row % 2 == 1 ? name : ""
    }

    struct MonthLabel {
        let offset: Int
        let label: String
        let span: Int
    }

    private func buildMonthLabels(grid: [[DailySummary?]], cal: Calendar) -> [MonthLabel] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM"
        var labels: [MonthLabel] = []
        var lastMonth = -1
        var spanCount = 0

        for (i, week) in grid.enumerated() {
            // Use the first day of the week to determine the month
            let firstDay = week.compactMap({ $0?.date }).min()
                ?? cal.date(byAdding: .day, value: -(grid.count - 1 - i) * 7, to: Date())!
            let month = cal.component(.month, from: firstDay)

            if month != lastMonth {
                if !labels.isEmpty {
                    labels[labels.count - 1] = MonthLabel(
                        offset: labels.last!.offset,
                        label: labels.last!.label,
                        span: spanCount
                    )
                }
                labels.append(MonthLabel(offset: i, label: f.string(from: firstDay), span: 1))
                spanCount = 1
                lastMonth = month
            } else {
                spanCount += 1
            }
        }
        if !labels.isEmpty {
            labels[labels.count - 1] = MonthLabel(
                offset: labels.last!.offset,
                label: labels.last!.label,
                span: spanCount
            )
        }
        return labels
    }

    private func heatColor(_ intensity: Double) -> Color {
        switch intensity {
        case 0:       return Color.primary.opacity(0.06)
        case ..<0.15: return Color.green.opacity(0.3)
        case ..<0.4:  return Color.green.opacity(0.5)
        case ..<0.7:  return Color.green.opacity(0.7)
        default:      return Color.green.opacity(0.95)
        }
    }
}

struct RingView: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            Text("\(Int((1 - progress) * 100))%")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var color: Color {
        switch progress {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }
}
