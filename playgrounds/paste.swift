#!/usr/bin/env swift

// Playground B — clipboard-swap + simulated ⌘V + clipboard restore
//
// Validates (manually — you check the target app after running):
//   1. Clipboard can be saved, overwritten, and restored
//   2. Simulated ⌘V actually lands a paste in the target app
//   3. Works across Cocoa and Electron apps
//
// Run (the target app must be running and have a text field focused):
//   swift playgrounds/paste.swift "hello from englify" "Slack"
//
// Requires Accessibility permission granted to whatever process runs this
// script (usually Terminal.app or iTerm). On first run, macOS will prompt
// via System Settings → Privacy → Accessibility.

import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: swift paste.swift <text> <target-app-name>")
    print("Example: swift paste.swift \"hello\" \"Slack\"")
    exit(1)
}

let textToPaste = args[1]
let targetAppName = args[2]

// Accessibility permission check
let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
if !AXIsProcessTrustedWithOptions(options) {
    print("❌ Accessibility permission not granted to this process.")
    print("   Grant in: System Settings → Privacy & Security → Accessibility")
    print("   Then re-run.")
    exit(1)
}

// Find target app
guard let targetApp = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == targetAppName
}) else {
    print("❌ App '\(targetAppName)' is not running.")
    print("   Running apps (short list):")
    for app in NSWorkspace.shared.runningApplications.prefix(20) {
        if let name = app.localizedName { print("     \(name)") }
    }
    exit(1)
}

print("Target app: \(targetApp.localizedName!) (PID \(targetApp.processIdentifier))")
print("Will paste: \(textToPaste)")
print()
print("Switching focus in 2 seconds — click into a text field in \(targetAppName) now if you haven't already.")
for i in stride(from: 2, through: 1, by: -1) {
    print("  \(i)…")
    Thread.sleep(forTimeInterval: 1)
}

// Save clipboard
let pb = NSPasteboard.general
let originalChangeCount = pb.changeCount
let originalString = pb.string(forType: .string)
print("Saved clipboard (changeCount=\(originalChangeCount)): \"\(originalString ?? "<empty>")\"")

// Write new text
pb.clearContents()
pb.setString(textToPaste, forType: .string)

// Activate target app
targetApp.activate(options: [])

// Wait for app activation
Thread.sleep(forTimeInterval: 0.15)

// Post CGEvent for ⌘V
let src = CGEventSource(stateID: .hidSystemState)
let kVK_ANSI_V: CGKeyCode = 0x09
guard let vDown = CGEvent(keyboardEventSource: src, virtualKey: kVK_ANSI_V, keyDown: true),
      let vUp   = CGEvent(keyboardEventSource: src, virtualKey: kVK_ANSI_V, keyDown: false) else {
    print("❌ Failed to create CGEvent")
    exit(1)
}
vDown.flags = .maskCommand
vUp.flags = .maskCommand
vDown.post(tap: .cghidEventTap)
vUp.post(tap: .cghidEventTap)

// Wait for paste to land in the target app
Thread.sleep(forTimeInterval: 0.1)

// Restore clipboard
pb.clearContents()
if let original = originalString {
    pb.setString(original, forType: .string)
}
let restored = pb.string(forType: .string)

print()
print("Results:")
print("  Clipboard before: \"\(originalString ?? "<empty>")\"")
print("  Clipboard after:  \"\(restored ?? "<empty>")\"")
print("  Clipboard restored correctly: \(originalString == restored ? "✅" : "❌")")
print()
print("→ Check \(targetAppName) — did '\(textToPaste)' actually paste into the focused field?")
print("  Report results per app in playgrounds/RESULTS.md")
