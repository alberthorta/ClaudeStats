import Foundation

/// Response of chatgpt.com/backend-api/wham/usage, the endpoint the Codex CLI itself
/// polls for the subscription rate limits. It is not a public API, so every field is
/// optional and only what the app reads is modelled.
struct CodexUsage: Decodable {
    let planType: String?
    let rateLimit: RateLimit?

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Double?
        let resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }

        var usedFraction: Double? {
            usedPercent.map { max(0, min(1, $0 / 100)) }
        }

        var resetDate: Date? {
            resetAt.map { Date(timeIntervalSince1970: $0) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

/// Uses ClaudeStats' own ChatGPT sign-in when there is one, otherwise borrows the
/// sign-in of the Codex CLI. That file is read again on every request and never
/// copied: Codex rotates the tokens when it refreshes them, and refreshing them from
/// here would invalidate the copy Codex keeps.
enum CodexClient {
    enum Source { case ownSignIn, codexCLI }
    static let authURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")

    private struct AuthFile: Decodable {
        let authMode: String?
        let tokens: Tokens?

        struct Tokens: Decodable {
            let accessToken: String?
            let accountId: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case accountId = "account_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case authMode = "auth_mode"
            case tokens
        }
    }

    private struct Credentials {
        let accessToken: String
        let accountId: String?
    }

    /// The Codex CLI only counts when signed in with a ChatGPT account: API-key mode
    /// has no subscription windows.
    static var source: Source? {
        if ChatGPTLogin.isSignedIn { return .ownSignIn }
        return (try? codexCredentials()) != nil ? .codexCLI : nil
    }

    static func fetchUsage() async throws -> CodexUsage {
        guard ChatGPTLogin.isSignedIn else {
            let creds = try codexCredentials()
            if let exp = JWT.expiry(of: creds.accessToken), exp < Date() {
                throw ClientError.expired
            }
            return try await fetchUsage(with: creds)
        }
        let tokens = try await ChatGPTLogin.shared.validTokens()
        do {
            return try await fetchUsage(with: Credentials(accessToken: tokens.accessToken, accountId: tokens.accountId))
        } catch ClientError.expired {
            // The token can be revoked before its exp; one forced refresh tells the two apart.
            let renewed = try await ChatGPTLogin.shared.validTokens(forceRefresh: true)
            do {
                return try await fetchUsage(with: Credentials(accessToken: renewed.accessToken, accountId: renewed.accountId))
            } catch ClientError.expired {
                throw ClientError.rejected
            }
        }
    }

    private static func fetchUsage(with creds: Credentials) async throws -> CodexUsage {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = creds.accountId {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        req.setValue("ClaudeStats (macOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try JSONDecoder().decode(CodexUsage.self, from: data)
        case 401, 403: throw ClientError.expired
        default: throw ClientError.http(status)
        }
    }

    private static func codexCredentials() throws -> Credentials {
        guard let data = try? Data(contentsOf: authURL) else { throw ClientError.notFound }
        let auth = try JSONDecoder().decode(AuthFile.self, from: data)
        guard auth.authMode == "chatgpt", let token = auth.tokens?.accessToken, !token.isEmpty else {
            throw ClientError.notChatGPT
        }
        return Credentials(accessToken: token, accountId: auth.tokens?.accountId)
    }

    enum ClientError: Error, LocalizedError {
        case notFound, notChatGPT, expired, rejected, http(Int)
        var errorDescription: String? {
            switch self {
            case .notFound: "Codex is not signed in (~/.codex/auth.json not found)"
            case .notChatGPT: "Codex is not signed in with a ChatGPT account"
            case .expired: "Codex sign-in expired. Run codex once to refresh it"
            case .rejected: "chatgpt.com rejected the ChatGPT sign-in. Sign out and sign in again"
            case .http(let code): "chatgpt.com returned HTTP \(code)"
            }
        }
    }
}
