// Menu-bar recording controller — the always-available capture surface.
// Record/stop with the live waveform, plus appearance (System/Mocha/Latte)
// and accent (peach/mauve/sapphire/green) to demo the token system live.

import SwiftUI

struct MenuBarControllerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.awAccent) private var accent

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // header
            HStack(spacing: 10) {
                Waveform(state: model.isRecording ? .recording : .idle, height: 22)
                    .padding(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
                    .awSurface(Aw.surfaceChrome2, radius: AwRadius.button, borderColor: Aw.border)
                VStack(alignment: .leading, spacing: 2) {
                    Text("awesoMeeting")
                        .font(AwFont.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(Aw.text1)
                    Text(model.isRecording ? "Recording" : "Idle · ⌘⇧R to start")
                        .font(AwFont.pill)
                        .foregroundStyle(Aw.text3)
                }
            }

            // record / stop
            Button {
                model.toggleRecording()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 12))
                        .foregroundStyle(accent.color)
                    Text(model.isRecording ? "Stop recording" : "Start recording")
                    Spacer()
                    HStack(spacing: 3) {
                        KBD(key: "⌘")
                        KBD(key: "⇧")
                        KBD(key: "R")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AwButtonStyle(variant: model.isRecording ? .primary : .secondary))
            .padding(.top, 12)

            // appearance
            KickerText(text: "Appearance")
                .padding(.init(top: 13, leading: 0, bottom: 7, trailing: 0))
            SegmentedTabs(tabs: AppearanceChoice.allCases.map { .init(id: $0, label: $0.label) },
                          selection: $model.appearance)
                .frame(maxWidth: .infinity)

            // accent
            HStack(spacing: 8) {
                ForEach(AwAccent.allCases, id: \.self) { choice in
                    AccentSwatch(choice: choice, selected: model.accent == choice) {
                        model.accent = choice
                    }
                }
            }
            .padding(.top, 9)
        }
        .padding(14)
        .frame(width: 268)
        .background(Aw.surfaceElevated)
    }
}
