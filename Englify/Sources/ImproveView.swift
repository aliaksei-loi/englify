import AppKit
import SwiftUI

struct ImproveView: View {
    @Bindable var service: ImproveService
    var onCopy: (String) -> Void
    var onDismiss: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputField

            HStack {
                Spacer()
                if service.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Improve") {
                    service.improve()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(service.isRunning || service.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            resultSection
        }
        .padding(16)
        .frame(width: 560)
        .background(
            // Esc dismisses.
            Button("") { onDismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .onAppear { inputFocused = true }
    }

    private var inputField: some View {
        TextEditor(text: $service.input)
            .font(.system(size: 14))
            .frame(minHeight: 120, maxHeight: 200)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .focused($inputFocused)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch service.status {
        case .idle:
            EmptyView()
        case .running:
            Text("Improving…")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        case .ready(let text):
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                ScrollView {
                    Text(text)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                HStack {
                    Spacer()
                    Button("Copy") {
                        onCopy(text)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }
        }
    }
}
