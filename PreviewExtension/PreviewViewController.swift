import Cocoa
import OSLog
import Quartz
import WebKit

/// Quick Look preview (Space bar in Finder) for Markdown files.
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private let log = Logger(subsystem: "com.markdownpeek", category: "preview")
    private var webView: WKWebView!
    private var documentURL: URL?
    private var pendingHandler: ((Error?) -> Void)?
    private var fallbackTimer: Timer?

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let size = NSSize(width: 900, height: 1000)
        webView = WebViewFactory.make(frame: NSRect(origin: .zero, size: size))
        webView.navigationDelegate = self
        view = webView
        preferredContentSize = size
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let settings = PreviewSettings.load()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try MarkdownRenderer(settings: settings).renderDocument(fileURL: url) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let html):
                    self.log.info("Rendered \(url.lastPathComponent, privacy: .public) (\(html.utf8.count) bytes)")
                    self.show(html: html, fileURL: url, handler: handler)
                case .failure(let error):
                    self.log.error("Render failed: \(error.localizedDescription, privacy: .public)")
                    handler(error)
                }
            }
        }
    }

    private func show(html: String, fileURL: URL, handler: @escaping (Error?) -> Void) {
        _ = view  // ensure loadView ran
        documentURL = fileURL
        pendingHandler = handler
        // Reply once the page has painted, but never leave Quick Look waiting.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.finish(nil)
        }
        webView.loadHTMLString(html, baseURL: fileURL)
    }

    private func finish(_ error: Error?) {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        guard let handler = pendingHandler else { return }
        pendingHandler = nil
        handler(error)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.info("Page loaded")
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if WebViewFactory.isSameDocument(url, as: documentURL) {
            decisionHandler(.allow)  // in-page #anchor
        } else {
            WebViewFactory.openExternally(url)
            decisionHandler(.cancel)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Web content process terminated")
        finish(nil)
    }
}
