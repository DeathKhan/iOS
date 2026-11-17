import Shared
import UIKit
import WebKit

// Sign-in pages served by a proxy in front of the server (Cloudflare Access, Authelia, oauth2-proxy, ...)
// and the identity providers they hand off to (Google, Apple, GitHub, Microsoft, ...).
//
// They are completed in this web view, not in an external browser or ASWebAuthenticationSession: the
// proxy's session cookie has to end up in this web view's cookie store, and only an https callback with
// an associated domain would let another browser hand it back, which a self-hosted server can't have.

extension WebViewController {
    /// Whether `url` is an http(s) page outside the server, i.e. a sign-in page the server or its proxy
    /// navigated us to. Same rules as `isOnForeignPage`.
    func isExternalSignInURL(_ url: URL?) -> Bool {
        Self.isOnForeignPage(
            currentURL: url,
            serverURLs: server.info.connection.configuredURLs,
            lastLoadedIdentity: lastLoadedHostAndPortIdentity
        )
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        overlayState?.isShowingExternalPage = isExternalSignInURL(webView.url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if Self.switchUserAgentIfNeeded(
            in: webView,
            for: navigationAction,
            returningToServer: !isExternalSignInURL(navigationAction.request.url)
        ) {
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    /// Presents a window opened by a sign-in page (`window.open`, `target=_blank`) in a sheet that shares
    /// this web view's configuration, so `window.opener`, cookies and the eventual redirect all stay in
    /// the app.
    func presentExternalSignInWindow(configuration: WKWebViewConfiguration) -> WKWebView {
        let controller = ExternalSignInWindowController(
            configuration: configuration,
            isServerURL: { [weak self] url in
                guard let self else { return false }
                return isServerPageURL(url)
            },
            onReturnToServer: { [weak self] request in
                self?.load(request: request)
            }
        )
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        (presentedViewController ?? self).present(navigation, animated: true)
        return controller.webView
    }

    /// Whether `url` is an http(s) page on the server, i.e. where a sign-in flow ends. `about:blank` and
    /// other non-web URLs a popup starts on are neither a sign-in page nor the server.
    func isServerPageURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return !isExternalSignInURL(url)
    }

    /// Hosts that refuse to sign in from an embedded web view based on its user agent
    /// (Google: "Error 403: disallowed_useragent").
    static let browserUserAgentHosts: Set<String> = ["accounts.google.com"]

    static func requiresBrowserUserAgent(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return browserUserAgentHosts.contains(host)
    }

    /// The Mobile Safari user agent for this device, without the app's own suffix.
    static func browserUserAgent(
        model: String = UIDevice.current.model,
        systemVersion: String = UIDevice.current.systemVersion
    ) -> String {
        let osVersion = systemVersion.replacingOccurrences(of: ".", with: "_")
        let safariVersion = systemVersion.split(separator: ".").prefix(2).joined(separator: ".")
        let platform = model.hasPrefix("iPad")
            ? "iPad; CPU OS \(osVersion) like Mac OS X"
            : "\(model.hasPrefix("iPod") ? "iPod touch" : "iPhone"); CPU iPhone OS \(osVersion) like Mac OS X"
        return "Mozilla/5.0 (\(platform)) AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }

    /// Switches `webView` to the browser user agent before it navigates to a host that requires one, and
    /// back to the app's own user agent before it returns to the server. Returns true when the navigation
    /// was cancelled and restarted with the new user agent (only done for GETs, which can be replayed).
    @discardableResult
    static func switchUserAgentIfNeeded(
        in webView: WKWebView,
        for navigationAction: WKNavigationAction,
        returningToServer: Bool
    ) -> Bool {
        guard navigationAction.targetFrame?.isMainFrame ?? true,
              (navigationAction.request.httpMethod ?? "GET").uppercased() == "GET",
              let url = navigationAction.request.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return false
        }
        let wanted: String?
        switch userAgentDecision(
            for: url,
            usingBrowserUserAgent: isUsingBrowserUserAgent(webView.customUserAgent),
            returningToServer: returningToServer
        ) {
        case .keep: return false
        case .useBrowser: wanted = browserUserAgent()
        case .useApp: wanted = nil
        }
        Current.Log.info("switching user agent for \(url.host ?? "?") to \(wanted == nil ? "app" : "browser")")
        webView.customUserAgent = wanted
        webView.load(navigationAction.request)
        return true
    }

    /// `customUserAgent` reads back as "" rather than nil when it was never set, so both mean the app's own.
    static func isUsingBrowserUserAgent(_ customUserAgent: String?) -> Bool {
        !(customUserAgent ?? "").isEmpty
    }

    enum UserAgentDecision: Equatable {
        case keep
        case useBrowser
        case useApp
    }

    static func userAgentDecision(
        for url: URL,
        usingBrowserUserAgent: Bool,
        returningToServer: Bool
    ) -> UserAgentDecision {
        if !usingBrowserUserAgent, requiresBrowserUserAgent(url) {
            return .useBrowser
        }
        if usingBrowserUserAgent, returningToServer {
            return .useApp
        }
        return .keep
    }
}

/// A window a sign-in page opened, shown as a sheet. Closes itself when the page calls `window.close()`
/// or navigates back to the server, which is then loaded in the frontend's own web view.
final class ExternalSignInWindowController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let isServerURL: (URL?) -> Bool
    private let onReturnToServer: (URLRequest) -> Void

    init(
        configuration: WKWebViewConfiguration,
        isServerURL: @escaping (URL?) -> Bool,
        onReturnToServer: @escaping (URLRequest) -> Void
    ) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.isServerURL = isServerURL
        self.onReturnToServer = onReturnToServer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        titleObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            self?.navigationItem.title = webView.url?.host
        }
    }

    private var titleObservation: NSKeyValueObservation?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame ?? true, isServerURL(navigationAction.request.url) {
            decisionHandler(.cancel, preferences)
            onReturnToServer(navigationAction.request)
            dismiss(animated: true)
            return
        }
        if WebViewController.switchUserAgentIfNeeded(in: webView, for: navigationAction, returningToServer: false) {
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // A sign-in popup opening another one: keep it in this sheet.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        dismiss(animated: true)
    }
}
