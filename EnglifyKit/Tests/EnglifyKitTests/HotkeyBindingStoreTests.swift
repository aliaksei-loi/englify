import Testing
import Foundation
@testable import EnglifyKit

@Suite struct HotkeyBindingStoreTests {
    @Test func defaultsToCommandShiftE() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HotkeyBindingStore(defaults: defaults)
        #expect(store.load() == .default)
    }

    @Test func roundTripsCustomBinding() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HotkeyBindingStore(defaults: defaults)
        let custom = HotkeyBinding(keyCode: 31 /* kVK_ANSI_O */, modifiers: 0x100000 /* command */)
        store.save(custom)
        #expect(store.load() == custom)
    }
}
