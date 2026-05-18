import AppKit
import HotKey
import EnglifyKit

/// Wraps the `HotKey` package and exposes a rebindable global hotkey.
///
/// Phase 4: binding is loaded from `HotkeyBindingStore` on init (defaults to
/// ⌘⇧E). `rebind(_:)` disposes the current registration, persists the new
/// binding via the store, and rebinds. Kept as a singleton so the Settings
/// window can reach the same instance the AppDelegate registered.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private let store = HotkeyBindingStore()
    private var hotKey: HotKey?
    private var handler: (() -> Void)?
    private(set) var currentBinding: HotkeyBinding

    init() {
        self.currentBinding = HotkeyBindingStore().load()
    }

    func register(handler: @escaping () -> Void) {
        self.handler = handler
        install(binding: currentBinding)
    }

    func rebind(_ binding: HotkeyBinding) {
        store.save(binding)
        currentBinding = binding
        install(binding: binding)
    }

    func unregister() {
        hotKey = nil
        handler = nil
    }

    private func install(binding: HotkeyBinding) {
        // Drop the old one first — HotKey unregisters on deinit.
        hotKey = nil
        guard let key = Key(carbonKeyCode: binding.keyCode) else { return }
        let modifiers = NSEvent.ModifierFlags(rawValue: binding.modifiers)
        let hk = HotKey(key: key, modifiers: modifiers)
        hk.keyDownHandler = { [weak self] in
            self?.handler?()
        }
        self.hotKey = hk
    }
}
