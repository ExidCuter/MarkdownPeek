import Foundation

/// User-tunable rendering options, shared between the host app and both
/// Quick Look extensions through App Group user defaults.
struct PreviewSettings: Equatable {
    enum Theme: String, CaseIterable, Identifiable {
        case auto, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: "Auto"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    enum ContentWidth: String, CaseIterable, Identifiable {
        case narrow, medium, full
        var id: String { rawValue }
        var label: String {
            switch self {
            case .narrow: "Narrow"
            case .medium: "Medium"
            case .full: "Full width"
            }
        }
        var css: String {
            switch self {
            case .narrow: "720px"
            case .medium: "980px"
            case .full: "none"
            }
        }
    }

    enum Keys {
        static let theme = "theme"
        static let fontSize = "fontSize"
        static let contentWidth = "contentWidth"
        static let showFrontMatter = "showFrontMatter"
        static let highlightCode = "highlightCode"
    }

    static let fontSizeRange: ClosedRange<Double> = 12...24

    var theme: Theme = .auto
    var fontSize: Double = 15
    var contentWidth: ContentWidth = .medium
    var showFrontMatter = true
    var highlightCode = true

    static let `default` = PreviewSettings()

    /// The host app's bundle identifier (`MarkdownPeekHostBundleIdentifier` in every Info.plist).
    /// The unsandboxed host app writes its normal preferences domain; the sandboxed
    /// extensions read that domain through the
    /// `temporary-exception.shared-preference.read-only` entitlement. Unlike App Groups,
    /// this needs no provisioning profile, so locally signed builds work.
    static var hostBundleID: String {
        (Bundle.main.object(forInfoDictionaryKey: "MarkdownPeekHostBundleIdentifier") as? String)
            ?? "com.markdownpeek.MarkdownPeek"
    }

    static var store: UserDefaults {
        if Bundle.main.bundleIdentifier == hostBundleID { return .standard }
        return UserDefaults(suiteName: hostBundleID) ?? .standard
    }

    static func load(from store: UserDefaults = PreviewSettings.store) -> PreviewSettings {
        var s = PreviewSettings()
        if let raw = store.string(forKey: Keys.theme), let v = Theme(rawValue: raw) { s.theme = v }
        if store.object(forKey: Keys.fontSize) != nil {
            s.fontSize = min(max(store.double(forKey: Keys.fontSize), fontSizeRange.lowerBound), fontSizeRange.upperBound)
        }
        if let raw = store.string(forKey: Keys.contentWidth), let v = ContentWidth(rawValue: raw) { s.contentWidth = v }
        if store.object(forKey: Keys.showFrontMatter) != nil { s.showFrontMatter = store.bool(forKey: Keys.showFrontMatter) }
        if store.object(forKey: Keys.highlightCode) != nil { s.highlightCode = store.bool(forKey: Keys.highlightCode) }
        return s
    }
}
