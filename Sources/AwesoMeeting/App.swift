// awesoMeeting: local-first macOS meeting recorder.
// Mail-style three-column layout; recording also reachable from the menu bar.

import SwiftUI
import AppKit

@main
struct AwesoMeetingApp: App {
    @State private var model = AppModel()

    // Design review from the terminal, no screen-recording permission needed:
    // `swift run AwesoMeeting --snapshot <dir>` captures the main window in
    // Mocha + Latte, then opens Settings and captures every tab per theme
    // (plus the high-contrast ramps and an expanded AI Models variant),
    // writes PNGs, and exits.
    private static let snapshotDir: String? = {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshot"),
              CommandLine.arguments.indices.contains(i + 1) else { return nil }
        return CommandLine.arguments[i + 1]
    }()

    private static let themes: [(String, NSAppearance.Name)] = [("mocha", .darkAqua), ("latte", .aqua)]

    @MainActor private static func writePNG(of view: NSView, named name: String, dir: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("error: could not create bitmap rep for \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            print("error: could not encode PNG for \(name)")
            return
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        do {
            try png.write(to: url)
            print("wrote \(url.path)")
        } catch {
            print("error: could not write \(url.path): \(error)")
        }
    }

    @MainActor fileprivate static func captureSnapshots(model: AppModel, to dir: String,
                                                        openSettings: () -> Void) async {
        // A persisted Mocha/Latte choice would clobber the per-theme window
        // override below (preferredColorScheme wins over window.appearance).
        model.appearance = .system
        try? await Task.sleep(for: .seconds(1)) // let layout settle

        // Main window, Mocha + Latte (unchanged).
        for (name, appearance) in themes {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView else {
                print("error: no visible main window for \(name)")
                continue
            }
            window.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .seconds(0.4))
            writePNG(of: view, named: "awesomeeting-\(name)", dir: dir)
        }

        // Settings window: every tab per theme, including the high-contrast
        // ramps (proves the HC palettes and the vanishing shadows).
        openSettings()
        var waited = 0.0
        while SettingsWindowRef.window == nil && waited < 5 {
            try? await Task.sleep(for: .seconds(0.2))
            waited += 0.2
        }
        guard let window = SettingsWindowRef.window, let view = window.contentView else {
            print("error: settings window did not appear within 5s; settings snapshots missing")
            exit(1)
        }
        let settingsThemes = themes + [
            ("mocha-hc", NSAppearance.Name.accessibilityHighContrastDarkAqua),
            ("latte-hc", .accessibilityHighContrastAqua),
        ]
        for (name, appearance) in settingsThemes {
            window.appearance = NSAppearance(named: appearance)
            // AppKit strips the HC appearances back to plain aqua/darkAqua
            // unless the OS "Increase Contrast" setting is on. A capture then
            // would just duplicate the plain theme under an HC filename, so
            // skip and say so instead of faking it.
            if name.hasSuffix("-hc"), window.effectiveAppearance.name != appearance {
                print("warning: \(name) resolves to \(window.effectiveAppearance.name.rawValue); "
                    + "turn on System Settings > Accessibility > Display > Increase Contrast "
                    + "and rerun to capture the HC variants")
                continue
            }
            for tab in SettingsTab.allCases {
                model.settingsTab = tab
                await settle(window) // tab switches animate a window resize
                writePNG(of: view, named: "settings-\(tab.rawValue)-\(name)", dir: dir)
            }
            // AI Models again with Options 2 + 3 on and the custom-endpoint
            // disclosure open, so the expanded designs are reviewable.
            // Snapshot-only; defaults stay off.
            do {
                SettingsWindowRef.expandedAIOptions = true
                defer { SettingsWindowRef.expandedAIOptions = false }
                model.settingsTab = .aiModels // fresh tab identity re-reads the preset
                await settle(window)
                writePNG(of: view, named: "settings-ai-models-expanded-\(name)", dir: dir)
            }
            model.settingsTab = .general
            await settle(window)
        }
        exit(0)
    }

    /// Wait until the window's animated resize finishes (frame stable for two
    /// consecutive 0.2s reads, capped at 4s).
    @MainActor private static func settle(_ window: NSWindow) async {
        var last = window.frame
        var stableReads = 0
        for _ in 0..<20 {
            try? await Task.sleep(for: .seconds(0.2))
            if window.frame == last {
                stableReads += 1
                if stableReads >= 2 { return }
            } else {
                stableReads = 0
                last = window.frame
            }
        }
        print("warning: window frame did not settle within 4s; capturing anyway")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(\.awAccent, model.accent)
                .preferredColorScheme(model.appearance.colorScheme)
                .frame(minWidth: 900, minHeight: 560)
                .background {
                    if let dir = Self.snapshotDir { SnapshotDriver(model: model, dir: dir) }
                }
        }
        .defaultSize(width: 1080, height: 700)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Meeting") {
                Button(model.isRecording ? "Stop Recording" : "Start Recording") {
                    model.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Enhance Notes") { model.enhanceNotes() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.selectedMeeting == nil)
            }
        }

        // ⌘,: design-pass mock; all controls are dummy state except appearance/accent.
        Settings {
            SettingsRootView()
                .environment(model)
                .environment(\.awAccent, model.accent)
                .preferredColorScheme(model.appearance.colorScheme)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarControllerView()
                .environment(model)
                .environment(\.awAccent, model.accent)
                .preferredColorScheme(model.appearance.colorScheme)
        } label: {
            Image(systemName: model.isRecording ? "waveform.badge.microphone" : "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Invisible: exists only to reach the `openSettings` environment action,
/// which lives on views, not on the App.
private struct SnapshotDriver: View {
    let model: AppModel
    let dir: String
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.task {
            await AwesoMeetingApp.captureSnapshots(model: model, to: dir) { openSettings() }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: DetailTab = .transcript

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            HStack(spacing: 0) {
                SidebarView()
                Aw.border.frame(width: 0.5)
                if let meeting = model.selectedMeeting {
                    NotesEditorView(meeting: meeting)
                    Aw.border.frame(width: 0.5)
                    DetailPanelView(meeting: meeting, tab: $tab)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "mic").font(.system(size: 20))
                        Text("No meeting selected").font(AwFont.monoMeta)
                    }
                    .foregroundStyle(Aw.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Aw.surfaceWindow)
                }
            }
        }
        .background(Aw.surfaceWindow)
        .ignoresSafeArea(.container, edges: .top) // titlebar row abuts the traffic lights
        .onChange(of: model.selectedID) { tab = .transcript }
    }

    // Custom 38pt chrome row abutting the native traffic lights (.hiddenTitleBar).
    private var titlebar: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 58) // traffic-light carve-out
            Spacer()
            Text(model.selectedMeeting?.title ?? "awesoMeeting")
                .font(AwFont.label)
                .fontWeight(.semibold)
                .foregroundStyle(Aw.text2)
            Spacer()
            Button {
                model.toggleRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10))
                    Text("New")
                }
            }
            .buttonStyle(AwButtonStyle(variant: .secondary, size: .sm))
            .padding(.trailing, 14)
        }
        .frame(minHeight: AwSpace.chromeTitlebar)
        .background(Aw.surfaceChrome)
        .overlay(alignment: .bottom) { Aw.border.frame(height: 0.5) }
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}
