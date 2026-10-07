import SwiftUI
import AppKit

// MARK: - Palette

enum Theme {
    /// Claude's terracotta. Used as the single hue of the activity ramp and as the app accent.
    static let accent = dynamic(light: 0xD97757, dark: 0xCC6A4A)

    static let cardRadius: CGFloat = 14
    static let springy = Animation.spring(duration: 0.55, bounce: 0.18)
    static let smooth = Animation.smooth(duration: 0.35)

    /// Each mode has its own validated steps (dataviz validate_palette.js): dark is not a flip of light.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    /// `level` is 0…1. Callers scale against the busiest visible day: a fixed token cap
    /// saturated every cell for heavy users.
    static func heatColor(_ level: Double, onDark: Bool = false) -> Color {
        switch level {
        case ..<0.001: return onDark ? .white.opacity(0.08) : Color.primary.opacity(0.07)
        case ..<0.15:  return accent.opacity(0.3)
        case ..<0.4:   return accent.opacity(0.52)
        case ..<0.7:   return accent.opacity(0.76)
        default:       return accent
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension StatsStore.Pace {
    var color: Color {
        switch ratio {
        case ..<0.75:  return .green
        case ..<0.95:  return .mint
        case ..<1.10:  return .yellow
        case ..<1.35:  return .orange
        default:       return .red
        }
    }

    var symbol: String {
        switch ratio {
        case ..<0.95:  return "checkmark.circle.fill"
        case ..<1.10:  return "equal.circle.fill"
        case ..<1.35:  return "exclamationmark.triangle.fill"
        default:       return "flame.fill"
        }
    }
}

func percentText(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
}

// MARK: - Model identity

/// Colour follows the model family, never its rank, so Opus keeps its hue when Sonnet overtakes it.
enum ModelFamily: CaseIterable {
    case opus, sonnet, haiku, fable, other

    init(model: String) {
        let m = model.lowercased()
        if m.contains("opus") { self = .opus }
        else if m.contains("sonnet") { self = .sonnet }
        else if m.contains("haiku") { self = .haiku }
        else if m.contains("fable") { self = .fable }
        else { self = .other }
    }

    var color: Color {
        switch self {
        case .opus:   return Theme.dynamic(light: 0xD97757, dark: 0xCC6A4A)
        case .sonnet: return Theme.dynamic(light: 0x5E5CE6, dark: 0x7472F5)
        case .haiku:  return Theme.dynamic(light: 0x30A2B8, dark: 0x1F98AF)
        case .fable:  return Theme.dynamic(light: 0xB05FD9, dark: 0xB86AF0)
        case .other:  return .gray
        }
    }
}

/// "claude-opus-4-1-20250805" → "Opus 4.1", "claude-3-5-haiku-20241022" → "Haiku 3.5".
func prettyModelName(_ name: String) -> String {
    let parts = name.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
    let words = parts.filter { Int($0) == nil }
    let version = parts.filter { Int($0) != nil && $0.count < 8 }
    guard !words.isEmpty else { return name }
    let title = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    return version.isEmpty ? title : "\(title) \(version.joined(separator: "."))"
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }

    /// Fades and lifts content in when it appears, staggered by `index` so a stack reads top to bottom.
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

private struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.12).delay(Double(index) * 0.045)) {
                    shown = true
                }
            }
            .onDisappear { shown = false }
    }
}

// MARK: - Pace widgets

struct PacePill: View {
    let pace: StatsStore.Pace

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: pace.symbol)
                .foregroundStyle(pace.color)
                .contentTransition(.symbolEffect(.replace))
            Text(pace.label)
                .foregroundStyle(.primary)
                .contentTransition(.interpolate)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(pace.color.opacity(0.16), in: Capsule())
        .animation(Theme.smooth, value: pace.label)
    }
}

/// Ring gauge built on SupperGauge. One concentric ring per limit, outermost first; the marker is how
/// much of the window has elapsed.
struct PaceRing: View {
    let paces: [StatsStore.Pace]
    /// nil keeps SupperGauge's spark.
    var symbol: String?
    var size: CGFloat = 112
    @State private var shown = false

    init(pace: StatsStore.Pace, symbol: String? = nil, size: CGFloat = 112) {
        self.init(paces: [pace], symbol: symbol, size: size)
    }

    init(paces: [StatsStore.Pace], symbol: String? = nil, size: CGFloat = 112) {
        self.paces = paces
        self.symbol = symbol
        self.size = size
    }

    /// Tints the glow, so the most worrying pace wins.
    private var color: Color {
        paces.max { $0.ratio < $1.ratio }?.color ?? .secondary
    }

    /// SupperGauge draws one marker across every ring. Only show it when it is true for all of them.
    private var sharedElapsed: Double? {
        guard let first = paces.first?.elapsed,
              paces.allSatisfy({ abs($0.elapsed - first) < 0.01 }) else { return nil }
        return first
    }

    var body: some View {
        SupperGauge(
            values: paces.map { shown ? $0.used * 100 : 0 },
            marker: sharedElapsed.map { shown ? $0 * 100 : 0 },
            light: appearance(.light, marker: .black.opacity(0.8)),
            dark: appearance(.dark, marker: .white),
            lineWidth: paces.count > 1 ? 16 : 10,
            markerWidth: 3
        )
        .foregroundStyle(.secondary)
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.25), radius: 6)
        .onAppear {
            // Defer one runloop so the gauge first renders empty and then animates in.
            DispatchQueue.main.async { shown = true }
        }
        .onDisappear { shown = false }
        .accessibilityLabel(paces.map { "\(percentText($0.used)) used, \($0.label)" }.joined(separator: "; "))
    }

    private func appearance(_ base: SupperGaugeAppearance, marker: Color) -> SupperGaugeAppearance {
        var a = base
        a.trackColor = Color.primary.opacity(0.08)
        a.progressColor = color
        a.ringColors = paces.map(\.color)
        a.markerColor = marker
        if let symbol {
            a.image = Image(systemName: symbol)
        }
        return a
    }
}

/// One ring of the weekly gauge: the global weekly cap first, then each per-model cap.
struct WeeklyRing: Identifiable {
    let id: String
    let name: String
    let pace: StatsStore.Pace
    let resetText: String
}

extension StatsStore {
    var weeklyRings: [WeeklyRing] {
        var rings: [WeeklyRing] = []
        if let pace = effectiveWeeklyPace {
            rings.append(WeeklyRing(id: "weekly", name: "All models", pace: pace,
                                    resetText: weeklyResetText ?? "—"))
        }
        for limit in effectiveScopedWeeklyLimits {
            let name = limit.title.replacingOccurrences(of: "Weekly · ", with: "")
            rings.append(WeeklyRing(id: limit.id, name: name, pace: limit.pace, resetText: limit.resetText))
        }
        return rings
    }
}

/// Tiny legend glyph: `count` concentric rings with the one at `index` (0 = outermost) highlighted.
struct RingIndexIcon: View {
    let count: Int
    let index: Int
    var color: Color
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let d = size - CGFloat(i) * (size / CGFloat(count + 1)) * 1.4
                Circle()
                    .stroke(i == index ? color : Color.primary.opacity(0.18),
                            lineWidth: i == index ? 2 : 1)
                    .frame(width: d, height: d)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Linear gauge with the same encoding as `PaceRing`.
struct PaceBar: View {
    let pace: StatsStore.Pace
    var height: CGFloat = 8
    var trackColor: Color = Color.primary.opacity(0.08)
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(LinearGradient(colors: [pace.color.opacity(0.65), pace.color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, w * CGFloat(shown ? min(1, pace.used) : 0)))
                    .opacity(pace.used > 0 ? 1 : 0)
                    .shadow(color: pace.color.opacity(0.3), radius: 3)
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: height + 8)
                    .shadow(color: .black.opacity(0.45), radius: 1.2, y: 0.5)
                    .offset(x: w * CGFloat(shown ? min(1, pace.elapsed) : 0) - 1.5)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 8)
        .animation(Theme.springy, value: pace.used)
        .animation(Theme.springy, value: pace.elapsed)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.12).delay(0.1)) { shown = true }
        }
        .onDisappear { shown = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percentText(pace.used)) used, \(percentText(pace.elapsed)) elapsed")
    }
}

// MARK: - Model breakdown

struct ModelBreakdownBar: View {
    let tokensByModel: [(String, Int)]

    private struct Slice: Identifiable {
        let name: String
        let share: Double
        var id: String { name }
    }

    var body: some View {
        let total = Double(tokensByModel.reduce(0) { $0 + $1.1 })
        let slices = total > 0
            ? tokensByModel
                .map { Slice(name: $0.0, share: Double($0.1) / total) }
                .filter { $0.share >= 0.005 }
            : []
        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geo in
                    let gaps = CGFloat(slices.count - 1) * 2
                    HStack(spacing: 2) {
                        ForEach(slices) { s in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(ModelFamily(model: s.name).color)
                                .frame(width: max(2, (geo.size.width - gaps) * s.share))
                                .help("\(prettyModelName(s.name)): \(percentText(s.share))")
                        }
                    }
                }
                .frame(height: 5)
                .clipShape(Capsule())

                FlowLegend(items: slices.map { ($0.name, $0.share) })
            }
            .animation(Theme.smooth, value: slices.map(\.share))
        }
    }
}

private struct FlowLegend: View {
    let items: [(String, Double)]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
            ForEach(items, id: \.0) { name, share in
                HStack(spacing: 5) {
                    Circle()
                        .fill(ModelFamily(model: name).color)
                        .frame(width: 6, height: 6)
                    Text(prettyModelName(name))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(percentText(share))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: share))
                }
                .font(.system(size: 10.5, design: .rounded))
            }
        }
    }
}

// MARK: - Activity heatmap

/// GitHub-style grid: columns are weeks, rows are weekdays, the last column is the current week.
/// Takes an explicit width so it keeps an intrinsic size (the desktop overlay sizes its window from it).
struct ActivityHeatmap: View {
    let data: [DailySummary]
    let weeks: Int
    let width: CGFloat
    var showLabels = true
    var cellAspect: CGFloat = 1
    var onDark = false
    var spacing: CGFloat = 3

    @State private var hovered: Date?

    private let dayLabelWidth: CGFloat = 22

    var body: some View {
        let cal = Calendar.current
        let grid = buildGrid(cal: cal)
        let labelSpace = showLabels ? dayLabelWidth + spacing : 0
        let cols = CGFloat(max(grid.count, 1))
        let cell = floor((width - labelSpace - spacing * (cols - 1)) / cols)
        let cellH = max(3, floor(cell * cellAspect))
        let secondary: Color = onDark ? .white.opacity(0.45) : .secondary
        let peak = Double(max(1, grid.joined().compactMap { $0?.summary?.billableTokens }.max() ?? 1))

        VStack(alignment: .leading, spacing: 4) {
            if showLabels {
                ZStack(alignment: .topLeading) {
                    ForEach(monthStarts(grid: grid, cal: cal), id: \.column) { m in
                        Text(m.label)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(secondary)
                            .fixedSize()
                            .offset(x: labelSpace + CGFloat(m.column) * (cell + spacing))
                    }
                }
                .frame(width: width, height: 11, alignment: .topLeading)
            }

            HStack(alignment: .top, spacing: spacing) {
                if showLabels {
                    VStack(alignment: .trailing, spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(row % 2 == 1 ? weekdaySymbol(row, cal: cal) : "")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(secondary)
                                .frame(width: dayLabelWidth, height: cellH, alignment: .trailing)
                        }
                    }
                }
                ForEach(0..<grid.count, id: \.self) { col in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            cellView(grid[col][row], width: cell, height: cellH, peak: peak)
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func cellView(_ day: DayCell?, width: CGFloat, height: CGFloat, peak: Double) -> some View {
        if let day {
            let isHovered = hovered == day.date
            RoundedRectangle(cornerRadius: min(3, height / 3), style: .continuous)
                .fill(Theme.heatColor(Double(day.summary?.billableTokens ?? 0) / peak, onDark: onDark))
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: min(3, height / 3), style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 1)
                    }
                }
                .frame(width: width, height: height)
                .scaleEffect(isHovered ? 1.3 : 1)
                .zIndex(isHovered ? 1 : 0)
                .animation(.spring(duration: 0.25, bounce: 0.3), value: isHovered)
                .onHover { inside in
                    if inside { hovered = day.date } else if hovered == day.date { hovered = nil }
                }
                .help(tooltip(day))
        } else {
            Color.clear.frame(width: width, height: height)
        }
    }

    struct DayCell {
        let date: Date
        let summary: DailySummary?
        let isToday: Bool
    }

    private func buildGrid(cal: Calendar) -> [[DayCell?]] {
        let lookup = Dictionary(data.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let today = cal.startOfDay(for: Date())
        let rowOffset = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -(rowOffset + (weeks - 1) * 7), to: today)!

        return (0..<weeks).map { col in
            (0..<7).map { row in
                let date = cal.date(byAdding: .day, value: col * 7 + row, to: start)!
                guard date <= today else { return nil }
                return DayCell(date: date, summary: lookup[date], isToday: date == today)
            }
        }
    }

    private struct MonthStart {
        let column: Int
        let label: String
    }

    private func monthStarts(grid: [[DayCell?]], cal: Calendar) -> [MonthStart] {
        var result: [MonthStart] = []
        var lastMonth: Int?
        for (i, week) in grid.enumerated() {
            guard let first = week.compactMap({ $0 }).first else { continue }
            let month = cal.component(.month, from: first.date)
            if month != lastMonth {
                // Skip a label on a partial leading week if the next month starts right after it.
                if lastMonth != nil || cal.component(.day, from: first.date) <= 7 || grid.count - i > 3 {
                    result.append(MonthStart(column: i, label: Self.monthFormatter.string(from: first.date)))
                }
                lastMonth = month
            }
        }
        // Labels need ~3 columns of room; drop any that would collide with the next one.
        return result.enumerated().filter { idx, m in
            idx + 1 >= result.count || result[idx + 1].column - m.column >= 2
        }.map(\.element)
    }

    private func weekdaySymbol(_ row: Int, cal: Calendar) -> String {
        let weekday = (cal.firstWeekday - 1 + row) % 7
        return String(Self.weekdayFormatter.shortWeekdaySymbols[weekday].prefix(3))
    }

    private func tooltip(_ day: DayCell) -> String {
        let date = Self.tooltipFormatter.string(from: day.date)
        guard let s = day.summary, s.billableTokens > 0 else { return "\(date) · no usage" }
        return "\(date) · \(compactTokens(s.billableTokens)) billable tokens · \(s.eventCount) requests"
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    private static let tooltipFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}

func compactTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return "\(n / 1000)k" }
    return "\(n)"
}

// MARK: - Controls

/// Small round icon button with a soft hover plate, for toolbars and footers.
struct IconButton: View {
    let symbol: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(hovering ? (role == .destructive ? Color.red : Color.primary) : Color.secondary)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                }
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension View {
    /// Liquid Glass on macOS 26+, a dark-tinted material before that. The tint keeps white text legible on any wallpaper.
    @ViewBuilder
    func darkGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(.black.opacity(0.38)),
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.black.opacity(0.35)))
            }
            .environment(\.colorScheme, .dark)
        }
    }
}
