import Foundation
import JavaScriptCore

/// Runs highlight.js inside JavaScriptCore so highlighting happens before the
/// HTML reaches the web view, which can then run with JavaScript disabled.
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    /// Blocks larger than this are shown unhighlighted to keep previews fast.
    static let maxCodeLength = 200_000

    private let queue = DispatchQueue(label: "com.markdownpeek.highlighter")
    private var context: JSContext?
    private var highlightFunction: JSValue?
    private var didLoad = false

    private init() {}

    /// Returns highlighted HTML for `code`, or nil if the language is unknown
    /// or highlighting failed (caller should fall back to escaped text).
    func highlight(_ code: String, language: String) -> String? {
        guard code.utf16.count <= Self.maxCodeLength, !language.isEmpty else { return nil }
        return queue.sync {
            loadIfNeeded()
            guard let fn = highlightFunction,
                  let result = fn.call(withArguments: [code, language]),
                  result.isString else { return nil }
            return result.toString()
        }
    }

    func supports(language: String) -> Bool {
        queue.sync {
            loadIfNeeded()
            guard let ctx = context,
                  let fn = ctx.objectForKeyedSubscript("__mpHasLanguage"),
                  let result = fn.call(withArguments: [language]) else { return false }
            return result.toBool()
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let url = ResourceBundle.url(forResource: "highlight.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let ctx = JSContext() else { return }
        ctx.exceptionHandler = { _, _ in }
        ctx.evaluateScript("var console = { log(){}, warn(){}, error(){}, info(){}, debug(){} };")
        ctx.evaluateScript(source, withSourceURL: url)
        ctx.evaluateScript("""
            function __mpHasLanguage(lang) { return !!hljs.getLanguage(lang); }
            function __mpHighlight(code, lang) {
              if (!hljs.getLanguage(lang)) return null;
              try { return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value; }
              catch (e) { return null; }
            }
            """)
        guard let fn = ctx.objectForKeyedSubscript("__mpHighlight"), !fn.isUndefined else { return }
        context = ctx
        highlightFunction = fn
    }
}

/// Locates bundled resources whether the shared code is compiled into the app,
/// an extension, or the unit-test bundle.
enum ResourceBundle {
    private final class Token {}
    static let bundle = Bundle(for: Token.self)

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }

    static func string(_ name: String, _ ext: String) -> String {
        guard let url = url(forResource: name, withExtension: ext) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
