import SwiftUI
import AppKit

// MARK: - History Window Controller

enum HistoryWindowController {
    private static var window: NSWindow?

    @MainActor
    static func present(store: StatsStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryView(store: store)
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Usage History"
        win.setContentSize(NSSize(width: 520, height: 560))
        win.styleMask = [.titled, .closable, .resizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

// MARK: - History View

struct HistoryView: View {
    let store: StatsStore

    var body: some View {
        let summaries = store.cachedSummaries
        let streak = store.cachedStreak
        let last7 = Array(summaries.suffix(7))
        let heatmapData = Array(summaries.suffix(12 * 7))

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                streakSection(streak: streak, totalDays: summaries.filter { $0.eventCount > 0 }.count)
                barChartSection(days: last7)
                heatmapSection(data: heatmapData)
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    // MARK: - Streak

    private func streakSection(streak: Int, totalDays: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            HStack(spacing: 12) {
                statBox(value: "\(streak)", label: streak == 1 ? "day streak" : "days streak")
                statBox(value: "\(totalDays)", label: "active days (90d)")
            }
        }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bar Chart (last 7 days)

    private func barChartSection(days: [DailySummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            BarChartView(days: days)
                .frame(height: 120)
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Heatmap

    private func heatmapSection(data: [DailySummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage heatmap")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            HeatmapView(data: data)
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Bar Chart

struct BarChartView: View {
    let days: [DailySummary]

    var body: some View {
        let maxTokens = max(1, days.map(\.billableTokens).max() ?? 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if day.billableTokens > 0 {
                            Text(shortTokens(day.billableTokens))
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(day).gradient)
                            .frame(height: max(2, geo.size.height * 0.75 * CGFloat(day.billableTokens) / CGFloat(maxTokens)))
                        Text(dayLabel(day.date))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func barColor(_ day: DailySummary) -> Color {
        switch day.intensity {
        case ..<0.15: return .green
        case ..<0.4:  return .mint
        case ..<0.7:  return .orange
        default:      return .red
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func shortTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}

// MARK: - Heatmap (GitHub-style)

struct HeatmapView: View {
    let data: [DailySummary]
    private let spacing: CGFloat = 3
    private let dayLabelWidth: CGFloat = 24

    var body: some View {
        let cal = Calendar.current
        let grid = buildGrid(cal: cal)

        VStack(alignment: .leading, spacing: 6) {
            // Month labels
            monthLabelsRow(grid: grid, cal: cal)

            // Grid: rows = weekdays, columns = weeks
            GeometryReader { geo in
                let gridWidth = geo.size.width - dayLabelWidth - spacing
                let columns = CGFloat(max(grid.count, 1))
                let cellSize = (gridWidth - spacing * (columns - 1)) / columns

                HStack(alignment: .top, spacing: spacing) {
                    // Day labels
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            let label = weekdayLabel(row)
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

                    ForEach(0..<grid.count, id: \.self) { col in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { row in
                                if let summary = grid[col][row] {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(heatColor(summary.intensity))
                                        .frame(width: cellSize, height: cellSize)
                                        .help(tooltipText(summary))
                                } else {
                                    Color.clear.frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: gridHeight(grid: grid))

            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                ForEach([0.0, 0.15, 0.4, 0.7, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(level))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func monthLabelsRow(grid: [[DailySummary?]], cal: Calendar) -> some View {
        let labels = monthLabels(grid: grid, cal: cal)
        let totalColumns = grid.count
        return GeometryReader { geo in
            let gridWidth = geo.size.width - dayLabelWidth - spacing
            let colWidth = totalColumns > 0 ? gridWidth / CGFloat(totalColumns) : 0
            ZStack(alignment: .leading) {
                ForEach(labels, id: \.offset) { item in
                    Text(item.label)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                        .position(
                            x: dayLabelWidth + spacing + CGFloat(item.offset) * colWidth + 12,
                            y: 6
                        )
                }
            }
        }
        .frame(height: 14)
    }

    private func gridHeight(grid: [[DailySummary?]]) -> CGFloat {
        // Estimate based on available width (~460 inner width minus padding)
        let estimatedWidth: CGFloat = 430 - dayLabelWidth - spacing
        let columns = CGFloat(max(grid.count, 1))
        let cellSize = (estimatedWidth - spacing * (columns - 1)) / columns
        return 7 * cellSize + 6 * spacing
    }

    private func buildGrid(cal: Calendar) -> [[DailySummary?]] {
        let lookup = Dictionary(uniqueKeysWithValues: data.map { (cal.startOfDay(for: $0.date), $0) })
        let today = cal.startOfDay(for: Date())
        let todayWeekday = cal.component(.weekday, from: today)
        let firstWeekday = cal.firstWeekday
        let rowOffset = (todayWeekday - firstWeekday + 7) % 7
        let totalDays = data.count > 0 ? max(data.count, 7 * 12) : 7 * 12

        let weeksBack = (totalDays + rowOffset) / 7
        let startDate = cal.date(byAdding: .day, value: -(weeksBack * 7 + rowOffset), to: today)!

        var grid: [[DailySummary?]] = []
        var current = startDate

        while current <= today {
            var week: [DailySummary?] = []
            for _ in 0..<7 {
                if current <= today {
                    week.append(lookup[current])
                } else {
                    week.append(nil)
                }
                current = cal.date(byAdding: .day, value: 1, to: current)!
            }
            grid.append(week)
        }
        return grid
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

    private func weekdayLabel(_ row: Int) -> String {
        let cal = Calendar.current
        let firstWeekday = cal.firstWeekday
        let weekday = ((firstWeekday - 1 + row) % 7) + 1
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        return row % 2 == 1 ? f.shortWeekdaySymbols[weekday - 1] : ""
    }

    private func tooltipText(_ summary: DailySummary) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateStyle = .medium
        let tokens = summary.billableTokens
        if tokens == 0 { return "\(f.string(from: summary.date)): no usage" }
        return "\(f.string(from: summary.date)): \(tokens.formatted()) billable tokens, \(summary.eventCount) requests"
    }

    struct MonthLabel: Identifiable {
        let offset: Int
        let label: String
        let span: Int
        var id: Int { offset }
    }

    private func monthLabels(grid: [[DailySummary?]], cal: Calendar) -> [MonthLabel] {
        var labels: [MonthLabel] = []
        var lastMonth = -1
        var currentSpan = 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM"

        for (i, week) in grid.enumerated() {
            let date = week.compactMap({ $0?.date }).first
                ?? cal.date(byAdding: .day, value: i * 7, to: data.first?.date ?? Date())!
            let month = cal.component(.month, from: date)
            if month != lastMonth {
                if !labels.isEmpty {
                    labels[labels.count - 1] = MonthLabel(
                        offset: labels.last!.offset,
                        label: labels.last!.label,
                        span: currentSpan
                    )
                }
                labels.append(MonthLabel(offset: i, label: f.string(from: date), span: 1))
                currentSpan = 1
                lastMonth = month
            } else {
                currentSpan += 1
            }
        }
        if !labels.isEmpty {
            labels[labels.count - 1] = MonthLabel(
                offset: labels.last!.offset,
                label: labels.last!.label,
                span: currentSpan
            )
        }
        return labels
    }
}
