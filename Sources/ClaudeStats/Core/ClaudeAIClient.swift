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
