import Foundation

/// Persisted hotkey binding. `keyCode` is a Carbon virtual key code (e.g.
/// `kVK_ANSI_E = 14`); `modifiers` is the raw `NSEvent.ModifierFlags`
/// `rawValue` (UInt). Codable so it can round-trip through `UserDefaults`
/// as a single Data blob.
public struct HotkeyBinding: Equatable, Sendable, Codable {
    public let keyCode: UInt32
    public let modifiers: UInt   // raw NSEvent.ModifierFlags rawValue

    public init(keyCode: UInt32, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧E — matches the Phase 1 hardcoded binding.
    /// `0x100000` = command, `0x20000` = shift (NSEvent.ModifierFlags raw values).
    public static let `default` = HotkeyBinding(keyCode: 14 /* kVK_ANSI_E */, modifiers: 0x100000 | 0x20000)
}

/// Persists the user's hotkey choice across launches via `UserDefaults`. Stores
/// the binding as JSON-encoded Data under a single versioned key so future
/// shape changes can migrate cleanly.
public struct HotkeyBindingStore: @unchecked Sendable {
    // UserDefaults isn't marked `Sendable`, but its API is documented as
    // thread-safe; `@unchecked` is appropriate here.
    private let defaults: UserDefaults
    private let key = "hotkey.binding.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HotkeyBinding {
        guard let data = defaults.data(forKey: key),
              let b = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else {
            return .default
        }
        return b
    }

    public func save(_ b: HotkeyBinding) {
        guard let data = try? JSONEncoder().encode(b) else { return }
        defaults.set(data, forKey: key)
    }
}
