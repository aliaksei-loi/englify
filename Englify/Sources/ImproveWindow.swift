import AppKit
import SwiftUI

/// Floating `NSPanel` that hosts the SwiftUI improve view.
///
/// Phase 1 keeps this simple: one window instance is created on demand and
/// reused. Re-opening clears the textarea and result, then orders the panel
/// to the front and gives it key status so the textarea can take input.
@MainActor
final class ImproveWindowController {
    private let service = ImproveService()
    private var panel: ImprovePanel?

    func toggle() {
        if let panel, panel.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        service.reset()

        guard let panel else { return }
        centerOnActiveScreen(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> ImprovePanel {
        let panel = ImprovePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Englify"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        let root = ImproveView(
            service: service,
            onCopy: { [weak self] text in
                self?.copy(text)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        dismiss()
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

/// `NSPanel` subclass that can become key/main so the embedded text editor
/// receives keyboard input even though the app is a non-activating accessory.
final class ImprovePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
