@testable import HomeAssistant
import XCTest

/// Coming back to the app must not drag an auth proxy's sign-in page (Cloudflare Access, Authelia, SSO)
/// onto the server's host: that broke the login mid-flow with "Invalid login session".
final class WebViewControllerForeignPageTests: XCTestCase {
    private let servers = [
        URL(string: "https://ha.example.net")!,
        URL(string: "http://192.168.1.10:8123")!,
    ]

    func testCloudflareAccessLoginIsForeign() {
        let url = URL(string: "https://team.cloudflareaccess.com/cdn-cgi/access/verify-code/ha.example.net?kid=1")
        XCTAssertTrue(WebViewController.isOnForeignPage(currentURL: url, serverURLs: servers, lastLoadedIdentity: "ha.example.net:443"))
    }

    func testServerHostsAreNotForeign() {
        XCTAssertFalse(WebViewController.isOnForeignPage(
            currentURL: URL(string: "https://ha.example.net/lovelace/0"), serverURLs: servers, lastLoadedIdentity: nil
        ))
        // Switching internal <-> external still reloads onto the active URL.
        XCTAssertFalse(WebViewController.isOnForeignPage(
            currentURL: URL(string: "http://192.168.1.10:8123/lovelace"), serverURLs: servers, lastLoadedIdentity: nil
        ))
    }

    func testHostWeLoadedOurselvesIsNotForeign() {
        // e.g. the server's URL was edited in settings: the old host must still be replaced.
        XCTAssertFalse(WebViewController.isOnForeignPage(
            currentURL: URL(string: "https://old.example.net/"), serverURLs: servers, lastLoadedIdentity: "old.example.net:443"
        ))
    }

    func testNonWebAndEmptyURLsAreNotForeign() {
        XCTAssertFalse(WebViewController.isOnForeignPage(currentURL: nil, serverURLs: servers, lastLoadedIdentity: nil))
        XCTAssertFalse(WebViewController.isOnForeignPage(
            currentURL: URL(string: "about:blank"), serverURLs: servers, lastLoadedIdentity: nil
        ))
    }
}
