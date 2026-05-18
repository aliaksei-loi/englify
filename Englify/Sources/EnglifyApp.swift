import AppKit
import SwiftUI

@main
struct EnglifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No standard windows; the improve panel is summoned by hotkey.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkey = HotkeyManager()
    private let window = ImproveWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkey.register { [weak self] in
            self?.window.toggle()
        }
    }
}
