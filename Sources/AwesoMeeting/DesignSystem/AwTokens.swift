// awesoMeeting design tokens — ported from the awesoMeeting design system
// (tokens/colors.css, typography.css, spacing.css, effects.css), itself ported
// from awesoMux `Sources/DesignSystem/Tokens/`.
//
// Colors resolve live per NSAppearance: Mocha (dark), Latte (light), plus the
// increased-contrast ramps (mocha-hc / latte-hc) when the OS "Increase
// Contrast" setting is on. Product code uses ONLY the semantic roles in `Aw`,
// never the raw ramp.

import SwiftUI
import AppKit

// MARK: - Raw Catppuccin ramp (one palette per appearance)

struct AwPalette: Sendable {
    let rosewater, flamingo, pink, mauve, red, maroon, peach: UInt32
    let yellow, green, teal, sky, sapphire, blue, lavender: UInt32
    let text, subtext1, subtext0, overlay2, overlay1, overlay0: UInt32
    let surface2, surface1, surface0, base, mantle, crust: UInt32
    let statusNeeds, statusError, statusThinking, statusDone: UInt32
    let statusOutput, statusWaiting, statusRunning, statusIdle: UInt32
    let statusOnLoud, statusOnQuiet: UInt32
    let tintBorderMauve, tintBorderPeach, tintBorderTeal, tintBorderSky: UInt32
    let tintBorderGreen, tintBorderLavender, tintBorderPink: UInt32
    let dividerRest, dividerHover, shadow: UInt32

    static let mocha = AwPalette(
        rosewater: 0xF5E0DC, flamingo: 0xF2CDCD, pink: 0xF5C2E7, mauve: 0xCBA6F7,
        red: 0xF38BA8, maroon: 0xEBA0AC, peach: 0xFAB387,
        yellow: 0xF9E2AF, green: 0xA6E3A1, teal: 0x94E2D5, sky: 0x89DCEB,
        sapphire: 0x74C7EC, blue: 0x89B4FA, lavender: 0xB4BEFE,
        text: 0xCDD6F4, subtext1: 0xBAC2DE, subtext0: 0xA6ADC8,
        overlay2: 0x9399B2, overlay1: 0x7F849C, overlay0: 0x6C7086,
        surface2: 0x585B70, surface1: 0x45475A, surface0: 0x313244,
        base: 0x1E1E2E, mantle: 0x181825, crust: 0x11111B,
        statusNeeds: 0xFAB387, statusError: 0xF38BA8, statusThinking: 0xCBA6F7,
        statusDone: 0x94E2D5, statusOutput: 0xA6E3A1, statusWaiting: 0x89B4FA,
        statusRunning: 0x74C7EC, statusIdle: 0x6C7086,
        statusOnLoud: 0x12121C, statusOnQuiet: 0xCDD6F4,
        tintBorderMauve: 0xCBA6F7, tintBorderPeach: 0xFAB387, tintBorderTeal: 0x94E2D5,
        tintBorderSky: 0x89DCEB, tintBorderGreen: 0xA6E3A1,
        tintBorderLavender: 0xB4BEFE, tintBorderPink: 0xF5C2E7,
        dividerRest: 0x6C7086, dividerHover: 0x7F849C, shadow: 0x000000)

    static let latte = AwPalette(
        rosewater: 0xDC8A78, flamingo: 0xDD7878, pink: 0xEA76CB, mauve: 0x8839EF,
        red: 0xD20F39, maroon: 0xE64553, peach: 0xFE640B,
        yellow: 0xDF8E1D, green: 0x40A02B, teal: 0x179299, sky: 0x04A5E5,
        sapphire: 0x209FB5, blue: 0x1E66F5, lavender: 0x7287FD,
        text: 0x4C4F69, subtext1: 0x5C5F77, subtext0: 0x6C6F85,
        overlay2: 0x7C7F93, overlay1: 0x8C8FA1, overlay0: 0x9CA0B0,
        surface2: 0xACB0BE, surface1: 0xBCC0CC, surface0: 0xCCD0DA,
        base: 0xEFF1F5, mantle: 0xE6E9EF, crust: 0xDCE0E8,
        statusNeeds: 0xAD4001, statusError: 0xD20F39, statusThinking: 0x8839EF,
        statusDone: 0x116E74, statusOutput: 0x2D711F, statusWaiting: 0x1E66F5,
        statusRunning: 0x0A6D86, statusIdle: 0x9CA0B0,
        statusOnLoud: 0xFFFFFF, statusOnQuiet: 0x4C4F69,
        tintBorderMauve: 0x8839EF, tintBorderPeach: 0xC14701, tintBorderTeal: 0x137B81,
        tintBorderSky: 0x0376A4, tintBorderGreen: 0x327E22,
        tintBorderLavender: 0x405CFC, tintBorderPink: 0xC91F9C,
        dividerRest: 0x82849A, dividerHover: 0x6F7288, shadow: 0x3C2814)

    static let mochaHC = AwPalette(
        rosewater: 0xFFF0ED, flamingo: 0xFFE0E0, pink: 0xFFD6F0, mauve: 0xDCC2FF,
        red: 0xFFB3C4, maroon: 0xFFC0C8, peach: 0xFFC8A3,
        yellow: 0xFFF0C2, green: 0xC2F5BD, teal: 0xB0F4EA, sky: 0xAEEFFF,
        sapphire: 0x9EE4FF, blue: 0xB7CCFF, lavender: 0xD0D8FF,
        text: 0xFFFFFF, subtext1: 0xF2F5FF, subtext0: 0xE8EDFF,
        overlay2: 0xDDE4FF, overlay1: 0xD5DCFB, overlay0: 0xCDD6F4,
        surface2: 0x585B70, surface1: 0x45475A, surface0: 0x313244,
        base: 0x1E1E2E, mantle: 0x181825, crust: 0x11111B,
        statusNeeds: 0xFFC8A3, statusError: 0xFFB3C4, statusThinking: 0xDCC2FF,
        statusDone: 0xB0F4EA, statusOutput: 0xC2F5BD, statusWaiting: 0xB7CCFF,
        statusRunning: 0x9EE4FF, statusIdle: 0xCDD6F4,
        statusOnLoud: 0x12121C, statusOnQuiet: 0xFFFFFF,
        tintBorderMauve: 0xDCC2FF, tintBorderPeach: 0xFFC8A3, tintBorderTeal: 0xB0F4EA,
        tintBorderSky: 0xAEEFFF, tintBorderGreen: 0xC2F5BD,
        tintBorderLavender: 0xD0D8FF, tintBorderPink: 0xFFD6F0,
        dividerRest: 0x9399B2, dividerHover: 0xA6ADC8, shadow: 0x000000)

    static let latteHC = AwPalette(
        rosewater: 0x963B31, flamingo: 0x963737, pink: 0x9A2D82, mauve: 0x6F20D1,
        red: 0xB00030, maroon: 0xA82D37, peach: 0x9B3D07,
        yellow: 0x835100, green: 0x29661C, teal: 0x00685C, sky: 0x0058A8,
        sapphire: 0x00627D, blue: 0x084FBD, lavender: 0x354FB5,
        text: 0x0A0A14, subtext1: 0x15151F, subtext0: 0x1E1E2E,
        overlay2: 0x27273B, overlay1: 0x303049, overlay0: 0x3A3A55,
        surface2: 0xACB0BE, surface1: 0xBCC0CC, surface0: 0xCCD0DA,
        base: 0xEFF1F5, mantle: 0xE6E9EF, crust: 0xDCE0E8,
        statusNeeds: 0x9B3D07, statusError: 0xB00030, statusThinking: 0x6F20D1,
        statusDone: 0x00685C, statusOutput: 0x29661C, statusWaiting: 0x084FBD,
        statusRunning: 0x00627D, statusIdle: 0x3A3A55,
        statusOnLoud: 0xFFFFFF, statusOnQuiet: 0xFFFFFF,
        tintBorderMauve: 0x6F20D1, tintBorderPeach: 0x9B3D07, tintBorderTeal: 0x00685C,
        tintBorderSky: 0x0058A8, tintBorderGreen: 0x29661C,
        tintBorderLavender: 0x354FB5, tintBorderPink: 0x9A2D82,
        dividerRest: 0x6C6F85, dividerHover: 0x5C5F77, shadow: 0x3C2814)
}

// MARK: - Dynamic color resolution (appearance-aware)

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// A color that resolves through the active appearance's Catppuccin palette
    /// (Mocha / Latte / mocha-hc / latte-hc), live, including Increase Contrast.
    static func aw(_ key: KeyPath<AwPalette, UInt32> & Sendable) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua,
                .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            let palette: AwPalette = switch match {
            case .some(.darkAqua): .mocha
            case .some(.accessibilityHighContrastDarkAqua): .mochaHC
            case .some(.accessibilityHighContrastAqua): .latteHC
            default: .latte
            }
            return NSColor(hex: palette[keyPath: key])
        })
    }
}

// MARK: - Semantic roles (the only names product code uses)

enum Aw {
    // surfaces
    static let surfaceWindow = Color.aw(\.base)
    static let surfaceChrome = Color.aw(\.mantle)
    static let surfaceChrome2 = Color.aw(\.crust)
    static let surfaceSidebar = Color.aw(\.mantle)
    static let surfaceElevated = Color.aw(\.surface0)
    static let surfaceHover = Color.aw(\.text).opacity(0.06)
    static let surfaceActive = Color.aw(\.text).opacity(0.10)

    // text — four AA-guaranteed steps
    static let text1 = Color.aw(\.text)
    static let text2 = Color.aw(\.subtext0)
    static let text3 = Color.aw(\.overlay1)
    static let textFaint = Color.aw(\.overlay0)

    // borders — hairlines only
    static let border = Color.aw(\.text).opacity(0.08)
    static let border2 = Color.aw(\.text).opacity(0.14)

    static let shadowColor = Color.aw(\.shadow)

    // status
    static let statusError = Color.aw(\.statusError)
    static let statusThinking = Color.aw(\.statusThinking)
    static let statusDone = Color.aw(\.statusDone)
    static let statusRunning = Color.aw(\.statusRunning)
    static let statusIdle = Color.aw(\.statusIdle)
}

// MARK: - Accent (single global choice, default peach)

enum AwAccent: String, CaseIterable, Sendable {
    case peach, mauve, sapphire, green

    var color: Color {
        switch self {
        case .peach: Color.aw(\.peach)
        case .mauve: Color.aw(\.mauve)
        case .sapphire: Color.aw(\.sapphire)
        case .green: Color.aw(\.green)
        }
    }
}

private struct AwAccentKey: EnvironmentKey {
    static let defaultValue: AwAccent = .peach
}

extension EnvironmentValues {
    var awAccent: AwAccent {
        get { self[AwAccentKey.self] }
        set { self[AwAccentKey.self] = newValue }
    }
}

// MARK: - Workspace tints (speaker hues, AI-lavender)

enum AwTint: String, CaseIterable, Sendable {
    case mauve, peach, teal, sky, green, lavender, pink

    var color: Color {
        switch self {
        case .mauve: Color.aw(\.mauve)
        case .peach: Color.aw(\.peach)
        case .teal: Color.aw(\.teal)
        case .sky: Color.aw(\.sky)
        case .green: Color.aw(\.green)
        case .lavender: Color.aw(\.lavender)
        case .pink: Color.aw(\.pink)
        }
    }

    /// Latte-darkened hairline counterpart (`--tint-border-*`).
    var borderColor: Color {
        switch self {
        case .mauve: Color.aw(\.tintBorderMauve)
        case .peach: Color.aw(\.tintBorderPeach)
        case .teal: Color.aw(\.tintBorderTeal)
        case .sky: Color.aw(\.tintBorderSky)
        case .green: Color.aw(\.tintBorderGreen)
        case .lavender: Color.aw(\.tintBorderLavender)
        case .pink: Color.aw(\.tintBorderPink)
        }
    }
}

// MARK: - Typography (AwFont: system for prose, mono for data)

enum AwFont {
    static let display = Font.system(size: 26, weight: .semibold)
    static let sectionHead = Font.system(size: 17, weight: .semibold)
    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let label = Font.system(size: 12, weight: .medium)
    static let meta = Font.system(size: 11)

    static let monoBody = Font.system(size: 13, design: .monospaced)
    static let monoMeta = Font.system(size: 11, design: .monospaced)
    static let kicker = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let pill = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let kbd = Font.system(size: 10, weight: .semibold, design: .monospaced)
}

/// Mono, bold, UPPERCASE, letter-spaced section label ("TRANSCRIPT", "RECENT", "AI").
struct KickerText: View {
    let text: String
    var color: Color = Aw.textFaint

    var body: some View {
        Text(text.uppercased())
            .font(AwFont.kicker)
            .tracking(0.9) // 0.09em at 10pt
            .foregroundStyle(color)
    }
}

// MARK: - Shape & spacing

enum AwRadius {
    static let chip: CGFloat = 3
    static let kbd: CGFloat = 4
    static let pill: CGFloat = 5
    static let button: CGFloat = 6
    static let panel: CGFloat = 8
    static let window: CGFloat = 10
}

enum AwSpace {
    static let panelPadding: CGFloat = 18
    static let sectionGap: CGFloat = 26
    static let chromeFooter: CGFloat = 38
    static let chromeTitlebar: CGFloat = 38
    static let fieldHeight: CGFloat = 30
}

// MARK: - Depth (soft downward shadows; CSS blur ≈ 2 × SwiftUI radius)

enum AwShadow {
    case window, overlay, sheet, toast, handle

    var parameters: (radius: CGFloat, y: CGFloat, opacity: Double) {
        switch self {
        case .window: (12, 18, 0.30)
        case .overlay: (8, 10, 0.24)
        case .sheet: (14, 22, 0.30)
        case .toast: (9, 12, 0.24)
        case .handle: (4, 4, 0.16)
        }
    }
}

extension View {
    func awShadow(_ style: AwShadow) -> some View {
        let p = style.parameters
        return shadow(color: Aw.shadowColor.opacity(p.opacity), radius: p.radius, y: p.y)
    }

    /// Hairline-bordered, rounded surface — the standard card/control chrome.
    func awSurface(_ fill: Color, radius: CGFloat, borderColor: Color, borderWidth: CGFloat = 0.5) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(borderColor, lineWidth: borderWidth))
    }
}
