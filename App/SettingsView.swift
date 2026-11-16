import SwiftUI
import WebKit

struct SettingsView: View {
    private static let store = PreviewSettings.store
    private typealias Keys = PreviewSettings.Keys

    @AppStorage(Keys.theme, store: store) private var theme: PreviewSettings.Theme = PreviewSettings.default.theme
    @AppStorage(Keys.fontSize, store: store) private var fontSize: Double = PreviewSettings.default.fontSize
    @AppStorage(Keys.contentWidth, store: store) private var contentWidth: PreviewSettings.ContentWidth = PreviewSettings.default.contentWidth
    @AppStorage(Keys.showFrontMatter, store: store) private var showFrontMatter = PreviewSettings.default.showFrontMatter
    @AppStorage(Keys.highlightCode, store: store) private var highlightCode = PreviewSettings.default.highlightCode

    private var settings: PreviewSettings {
        PreviewSettings(theme: theme, fontSize: fontSize, contentWidth: contentWidth,
                        showFrontMatter: showFrontMatter, highlightCode: highlightCode)
    }

    var body: some View {
        HSplitView {
            Form {
                Section("Quick Look") {
                    Label("Select a Markdown file in Finder and press Space.", systemImage: "eye")
                    Text("If Finder still shows plain text, turn on MarkdownPeek under System Settings › General › Login Items & Extensions › Quick Look.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Extension Settings…", action: openExtensionSettings)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        ForEach(PreviewSettings.Theme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Font size") {
                        HStack {
                            Slider(value: $fontSize, in: PreviewSettings.fontSizeRange, step: 1)
                            Text("\(Int(fontSize)) px")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    Picker("Content width", selection: $contentWidth) {
                        ForEach(PreviewSettings.ContentWidth.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Content") {
                    Toggle("Syntax-highlight code blocks", isOn: $highlightCode)
                    Toggle("Show YAML front matter", isOn: $showFrontMatter)
                }

                Section {
                    Button("Reset to Defaults", action: reset)
                } footer: {
                    Text("Changes apply the next time you open a Quick Look preview. Finder caches thumbnails, so icons update when files change.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, idealWidth: 350, maxWidth: 420)

            SamplePreview(settings: settings)
                .frame(minWidth: 480)
        }
    }

    private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reset() {
        let d = PreviewSettings.default
        theme = d.theme
        fontSize = d.fontSize
        contentWidth = d.contentWidth
        showFrontMatter = d.showFrontMatter
        highlightCode = d.highlightCode
    }
}

/// Live preview of the bundled sample document using the same renderer as the extension.
struct SamplePreview: NSViewRepresentable {
    var settings: PreviewSettings

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WebViewFactory.make()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastSettings != settings,
              let url = Bundle.main.url(forResource: "sample", withExtension: "md") else { return }
        context.coordinator.lastSettings = settings
        context.coordinator.documentURL = url
        switch settings.theme {
        case .auto: webView.appearance = nil
        case .light: webView.appearance = NSAppearance(named: .aqua)
        case .dark: webView.appearance = NSAppearance(named: .darkAqua)
        }
        let html = (try? MarkdownRenderer(settings: settings).renderDocument(fileURL: url))
            ?? "<p>Could not load sample.md</p>"
        webView.loadHTMLString(html, baseURL: url)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastSettings: PreviewSettings?
        var documentURL: URL?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if WebViewFactory.isSameDocument(url, as: documentURL) {
                decisionHandler(.allow)
            } else {
                WebViewFactory.openExternally(url)
                decisionHandler(.cancel)
            }
        }
    }
}
