import Foundation

/// ClaudeStats' own ChatGPT sign-in, separate from the one in ~/.codex/auth.json.
///
/// It is the device-code flow of `codex login --device-auth`, with the Codex CLI's
/// public client id. OpenAI's official "Sign in with ChatGPT" registration was tried
/// first: sign-in works, but chatgpt.com/backend-api/wham/usage answers 401 to its
/// tokens, so only a Codex token can read the plan limits.
/// Endpoints and fields follow openai/codex: codex-rs/login/src/device_code_auth.rs
/// and auth/manager.rs.
actor ChatGPTLogin {
    static let shared = ChatGPTLogin()

    static let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    private static let issuer = "https://auth.openai.com"

    private static let accessKey = "chatgpt.accessToken"
    private static let refreshKey = "chatgpt.refreshToken"
    private static let accountKey = "chatgpt.accountId"
    private static let emailKey = "chatgpt.email"

    struct Tokens {
        let accessToken: String
        let accountId: String?
    }

    struct DeviceCode {
        let deviceAuthId: String
        let userCode: String
        let interval: Double
    }

    static var isSignedIn: Bool { Keychain.get(refreshKey) != nil }
    static var email: String? { Keychain.get(emailKey) }

    static func signOut() {
        [accessKey, refreshKey, accountKey, emailKey].forEach(Keychain.remove)
    }

    // MARK: Device-code sign-in

    static func requestDeviceCode() async throws -> DeviceCode {
        let (data, status) = try await post(
            "\(issuer)/api/accounts/deviceauth/usercode",
            body: try JSONSerialization.data(withJSONObject: ["client_id": clientId]),
            contentType: "application/json")
        if status == 404 { throw LoginError.deviceCodeDisabled }
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["device_auth_id"] as? String,
              let code = (json["user_code"] ?? json["usercode"]) as? String
        else { throw status == 200 ? LoginError.unexpectedResponse : LoginError.http(status) }
        // The server sends the interval as a string.
        let interval = Double("\(json["interval"] ?? "")".trimmingCharacters(in: .whitespaces)) ?? 5
        return DeviceCode(deviceAuthId: id, userCode: code, interval: max(1, interval))
    }

    /// Polls until the code is approved in the browser, then stores the tokens.
    /// Codex gives up after 15 minutes, and so do we. Cancel the task to stop early.
    static func completeSignIn(_ code: DeviceCode) async throws {
        let deadline = Date().addingTimeInterval(15 * 60)
        while true {
            try await Task.sleep(for: .seconds(code.interval))
            let (data, status) = try await post(
                "\(issuer)/api/accounts/deviceauth/token",
                body: try JSONSerialization.data(withJSONObject: [
                    "device_auth_id": code.deviceAuthId,
                    "user_code": code.userCode,
                ]),
                contentType: "application/json")
            if status == 403 || status == 404 {
                if Date() > deadline { throw LoginError.timedOut }
                continue
            }
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let authCode = json["authorization_code"] as? String,
                  let verifier = json["code_verifier"] as? String
            else { throw LoginError.http(status) }
            try await exchange(authCode: authCode, verifier: verifier)
            return
        }
    }

    private static func exchange(authCode: String, verifier: String) async throws {
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code", value: authCode),
            URLQueryItem(name: "redirect_uri", value: "\(issuer)/deviceauth/callback"),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        // URLComponents leaves "+" alone, but a form decoder reads it as a space.
        let body = (form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        let (data, status) = try await post("\(issuer)/oauth/token", body: Data(body.utf8),
                                            contentType: "application/x-www-form-urlencoded")
        guard status == 200 else { throw LoginError.http(status) }
        try store(tokenResponse: data)
    }

    // MARK: Tokens

    /// Refreshes are serialized by the actor: OpenAI rotates the refresh token on
    /// every use, so two refreshes racing would end the session.
    func validTokens(forceRefresh: Bool = false) async throws -> Tokens {
        guard let access = Keychain.get(Self.accessKey) else { throw LoginError.signedOut }
        // Access tokens live about an hour; renew a little before that.
        let expiring = JWT.expiry(of: access).map { $0 < Date().addingTimeInterval(300) } ?? false
        if forceRefresh || expiring {
            try await refresh(replacing: access)
        }
        guard let current = Keychain.get(Self.accessKey) else { throw LoginError.signedOut }
        return Tokens(accessToken: current, accountId: Keychain.get(Self.accountKey))
    }

    private func refresh(replacing staleAccess: String) async throws {
        // Another caller may have refreshed while this one waited on the actor.
        if let current = Keychain.get(Self.accessKey), current != staleAccess { return }
        guard let refreshToken = Keychain.get(Self.refreshKey) else { throw LoginError.signedOut }
        // Codex sends the refresh grant as JSON, unlike the code exchange.
        let (data, status) = try await Self.post(
            "\(Self.issuer)/oauth/token",
            body: try JSONSerialization.data(withJSONObject: [
                "grant_type": "refresh_token",
                "client_id": Self.clientId,
                "refresh_token": refreshToken,
            ]),
            contentType: "application/json")
        if status == 400 || status == 401 {
            Self.signOut()
            throw LoginError.sessionEnded
        }
        guard status == 200 else { throw LoginError.http(status) }
        try Self.store(tokenResponse: data)
    }

    private static func store(tokenResponse data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { throw LoginError.unexpectedResponse }
        Keychain.set(access, for: accessKey)
        if let refresh = json["refresh_token"] as? String {
            Keychain.set(refresh, for: refreshKey)
        }
        if let idToken = json["id_token"] as? String {
            let claims = JWT.claims(of: idToken)
            let auth = claims["https://api.openai.com/auth"] as? [String: Any]
            if let account = auth?["chatgpt_account_id"] as? String {
                Keychain.set(account, for: accountKey)
            }
            if let email = claims["email"] as? String {
                Keychain.set(email, for: emailKey)
            }
        }
    }

    private static func post(_ url: String, body: Data, contentType: String) async throws -> (Data, Int) {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    enum LoginError: Error, LocalizedError {
        case signedOut, sessionEnded, timedOut, deviceCodeDisabled, unexpectedResponse, http(Int)
        var errorDescription: String? {
            switch self {
            case .signedOut: "Not signed in to ChatGPT"
            case .sessionEnded: "ChatGPT sign-in ended. Sign in again in Settings"
            case .timedOut: "The code expired before it was approved. Try again"
            case .deviceCodeDisabled: "OpenAI did not accept the device code sign-in"
            case .unexpectedResponse: "Unexpected answer from auth.openai.com"
            case .http(let code): "auth.openai.com returned HTTP \(code)"
            }
        }
    }
}

enum JWT {
    static func claims(of jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let payload = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return [:] }
        return json
    }

    static func expiry(of jwt: String) -> Date? {
        (claims(of: jwt)["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
    }
}
