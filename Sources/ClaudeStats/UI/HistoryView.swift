import SwiftUI
import AppKit
import Charts

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
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        win.setContentSize(NSSize(width: HistoryView.width, height: 660))
        // Content is laid out at a fixed width; only let the window grow vertically.
        win.contentMinSize = NSSize(width: HistoryView.width, height: 420)
        win.contentMaxSize = NSSize(width: HistoryView.width, height: 4000)
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

    static let width: CGFloat = 580
    private static let padding: CGFloat = 22
    private static let cardInnerWidth = width - padding * 2 - 28

    var body: some View {
        let summaries = store.cachedSummaries
        let last7 = summaries.suffix(7)
        let active = summaries.filter { $0.eventCount > 0 }
        let busiest = summaries.max { $0.billableTokens < $1.billableTokens }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Usage History")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .padding(.top, 8)
                    .entrance(0)

                HStack(spacing: 10) {
                    StatTile(symbol: "flame.fill", value: Double(store.cachedStreak),
                             text: "\(store.cachedStreak)",
                             label: store.cachedStreak == 1 ? "day streak" : "days streak")
                    StatTile(symbol: "calendar", value: Double(active.count),
                             text: "\(active.count)", label: "active days (90d)")
                    StatTile(symbol: "sum", value: Double(last7.reduce(0) { $0 + $1.billableTokens }),
                             text: compactTokens(last7.reduce(0) { $0 + $1.billableTokens }),
                             label: "tokens, last 7 days")
                    StatTile(symbol: "trophy.fill", value: Double(busiest?.billableTokens ?? 0),
                             text: compactTokens(busiest?.billableTokens ?? 0),
                             label: busiest.map { "best day · \(Self.shortDate.string(from: $0.date))" } ?? "best day")
                }
                .entrance(1)

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Last 14 days", subtitle: "Billable tokens per day, by model")
                    DailyUsageChart(days: Array(summaries.suffix(14)))
                        .frame(height: 190)
                }
                .card()
                .entrance(2)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        sectionTitle("Activity", subtitle: "Last 13 weeks")
                        Spacer()
                        heatLegend
                    }
                    ActivityHeatmap(data: summaries, weeks: 13, width: Self.cardInnerWidth,
                                    cellAspect: 0.5, spacing: 4)
                }
                .card()
                .entrance(3)
            }
            .padding(.horizontal, Self.padding)
            .padding(.bottom, Self.padding)
            .padding(.top, 30)
        }
        .frame(width: Self.width)
        .frame(minHeight: 420)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(.headline, design: .rounded))
            Text(subtitle)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 3) {
            Text("Less")
            ForEach([0.0, 0.1, 0.3, 0.6, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Theme.heatColor(level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.system(size: 9.5, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - Stat tile

private struct StatTile: View {
    let symbol: String
    let value: Double
    let text: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(text)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .card()
    }
}

// MARK: - Daily chart

private struct DailyUsageChart: View {
    let days: [DailySummary]
    @State private var selected: Date?
    @State private var grow = false

    private struct Point: Identifiable {
        let day: Date
        let family: ModelFamily
        let tokens: Int
        var id: String { "\(day.timeIntervalSince1970)-\(family)" }
    }

    private static let locale = Locale(identifier: "en_US")

    private var points: [Point] {
        days.flatMap { day in
            var acc: [ModelFamily: Int] = [:]
            for (model, tokens) in day.tokensByModel { acc[ModelFamily(model: model), default: 0] += tokens }
            return ModelFamily.allCases.compactMap { f in
                acc[f].map { Point(day: day.date, family: f, tokens: $0) }
            }
        }
    }

    private var presentFamilies: [ModelFamily] {
        let used = Set(points.map(\.family))
        return ModelFamily.allCases.filter(used.contains)
    }

    var body: some View {
        let selectedDay = selected.flatMap { sel in
            days.first { Calendar.current.isDate($0.date, inSameDayAs: sel) }
        }
        Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Day", p.day, unit: .day),
                    y: .value("Tokens", grow ? p.tokens : 0),
                    width: .ratio(0.62)
                )
                .foregroundStyle(by: .value("Model", p.family.name))
                .cornerRadius(3)
                .opacity(selectedDay == nil || Calendar.current.isDate(p.day, inSameDayAs: selectedDay!.date) ? 1 : 0.35)
            }
            if let selectedDay {
                RuleMark(x: .value("Day", selectedDay.date, unit: .day))
                    .foregroundStyle(Color.primary.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(selectedDay)
                    }
            }
        }
        .chartForegroundStyleScale(
            domain: presentFamilies.map(\.name),
            range: presentFamilies.map(\.color)
        )
        .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(Self.locale), centered: true)
                    .font(.system(size: 9.5, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(compactTokens(n)).font(.system(size: 9.5, design: .rounded))
                    }
                }
            }
        }
        .chartXSelection(value: $selected)
        .animation(.easeOut(duration: 0.15), value: selected)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.12).delay(0.15)) { grow = true }
        }
    }

    private func tooltip(_ day: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(Self.locale))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            Text("\(compactTokens(day.billableTokens)) tokens · \(day.eventCount) requests")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

extension ModelFamily {
    var name: String {
        switch self {
        case .opus:   return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku:  return "Haiku"
        case .fable:  return "Fable"
        case .other:  return "Other"
        }
    }
}
