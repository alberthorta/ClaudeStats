import Foundation

struct DailySummary: Identifiable {
    let date: Date
    let billableTokens: Int
    let tokensByModel: [(String, Int)]
    let eventCount: Int

    var id: Date { date }

    var intensity: Double {
        // Normalize: 0 = no usage, 1 = heavy usage (500k+ billable tokens)
        min(1.0, Double(billableTokens) / 500_000)
    }
}

enum UsageHistory {
    /// Aggregate events into daily summaries for the last N days.
    static func dailySummaries(from events: [UsageEvent], days: Int) -> [DailySummary] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Build a map of day → events
        var byDay: [Date: [UsageEvent]] = [:]
        for i in 0..<days {
            let day = cal.date(byAdding: .day, value: -i, to: today)!
            byDay[day] = []
        }
        for event in events where event.model != "<synthetic>" {
            let day = cal.startOfDay(for: event.timestamp)
            byDay[day, default: []].append(event)
        }

        return byDay.map { (day, events) in
            var modelAcc: [String: Int] = [:]
            for e in events {
                modelAcc[e.model, default: 0] += e.billableTokens
            }
            return DailySummary(
                date: day,
                billableTokens: events.reduce(0) { $0 + $1.billableTokens },
                tokensByModel: modelAcc.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 },
                eventCount: events.count
            )
        }.sorted { $0.date < $1.date }
    }

    /// Current streak: number of consecutive days (ending today or yesterday) with at least one event.
    static func streak(from summaries: [DailySummary]) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sorted = summaries.sorted { $0.date > $1.date }

        var count = 0
        var expected = today

        for summary in sorted {
            let day = cal.startOfDay(for: summary.date)
            if day == expected && summary.eventCount > 0 {
                count += 1
                expected = cal.date(byAdding: .day, value: -1, to: expected)!
            } else if day == expected {
                // Day exists but no events — streak broken (unless it's today)
                if day == today {
                    expected = cal.date(byAdding: .day, value: -1, to: expected)!
                    continue
                }
                break
            } else if day < expected {
                break
            }
        }
        return count
    }

    /// Generate summaries for the heatmap: last N weeks (7 * N days).
    static func heatmapData(from events: [UsageEvent], weeks: Int) -> [DailySummary] {
        dailySummaries(from: events, days: weeks * 7)
    }
}
