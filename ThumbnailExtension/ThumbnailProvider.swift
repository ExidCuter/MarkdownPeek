import AppKit
import OSLog
import QuickLookThumbnailing
import WebKit

/// Finder icon thumbnails: renders the top of the document as a page.
final class ThumbnailProvider: QLThumbnailProvider {
    private let log = Logger(subsystem: "com.markdownpeek", category: "thumbnail")
    /// Page proportions (width / height) of the thumbnail, roughly a sheet of paper.
    private static let pageAspect: CGFloat = 0.78
    private static let renderWidth: CGFloat = 800

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let html: String
        do {
            var settings = PreviewSettings.load()
            settings.showFrontMatter = false  // icons should show the document, not its metadata
            html = try MarkdownRenderer(settings: settings)
                .renderDocument(fileURL: request.fileURL, mode: .thumbnail)
        } catch {
            log.error("Render failed: \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
            return
        }

        let maxSize = request.maximumSize
        var contextSize = CGSize(width: maxSize.height * Self.pageAspect, height: maxSize.height)
        if contextSize.width > maxSize.width {
            contextSize = CGSize(width: maxSize.width, height: maxSize.width / Self.pageAspect)
        }
        let renderSize = CGSize(width: Self.renderWidth, height: (Self.renderWidth / Self.pageAspect).rounded())

        DispatchQueue.main.async {
            HTMLSnapshotter.snapshot(html: html, baseURL: request.fileURL, size: renderSize) { image in
                guard let image else {
                    self.log.error("Snapshot failed for \(request.fileURL.lastPathComponent, privacy: .public)")
                    handler(nil, ThumbnailError.renderFailed)
                    return
                }
                let reply = QLThumbnailReply(contextSize: contextSize, currentContextDrawing: { () -> Bool in
                    let rect = CGRect(origin: .zero, size: contextSize)
                    NSColor.white.setFill()
                    rect.fill()
                    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                    return true
                })
                reply.extensionBadge = "MD"
                self.log.info("Thumbnail ready for \(request.fileURL.lastPathComponent, privacy: .public)")
                handler(reply, nil)
            }
        }
    }
}

enum ThumbnailError: Error {
    case renderFailed
}

/// Loads HTML into an offscreen web view and snapshots it once.
@MainActor
final class HTMLSnapshotter: NSObject, WKNavigationDelegate {
    private static var active = Set<HTMLSnapshotter>()

    private let webView: WKWebView
    private let size: CGSize
    private var completion: ((NSImage?) -> Void)?
    private var timeout: Timer?

    static func snapshot(html: String, baseURL: URL, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let snapshotter = HTMLSnapshotter(size: size, completion: completion)
        active.insert(snapshotter)
        snapshotter.start(html: html, baseURL: baseURL)
    }

    private init(size: CGSize, completion: @escaping (NSImage?) -> Void) {
        self.size = size
        self.completion = completion
        self.webView = WebViewFactory.make(frame: NSRect(origin: .zero, size: size))
        super.init()
        webView.appearance = NSAppearance(named: .aqua)
        webView.navigationDelegate = self
    }

    private func start(html: String, baseURL: URL) {
        timeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func finish(_ image: NSImage?) {
        timeout?.invalidate()
        timeout = nil
        webView.navigationDelegate = nil
        completion?(image)
        completion = nil
        Self.active.remove(self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.snapshotWidth = NSNumber(value: Double(size.width))
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            MainActor.assumeIsolated { self?.finish(image) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the initial HTML load; never follow links in a thumbnail.
        decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
    }
}
