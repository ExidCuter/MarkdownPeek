import XCTest

final class MarkdownRendererTests: XCTestCase {
    private let renderer = MarkdownRenderer()

    private func body(_ md: String, dir: URL? = nil, settings: PreviewSettings = .default) -> String {
        MarkdownRenderer(settings: settings).renderBody(markdown: md, baseDirectory: dir)
    }

    func testTable() {
        let html = body("| a | b |\n|:-|-:|\n| 1 | 2 |\n")
        XCTAssertTrue(html.contains("<table>"), html)
        XCTAssertTrue(html.contains("<th align=\"left\">a</th>"), html)
        XCTAssertTrue(html.contains("<td align=\"right\">2</td>"), html)
    }

    func testTaskListStrikethroughAutolink() {
        let html = body("- [x] done\n- [ ] todo\n\n~~gone~~ https://example.com\n")
        XCTAssertTrue(html.contains("type=\"checkbox\""), html)
        XCTAssertTrue(html.contains("checked"), html)
        XCTAssertTrue(html.contains("<del>gone</del>"), html)
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">"), html)
    }

    func testFootnote() {
        let html = body("Text[^n].\n\n[^n]: The note.\n")
        XCTAssertTrue(html.contains("class=\"footnotes\""), html)
        XCTAssertTrue(html.contains("The note."), html)
    }

    func testHighlightedCodeBlock() {
        let html = body("```swift\nlet x = 1\n```\n")
        XCTAssertTrue(html.contains("<code class=\"hljs language-swift\">"), html)
        XCTAssertTrue(html.contains("<span class=\"hljs-keyword\">let</span>"), html)
    }

    func testUnknownLanguageAndNoLanguageAreEscaped() {
        let unknown = body("```nosuchlang\n<b>&</b>\n```\n")
        XCTAssertTrue(unknown.contains("<code class=\"language-nosuchlang\">&lt;b&gt;&amp;&lt;/b&gt;"), unknown)
        let plain = body("```\n<i>\n```\n")
        XCTAssertTrue(plain.contains("<pre><code>&lt;i&gt;"), plain)
    }

    func testHighlightingCanBeDisabled() {
        var s = PreviewSettings.default
        s.highlightCode = false
        let html = body("```swift\nlet x = 1\n```\n", settings: s)
        XCTAssertFalse(html.contains("hljs-keyword"), html)
        XCTAssertTrue(html.contains("<code class=\"language-swift\">let x = 1"), html)
    }

    func testFrontMatter() {
        let md = "---\ntitle: Hi\ntags: [a]\n---\n# Heading\n"
        let (fm, rest) = MarkdownRenderer.splitFrontMatter(md)
        XCTAssertEqual(fm, "title: Hi\ntags: [a]")
        XCTAssertEqual(rest, "# Heading\n")

        let shown = body(md)
        XCTAssertTrue(shown.contains("class=\"front-matter\""), shown)
        XCTAssertTrue(shown.contains("language-yaml"), shown)

        var s = PreviewSettings.default
        s.showFrontMatter = false
        let hidden = body(md, settings: s)
        XCTAssertFalse(hidden.contains("front-matter"), hidden)
        XCTAssertFalse(hidden.contains("title"), hidden)
    }

    func testThematicBreakIsNotFrontMatter() {
        let md = "---\nJust a paragraph\n---\n"
        XCTAssertNil(MarkdownRenderer.splitFrontMatter(md).frontMatter)
    }

    func testHeadingIDs() {
        let html = body("# Hello, World!\n## Hello World\n## Hello World\n### `code` & *more*\n")
        XCTAssertTrue(html.contains("<h1 id=\"hello-world\">"), html)
        XCTAssertTrue(html.contains("<h2 id=\"hello-world-1\">"), html)
        XCTAssertTrue(html.contains("<h2 id=\"hello-world-2\">"), html)
        XCTAssertTrue(html.contains("<h3 id=\"code--more\">"), html)
    }

    func testRelativeImageIsInlined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("img dir"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try png.write(to: dir.appendingPathComponent("img dir/pic.png"))

        let html = body("![alt](<img dir/pic.png>)\n\n<img src=\"img dir/pic.png\" width=\"10\">\n\n![remote](https://example.com/x.png)\n", dir: dir)
        let expected = "data:image/png;base64,\(png.base64EncodedString())"
        XCTAssertEqual(html.components(separatedBy: expected).count - 1, 2, html)
        XCTAssertTrue(html.contains("src=\"https://example.com/x.png\""), html)
    }

    func testMissingImageLeftAlone() {
        let html = body("![x](nope.png)\n", dir: FileManager.default.temporaryDirectory)
        XCTAssertTrue(html.contains("src=\"nope.png\""), html)
    }

    func testDangerousHTMLIsNeutralised() {
        let html = body("<script>alert(1)</script>\n\n<iframe src=x></iframe>\n")
        XCTAssertFalse(html.contains("<script"), html)
        XCTAssertFalse(html.contains("<iframe"), html)
    }

    func testDocumentHasCSPAndTheme() {
        var s = PreviewSettings.default
        s.theme = .dark
        s.fontSize = 18
        let doc = MarkdownRenderer(settings: s).renderDocument(markdown: "# Hi", baseDirectory: nil, title: "t.md")
        XCTAssertTrue(doc.contains("Content-Security-Policy"), doc)
        XCTAssertTrue(doc.contains("default-src 'none'"))
        XCTAssertTrue(doc.contains("--mp-font-size: 18px"))
        XCTAssertTrue(doc.contains("content=\"dark\""))
        XCTAssertTrue(doc.contains(".markdown-body"), "github-markdown-css should be bundled")
        XCTAssertFalse(doc.contains("prefers-color-scheme: light"))
    }

    func testAutoThemeIncludesBothSchemes() {
        let doc = renderer.renderDocument(markdown: "x", baseDirectory: nil, title: "t")
        XCTAssertTrue(doc.contains("@media (prefers-color-scheme: light)"))
        XCTAssertTrue(doc.contains("@media (prefers-color-scheme: dark)"))
    }

    func testSampleFileRenders() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/sample.md")
        let doc = try renderer.renderDocument(fileURL: url)
        XCTAssertTrue(doc.contains("<table>"))
        XCTAssertTrue(doc.contains("hljs-keyword"))
        XCTAssertTrue(doc.contains("data:image/png;base64,"))
        XCTAssertTrue(doc.contains("id=\"syntax-highlighting\""))
    }

    func testLegacyEncodingFallback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "# Café".data(using: .isoLatin1)!.write(to: url)
        let text = try MarkdownRenderer.readText(at: url)
        XCTAssertTrue(text.hasPrefix("# Caf"))
        XCTAssertFalse(text.isEmpty)
    }
}
