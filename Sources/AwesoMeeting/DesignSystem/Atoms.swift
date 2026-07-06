// Atoms ported verbatim from awesoMux via the design system: StatusDot, AwPill, KBD.
// State is color + SHAPE, never color alone — it must survive color-blindness
// and reduce-motion.

import SwiftUI

// MARK: - StatusDot

struct StatusDot: View {
    var state: PipelineState
    var size: CGFloat = 14

    @Environment(\.awAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var color: Color { state.color(accent: accent) }
    private var glowAllowed: Bool { !reduceTransparency && contrast != .increased }

    var body: some View {
        glyph
            .frame(width: size, height: size)
            .accessibilityLabel(state.label)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .transcribing, .diarizing:
            spinner
        case .done:
            let s = size / 14
            Path { p in
                p.move(to: .init(x: 3.2 * s, y: 7.4 * s))
                p.addLine(to: .init(x: 6 * s, y: 10 * s))
                p.addLine(to: .init(x: 10.8 * s, y: 4.2 * s))
            }
            .stroke(color, style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        case .error:
            let s = size / 14
            Path { p in
                p.move(to: .init(x: 3.6 * s, y: 3.6 * s)); p.addLine(to: .init(x: 10.4 * s, y: 10.4 * s))
                p.move(to: .init(x: 10.4 * s, y: 3.6 * s)); p.addLine(to: .init(x: 3.6 * s, y: 10.4 * s))
            }
            .stroke(color, style: .init(lineWidth: 1.8, lineCap: .round))
        case .recording:
            recordingGlyph
        case .idle:
            Circle()
                .strokeBorder(color, lineWidth: 1.2)
                .padding(size * (3.6 / 14)) // r 3.4 of viewBox 14
        }
    }

    // Trimmed rotating arc (transcribing = sapphire, diarizing = mauve).
    private var spinner: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(color, style: .init(lineWidth: 1.6, lineCap: .round))
                .padding(size * (2 / 14))
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
        }
    }

    // Concentric ring + filled core, pulsing accent glow while live.
    private var recordingGlyph: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0.0 : sin(t / 1.4 * 2 * .pi)
            ZStack {
                Circle().strokeBorder(color.opacity(0.9), lineWidth: 1.5)
                Circle().fill(color).padding(size * (4 / 14)) // r 3 of 14
            }
            .opacity(0.775 + 0.225 * phase) // 1.0 ↔ 0.55
            .shadow(color: glowAllowed ? color : .clear, radius: 3)
        }
    }
}

// MARK: - AwPill

/// Capsule with an optional leading StatusDot + a mono label. 7h/4v padding,
/// radius 5, hairline border, translucent tint.
struct AwPill: View {
    var text: String
    var state: PipelineState?
    var tint: AwTint?
    var dot = true

    @Environment(\.awAccent) private var accent

    var body: some View {
        let color: Color = if let state { state.color(accent: accent) }
            else if let tint { tint.color }
            else { Aw.text1 }
        let isLoud = state == .recording || state == .error
        let tinted = state != nil || tint != nil

        HStack(spacing: 6) {
            if let state, dot {
                StatusDot(state: state, size: 12)
            } else if let tint, dot {
                Circle().fill(tint.color).frame(width: 7, height: 7)
            }
            Text(text)
                .font(AwFont.pill)
                .foregroundStyle(Color.aw(\.statusOnQuiet))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .awSurface(color.opacity(tinted ? (isLoud ? 0.18 : 0.10) : 0.10),
                   radius: AwRadius.pill,
                   borderColor: color.opacity(tinted ? 0.28 : 0.12))
        .fixedSize()
    }
}

// MARK: - KBD

/// Keyboard-hint key: mono 10pt semibold, elevated surface, radius 4, hairline.
struct KBD: View {
    var key: String

    var body: some View {
        Text(key)
            .font(AwFont.kbd)
            .foregroundStyle(Aw.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 18)
            .awSurface(Aw.surfaceElevated, radius: AwRadius.kbd, borderColor: Aw.border2)
    }
}
