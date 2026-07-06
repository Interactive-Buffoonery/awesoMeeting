// awesoMeeting — local-first macOS meeting recorder.
// Mail-style three-column layout; recording also reachable from the menu bar.

import SwiftUI
import AppKit

@main
enum Main {
    static func main() {
        // Headless capture diagnostic (--capture-check) runs before any UI;
        // exit code comes from the check. See CaptureCheck.swift.
        if let config = CaptureCheck.parseOrExit(CommandLine.arguments) {
            Task { exit(await CaptureCheck.run(config)) }
            dispatchMain() // parked until the Task above calls exit()
        } else {
            AwesoMeetingApp.main()
        }
    }
}

struct AwesoMeetingApp: App {
    @State private var model = AppModel()

    // Design review from the terminal, no screen-recording permission needed:
    // `swift run AwesoMeeting --snapshot <dir>` opens the window, captures its
    // own content view in Mocha + Latte, writes PNGs, and exits.
    private static let snapshotDir: String? = {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshot"),
              CommandLine.arguments.indices.contains(i + 1) else { return nil }
        return CommandLine.arguments[i + 1]
    }()

    @MainActor private static func captureSnapshots(to dir: String) async {
        try? await Task.sleep(for: .seconds(1)) // let layout settle
        for (name, appearance) in [("mocha", NSAppearance.Name.darkAqua), ("latte", .aqua)] {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView else { continue }
            window.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .seconds(0.4))
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    let url = URL(fileURLWithPath: dir).appendingPathComponent("awesomeeting-\(name).png")
                    try? png.write(to: url)
                    print("wrote \(url.path)")
                }
            }
        }
        exit(0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(\.awAccent, model.accent)
                .preferredColorScheme(model.appearance.colorScheme)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    if let dir = Self.snapshotDir { await Self.captureSnapshots(to: dir) }
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
