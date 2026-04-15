import Foundation
import AppKit

enum UpdateInstaller {
    enum InstallError: LocalizedError {
        case noZip, downloadFailed(Int), unzipFailed, noAppInZip
        var errorDescription: String? {
            switch self {
            case .noZip: "Release has no .zip asset"
            case .downloadFailed(let s): "Download failed (HTTP \(s))"
            case .unzipFailed: "Couldn't unzip the downloaded archive"
            case .noAppInZip: "Downloaded archive doesn't contain a .app bundle"
            }
        }
    }

    static func installAndRestart(release: LatestRelease) async throws {
        guard let downloadURL = release.downloadURL else { throw InstallError.noZip }

        let cache = try cacheDir()
        let zipURL = cache.appendingPathComponent("ClaudeStats-\(release.normalizedVersion).zip")
        let stageDir = cache.appendingPathComponent("staged-\(release.normalizedVersion)", isDirectory: true)

        try? FileManager.default.removeItem(at: stageDir)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        // 1. Download
        let (tmp, response) = try await URLSession.shared.download(from: downloadURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InstallError.downloadFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try? FileManager.default.removeItem(at: zipURL)
        try FileManager.default.moveItem(at: tmp, to: zipURL)

        // 2. Unzip via /usr/bin/ditto (handles macOS .app bundles correctly)
        try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, stageDir.path])

        // 3. Find the .app inside the staged directory
        let stagedApp = try findAppBundle(in: stageDir)

        // 4. Write a helper script that swaps the bundle once we exit
        let destApp = URL(fileURLWithPath: Bundle.main.bundlePath)
        let pid = ProcessInfo.processInfo.processIdentifier
        let logURL = cache.appendingPathComponent("update.log")
        let helperURL = cache.appendingPathComponent("install.sh")

        let script = """
        #!/bin/bash
        set -e
        exec >> "\(logURL.path)" 2>&1
        echo "[$(date)] waiting for PID \(pid) to exit"
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        echo "[$(date)] replacing \(destApp.path)"
        rm -rf "\(destApp.path)"
        cp -R "\(stagedApp.path)" "\(destApp.path)"
        codesign --force --deep --sign - "\(destApp.path)" || true
        xattr -dr com.apple.quarantine "\(destApp.path)" || true
        echo "[$(date)] launching"
        open "\(destApp.path)"
        """

        try script.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)

        // 5. Spawn detached and quit
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [helperURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private static func cacheDir() throws -> URL {
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("ClaudeStats", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func findAppBundle(in dir: URL) throws -> URL {
        let fm = FileManager.default
        if let direct = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        // Search one level deeper
        if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for sub in entries where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let nested = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "app" }) {
                    return nested
                }
            }
        }
        throw InstallError.noAppInZip
    }

    private static func runProcess(_ launch: String, _ args: [String]) throws {
        let p = Process()
        p.launchPath = launch
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw InstallError.unzipFailed }
    }
}
