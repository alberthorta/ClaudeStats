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
}

enum ClaudeAIClient {
    static let sessionKeyKey = "claudeai.sessionKey"
    static let orgIdKey = "claudeai.orgId"

    static var hasSession: Bool { Keychain.get(sessionKeyKey) != nil }

    static func storeSessionKey(_ value: String) {
        Keychain.set(value, for: sessionKeyKey)
    }

    static func storeOrgId(_ value: String) {
        Keychain.set(value, for: orgIdKey)
    }

    static func clear() {
        Keychain.remove(sessionKeyKey)
        Keychain.remove(orgIdKey)
    }

    static func fetchOrgId() async throws -> String {
        let req = try authedRequest(url: URL(string: "https://claude.ai/api/organizations")!)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClientError.unauthorized
        }
        let orgs = try JSONDecoder().decode([OrgListItem].self, from: data)
        guard let first = orgs.first else { throw ClientError.noOrg }
        return first.uuid
    }

    static func fetchUsage() async throws -> RemoteUsage {
        let orgId: String
        if let stored = Keychain.get(orgIdKey) {
            orgId = stored
        } else {
            orgId = try await fetchOrgId()
            Keychain.set(orgId, for: orgIdKey)
        }
        let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!
        let req = try authedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClientError.unauthorized
        }
        return try JSONDecoder().decode(RemoteUsage.self, from: data)
    }

    private static func authedRequest(url: URL) throws -> URLRequest {
        guard let sessionKey = Keychain.get(sessionKeyKey) else {
            throw ClientError.unauthorized
        }
        var req = URLRequest(url: url)
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue("ClaudeStats/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    enum ClientError: Error, LocalizedError {
        case unauthorized, noOrg
        var errorDescription: String? {
            switch self {
            case .unauthorized: "Not signed in or session expired"
            case .noOrg: "No organization found on this account"
            }
        }
    }
}
