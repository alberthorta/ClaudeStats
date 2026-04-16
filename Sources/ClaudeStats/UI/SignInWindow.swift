import SwiftUI
import WebKit
import AppKit
import AuthenticationServices

// MARK: - WKWebView-based sign-in (email login)

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
    @State private var status: String = "Sign in with your email account"

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
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
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

// MARK: - ASWebAuthenticationSession-based sign-in (Google login)

final class GoogleSignInHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleSignInHelper()
    private var session: ASWebAuthenticationSession?
    private var pollTimer: Timer?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    @MainActor
    func start(onComplete: @escaping (Result<String, Error>) -> Void) {
        // Use ASWebAuthenticationSession which opens a real Safari sheet.
        // Google allows OAuth here because it's not an embedded WKWebView.
        // We use a dummy callback scheme — the session stays open until
        // the user closes it or we cancel it after detecting the cookie.
        let session = ASWebAuthenticationSession(
            url: URL(string: "https://claude.ai/login")!,
            callbackURLScheme: "claudestats"
        ) { [weak self] _, error in
            // Session was dismissed (user closed it or we cancelled it).
            // Check if the cookie made it into shared HTTPCookieStorage.
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil

            if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://claude.ai")!),
               let sk = cookies.first(where: { $0.name == "sessionKey" }) {
                onComplete(.success(sk.value))
                return
            }

            // Cookie not in shared storage — user needs to paste manually.
            if let error, (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                onComplete(.failure(GoogleSignInError.needsManualPaste))
            } else {
                onComplete(.failure(GoogleSignInError.needsManualPaste))
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self
        self.session = session

        // Poll HTTPCookieStorage while the session is active — if the cookie
        // appears we can auto-cancel the session and complete immediately.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://claude.ai")!),
               let sk = cookies.first(where: { $0.name == "sessionKey" }) {
                self?.pollTimer?.invalidate()
                self?.pollTimer = nil
                self?.session?.cancel()
                self?.session = nil
                onComplete(.success(sk.value))
            }
        }

        session.start()
    }

    enum GoogleSignInError: LocalizedError {
        case needsManualPaste

        var errorDescription: String? {
            "Google login completed but the cookie couldn't be captured automatically. Please paste your sessionKey manually below."
        }
    }
}
