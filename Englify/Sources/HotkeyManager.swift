import AppKit
import HotKey

/// Wraps the `HotKey` package and exposes a single ⌘⇧E binding for Phase 1.
@MainActor
final class HotkeyManager {
    private var hotKey: HotKey?
    private var handler: (() -> Void)?

    func register(handler: @escaping () -> Void) {
        self.handler = handler
        let hk = HotKey(key: .e, modifiers: [.command, .shift])
        hk.keyDownHandler = { [weak self] in
            self?.handler?()
        }
        self.hotKey = hk
    }

    func unregister() {
        hotKey = nil
        handler = nil
    }
}
