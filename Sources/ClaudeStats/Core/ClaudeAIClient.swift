import Foundation

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

struct RemoteUsage: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?
    let limits: [Limit]?

    /// Decodes one limit independently of its siblings, so a single entry in an
    /// unfamiliar shape costs us that entry rather than the whole array.
    private struct LenientLimit: Decodable {
        let value: Limit?
        init(from decoder: Decoder) throws {
            value = try? Limit(from: decoder)
        }
    }

    /// An entry of the generic `limits` array claude.ai returns alongside the legacy
    /// `five_hour` / `seven_day` objects. Scoped entries (`weekly_scoped`) carry a
    /// per-model or per-surface cap — that is where the Fable weekly cap arrives.
    /// Only the fields the app actually reads are modelled, and all are optional:
    /// anything else claude.ai sends is one more thing that could fail the decode.
    struct Limit: Decodable {
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?

        struct Scope: Decodable {
            let model: Label?
            let surface: Label?
        }

        /// `surface` has only ever been observed as null, so accept either a bare
        /// string or a `{id, display_name}` object rather than guess at one.
        struct Label: Decodable {
            let displayName: String?

            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer(),
                   let text = try? single.decode(String.self) {
                    displayName = text
                    return
                }
                let container = try? decoder.container(keyedBy: CodingKeys.self)
                displayName = try? container?.decodeIfPresent(String.self, forKey: .displayName)
            }

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case kind, percent, scope
            case resetsAt = "resets_at"
        }

        var utilizationFraction: Double? {
            percent.map { max(0, min(1, $0 / 100)) }
        }

        /// Name to label this cap with, e.g. "Fable".
        var scopeLabel: String? {
            scope?.model?.displayName ?? scope?.surface?.displayName
        }

        /// Model and surface combined, so two caps on the same model but different
        /// surfaces stay distinct as SwiftUI identities.
        var scopeIdentity: String? {
            let parts = [scope?.model?.displayName, scope?.surface?.displayName].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: "/")
        }
    }

    struct Window: Decodable {
        /// 0-100 (percent used). Clamp & convert to 0-1 where needed.
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        var utilizationFraction: Double? {
            utilization.map { max(0, min(1, $0 / 100)) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try c.decodeIfPresent(Window.self, forKey: .fiveHour)
        sevenDay = try c.decodeIfPresent(Window.self, forKey: .sevenDay)
        // Deliberately non-throwing: an unrecognised limit entry must not take the
        // 5h and weekly sections down with it.
        let decoded = try? c.decodeIfPresent([LenientLimit].self, forKey: .limits)
        limits = decoded?.compactMap(\.value)
    }
}

struct OrgListItem: Decodable {
    let uuid: String
    let name: String?
    let capabilities: [String]?

    /// A paid org (Pro, Max, Team / Enterprise). A Team member also gets a free
    /// personal org, and that one has no usage limits worth showing.
    var isPaid: Bool {
        (capabilities ?? []).contains { ["claude_pro", "claude_max", "raven"].contains($0) }
    }
}

/// The app tracks a main account plus one optional extra (e.g. a work account).
/// Only the main one drives the menu bar icon.
enum ClaudeAccount: String, CaseIterable, Identifiable {
    case primary, secondary
    var id: String { rawValue }

    var other: ClaudeAccount { self == .primary ? .secondary : .primary }

    // The primary keys predate multi-account support; keep them so existing sign-ins survive.
    fileprivate var keyPrefix: String { self == .primary ? "claudeai." : "claudeai.secondary." }
}

enum ClaudeAIClient {
    static func hasSession(_ account: ClaudeAccount = .primary) -> Bool {
        Keychain.get(sessionKeyKey(account)) != nil
    }

    private static func sessionKeyKey(_ account: ClaudeAccount) -> String { account.keyPrefix + "sessionKey" }
    private static func orgIdKey(_ account: ClaudeAccount) -> String { account.keyPrefix + "orgId" }

    /// Stores the key only after claude.ai accepts it, so a bad paste can't replace a working session.
    static func signIn(_ account: ClaudeAccount, sessionKey: String) async throws {
        if sessionKey == Keychain.get(sessionKeyKey(account.other)) {
            throw ClientError.sameAccount
        }
        let orgId = try await fetchOrgId(sessionKey: sessionKey)
        Keychain.set(sessionKey, for: sessionKeyKey(account))
        Keychain.set(orgId, for: orgIdKey(account))
    }

    static func clear(_ account: ClaudeAccount = .primary) {
        Keychain.remove(sessionKeyKey(account))
        Keychain.remove(orgIdKey(account))
    }

    private static func fetchOrgId(sessionKey: String) async throws -> String {
        let req = request(url: URL(string: "https://claude.ai/api/organizations")!, sessionKey: sessionKey)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClientError.unauthorized
        }
        let orgs = try JSONDecoder().decode([OrgListItem].self, from: data)
        guard let org = orgs.first(where: \.isPaid) ?? orgs.first else { throw ClientError.noOrg }
        return org.uuid
    }

    static func fetchUsage(_ account: ClaudeAccount = .primary) async throws -> RemoteUsage {
        guard let sessionKey = Keychain.get(sessionKeyKey(account)) else {
            throw ClientError.unauthorized
        }
        let orgId: String
        if let stored = Keychain.get(orgIdKey(account)) {
            orgId = stored
        } else {
            orgId = try await fetchOrgId(sessionKey: sessionKey)
            Keychain.set(orgId, for: orgIdKey(account))
        }
        let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!
        let (data, response) = try await URLSession.shared.data(for: request(url: url, sessionKey: sessionKey))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClientError.unauthorized
        }
        return try JSONDecoder().decode(RemoteUsage.self, from: data)
    }

    private static func request(url: URL, sessionKey: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue("ClaudeStats/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    enum ClientError: Error, LocalizedError {
        case unauthorized, noOrg, sameAccount
        var errorDescription: String? {
            switch self {
            case .unauthorized: "Not signed in or session expired"
            case .noOrg: "No organization found on this account"
            case .sameAccount: "This is the same session as your other Claude account. Sign out of claude.ai first, then sign in with the other account."
            }
        }
    }
}
