// DetailPanel — tabbed Transcript / AI Summary (trailing column). Speaker
// rename is a first-class flow: click a SpeakerTag → popover with a name
// field and "just this line" vs "all N lines" scope.

import SwiftUI

enum DetailTab: Hashable {
    case transcript, summary
}

struct DetailPanelView: View {
    let meeting: Meeting
    @Binding var tab: DetailTab

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            switch tab {
            case .transcript: TranscriptTab(meeting: meeting)
            case .summary: SummaryTab(meeting: meeting)
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(Aw.surfaceChrome)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            SegmentedTabs(tabs: [
                .init(id: DetailTab.transcript, label: "Transcript"),
                .init(id: DetailTab.summary, label: "AI Summary"),
            ], selection: $tab)
            Spacer(minLength: 0)
        }
        .padding(.init(top: 10, leading: 14, bottom: 10, trailing: 14))
        .overlay(alignment: .bottom) { Aw.border.frame(height: 0.5) }
    }
}

// MARK: - Transcript

private struct TranscriptTab: View {
    let meeting: Meeting

    @Environment(AppModel.self) private var model
    @State private var renamingLineID: UUID?

    var body: some View {
        if meeting.transcript.isEmpty {
            EmptyStateView(icon: "mic",
                           label: meeting.state == .transcribing ? "Transcribing on-device…" : "No transcript yet")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(meeting.transcript) { line in
                        TranscriptLineView(meeting: meeting, line: line,
                                           renamingLineID: $renamingLineID)
                    }
                }
                .padding(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: meeting.id) { renamingLineID = nil }
        }
    }
}

private struct TranscriptLineView: View {
    let meeting: Meeting
    let line: TranscriptLine
    @Binding var renamingLineID: UUID?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.time)
                .font(AwFont.monoMeta)
                .foregroundStyle(Aw.textFaint)
                .fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                SpeakerTag(name: meeting.speakerName(for: line),
                           index: meeting.speaker(id: line.speakerID)?.index ?? 0,
                           active: renamingLineID == line.id) {
                    renamingLineID = line.id
                }
                .popover(isPresented: Binding(
                    get: { renamingLineID == line.id },
                    set: { if !$0 { renamingLineID = nil } }
                ), arrowEdge: .bottom) {
                    RenamePopover(meeting: meeting, line: line) { renamingLineID = nil }
                }
                Text(line.text)
                    .font(AwFont.body)
                    .lineSpacing(3)
                    .foregroundStyle(Aw.text1)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct RenamePopover: View {
    let meeting: Meeting
    let line: TranscriptLine
    let dismiss: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.awAccent) private var accent
    @State private var name = ""
    @FocusState private var focused: Bool

    private var speakerLineCount: Int {
        meeting.transcript.count { $0.speakerID == line.speakerID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KickerText(text: "Rename speaker", color: Aw.text3)
                .padding(.bottom, 8)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(AwFont.body)
                .foregroundStyle(Aw.text1)
                .focused($focused)
                .padding(.horizontal, 10)
                .frame(minHeight: AwSpace.fieldHeight)
                .awSurface(Aw.surfaceWindow, radius: AwRadius.button, borderColor: Aw.border2)
            VStack(spacing: 6) {
                ScopeButton(label: "Just this line", primary: false) { commit(.line) }
                ScopeButton(label: "All \(speakerLineCount) lines from \(meeting.speakerName(for: line))",
                            primary: true) { commit(.all) }
            }
            .padding(.top, 10)
        }
        .padding(12)
        .frame(width: 244)
        .background(Aw.surfaceElevated)
        .onAppear {
            name = meeting.speakerName(for: line)
            focused = true
        }
    }

    private func commit(_ scope: AppModel.RenameScope) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            model.renameSpeaker(meetingID: meeting.id, lineID: line.id, to: trimmed, scope: scope)
        }
        dismiss()
    }
}

private struct ScopeButton: View {
    let label: String
    let primary: Bool
    let action: () -> Void

    @Environment(\.awAccent) private var accent

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AwFont.label)
                .foregroundStyle(Aw.text1)
                .lineLimit(1)
                .padding(.init(top: 7, leading: 10, bottom: 7, trailing: 10))
                .frame(maxWidth: .infinity, alignment: .leading)
                .awSurface(primary ? accent.color.opacity(0.20) : Aw.surfaceWindow,
                           radius: AwRadius.button,
                           borderColor: primary ? accent.color.opacity(0.45) : Aw.border2)
                .contentShape(RoundedRectangle(cornerRadius: AwRadius.button))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Summary

private struct SummaryTab: View {
    let meeting: Meeting

    @Environment(\.awAccent) private var accent

    var body: some View {
        if let summary = meeting.summary {
            ScrollView {
                VStack(alignment: .leading, spacing: AwSpace.sectionGap) {
                    SummarySection(title: "Highlights", icon: "star") {
                        BulletList(items: summary.highlights)
                    }
                    SummarySection(title: "Decisions", icon: "checkmark.circle") {
                        BulletList(items: summary.decisions)
                    }
                    SummarySection(title: "Next steps", icon: "checklist") {
                        VStack(spacing: 8) {
                            ForEach(summary.nextSteps.indices, id: \.self) { i in
                                NextStepRow(step: summary.nextSteps[i])
                            }
                        }
                    }
                }
                .padding(.init(top: 16, leading: 18, bottom: 16, trailing: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyStateView(icon: "sparkles", label: "Summary generates when the meeting ends")
        }
    }
}

private struct SummarySection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Aw.text3)
                Text(title)
                    .font(AwFont.sectionHead)
                    .foregroundStyle(Aw.text1)
            }
            content
        }
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(AwFont.body)
                    .lineSpacing(3)
                    .foregroundStyle(Aw.text1)
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct NextStepRow: View {
    let step: MeetingSummary.NextStep

    @Environment(\.awAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square")
                .font(.system(size: 12))
                .foregroundStyle(Aw.textFaint)
                .padding(.top, 1)
            Text(step.task)
                .font(AwFont.body)
                .foregroundStyle(Aw.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text("@\(step.who)").foregroundStyle(accent.color)
                Text(step.by).foregroundStyle(Aw.textFaint)
            }
            .font(AwFont.monoMeta)
        }
        .padding(.init(top: 9, leading: 11, bottom: 9, trailing: 11))
        .awSurface(Aw.surfaceWindow, radius: AwRadius.panel, borderColor: Aw.border)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20))
            Text(label).font(AwFont.monoMeta)
        }
        .foregroundStyle(Aw.textFaint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
