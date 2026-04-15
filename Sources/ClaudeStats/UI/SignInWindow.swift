import SwiftUI
import WebKit
import AppKit

enum SignInWindowController {
    private static var window: NSWindow?

    @MainActor
    static func present(onCaptured: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SignInView(onCaptured: {
            onCaptured()
            close()
        })

        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Sign in to Claude.ai"
        win.setContentSize(NSSize(width: 520, height: 700))
        win.styleMask = [.titled, .closable, .resizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    @MainActor
    static func close() {
        window?.close()
        window = nil
    }
}

private struct SignInView: View {
    let onCaptured: () -> Void
    @State private var status: String = "Sign in with email — Google may refuse embedded windows"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.shield")
                Text(status)
                    .font(.caption)
                Spacer()
            }
            .padding(10)
            .background(.regularMaterial)

            ClaudeWebView(onSessionCaptured: { key in
                Task { @MainActor in
                    ClaudeAIClient.storeSessionKey(key)
                    status = "Captured — fetching organization…"
                    do {
                        let orgId = try await ClaudeAIClient.fetchOrgId()
                        ClaudeAIClient.storeOrgId(orgId)
                        status = "Done"
                        onCaptured()
                    } catch {
                        status = "Signed in, but org fetch failed: \(error.localizedDescription)"
                    }
                }
            })
        }
    }
}

private struct ClaudeWebView: NSViewRepresentable {
    let onSessionCaptured: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        startPolling(webView: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptured: onSessionCaptured)
    }

    private func startPolling(webView: WKWebView, coordinator: Coordinator) {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                if let sk = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") }),
                   !coordinator.captured {
                    coordinator.captured = true
                    coordinator.onCaptured(sk.value)
                }
            }
        }
        coordinator.timer = timer
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var captured = false
        var timer: Timer?
        let onCaptured: (String) -> Void
        init(onCaptured: @escaping (String) -> Void) { self.onCaptured = onCaptured }
        deinit { timer?.invalidate() }
    }
}
