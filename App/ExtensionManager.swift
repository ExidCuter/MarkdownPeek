import AppKit
import CoreServices
import OSLog

/// Registers, inspects and removes the app's Quick Look extensions, so no
/// install script is needed: opening the app is enough.
@MainActor
final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()

    struct Extension: Identifiable {
        let id: String
        let name: String
        let bundleName: String
    }

    enum State: Equatable {
        case checking
        case active
        case disabled
        case otherCopy(path: String)
        case notRegistered
    }

    static let extensions = [
        Extension(id: "com.markdownpeek.MarkdownPeek.Preview", name: "Space-bar preview", bundleName: "MarkdownPreview.appex"),
        Extension(id: "com.markdownpeek.MarkdownPeek.Thumbnail", name: "Finder thumbnails", bundleName: "MarkdownThumbnail.appex"),
    ]

    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var isWorking = false

    /// Set when the user removes the extensions, so launching the app doesn't bring them back.
    @Published private(set) var userRemoved = UserDefaults.standard.bool(forKey: removedKey)
    private static let removedKey = "extensionsRemoved"

    private let appURL = Bundle.main.bundleURL.standardizedFileURL

    /// Extensions registered from a disk image, Downloads or another temporary
    /// place break once that place goes away, so only auto-register from an
    /// Applications folder (or an Xcode build, for development).
    var isInStableLocation: Bool {
        let path = appURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(home + "/Applications/")
            || path.contains("/DerivedData/")
    }

    var allActive: Bool {
        Self.extensions.allSatisfy { states[$0.id] == .active }
    }

    // MARK: - Lifecycle

    /// Identifies this copy and build. When it changes (first install, update,
    /// app moved, Xcode build) the full registration runs again, because macOS
    /// may have registered the extensions itself while leaving other copies
    /// and a stale thumbnail agent behind.
    private var installFingerprint: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(appURL.path)|\(version)|\(build)"
    }
    private static let fingerprintKey = "registeredInstall"

    func appDidLaunch() async {
        await refresh()
        guard !userRemoved, isInStableLocation else { return }
        let isNewInstall = UserDefaults.standard.string(forKey: Self.fingerprintKey) != installFingerprint
        if isNewInstall || !allActive {
            await register()
        }
    }

    func refresh() async {
        var result: [String: State] = [:]
        for ext in Self.extensions {
            let out = await Shell.run("/usr/bin/pluginkit", ["-m", "-v", "-i", ext.id]).output
            result[ext.id] = Self.parseState(pluginkitOutput: out, expectedPath: pluginURL(ext).path)
        }
        states = result
    }

    // MARK: - Register / remove

    func register() async {
        isWorking = true
        defer { isWorking = false }
        UserDefaults.standard.set(false, forKey: Self.removedKey)
        userRemoved = false

        // Make the copy that's running now the only one Quick Look knows about.
        for other in otherInstalledCopies() {
            for ext in Self.extensions {
                await run("/usr/bin/pluginkit", "-r", other.appendingPathComponent("Contents/PlugIns/\(ext.bundleName)").path)
            }
            await run(Self.lsregister, "-u", other.path)
        }

        let status = LSRegisterURL(appURL as CFURL, true)
        Self.log.notice("LSRegisterURL \(self.appURL.path, privacy: .public) -> \(status); other copies: \(self.otherInstalledCopies().map(\.path), privacy: .public)")
        for ext in Self.extensions {
            await run("/usr/bin/pluginkit", "-a", pluginURL(ext).path)
            await run("/usr/bin/pluginkit", "-e", "use", "-i", ext.id)
        }
        await resetQuickLook()
        await refresh()
        if allActive {
            UserDefaults.standard.set(installFingerprint, forKey: Self.fingerprintKey)
        }
    }

    func remove() async {
        isWorking = true
        defer { isWorking = false }

        // "ignore" is remembered by the system, so the extensions stay off even
        // if LaunchServices sees the app again.
        for ext in Self.extensions {
            await run("/usr/bin/pluginkit", "-e", "ignore", "-i", ext.id)
        }
        for app in [appURL] + otherInstalledCopies() {
            for ext in Self.extensions {
                await run("/usr/bin/pluginkit", "-r", app.appendingPathComponent("Contents/PlugIns/\(ext.bundleName)").path)
            }
        }
        UserDefaults.standard.set(true, forKey: Self.removedKey)
        userRemoved = true
        await resetQuickLook()
        await refresh()
    }

    /// Clears Quick Look's caches and restarts the thumbnail agent, which
    /// otherwise keeps using its old list of extensions until logout.
    private func resetQuickLook() async {
        await run("/usr/bin/qlmanage", "-r")
        await run("/usr/bin/qlmanage", "-r", "cache")
        await run("/usr/bin/killall", "-9", "com.apple.quicklook.ThumbnailsAgent")
    }

    // MARK: - Helpers

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    private func pluginURL(_ ext: Extension) -> URL {
        appURL.appendingPathComponent("Contents/PlugIns/\(ext.bundleName)")
    }

    private func otherInstalledCopies() -> [URL] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .map(\.standardizedFileURL)
            .filter { $0 != appURL }
    }

    private static let log = Logger(subsystem: "com.markdownpeek", category: "extensions")

    @discardableResult
    private func run(_ path: String, _ args: String...) async -> Shell.Result {
        let result = await Shell.run(path, args)
        let command = ([URL(fileURLWithPath: path).lastPathComponent] + args).joined(separator: " ")
        Self.log.notice("\(command, privacy: .public) -> \(result.status) \(result.output.prefix(300), privacy: .public)")
        return result
    }

    /// Parses `pluginkit -m -v -i <id>` lines such as
    /// `+    com.example.Ext(1.0)\t<UUID>\t<date>\t/path/to/Ext.appex`.
    /// The first character is the user election: `+` use, `-` ignore, blank none.
    nonisolated static func parseState(pluginkitOutput: String, expectedPath: String) -> State {
        let lines = pluginkitOutput.split(separator: "\n").filter { $0.contains("\t") }
        guard !lines.isEmpty else { return .notRegistered }
        let parsed = lines.map { line -> (election: Character, path: String) in
            (line.first ?? " ", String(line.split(separator: "\t").last ?? ""))
        }
        let match = parsed.first { $0.path == expectedPath } ?? parsed[0]
        if match.election == "-" { return .disabled }
        return match.path == expectedPath ? .active : .otherCopy(path: match.path)
    }
}

enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(_ path: String, _ args: [String]) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: Result(status: process.terminationStatus,
                                                      output: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
