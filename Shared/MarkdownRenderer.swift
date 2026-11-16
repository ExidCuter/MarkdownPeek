import Foundation
import UniformTypeIdentifiers
import cmark_gfm
import cmark_gfm_extensions

/// Converts a Markdown file into a self-contained HTML document:
/// GitHub-flavored Markdown via cmark-gfm, code highlighted ahead of time,
/// local images inlined as data URIs, headings given GitHub-style anchors.
struct MarkdownRenderer {
    enum Mode { case preview, thumbnail }

    var settings: PreviewSettings

    static let maxInlineImageBytes = 10 * 1024 * 1024
    static let maxTotalInlineBytes = 40 * 1024 * 1024

    init(settings: PreviewSettings = .default) {
        self.settings = settings
    }

    // MARK: - Public entry points

    func renderDocument(fileURL: URL, mode: Mode = .preview) throws -> String {
        let text = try Self.readText(at: fileURL)
        return renderDocument(markdown: text,
                              baseDirectory: fileURL.deletingLastPathComponent(),
                              title: fileURL.lastPathComponent,
                              mode: mode)
    }

    func renderDocument(markdown: String, baseDirectory: URL?, title: String, mode: Mode = .preview) -> String {
        let body = renderBody(markdown: markdown, baseDirectory: baseDirectory)
        return HTMLTemplate.document(body: body, title: title, settings: settings, mode: mode)
    }

    /// The `<article>` contents only (no template). Exposed for tests.
    func renderBody(markdown: String, baseDirectory: URL?) -> String {
        let (frontMatter, content) = Self.splitFrontMatter(markdown)
        var html = ""
        if let frontMatter, settings.showFrontMatter {
            html += "<details class=\"front-matter\" open><summary>Front matter</summary>\n"
            html += codeBlockHTML(frontMatter + "\n", language: "yaml")
            html += "</details>\n"
        }
        html += CMark.renderHTML(content) { code, language in
            codeBlockHTML(code, language: language)
        }
        html = Self.addHeadingIDs(html)
        if let baseDirectory {
            html = Self.inlineLocalImages(html, baseDirectory: baseDirectory)
        }
        return html
    }

    // MARK: - Code blocks

    func codeBlockHTML(_ code: String, language: String) -> String {
        let highlighted = (settings.highlightCode && !language.isEmpty)
            ? SyntaxHighlighter.shared.highlight(code, language: language)
            : nil
        var classes: [String] = []
        if highlighted != nil { classes.append("hljs") }
        if !language.isEmpty { classes.append("language-" + HTML.escapeAttribute(language)) }
        let classAttr = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
        return "<pre><code\(classAttr)>\(highlighted ?? HTML.escape(code))</code></pre>\n"
    }

    // MARK: - Input

    static func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            var used: UInt = 0
            if let detected = try? NSString(contentsOf: url, usedEncoding: &used) {
                text = detected as String
            } else {
                text = String(decoding: data, as: UTF8.self)
            }
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// Splits a leading YAML front matter block (`---` … `---`/`...`) from the body.
    static func splitFrontMatter(_ text: String) -> (frontMatter: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        let trim = CharacterSet(charactersIn: " \t\r")
        guard lines.count > 2, lines[0].trimmingCharacters(in: trim) == "---" else { return (nil, text) }
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: trim)
            guard line == "---" || line == "..." else { continue }
            let yamlLines = lines[1..<i].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            // Must look like YAML, otherwise it's just a thematic break.
            guard yamlLines.contains(where: { $0.range(of: #"^\s*[^\s#][^:]*:(\s|$)"#, options: .regularExpression) != nil })
            else { return (nil, text) }
            let body = lines[(i + 1)...].joined(separator: "\n")
            return (yamlLines.joined(separator: "\n"), body)
        }
        return (nil, text)
    }

    // MARK: - Heading anchors

    private static let headingRegex = try! NSRegularExpression(pattern: #"<h([1-6])>(.*?)</h\1>"#)

    static func addHeadingIDs(_ html: String) -> String {
        let ns = html as NSString
        var used: [String: Int] = [:]
        var out = ""
        var cursor = 0
        for match in headingRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let level = ns.substring(with: match.range(at: 1))
            let inner = ns.substring(with: match.range(at: 2))
            let base = slug(fromHTML: inner)
            var id = base
            if let n = used[base] {
                id = "\(base)-\(n)"
                used[base] = n + 1
            } else {
                used[base] = 1
            }
            out += "<h\(level) id=\"\(HTML.escapeAttribute(id))\">\(inner)</h\(level)>"
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// GitHub's anchor algorithm: lowercase, drop punctuation except `-`/`_`, spaces → `-`.
    static func slug(fromHTML html: String) -> String {
        let text = HTML.unescape(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .connectorPunctuation:
                scalars.append(scalar)
            default:
                if scalar == "-" { scalars.append(scalar) }
                else if scalar == " " { scalars.append("-") }
            }
        }
        return String(scalars)
    }

    // MARK: - Local images

    private static let imgRegex = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators])

    static func inlineLocalImages(_ html: String, baseDirectory: URL) -> String {
        let ns = html as NSString
        var out = ""
        var cursor = 0
        var budget = maxTotalInlineBytes
        for match in imgRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let srcRange = match.range(at: 3)
            out += ns.substring(with: NSRange(location: cursor, length: srcRange.location - cursor))
            let src = ns.substring(with: srcRange)
            if let fileURL = resolveLocalImage(src, baseDirectory: baseDirectory),
               let dataURI = dataURI(for: fileURL, budget: &budget) {
                out += dataURI
            } else {
                out += src
            }
            cursor = srcRange.location + srcRange.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    static func resolveLocalImage(_ src: String, baseDirectory: URL) -> URL? {
        let raw = HTML.unescape(src).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, !raw.hasPrefix("#"), !raw.hasPrefix("~") else { return nil }
        if let schemeEnd = raw.range(of: ":"),
           raw[..<schemeEnd.lowerBound].range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil {
            // Has a URL scheme: only file:// is local.
            guard raw.lowercased().hasPrefix("file:"), let url = URL(string: raw) else { return nil }
            return url.standardizedFileURL
        }
        var path = raw
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<cut]) }
        path = path.removingPercentEncoding ?? path
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return baseDirectory.appendingPathComponent(path).standardizedFileURL
    }

    static func dataURI(for fileURL: URL, budget: inout Int) -> String? {
        guard let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size > 0, size <= maxInlineImageBytes, size <= budget,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        budget -= data.count
        let ext = fileURL.pathExtension.lowercased()
        let mime = ext == "svg" ? "image/svg+xml"
            : (UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream")
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}

// MARK: - cmark-gfm

enum CMark {
    private static let registerExtensions: Void = { cmark_gfm_core_extensions_ensure_registered() }()
    static let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    /// Raw HTML is allowed (like GitHub) but dangerous tags are neutralised by
    /// `tagfilter`, and the web view runs with JavaScript disabled plus a CSP.
    static let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8

    /// Parses GFM and renders HTML. Every code block is replaced by the HTML
    /// returned from `codeBlock(code, language)`.
    static func renderHTML(_ markdown: String, codeBlock: (String, String) -> String) -> String {
        _ = registerExtensions
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        var source = markdown
        source.withUTF8 { buffer in
            buffer.withMemoryRebound(to: CChar.self) { chars in
                cmark_parser_feed(parser, chars.baseAddress, chars.count)
            }
        }
        guard let root = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(root) }

        var codeNodes: [UnsafeMutablePointer<cmark_node>] = []
        if let iter = cmark_iter_new(root) {
            while true {
                let event = cmark_iter_next(iter)
                if event == CMARK_EVENT_DONE { break }
                if event == CMARK_EVENT_ENTER,
                   let node = cmark_iter_get_node(iter),
                   cmark_node_get_type(node) == CMARK_NODE_CODE_BLOCK {
                    codeNodes.append(node)
                }
            }
            cmark_iter_free(iter)
        }

        for node in codeNodes {
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            let info = cmark_node_get_fence_info(node).map { String(cString: $0) } ?? ""
            let language = info
                .split(whereSeparator: { " \t{,".contains($0) })
                .first.map { String($0).lowercased() } ?? ""
            guard let replacement = cmark_node_new(CMARK_NODE_HTML_BLOCK) else { continue }
            cmark_node_set_literal(replacement, codeBlock(literal, language))
            if cmark_node_replace(node, replacement) != 0 {
                cmark_node_free(node)
            } else {
                cmark_node_free(replacement)
            }
        }

        guard let html = cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }
}

// MARK: - HTML escaping

enum HTML {
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }

    static func escapeAttribute(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
