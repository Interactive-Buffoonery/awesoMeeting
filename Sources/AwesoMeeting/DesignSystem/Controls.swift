// Intentional additions (no verbatim awesoMux counterpart): Button style and
// SegmentedTabs. Both apply the family DNA — radius 6, hairline borders,
// accent focus ring.

import SwiftUI

// MARK: - AwButtonStyle

struct AwButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost }
    enum Size { case sm, md }

    var variant: Variant = .secondary
    var size: Size = .md

    @Environment(\.awAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let (bg, borderColor, fg): (Color, Color, Color) = switch variant {
        case .primary: (accent.color.opacity(0.20), accent.color.opacity(0.45), Aw.text1)
        case .secondary: (Aw.surfaceElevated, Aw.border2, Aw.text1)
        case .ghost: (.clear, .clear, Aw.text2)
        }
        configuration.label
            .font(size == .sm ? Font.system(size: 11, weight: .medium) : Font.system(size: 12, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, size == .sm ? 9 : 12)
            .padding(.vertical, size == .sm ? 4 : 6)
            .awSurface(bg, radius: AwRadius.button, borderColor: borderColor)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .offset(y: configuration.isPressed ? 0.5 : 0) // press = 0.5px downward nudge
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: AwRadius.button))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AwButtonStyle {
    static var awPrimary: AwButtonStyle { AwButtonStyle(variant: .primary) }
    static var awSecondary: AwButtonStyle { AwButtonStyle(variant: .secondary) }
    static var awGhost: AwButtonStyle { AwButtonStyle(variant: .ghost) }
}

// MARK: - SegmentedTabs

/// Compact segmented control: chrome2 well, elevated selected segment,
/// radius 6 outside / 5 inside, hairline border.
struct SegmentedTabs<ID: Hashable>: View {
    struct Tab {
        let id: ID
        let label: String
    }

    var tabs: [Tab]
    @Binding var selection: ID
    /// VoiceOver group label ("Settings section", "Appearance", ...). Optional
    /// because some call sites sit in rows whose label already provides context.
    var label: String?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.id) { tab in
                let selected = tab.id == selection
                Button {
                    selection = tab.id
                } label: {
                    Text(tab.label)
                        .font(AwFont.label)
                        .foregroundStyle(selected ? Aw.text1 : Aw.text3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: AwRadius.pill)
                                .fill(selected ? Aw.surfaceElevated : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AwRadius.pill))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .if(selected) { $0.awShadow(.handle) }
            }
        }
        .padding(2)
        .awSurface(Aw.surfaceChrome2, radius: AwRadius.button, borderColor: Aw.border)
        .animation(.easeOut(duration: 0.12), value: selection)
        .accessibilityElement(children: .contain)
        .if(label != nil) { $0.accessibilityLabel(label ?? "") }
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - AccentSwatch

/// One accent choice as a clickable color chip; selection = text-colored ring
/// (shape survives without color). Used by the menu-bar controller + Settings.
struct AccentSwatch: View {
    let choice: AwAccent
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3)
                .fill(choice.color)
                .frame(height: 16)
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: AwRadius.button)
                        .strokeBorder(selected ? Aw.text1 : .clear, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: AwRadius.button))
        }
        .buttonStyle(.plain)
        .help(choice.rawValue)
        .accessibilityLabel(choice.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
