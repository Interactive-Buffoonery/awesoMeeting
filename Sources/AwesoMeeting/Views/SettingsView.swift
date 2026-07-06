// Settings: DESIGN-PASS MOCK. Every control here is local @State with
// plausible dummy values; nothing persists and nothing reaches a backend.
// The two exceptions are appearance + accent, which bind to the real AppModel
// (same pattern as the menu-bar controller) so the panel demos the tokens live.

import SwiftUI
import AppKit

// MARK: - Tab geometry (the SettingsTab enum itself lives in Model.swift)

// ponytail: hand-tuned heights: NSHostingView under-measures wrapping row
// captions in the Settings scene and compresses the layout. Revisit when
// the panel gets real (text-scale-aware) sizing.
private extension SettingsTab {
    var height: CGFloat {
        switch self {
        case .general: 400
        case .recording: 505
        case .transcription: 425
        case .aiModels: 720
        case .privacy: 450
        }
    }
}

/// AI Models reports how far its interactive expansions (options 2/3, custom
/// endpoint) grow it past the hand-tuned base height, so the fixed frame can
/// follow instead of clipping.
private struct ExtraHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

/// Snapshot hook: `--snapshot` needs the settings NSWindow to retheme + capture.
@MainActor enum SettingsWindowRef {
    static weak var window: NSWindow?
    /// Snapshot-only preset: renders AI Models with Options 2 and 3 toggled on
    /// so their expanded designs are reviewable. Never set outside --snapshot;
    /// the real defaults stay off.
    static var expandedAIOptions = false
}

private struct WindowGrabber: NSViewRepresentable {
    final class GrabView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SettingsWindowRef.window = window }
        }
    }

    func makeNSView(context: Context) -> NSView { GrabView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Root

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @State private var aiModelsExtraHeight: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SegmentedTabs(tabs: SettingsTab.allCases.map { .init(id: $0, label: $0.label) },
                          selection: $model.settingsTab,
                          label: "Settings section")
                .padding(.top, 14)
            Group {
                switch model.settingsTab {
                case .general: GeneralTab()
                case .recording: RecordingTab()
                case .transcription: TranscriptionTab()
                case .aiModels: AIModelsTab(allOptionsOn: SettingsWindowRef.expandedAIOptions)
                case .privacy: PrivacyTab()
                }
            }
            .padding(AwSpace.panelPadding)
            Spacer(minLength: 0)
        }
        .onPreferenceChange(ExtraHeightKey.self) { [$aiModelsExtraHeight] value in
            $aiModelsExtraHeight.wrappedValue = value
        }
        // Base height per tab, plus whatever AI Models reports for its expanded
        // option cards (interactive toggles and the snapshot preset alike).
        .frame(width: 640,
               height: model.settingsTab.height
                   + (model.settingsTab == .aiModels ? aiModelsExtraHeight : 0),
               alignment: .top)
        .background(Aw.surfaceWindow)
        .background(WindowGrabber())
    }
}

// MARK: - Section / row scaffolding (settings-local, not generic DS material)

private struct SettingsSection<Content: View>: View {
    let kicker: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            KickerText(text: kicker)
                .padding(.leading, 2)
            VStack(spacing: 0) { content }
                .awSurface(Aw.surfaceElevated.opacity(0.5), radius: AwRadius.panel,
                           borderColor: Aw.border)
            if let footnote {
                Text(footnote)
                    .font(AwFont.meta)
                    .foregroundStyle(Aw.text3)
                    .padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    var caption: String?
    /// Off-state hint for OptionSection: dims only the caption, never below
    /// 0.8, so the text stays readable and the live control stays full-strength.
    var dimCaption = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(AwFont.body).foregroundStyle(Aw.text1)
                if let caption {
                    Text(caption)
                        .font(AwFont.meta)
                        .foregroundStyle(Aw.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(dimCaption ? 0.8 : 1)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: AwSpace.fieldHeight + 4)
    }
}

private struct RowDivider: View {
    var body: some View {
        Aw.border.frame(height: 0.5).padding(.leading, 14)
    }
}

// MARK: - Settings-local controls (mock chrome around native inputs)

private struct AwToggle: View {
    let label: String // VoiceOver name; visually hidden (the row shows it)
    @Binding var isOn: Bool
    @Environment(\.awAccent) private var accent

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(accent.color)
    }
}

/// Dropdown with design-system chrome; option values are data, so mono.
private struct AwMenuPicker: View {
    let label: String // VoiceOver name; the row shows it visually
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { selection = option }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection)
                    .font(AwFont.monoMeta)
                    .foregroundStyle(Aw.text1)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Aw.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .awSurface(Aw.surfaceChrome2, radius: AwRadius.button, borderColor: Aw.border2)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(selection)
    }
}

/// Plain text/secure field in the standard field chrome; contents are data → mono.
private struct AwField: View {
    let label: String // VoiceOver name; the row shows it visually
    let placeholder: String
    @Binding var text: String
    var secure = false
    var width: CGFloat = 190

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .accessibilityLabel(label)
        .font(AwFont.monoMeta)
        .foregroundStyle(Aw.text1)
        .padding(.horizontal, 8)
        .frame(width: width, height: AwSpace.fieldHeight - 4)
        .awSurface(Aw.surfaceChrome2, radius: AwRadius.button, borderColor: Aw.border)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.awAccent) private var accent
    // ponytail: mock state: real persistence lands with the preferences store
    @State private var textScale = 1.0
    @State private var launchAtLogin = false
    @State private var showMenuBarIcon = true

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: AwSpace.sectionGap - 8) {
            SettingsSection(kicker: "Appearance") {
                SettingsRow(label: "Theme") {
                    SegmentedTabs(tabs: AppearanceChoice.allCases.map { .init(id: $0, label: $0.label) },
                                  selection: $model.appearance,
                                  label: "Appearance")
                }
                RowDivider()
                SettingsRow(label: "Accent") {
                    HStack(spacing: 8) {
                        ForEach(AwAccent.allCases, id: \.self) { choice in
                            AccentSwatch(choice: choice, selected: model.accent == choice) {
                                model.accent = choice
                            }
                            .frame(width: 36)
                        }
                    }
                }
                RowDivider()
                SettingsRow(label: "Interface text scale",
                            caption: "Menus and labels only. Notes and transcript keep their own sizes.") {
                    HStack(spacing: 10) {
                        Slider(value: $textScale, in: 0.85...1.35)
                            .controlSize(.small)
                            .tint(accent.color)
                            .frame(width: 140)
                            .accessibilityLabel("Interface text scale")
                            .accessibilityValue(String(format: "%.2f times", textScale))
                        Text(String(format: "%.2f×", textScale))
                            .font(AwFont.monoMeta)
                            .foregroundStyle(Aw.text2)
                            .frame(width: 44, alignment: .trailing)
                            .accessibilityHidden(true) // the slider already speaks this value
                    }
                }
            }
            SettingsSection(kicker: "System") {
                SettingsRow(label: "Launch at login") {
                    AwToggle(label: "Launch at login", isOn: $launchAtLogin)
                }
                RowDivider()
                SettingsRow(label: "Show menu-bar icon",
                            caption: "Recording stays one click away while the window is closed.") {
                    AwToggle(label: "Show menu-bar icon", isOn: $showMenuBarIcon)
                }
            }
        }
    }
}

// MARK: - Recording

/// Auto-start states. State is color + SHAPE: each option keeps a distinct
/// glyph, and the color only appears on top of that shape.
private enum AutoStart: String, CaseIterable {
    case off, notify, autoRecord

    var label: String {
        switch self {
        case .off: "Off"
        case .notify: "Notify"
        case .autoRecord: "Auto-record"
        }
    }

    var symbol: String {
        switch self {
        case .off: "circle.slash"
        case .notify: "bell"
        case .autoRecord: "record.circle"
        }
    }

    func color(accent: AwAccent) -> Color {
        switch self {
        case .off: Aw.statusIdle
        case .notify: Aw.statusRunning
        case .autoRecord: accent.color
        }
    }
}

private struct AutoStartControl: View {
    @Binding var selection: AutoStart
    @Environment(\.awAccent) private var accent

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AutoStart.allCases, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selected ? option.color(accent: accent) : Aw.text3)
                        Text(option.label)
                            .font(AwFont.label)
                            .foregroundStyle(selected ? Aw.text1 : Aw.text3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: AwRadius.pill)
                            .fill(selected ? Aw.surfaceElevated : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: AwRadius.pill))
                }
                .buttonStyle(.plain)
                .if(selected) { $0.awShadow(.handle) }
            }
        }
        .padding(2)
        .awSurface(Aw.surfaceChrome2, radius: AwRadius.button, borderColor: Aw.border)
        .animation(.easeOut(duration: 0.12), value: selection)
        // VoiceOver gets a real radio group with a value; visuals unchanged.
        .accessibilityRepresentation {
            Picker("When a call starts", selection: $selection) {
                ForEach(AutoStart.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
        }
    }
}

private struct RecordingTab: View {
    // ponytail: dummy devices/apps: real lists come from AVFoundation + the process tap
    @State private var micDevice = "MacBook Pro Microphone"
    @State private var systemSource = "Whatever is playing"
    @State private var keepAudio = true
    @State private var autoStart: AutoStart = .notify
    @State private var calendarNaming = true

    var body: some View {
        VStack(alignment: .leading, spacing: AwSpace.sectionGap - 8) {
            SettingsSection(
                kicker: "Capture",
                footnote: "Your mic and the meeting audio are recorded separately, labeled Me and Them."
            ) {
                SettingsRow(label: "Microphone") {
                    AwMenuPicker(label: "Microphone",
                                 options: ["MacBook Pro Microphone", "AirPods Pro",
                                           "Scarlett 2i2 USB", "Studio Display Microphone"],
                                 selection: $micDevice)
                }
                RowDivider()
                SettingsRow(label: "System audio",
                            caption: "The app whose audio joins the recording.") {
                    AwMenuPicker(label: "System audio",
                                 options: ["Whatever is playing", "Zoom", "Microsoft Teams",
                                           "Google Chrome", "Safari"],
                                 selection: $systemSource)
                }
            }
            SettingsSection(kicker: "Storage") {
                SettingsRow(label: "Location") {
                    HStack(spacing: 10) {
                        Text("~/Music/awesoMeeting")
                            .font(AwFont.monoMeta)
                            .foregroundStyle(Aw.text2)
                        Button("Change…") {}
                            .buttonStyle(AwButtonStyle(variant: .secondary, size: .sm))
                            .accessibilityLabel("Change storage location")
                    }
                    .accessibilityElement(children: .contain) // path + button read together
                }
                RowDivider()
                SettingsRow(label: "Keep audio after transcription",
                            caption: "Off frees disk space once the transcript is done.") {
                    AwToggle(label: "Keep audio after transcription", isOn: $keepAudio)
                }
            }
            SettingsSection(
                kicker: "Auto-start",
                footnote: "Watches call apps only. Zoom, Teams, and a browser tab in a call."
            ) {
                // ponytail: caption must stay one line: a wrap here miscomputes
                // the settings window height (ideal-width text measurement).
                SettingsRow(label: "When a call starts",
                            caption: "Notify asks first; Auto-record just starts.") {
                    AutoStartControl(selection: $autoStart)
                }
                RowDivider()
                SettingsRow(label: "Name recordings from your calendar",
                            caption: "Uses the event that overlaps the recording start.") {
                    AwToggle(label: "Name recordings from your calendar", isOn: $calendarNaming)
                }
            }
        }
    }
}

// MARK: - Transcription

private struct TranscriptionTab: View {
    @State private var engine = "Parakeet"
    @State private var language = "Auto-detect"
    @State private var diarization = true
    @State private var meLabel = "Me"
    @State private var themLabel = "Them"

    var body: some View {
        VStack(alignment: .leading, spacing: AwSpace.sectionGap - 8) {
            SettingsSection(
                kicker: "Engine",
                footnote: "Parakeet is the default and is fastest on this Mac. Whisper steps in when your language needs it."
            ) {
                SettingsRow(label: "Engine") {
                    SegmentedTabs(tabs: [.init(id: "Parakeet", label: "Parakeet"),
                                         .init(id: "Whisper", label: "Whisper")],
                                  selection: $engine,
                                  label: "Engine")
                }
                RowDivider()
                SettingsRow(label: "Language") {
                    AwMenuPicker(label: "Language",
                                 options: ["Auto-detect", "English", "German", "French",
                                           "Spanish", "Japanese"],
                                 selection: $language)
                }
            }
            SettingsSection(kicker: "Speakers") {
                SettingsRow(label: "Tell speakers apart",
                            caption: "Splits the transcript by who was talking.") {
                    AwToggle(label: "Tell speakers apart", isOn: $diarization)
                }
                RowDivider()
                SettingsRow(label: "You appear as") {
                    AwField(label: "You appear as", placeholder: "Me", text: $meLabel, width: 120)
                }
                RowDivider()
                SettingsRow(label: "Others appear as") {
                    AwField(label: "Others appear as", placeholder: "Them", text: $themLabel, width: 120)
                }
            }
        }
    }
}

// MARK: - AI Models

/// One numbered enhancement option: kicker, an enable row, detail rows that
/// only exist while enabled. Off = collapsed to the header row, so the state
/// survives without color (shape change, not color alone). The collapse itself
/// carries the off state; the Enabled row stays full-strength because its
/// toggle is live, and only the kicker/caption dim, never below 0.8, so the
/// text keeps readable contrast.
private struct OptionSection<Content: View>: View {
    let kicker: String
    let enableCaption: String
    @Binding var isOn: Bool
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            KickerText(text: kicker)
                .padding(.leading, 2)
                .opacity(isOn ? 1 : 0.8)
            VStack(spacing: 0) {
                SettingsRow(label: "Enabled", caption: enableCaption, dimCaption: !isOn) {
                    // VoiceOver: "Option 2, Your local endpoint, enabled" beats three bare "Enabled"s.
                    AwToggle(label: "\(kicker) enabled", isOn: $isOn)
                }
                if isOn {
                    RowDivider()
                    content
                }
            }
            .awSurface(Aw.surfaceElevated.opacity(0.5), radius: AwRadius.panel,
                       borderColor: Aw.border)
            if isOn, let footnote {
                Text(footnote)
                    .font(AwFont.meta)
                    .foregroundStyle(Aw.text3)
                    .padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AIModelsTab: View {
    // ponytail: mock state, nothing persists (design pass)
    @State private var builtInOn = true
    @State private var keepLoaded = false
    @State private var endpointOn: Bool
    @State private var preferEndpoint = true
    @State private var showCustomEndpoint: Bool

    /// `allOptionsOn` is the snapshot preset; the shipped default is false.
    /// It also opens the custom-endpoint disclosure so its fields get a PNG.
    init(allOptionsOn: Bool = false) {
        _endpointOn = State(initialValue: allOptionsOn)
        _pipesOn = State(initialValue: allOptionsOn)
        _showCustomEndpoint = State(initialValue: allOptionsOn)
    }
    @State private var endpointURL = ""
    @State private var apiKey = ""
    @State private var endpointModel = ""
    @State private var pipesOn: Bool
    @State private var templateOneOnOne = "Paragraph"
    @State private var templateTeamSync = "Bullets"
    @State private var templateDesignReview = "Agenda"
    @State private var templateDefault = "Bullets"
    @State private var autonomy = "Balanced"

    private static let templates = ["Bullets", "Agenda", "Paragraph"]

    // ponytail: hand-tuned like the base heights (same NSHostingView
    // under-measurement); each term is the growth of one expansion. Interactive
    // toggles and the snapshot preset both flow through here.
    private var extraHeight: CGFloat {
        (endpointOn ? 150 : 0)
            + (pipesOn ? 130 : 0)
            + (endpointOn && showCustomEndpoint ? 150 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AwSpace.sectionGap - 8) {
            OptionSection(kicker: "Option 1 · Built-in",
                          enableCaption: "Runs on this Mac. Works out of the box.",
                          isOn: $builtInOn) {
                // ponytail: mock shows the post-download state; pre-download the
                // same row reads "Downloads on first use · 2.9 GB".
                SettingsRow(label: "Status") {
                    AwPill(text: "Ready", state: .done)
                }
                RowDivider()
                SettingsRow(label: "Keep model loaded",
                            caption: "Off frees memory when enhancement finishes.") {
                    AwToggle(label: "Keep model loaded", isOn: $keepLoaded)
                }
            }
            OptionSection(kicker: "Option 2 · Your local endpoint",
                          enableCaption: "Use an AI app you already run, like LM Studio or Ollama.",
                          isOn: $endpointOn) {
                SettingsRow(label: "LM Studio detected",
                            caption: "Found running on this Mac.") {
                    HStack(spacing: 10) {
                        Text("localhost:1234")
                            .font(AwFont.monoMeta)
                            .foregroundStyle(Aw.text2)
                        AwPill(text: "Reachable", state: .done)
                        Button("Test connection") {}
                            .buttonStyle(AwButtonStyle(variant: .secondary, size: .sm))
                    }
                }
                RowDivider()
                SettingsRow(label: "Prefer the detected endpoint",
                            caption: "Used when reachable. Built-in covers the rest.") {
                    AwToggle(label: "Prefer the detected endpoint", isOn: $preferEndpoint)
                }
                RowDivider()
                customEndpointRows
            }
            OptionSection(kicker: "Option 3 · Pipe to commands",
                          enableCaption: "Send the transcript and notes to a command you choose.",
                          isOn: $pipesOn,
                          footnote: "Each command receives the transcript and notes on stdin and prints the enhanced notes.") {
                pipeRow(name: "Claude", command: "claude -p")
                RowDivider()
                pipeRow(name: "Local llm", command: "llm")
                RowDivider()
                addRow("Add command")
            }
            SettingsSection(
                kicker: "Summary",
                footnote: "Meetings use their type’s template. Default covers everything else."
            ) {
                templateRow("1:1", $templateOneOnOne)
                RowDivider()
                templateRow("Team sync", $templateTeamSync)
                RowDivider()
                templateRow("Design review", $templateDesignReview)
                RowDivider()
                templateRow("Default", $templateDefault)
                RowDivider()
                addRow("Add meeting type")
                RowDivider()
                SettingsRow(label: "Autonomy",
                            caption: "How far the AI may reframe your notes.") {
                    SegmentedTabs(tabs: [.init(id: "Faithful", label: "Faithful"),
                                         .init(id: "Balanced", label: "Balanced"),
                                         .init(id: "Free", label: "Free")],
                                  selection: $autonomy,
                                  label: "Autonomy")
                }
            }
        }
        .preference(key: ExtraHeightKey.self, value: extraHeight)
    }

    /// Manual configuration, demoted behind a disclosure. Detection is the
    /// primary path; these rows exist for servers we can't find on our own.
    @ViewBuilder private var customEndpointRows: some View {
        Button {
            showCustomEndpoint.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showCustomEndpoint ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Aw.text3)
                    .frame(width: 10)
                Text("Custom endpoint…")
                    .font(AwFont.body)
                    .foregroundStyle(Aw.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ponytail: annotations, not a native DisclosureGroup: the native one
        // brings its own chevron/indent chrome, and the approved look stays.
        .accessibilityValue(showCustomEndpoint ? "expanded" : "collapsed")
        .accessibilityAddTraits(.isButton)
        if showCustomEndpoint {
            RowDivider()
            SettingsRow(label: "Endpoint URL") {
                AwField(label: "Endpoint URL",
                        placeholder: "http://localhost:11434/v1", text: $endpointURL, width: 230)
            }
            RowDivider()
            SettingsRow(label: "API key",
                        caption: "Optional. Stored in the macOS Keychain.") {
                AwField(label: "API key",
                        placeholder: "sk-…", text: $apiKey, secure: true, width: 230)
            }
            RowDivider()
            SettingsRow(label: "Model",
                        caption: "Leave empty to use whatever the server has loaded.") {
                AwField(label: "Model",
                        placeholder: "server default", text: $endpointModel, width: 160)
            }
        }
    }

    private func templateRow(_ type: String, _ selection: Binding<String>) -> some View {
        SettingsRow(label: type) {
            AwMenuPicker(label: "Template for \(type)", options: Self.templates, selection: selection)
        }
    }

    private func addRow(_ title: String) -> some View {
        HStack {
            Button {
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .medium))
                    Text(title)
                }
            }
            .buttonStyle(AwButtonStyle(variant: .ghost, size: .sm))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func pipeRow(name: String, command: String) -> some View {
        SettingsRow(label: name) {
            HStack(spacing: 10) {
                Text(command)
                    .font(AwFont.monoMeta)
                    .foregroundStyle(Aw.text2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .awSurface(Aw.surfaceChrome2, radius: AwRadius.chip, borderColor: Aw.border)
                Button {
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(AwButtonStyle(variant: .ghost, size: .sm))
                .help("Remove command")
                .accessibilityLabel("Remove \(name)")
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AwSpace.sectionGap - 8) {
            Text("Local by default. Recording, transcription, and note enhancement run entirely on this Mac. Nothing leaves it unless you turn on an option that sends data somewhere yourself.")
                .font(AwFont.body)
                .foregroundStyle(Aw.text1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
            SettingsSection(
                kicker: "What leaves this Mac",
                footnote: "Options you have not turned on send nothing, ever."
            ) {
                optionRow(1, "Built-in. Nothing leaves this Mac.")
                RowDivider()
                optionRow(2, "Your local endpoint. Transcript and notes go to the endpoint you chose.")
                RowDivider()
                optionRow(3, "Pipe to commands. Transcript and notes go to the command you run.")
            }
            SettingsSection(kicker: "Permissions") {
                SettingsRow(label: "System-audio access") {
                    Text("Requested on first recording")
                        .font(AwFont.monoMeta)
                        .foregroundStyle(Aw.text3)
                }
            }
            SettingsSection(kicker: "Sync") {
                SettingsRow(label: "iCloud sync",
                            caption: "Keep meetings on your other Macs.") {
                    HStack(spacing: 10) {
                        AwPill(text: "Coming later")
                        AwToggle(label: "iCloud sync", isOn: .constant(false))
                            .disabled(true)
                    }
                }
            }
        }
    }

    private func optionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            KickerText(text: "Option \(number)", color: Aw.text3)
                .frame(width: 62, alignment: .leading)
            Text(text)
                .font(AwFont.meta)
                .foregroundStyle(Aw.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
