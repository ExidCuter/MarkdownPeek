import SwiftUI

@main
struct MarkdownPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("MarkdownPeek", id: "main") {
            SettingsView()
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = ExtensionManager.shared
        let args = CommandLine.arguments

        // Scriptable: `MarkdownPeek.app/Contents/MacOS/MarkdownPeek --remove-extensions`
        if args.contains("--remove-extensions") || args.contains("--register-extensions") {
            Task {
                if args.contains("--remove-extensions") {
                    await manager.remove()
                } else {
                    await manager.register()
                }
                NSApp.terminate(nil)
            }
            return
        }

        // Opening the app is the install step: it registers the Quick Look extensions.
        Task { await manager.appDidLaunch() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
