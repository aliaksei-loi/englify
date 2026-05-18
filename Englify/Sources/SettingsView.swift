import AppKit
import SwiftUI
import EnglifyKit

/// macOS Settings scene contents.
///
/// Phase 4: a single Form row that lets the user rebind the global hotkey.
/// The recorder swallows the next ⌘/⌥/⇧/⌃ + key combo via a local event
/// monitor and persists it through `HotkeyManager.shared.rebind(_:)` (which
/// writes through to `HotkeyBindingStore`).
struct SettingsView: View {
    @State private var binding: HotkeyBinding = HotkeyManager.shared.currentBinding

    var body: some View {
        Form {
            Section {
                LabeledContent("Hotkey") {
                    HotkeyRecorderView(binding: $binding) { newBinding in
                        HotkeyManager.shared.rebind(newBinding)
                    }
                }
                LabeledContent("Model") {
                    Text("claude-sonnet-4-6")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Renders the current hotkey as a clickable pill. Click → starts recording
/// (label flips to "Type combo…"); the next non-pure-modifier key event with
/// at least one modifier becomes the new binding. Esc cancels recording.
struct HotkeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    var onCommit: (HotkeyBinding) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(recording ? "Type combo…" : Self.format(binding: binding))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc cancels without rebinding.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let required: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            // Require at least one of ⌘/⌥/⇧/⌃; otherwise ignore (lets the user
            // type plain letters without accidentally binding "e").
            guard !mods.intersection(required).isEmpty else { return event }
            let newBinding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue)
            binding = newBinding
            onCommit(newBinding)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recording = false
    }

    // MARK: - Formatting

    static func format(binding: HotkeyBinding) -> String {
        let mods = NSEvent.ModifierFlags(rawValue: binding.modifiers)
        var out = ""
        if mods.contains(.control) { out += "⌃" }
        if mods.contains(.option) { out += "⌥" }
        if mods.contains(.shift) { out += "⇧" }
        if mods.contains(.command) { out += "⌘" }
        out += keyLabel(for: binding.keyCode)
        return out
    }

    private static func keyLabel(for code: UInt32) -> String {
        // Cover the common ANSI letters/numbers we expect users to bind. For
        // anything else fall back to a hex code so the pill is still readable.
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        case 49: return "Space"
        case 36: return "Return"
        default: return String(format: "0x%X", code)
        }
    }
}
