// ExportMenu — the Share affordance. Markdown-first, surfaced in-product:
// notes, transcript & summary are plain Markdown, yours to keep.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportMenuView: View {
    let meeting: Meeting

    @State private var open = false
    @State private var copied = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 11))
                Text("Share")
            }
        }
        .buttonStyle(.awSecondary)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                KickerText(text: "Export")
                    .padding(.init(top: 4, leading: 10, bottom: 8, trailing: 10))
                ExportRow(icon: copied ? "checkmark" : "doc.on.doc",
                          label: copied ? "Copied Markdown" : "Copy as Markdown",
                          hint: "⌘C", primary: true) { copyMarkdown(meeting.markdown) }
                ExportRow(icon: "arrow.down.circle", label: "Export .md file", hint: ".md") {
                    save(meeting.markdown, name: meeting.title)
                }
                ExportRow(icon: "doc.text", label: "Export transcript", hint: ".md") {
                    save(transcriptMarkdown, name: meeting.title + " — transcript")
                }
                footnote
            }
            .padding(8)
            .frame(width: 256)
            .background(Aw.surfaceElevated)
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(AwTint.lavender.color)
            Text("Notes, transcript & summary are plain Markdown — yours to keep.")
                .font(AwFont.monoMeta)
                .foregroundStyle(Aw.text3)
        }
        .padding(.init(top: 8, leading: 10, bottom: 4, trailing: 10))
        .overlay(alignment: .top) { Aw.border.frame(height: 0.5).padding(.horizontal, 10) }
        .padding(.top, 6)
    }

    private var transcriptMarkdown: String {
        "# \(meeting.title) — transcript\n\n"
            + meeting.transcript.map { "**[\($0.time)] \(meeting.speakerName(for: $0)):** \($0.text)\n\n" }.joined()
    }

    private func copyMarkdown(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }

    private func save(_ text: String, name: String) {
        open = false
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = name + ".md"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct ExportRow: View {
    let icon: String
    let label: String
    var hint: String?
    var primary = false
    let action: () -> Void

    @Environment(\.awAccent) private var accent
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(primary ? accent.color : Aw.text2)
                    .frame(width: 15)
                Text(label)
                    .font(AwFont.label)
                    .foregroundStyle(Aw.text1)
                Spacer(minLength: 0)
                if let hint {
                    Text(hint)
                        .font(AwFont.monoMeta)
                        .foregroundStyle(Aw.textFaint)
                }
            }
            .padding(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .awSurface(primary ? accent.color.opacity(0.16) : hovering ? Aw.surfaceHover : .clear,
                       radius: AwRadius.button,
                       borderColor: primary ? accent.color.opacity(0.40) : .clear)
            .contentShape(RoundedRectangle(cornerRadius: AwRadius.button))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
