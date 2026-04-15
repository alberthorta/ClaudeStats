import SwiftUI

struct PopoverView: View {
    @Bindable var store: StatsStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(scope: .window5h)
            Divider()
            section(scope: .week)
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

    private var footer: some View {
        HStack {
            Spacer()
            Button("Refresh") { store.reload() }
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
