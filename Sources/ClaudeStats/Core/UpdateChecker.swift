import Foundation

struct LatestRelease {
    let tag: String                  // e.g. "v0.1"
    let normalizedVersion: String    // e.g. "0.1"
    let htmlURL: URL
    let downloadURL: URL?            // first .zip asset, if any
    let publishedAt: String?
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(current: String, latest: String)
    case updateAvailable(latest: LatestRelease)
    case failed(String)

    static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking): return true
        case let (.upToDate(a, b), .upToDate(c, d)): return a == c && b == d
        case let (.updateAvailable(a), .updateAvailable(b)): return a.tag == b.tag
        case let (.failed(a), .failed(b)): return a == b
        default: return false
        }
    }
}

enum UpdateChecker {
    static let repoSlug = "alberthorta/ClaudeStats"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func check() async -> UpdateStatus {
        do {
            let release = try await fetchLatest()
            let cmp = compareVersions(currentVersion, release.normalizedVersion)
            if cmp < 0 {
                return .updateAvailable(latest: release)
            } else {
                return .upToDate(current: currentVersion, latest: release.normalizedVersion)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func fetchLatest() async throws -> LatestRelease {
        let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ClaudeStats", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "GitHub", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        let decoded = try JSONDecoder().decode(GHRelease.self, from: data)
        let normalized = decoded.tag_name.hasPrefix("v") ? String(decoded.tag_name.dropFirst()) : decoded.tag_name
        let downloadURL = decoded.assets.first { $0.name.hasSuffix(".zip") }
            .flatMap { URL(string: $0.browser_download_url) }
        guard let html = URL(string: decoded.html_url) else { throw URLError(.badURL) }
        return LatestRelease(
            tag: decoded.tag_name,
            normalizedVersion: normalized,
            htmlURL: html,
            downloadURL: downloadURL,
            publishedAt: decoded.published_at
        )
    }

    /// Returns -1 if a < b, 0 if equal, 1 if a > b. Pads short versions with zeros.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return -1 }
            if x > y { return 1 }
        }
        return 0
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let html_url: String
        let published_at: String?
        let assets: [GHAsset]
    }

    private struct GHAsset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
