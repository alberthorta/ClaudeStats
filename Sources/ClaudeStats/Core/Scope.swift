import Foundation

enum UsageScope: String, CaseIterable, Identifiable {
    case window5h = "5h"
    case week = "Week"

    var id: String { rawValue }
}

struct ScopeStats {
    let title: String
    let subtitle: String
    let tokensUsed: Int
    let tokenLimit: Int?            // nil = no cap (show just usage)
    let tokensByModel: [(String, Int)]
    let resetCountdown: String?     // nil if no reset concept

    var percentUsed: Double {
        guard let tokenLimit, tokenLimit > 0 else { return 0 }
        return min(1.0, Double(tokensUsed) / Double(tokenLimit))
    }
    var percentRemaining: Double { 1.0 - percentUsed }
}
