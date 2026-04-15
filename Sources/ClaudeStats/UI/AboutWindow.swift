import SwiftUI
import AppKit

enum AboutWindowController {
    private static var window: NSWindow?

    @MainActor
    static func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "About ClaudeStats"
        win.setContentSize(NSSize(width: 360, height: 420))
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 4) {
                Text("ClaudeStats")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("Version \(UpdateChecker.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.horizontal, 40)

            VStack(spacing: 8) {
                row(label: "Author", value: "Albert Horta Llobet")
                linkRow(label: "Email", text: "albert@horta.name", url: URL(string: "mailto:albert@horta.name")!)
                linkRow(label: "Project", text: "alberthorta.github.io/ClaudeStats", url: URL(string: "https://alberthorta.github.io/ClaudeStats")!)
                linkRow(label: "License", text: "MIT", url: URL(string: "https://github.com/alberthorta/ClaudeStats/blob/main/LICENSE")!)
            }
            .font(.callout)

            Spacer()

            Text("\u{00A9} 2026 Albert Horta")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 360, height: 420)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
            Spacer()
        }
    }

    private func linkRow(label: String, text: String, url: URL) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Link(text, destination: url)
            Spacer()
        }
    }
}
