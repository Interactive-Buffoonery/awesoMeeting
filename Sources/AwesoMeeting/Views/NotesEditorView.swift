// NotesEditor — the notes-primary center column. AI-enhanced blocks are
// clearly distinct (lavender gutter + wash + AI kicker) and never overwrite
// the user's raw notes.

import SwiftUI

struct NotesEditorView: View {
    let meeting: Meeting

    @Environment(AppModel.self) private var model
    @Environment(\.awAccent) private var accent
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(meeting.notes) { block in
                        NoteBlockView(block: block)
                    }
                    noteField
                }
                .frame(maxWidth: 640)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity) // centers the reading column
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Aw.surfaceWindow)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(meeting.title)
                    .font(AwFont.display)
                    .foregroundStyle(Aw.text1)
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ExportMenuView(meeting: meeting)
                    Button {
                        model.enhanceNotes()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(accent.color)
                            Text("Enhance notes")
                        }
                    }
                    .buttonStyle(.awPrimary)
                }
            }
            metaLine
        }
        .padding(.init(top: AwSpace.panelPadding, leading: AwSpace.panelPadding,
                       bottom: 12, trailing: AwSpace.panelPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Aw.border.frame(height: 0.5) }
    }

    private var metaLine: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 10))
                Text(meeting.dateLabel)
            }
            Text("·")
            Text(meeting.duration)
            Text("·")
            HStack(spacing: 5) {
                Image(systemName: "cpu").font(.system(size: 10))
                Text("on-device")
            }
            Text("·")
            Text("\(meeting.speakers.count) speakers")
            Text("·")
            HStack(spacing: 5) {
                Image(systemName: "doc.text").font(.system(size: 10))
                Text("Markdown")
            }
            .foregroundStyle(AwTint.lavender.color)
        }
        .font(AwFont.monoMeta)
        .foregroundStyle(Aw.text3)
    }

    private var noteField: some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent.color).frame(width: 1.5)
            TextField("Type a note…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AwFont.body)
                .foregroundStyle(Aw.text1)
                .padding(.leading, 8)
                .onSubmit {
                    model.addUserNote(draft.trimmingCharacters(in: .whitespaces))
                    draft = ""
                }
        }
        .padding(.init(top: 8, leading: 14, bottom: 8, trailing: 14))
    }
}

private struct NoteBlockView: View {
    let block: NoteBlock

    var body: some View {
        switch block.kind {
        case .user:
            Text(block.text)
                .font(AwFont.body)
                .lineSpacing(3) // ~1.55 leading
                .foregroundStyle(Aw.text1)
                .padding(.init(top: 6, leading: 14, bottom: 6, trailing: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ai:
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(AwTint.lavender.color)
                    KickerText(text: "AI", color: AwTint.lavender.color)
                }
                Text(block.text)
                    .font(AwFont.body)
                    .lineSpacing(3)
                    .foregroundStyle(Aw.text1)
            }
            .padding(.init(top: 10, leading: 16, bottom: 10, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AwRadius.panel)
                    .fill(AwTint.lavender.color.opacity(0.09))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AwTint.lavender.color)
                    .frame(width: 2.5)
                    .padding(.vertical, 8)
            }
            .padding(.vertical, 2)
        }
    }
}
