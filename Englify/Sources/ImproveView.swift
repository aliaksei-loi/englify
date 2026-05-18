import AppKit
import SwiftUI
import EnglifyKit

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
        case .ready(let response):
            readyView(response: response)
        case .readyRaw(let rawText, _):
            rawFallbackView(rawText: rawText)
        }
    }

    // MARK: - Structured result

    @ViewBuilder
    private func readyView(response: ImproveResponse) -> some View {
        if case .refusedRussian = response.status {
            refusedRussianView
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch response.status {
                        case .looksGood:
                            looksGoodBadge
                        case .rewritten:
                            nativeSection(text: response.native)
                        case .translatedFromRu:
                            translatedFromRussianTag
                            nativeSection(text: response.native)
                        case .refusedRussian:
                            // Handled above; unreachable.
                            EmptyView()
                        }

                        originalMarkedSection(text: response.originalMarked)

                        if !response.mistakes.isEmpty {
                            mistakesSection(items: response.mistakes)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)

                HStack {
                    Spacer()
                    Button("Copy") {
                        onCopy(response.native)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }
        }
    }

    private var looksGoodBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("No changes needed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.green.opacity(0.12))
        )
    }

    /// Small pill placed above the native section when the response was
    /// produced via the `[ru]` translation escape hatch. Mirrors the visual
    /// weight of the looks-good badge so the user notices the mode shift.
    private var translatedFromRussianTag: some View {
        HStack(spacing: 6) {
            Image(systemName: "character.book.closed")
                .foregroundStyle(Color.accentColor)
            Text("Translated from Russian")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    /// Replaces the whole result region when the model refuses Russian input
    /// without the `[ru]` prefix. No native section, no mistakes, no Copy —
    /// the only signal is the hint to retry with the directive.
    private var refusedRussianView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Russian input detected.")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add `[ru]` to translate, e.g. `[ru] я хочу сказать что...`")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func nativeSection(text: String) -> some View {
        // Primary surface — largest weight; this is what Copy targets.
        Text(text)
            .font(.system(size: 16))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func originalMarkedSection(text: String) -> some View {
        // Secondary surface — markdown-bolded error spans. Fall back to plain
        // text if AttributedString rejects the markdown for any reason.
        let rendered: AttributedString = {
            if let attributed = try? AttributedString(markdown: text) {
                return attributed
            }
            return AttributedString(text)
        }()

        return VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Original")
            Text(rendered)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func mistakesSection(items: [String]) -> some View {
        // Lowest visual weight — compact bullets.
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Mistakes")
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }

    // MARK: - Raw fallback

    @ViewBuilder
    private func rawFallbackView(rawText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Parse error — showing raw response")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }
            ScrollView {
                Text(rawText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            HStack {
                Spacer()
                Button("Copy") {
                    onCopy(rawText)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
