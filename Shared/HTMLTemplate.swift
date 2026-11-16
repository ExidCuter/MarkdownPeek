import Foundation

/// Wraps rendered Markdown in a standalone HTML page with GitHub styling.
enum HTMLTemplate {
    private static let markdownLight = ResourceBundle.string("github-markdown-light", "css")
    private static let markdownDark = ResourceBundle.string("github-markdown-dark", "css")
    private static let hljsLight = ResourceBundle.string("hljs-github", "css")
    private static let hljsDark = ResourceBundle.string("hljs-github-dark", "css")

    /// Scripts are blocked twice: the web view disables JavaScript, and this CSP forbids it.
    static let contentSecurityPolicy =
        "default-src 'none'; img-src data: file: https: http:; media-src data: file: https:; style-src 'unsafe-inline'; font-src data:"

    static func document(body: String, title: String, settings: PreviewSettings, mode: MarkdownRenderer.Mode) -> String {
        let theme: PreviewSettings.Theme = (mode == .thumbnail) ? .light : settings.theme
        let colorScheme: String
        let themeCSS: String
        switch theme {
        case .light:
            colorScheme = "light"
            themeCSS = lightCSS
        case .dark:
            colorScheme = "dark"
            themeCSS = darkCSS
        case .auto:
            colorScheme = "light dark"
            themeCSS = "@media (prefers-color-scheme: light) {\n\(lightCSS)\n}\n@media (prefers-color-scheme: dark) {\n\(darkCSS)\n}"
        }

        let fontSize = mode == .thumbnail ? 16 : Int(settings.fontSize.rounded())
        let maxWidth = mode == .thumbnail ? "none" : settings.contentWidth.css
        let padding = mode == .thumbnail ? "40px 48px" : "32px 40px 48px"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\(colorScheme)">
        <title>\(HTML.escape(title))</title>
        <style>
        \(themeCSS)
        </style>
        <style>
        :root { --mp-font-size: \(fontSize)px; --mp-max-width: \(maxWidth); --mp-padding: \(padding); }
        \(baseCSS)
        \(mode == .thumbnail ? thumbnailCSS : "")
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private static let lightCSS = """
    \(markdownLight)
    \(hljsLight)
    html, body { background-color: #ffffff; }
    .markdown-body .front-matter { background-color: #f6f8fa; border-color: #d1d9e0; }
    """

    private static let darkCSS = """
    \(markdownDark)
    \(hljsDark)
    html, body { background-color: #0d1117; }
    .markdown-body .front-matter { background-color: #151b23; border-color: #3d444d; }
    """

    private static let baseCSS = """
    html, body { margin: 0; padding: 0; }
    .markdown-body {
      box-sizing: border-box;
      max-width: var(--mp-max-width);
      margin: 0 auto;
      padding: var(--mp-padding);
      font-size: var(--mp-font-size);
    }
    .markdown-body .hljs { background: transparent; color: inherit; }
    .markdown-body pre code.hljs { padding: 0; overflow: visible; display: inline; }
    .markdown-body li:has(> input[type=checkbox]) { list-style-type: none; }
    .markdown-body li > input[type=checkbox] { margin: 0 0.2em 0.25em -1.4em; vertical-align: middle; }
    .markdown-body li:has(> p > input[type=checkbox]) { list-style-type: none; }
    .markdown-body li > p > input[type=checkbox] { margin: 0 0.2em 0.25em -1.4em; vertical-align: middle; }
    .markdown-body .front-matter {
      border-width: 1px; border-style: solid; border-radius: 6px; margin-bottom: 16px; padding: 4px 12px;
    }
    .markdown-body .front-matter summary {
      cursor: pointer; font-size: 85%; font-weight: 600; opacity: 0.7; padding: 4px 0;
    }
    .markdown-body .front-matter pre { margin: 4px 0 8px; padding: 8px 0; background: transparent; }
    .markdown-body img { background-color: transparent; }
    @media (max-width: 600px) { .markdown-body { padding: 16px; } }
    """

    private static let thumbnailCSS = """
    html, body { overflow: hidden; }
    .markdown-body pre { white-space: pre-wrap; }
    """
}
