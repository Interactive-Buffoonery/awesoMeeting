// awesoMeeting-specific components: Waveform (the recording state machine)
// and SpeakerTag (the renamable transcript speaker label).

import SwiftUI

// MARK: - Waveform

/// The recording controller that doubles as a state machine. On capture
/// failure the DEAD track is encoded by POSITION — mic dead ⇒ top half red,
/// system audio dead ⇒ bottom half red, both ⇒ solid red.
struct Waveform: View {
    enum State: Equatable {
        case idle, recording, transcribing, diarizing
        case failure(FailedTrack)
    }

    enum FailedTrack: String {
        case mic, system, both
    }

    var state: State
    var bars = 7
    var height: CGFloat = 18
    var barWidth: CGFloat = 2.5
    var gap: CGFloat = 2.5

    @Environment(\.awAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private static let barPattern: [CGFloat] = [0.45, 0.8, 0.55, 1.0, 0.65, 0.9, 0.4]

    private var animated: Bool {
        !reduceMotion && (state == .recording || state == .transcribing || state == .diarizing)
    }

    private var color: Color {
        switch state {
        case .idle: Aw.textFaint
        case .recording: accent.color
        case .transcribing: Aw.statusRunning
        case .diarizing: Aw.statusThinking
        case .failure: Aw.statusError
        }
    }

    private var label: String {
        switch state {
        case .idle: "Idle"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .diarizing: "Diarizing"
        case .failure(let track):
            "Capture failure — \(track == .both ? "mic and system audio" : track == .mic ? "microphone" : "system audio") not captured"
        }
    }

    var body: some View {
        TimelineView(.animation(paused: !animated)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let period = state == .recording ? 0.7 : 1.1
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<bars, id: \.self) { i in
                    bar(index: i, time: t, period: period)
                }
            }
        }
        .frame(height: height)
        .shadow(color: glowColor, radius: 4)
        .accessibilityLabel(label)
    }

    private var glowColor: Color {
        guard state == .recording, !reduceTransparency, contrast != .increased else { return .clear }
        return accent.color.opacity(0.6)
    }

    @ViewBuilder private func bar(index i: Int, time t: Double, period: Double) -> some View {
        let base = Self.barPattern[i % Self.barPattern.count]
        let fraction: CGFloat = switch state {
        case .idle: base * 0.4
        case .failure: max(0.32, base * 0.5)
        default: base
        }
        // scaleY oscillates 0.35…1.0, phase-shifted per bar (CSS aw-wave).
        let scale: CGFloat = animated
            ? 0.675 + 0.325 * CGFloat(sin((t / period - Double(i) * 0.09 / period) * 2 * .pi))
            : 1

        RoundedRectangle(cornerRadius: barWidth)
            .fill(barFill)
            .frame(width: barWidth, height: max(2, height * fraction * scale))
    }

    private var barFill: AnyShapeStyle {
        guard case .failure(let track) = state else { return AnyShapeStyle(color) }
        let red = Aw.statusError
        let faintRed = red.opacity(0.28)
        return switch track {
        case .both: AnyShapeStyle(red)
        case .mic: AnyShapeStyle(LinearGradient(
            stops: [.init(color: red, location: 0), .init(color: red, location: 0.5),
                    .init(color: faintRed, location: 0.5), .init(color: faintRed, location: 1)],
            startPoint: .top, endPoint: .bottom))
        case .system: AnyShapeStyle(LinearGradient(
            stops: [.init(color: faintRed, location: 0), .init(color: faintRed, location: 0.5),
                    .init(color: red, location: 0.5), .init(color: red, location: 1)],
            startPoint: .top, endPoint: .bottom))
        }
    }
}

// MARK: - SpeakerTag

/// Deterministic tint for a speaker index, so a speaker keeps a stable hue.
func speakerTint(_ index: Int) -> AwTint {
    let tints = AwTint.allCases // mauve, peach, teal, sky, green, lavender, pink
    return tints[((index % tints.count) + tints.count) % tints.count]
}

/// Colored, inline-renamable speaker label — the click target of the
/// first-class speaker-correction flow.
struct SpeakerTag: View {
    var name: String
    var index: Int = 0
    var active = false
    var onRename: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let tint = speakerTint(index)
        let glowAllowed = active && !reduceTransparency && contrast != .increased
        Button(action: { onRename?() }) {
            HStack(spacing: 6) {
                Circle().fill(tint.color).frame(width: 7, height: 7)
                Text(name)
                    .font(AwFont.pill)
                    .foregroundStyle(Aw.text1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .awSurface(tint.color.opacity(0.12), radius: AwRadius.pill,
                       borderColor: tint.borderColor.opacity(0.55))
            .shadow(color: glowAllowed ? tint.color.opacity(0.45) : .clear, radius: 2.5)
        }
        .buttonStyle(.plain)
        .disabled(onRename == nil)
        .help(onRename == nil ? name : "Rename speaker")
    }
}
