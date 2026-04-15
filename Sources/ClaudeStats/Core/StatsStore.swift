import Foundation
import Observation

@Observable
final class StatsStore {
    var events: [UsageEvent] = []
    var remote: RemoteUsage?
    var remoteError: String?
    var isSignedIn: Bool = ClaudeAIClient.hasSession

    private var timer: Timer?

    init() {
        reload()
        startTimer()
    }

    var windowPercentRemaining: Double {
        guard let util = remote?.fiveHour?.utilizationFraction else { return 1 }
        return 1 - util
    }

    /// Time until the 5h window resets, per the server-provided ISO timestamp.
    var windowResetText: String {
        guard let iso = remote?.fiveHour?.resetsAt,
              let date = ISO8601DateFormatter.flexible.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        else { return "—" }
        let secs = max(0, Int(date.timeIntervalSinceNow))
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func reload() {
        // Parse last 8 days of JSONLs so week + 5h breakdown is always covered.
        let lookback = Date().addingTimeInterval(-8 * 24 * 3600)
        events = JsonlUsageReader.loadEvents(since: lookback)
        isSignedIn = ClaudeAIClient.hasSession
        if isSignedIn { Task { await refreshRemote() } }
    }

    @MainActor
    func refreshRemote() async {
        guard ClaudeAIClient.hasSession else { return }
        do {
            remote = try await ClaudeAIClient.fetchUsage()
            remoteError = nil
        } catch {
            remoteError = error.localizedDescription
        }
    }

    func signOut() {
        ClaudeAIClient.clear()
        remote = nil
        remoteError = nil
        isSignedIn = false
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: - Scoped stats

    func stats(for scope: UsageScope) -> ScopeStats {
        switch scope {
        case .window5h: return window5hStats()
        case .week:     return weekStats()
        }
    }

    private func window5hStats() -> ScopeStats {
        let cutoff = Date().addingTimeInterval(-5 * 3600)
        let recent = events.filter { $0.timestamp >= cutoff }
        return ScopeStats(
            title: "5-hour window",
            subtitle: "",
            tokensUsed: 0,
            tokenLimit: nil,
            tokensByModel: tokensByModel(recent),
            resetCountdown: windowResetText
        )
    }

    private func weekStats() -> ScopeStats {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let week = events.filter { $0.timestamp >= cutoff }
        return ScopeStats(
            title: "Weekly",
            subtitle: "",
            tokensUsed: 0,
            tokenLimit: nil,
            tokensByModel: tokensByModel(week),
            resetCountdown: weeklyResetText
        )
    }

    /// Pace info for the 5h window, derived from remote utilization + resets_at.
    struct Pace {
        let used: Double       // 0-1, fraction of cap consumed
        let elapsed: Double    // 0-1, fraction of window elapsed
        var ratio: Double { elapsed > 0.01 ? used / elapsed : 0 }
        var projectedAtReset: Double { elapsed > 0.01 ? min(1.5, used / elapsed) : 0 }
        var label: String {
            switch ratio {
            case ..<0.75:  return "Well under pace"
            case ..<0.95:  return "Under pace"
            case ..<1.10:  return "On pace"
            case ..<1.35:  return "Over pace"
            default:       return "Burning fast"
            }
        }
    }

    var fiveHourPace: Pace? {
        guard let util = remote?.fiveHour?.utilizationFraction,
              let iso = remote?.fiveHour?.resetsAt,
              let reset = ISO8601DateFormatter.flexible.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        else { return nil }
        let duration: Double = 5 * 3600
        let remaining = max(0, reset.timeIntervalSinceNow)
        let elapsed = max(0, min(1, 1 - remaining / duration))
        return Pace(used: util, elapsed: elapsed)
    }

    var weeklyPace: Pace? {
        guard let util = remote?.sevenDay?.utilizationFraction,
              let iso = remote?.sevenDay?.resetsAt,
              let reset = ISO8601DateFormatter.flexible.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        else { return nil }
        let duration: Double = 7 * 24 * 3600
        let remaining = max(0, reset.timeIntervalSinceNow)
        let elapsed = max(0, min(1, 1 - remaining / duration))
        return Pace(used: util, elapsed: elapsed)
    }

    var weeklyResetText: String? {
        guard let iso = remote?.sevenDay?.resetsAt,
              let date = ISO8601DateFormatter.flexible.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return nil
        }
        let secs = max(0, Int(date.timeIntervalSinceNow))
        let d = secs / 86400, h = (secs % 86400) / 3600
        return d > 0 ? "\(d)d \(h)h" : "\(h)h"
    }

    private func tokensByModel(_ events: [UsageEvent]) -> [(String, Int)] {
        var acc: [String: Int] = [:]
        for e in events { acc[e.model, default: 0] += e.billableTokens }
        return acc.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}
