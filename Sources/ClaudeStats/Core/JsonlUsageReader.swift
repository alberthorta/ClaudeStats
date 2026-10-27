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

/// Claude Code appends to its JSONL logs and never rewrites them, so each file is parsed
/// once and later reads only pick up the bytes added since. Re-parsing ~1.5 GB every 30 s
/// took over 20 s per pass and froze the main thread.
/// Not thread-safe: use it from one serial queue.
final class JsonlUsageReader {
    static var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    private struct FileState {
        var offset: UInt64
        var events: [UsageEvent]
    }

    private var files: [URL: FileState] = [:]
    private let decoder = JSONDecoder()
    // Own instances: this runs off the main thread, which also uses the shared `.flexible`.
    private let ts: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let tsNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    // Most lines are prompts and tool results, often large. Skipping the ones without
    // usage before JSON decoding is where most of the time goes.
    private let usageNeedle = Data("\"usage\"".utf8)

    /// Every assistant usage event in JSONL files whose mtime is >= `since`, ordered by timestamp.
    func loadEvents(since: Date) -> [UsageEvent] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: Self.projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var seen = Set<URL>()
        var events: [UsageEvent] = []
        events.reserveCapacity(4096)

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mod = values?.contentModificationDate ?? .distantPast
                if mod < since { continue }
                let size = UInt64(values?.fileSize ?? 0)

                seen.insert(url)
                var state = files[url] ?? FileState(offset: 0, events: [])
                if size < state.offset { state = FileState(offset: 0, events: []) }
                // Without the pool, each file's bytes live until the whole pass ends (1.7 GB peak).
                if size > state.offset { autoreleasepool { read(url, into: &state) } }
                files[url] = state
                events.append(contentsOf: state.events.lazy.filter { $0.timestamp >= since })
            }
        }

        files = files.filter { seen.contains($0.key) }
        events.sort { $0.timestamp < $1.timestamp }
        return events
    }

    /// Parses the complete lines after `state.offset`. A trailing partial line is left for
    /// the next pass, since Claude Code may still be writing it.
    private func read(_ url: URL, into state: inout FileState) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: 0x0A) else { return }

        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard line.range(of: usageNeedle) != nil,
                  let parsed = try? decoder.decode(AssistantLine.self, from: line),
                  parsed.type == "assistant",
                  let msg = parsed.message,
                  let model = msg.model,
                  let usage = msg.usage,
                  let tsString = parsed.timestamp,
                  let date = ts.date(from: tsString) ?? tsNoFraction.date(from: tsString) else {
                continue
            }
            state.events.append(UsageEvent(
                timestamp: date,
                model: model,
                inputTokens: usage.input_tokens ?? 0,
                outputTokens: usage.output_tokens ?? 0,
                cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                cacheCreationTokens: usage.cache_creation_input_tokens ?? 0
            ))
        }
        state.offset += UInt64(complete.count)
    }
}
