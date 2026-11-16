import AppKit
import WebKit

enum WebViewFactory {
    /// A web view for untrusted Markdown: no JavaScript, no persistent storage.
    @MainActor
    static func make(frame: NSRect = .zero) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: frame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    /// True when `url` points at the currently loaded document (an in-page `#anchor`).
    static func isSameDocument(_ url: URL, as documentURL: URL?) -> Bool {
        guard let documentURL else { return false }
        func strip(_ u: URL) -> String {
            var c = URLComponents(url: u, resolvingAgainstBaseURL: true)
            c?.fragment = nil
            return c?.string ?? u.absoluteString
        }
        return strip(url) == strip(documentURL)
    }

    /// Opens links clicked in a preview with the system's default handler.
    static func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "file"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }
}
