@testable import HomeAssistant
import XCTest

final class WebViewControllerExternalSignInTests: XCTestCase {
    private let google = URL(string: "https://accounts.google.com/o/oauth2/auth?client_id=x")!
    private let access = URL(string: "https://team.cloudflareaccess.com/cdn-cgi/access/login/ha.example.com")!
    private let server = URL(string: "https://ha.example.com/cdn-cgi/access/authorized?nonce=1")!

    func testGoogleSignInNeedsTheBrowserUserAgent() {
        XCTAssertTrue(WebViewController.requiresBrowserUserAgent(google))
        XCTAssertFalse(WebViewController.requiresBrowserUserAgent(access))
        XCTAssertFalse(WebViewController.requiresBrowserUserAgent(nil))
    }

    func testSwitchesToTheBrowserUserAgentForGoogle() {
        XCTAssertEqual(
            WebViewController.userAgentDecision(for: google, usingBrowserUserAgent: false, returningToServer: false),
            .useBrowser
        )
        XCTAssertEqual(
            WebViewController.userAgentDecision(for: google, usingBrowserUserAgent: true, returningToServer: false),
            .keep
        )
    }

    func testKeepsTheBrowserUserAgentThroughTheProxyAndDropsItBackOnTheServer() {
        XCTAssertEqual(
            WebViewController.userAgentDecision(for: access, usingBrowserUserAgent: true, returningToServer: false),
            .keep
        )
        XCTAssertEqual(
            WebViewController.userAgentDecision(for: server, usingBrowserUserAgent: true, returningToServer: true),
            .useApp
        )
    }

    func testLeavesOrdinaryNavigationAlone() {
        XCTAssertEqual(
            WebViewController.userAgentDecision(for: server, usingBrowserUserAgent: false, returningToServer: true),
            .keep
        )
        XCTAssertEqual(
            WebViewController.userAgentDecision(for: access, usingBrowserUserAgent: false, returningToServer: false),
            .keep
        )
    }

    func testBrowserUserAgentLooksLikeMobileSafari() {
        let phone = WebViewController.browserUserAgent(model: "iPhone", systemVersion: "18.6.2")
        XCTAssertEqual(
            phone,
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) " +
                "Version/18.6 Mobile/15E148 Safari/604.1"
        )
        let pad = WebViewController.browserUserAgent(model: "iPad", systemVersion: "18.0")
        XCTAssertTrue(pad.hasPrefix("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)"))
        XCTAssertFalse(phone.contains("Home Assistant"))
    }

    func testAnEmptyCustomUserAgentIsTheAppUserAgent() {
        // WKWebView.customUserAgent is "" (not nil) until set; treating that as the browser user agent made
        // every server navigation "switch back" to the app user agent and reload, forever.
        XCTAssertFalse(WebViewController.isUsingBrowserUserAgent(nil))
        XCTAssertFalse(WebViewController.isUsingBrowserUserAgent(""))
        XCTAssertTrue(WebViewController.isUsingBrowserUserAgent(WebViewController.browserUserAgent()))
    }
}
