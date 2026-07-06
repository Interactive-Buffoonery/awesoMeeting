// Sidebar — meeting list (reverse-chronological) + the bottom record footer,
// the app's continuous status surface.

import AwesoMeetingCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.awAccent) private var accent

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // search
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Aw.text3)
                TextField("Search meetings", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(AwFont.meta)
                    .foregroundStyle(Aw.text1)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: AwSpace.fieldHeight)
            .awSurface(Aw.surfaceChrome2, radius: AwRadius.button, borderColor: Aw.border)
            .padding(.init(top: 10, leading: 12, bottom: 6, trailing: 12))

            // list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    KickerText(text: "Recent")
                        .padding(.init(top: 6, leading: 5, bottom: 4, trailing: 5))
                    ForEach(model.filteredMeetings) { meeting in
                        MeetingRow(meeting: meeting, selected: meeting.id == model.selectedID) {
                            model.selectedID = meeting.id
                        }
                    }
                }
                .padding(.init(top: 4, leading: 8, bottom: 8, trailing: 8))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // footer — record control + live waveform
            HStack(spacing: 9) {
                Button {
                    model.toggleRecording()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: model.isRecording ? "stop.fill" : "mic")
                            .font(.system(size: 11))
                            .foregroundStyle(accent.color)
                        Text(model.isRecording ? "Stop" : "Record")
                    }
                }
                .buttonStyle(AwButtonStyle(variant: model.isRecording ? .primary : .secondary, size: .sm))
                Spacer()
                Waveform(state: model.isRecording ? .recording : .idle, bars: 6, height: 16)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: AwSpace.chromeFooter)
            .background(Aw.surfaceChrome2)
            .overlay(alignment: .top) { Aw.border.frame(height: 0.5) }
        }
        .frame(width: 236)
        .background(Aw.surfaceSidebar)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let selected: Bool
    let onSelect: () -> Void

    @Environment(\.awAccent) private var accent
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(meeting.title)
                        .font(AwFont.label)
                        .foregroundStyle(Aw.text1)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if meeting.isProcessing {
                        StatusDot(state: meeting.state, size: 13)
                    }
                }
                Text("\(meeting.dateLabel) · \(meeting.duration)")
                    .font(AwFont.monoMeta)
                    .foregroundStyle(Aw.text3)
                if meeting.isProcessing {
                    AwPill(text: meeting.state == .transcribing ? "Transcribing…"
                            : meeting.state == .diarizing ? "Diarizing…" : "Recording",
                           state: meeting.state)
                        .padding(.top, 3)
                }
            }
            .padding(.init(top: 9, leading: 13, bottom: 9, trailing: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AwRadius.panel)
                    .fill(selected ? Aw.surfaceActive : hovering ? Aw.surfaceHover : .clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    // 2px accent hairline on the leading edge
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent.color)
                        .frame(width: 2)
                        .padding(.vertical, 9)
                        .padding(.leading, 3)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AwRadius.panel))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
