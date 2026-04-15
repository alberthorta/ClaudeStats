import Foundation

struct UsageEvent {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// Weighted to approximate Anthropic's billing/rate-limit accounting:
    /// cache reads ~10% of input cost, cache creation ~1.25× input cost.
    var billableTokens: Int {
        inputTokens
            + outputTokens
            + Int(Double(cacheReadTokens) * 0.10)
            + Int(Double(cacheCreationTokens) * 1.25)
    }
}

private struct AssistantLine: Decodable {
    let type: String?
    let timestamp: String?
    let message: AssistantMessage?
}

private struct AssistantMessage: Decodable {
    let model: String?
    let usage: Usage?
}

private struct Usage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
}

enum JsonlUsageReader {
    static var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    /// Stream every assistant usage event in JSONL files whose mtime is >= `since`.
    /// Returns events ordered by timestamp ascending.
    static func loadEvents(since: Date) -> [UsageEvent] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var events: [UsageEvent] = []
        events.reserveCapacity(4096)

        let decoder = JSONDecoder()
        let ts = ISO8601DateFormatter.flexible

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in files where url.pathExtension == "jsonl" {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if mod < since { continue }

                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let data = rawLine.data(using: .utf8),
                          let line = try? decoder.decode(AssistantLine.self, from: data),
                          line.type == "assistant",
                          let msg = line.message,
                          let model = msg.model,
                          let usage = msg.usage,
                          let tsString = line.timestamp,
                          let date = ts.date(from: tsString) ?? fallbackDate(tsString) else {
                        continue
                    }
                    if date < since { continue }
                    events.append(UsageEvent(
                        timestamp: date,
                        model: model,
                        inputTokens: usage.input_tokens ?? 0,
                        outputTokens: usage.output_tokens ?? 0,
                        cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                        cacheCreationTokens: usage.cache_creation_input_tokens ?? 0
                    ))
                }
            }
        }

        events.sort { $0.timestamp < $1.timestamp }
        return events
    }

    private static func fallbackDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
