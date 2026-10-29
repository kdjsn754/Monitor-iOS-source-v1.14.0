import Foundation

/// Starts a harmless Bonjour browse so iOS shows its Local Network permission
/// prompt before the first SSH connection is attempted.
final class LocalNetworkPermission: NSObject, NetServiceBrowserDelegate {
    static let shared = LocalNetworkPermission()

    private var browser: NetServiceBrowser?
    private var started = false

    func request() {
        guard !started else { return }
        started = true
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_ssh._tcp.", inDomain: "local.")
        self.browser = browser
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didNotSearch errorDict: [String: NSNumber]) {
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didRemove service: NetService,
                           moreComing: Bool) {
    }
}
