// App store + SwiftUI glue. Domain types and the backend protocols
// (Transcriber, NotesEnhancer) live in AwesoMeetingCore — the UI only talks
// to AppModel.

import AwesoMeetingCore
import Foundation
import Observation
import SwiftUI

// MARK: - SwiftUI-facing extensions on Core types

extension PipelineState {
    func color(accent: AwAccent) -> Color {
        switch self {
        case .recording: accent.color
        case .transcribing: Aw.statusRunning
        case .diarizing: Aw.statusThinking
        case .done: Aw.statusDone
        case .error: Aw.statusError
        case .idle: Aw.statusIdle
        }
    }
}

// MARK: - App store

enum AppearanceChoice: String, CaseIterable {
    case system, mocha, latte

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .mocha: .dark
        case .latte: .light
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .mocha: "Mocha"
        case .latte: "Latte"
        }
    }
}

@MainActor @Observable
final class AppModel {
    var meetings: [Meeting]
    var selectedID: String?
    var searchText = ""
    var isRecording = false
    var isEnhancing = false
    var enhanceError: String?

    var accent: AwAccent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") }
    }

    var appearance: AppearanceChoice {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    private var recordingStart: Date?
    private let transcriber: Transcriber
    private let enhancer: NotesEnhancer

    init(transcriber: Transcriber = MockTranscriber(), enhancer: NotesEnhancer = MockNotesEnhancer()) {
        self.meetings = MockData.meetings
        self.selectedID = MockData.meetings.first?.id
        self.transcriber = transcriber
        self.enhancer = enhancer
        self.accent = AwAccent(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .peach
        self.appearance = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    var filteredMeetings: [Meeting] {
        guard !searchText.isEmpty else { return meetings }
        return meetings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var selectedMeeting: Meeting? {
        meetings.first { $0.id == selectedID }
    }

    private func update(_ id: String, _ mutate: (inout Meeting) -> Void) {
        guard let i = meetings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&meetings[i])
    }

    // MARK: Recording pipeline (mock-driven; see Services below)

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        let meeting = Meeting(
            id: UUID().uuidString, title: "New meeting", dateLabel: "Now", duration: "0 min",
            state: .recording, speakers: [], notes: [], transcript: [], summary: nil)
        meetings.insert(meeting, at: 0)
        selectedID = meeting.id
        recordingStart = .now
        isRecording = true
    }

    private func stopRecording() {
        guard let id = meetings.first(where: { $0.state == .recording })?.id else {
            isRecording = false
            return
        }
        let minutes = max(1, Int((recordingStart.map { Date.now.timeIntervalSince($0) } ?? 60) / 60))
        isRecording = false
        recordingStart = nil
        update(id) {
            $0.state = .transcribing
            $0.duration = "\(minutes) min"
        }
        Task {
            let result = await transcriber.transcribe(meetingID: id)
            update(id) {
                $0.state = .done
                $0.speakers = result.speakers
                $0.transcript = result.transcript
                $0.summary = result.summary
            }
        }
    }

    // MARK: Notes

    func addUserNote(_ text: String) {
        guard let id = selectedID, !text.isEmpty else { return }
        update(id) { $0.notes.append(NoteBlock(kind: .user, text: text)) }
    }

    /// AI enhancement never overwrites raw notes: it appends a distinct
    /// block. Failures never become notes: they land in `enhanceError`.
    func enhanceNotes() {
        guard !isEnhancing, let meeting = selectedMeeting,
              meeting.notes.contains(where: { $0.kind == .user }) || !meeting.transcript.isEmpty
        else { return }
        isEnhancing = true
        Task {
            defer { isEnhancing = false }
            do {
                let text = try await enhancer.enhance(meeting)
                update(meeting.id) { $0.notes.append(NoteBlock(kind: .ai, text: text)) }
                enhanceError = nil
            } catch is CancellationError {
                // cancelled on purpose: no note, no error
            } catch {
                enhanceError = error.localizedDescription
            }
        }
    }

    // MARK: Speaker rename (first-class correction flow)

    enum RenameScope { case line, all }

    func renameSpeaker(meetingID: String, lineID: UUID, to name: String, scope: RenameScope) {
        update(meetingID) { meeting in
            switch scope {
            case .line:
                if let i = meeting.transcript.firstIndex(where: { $0.id == lineID }) {
                    meeting.transcript[i].speakerNameOverride = name
                }
            case .all:
                guard let line = meeting.transcript.first(where: { $0.id == lineID }),
                      let s = meeting.speakers.firstIndex(where: { $0.id == line.speakerID }) else { return }
                meeting.speakers[s].name = name
                for i in meeting.transcript.indices where meeting.transcript[i].speakerID == line.speakerID {
                    meeting.transcript[i].speakerNameOverride = nil
                }
            }
        }
    }
}

// MARK: - Backend seam mocks
// ponytail: the protocols live in AwesoMeetingCore. Real implementations
// later: AVAudioEngine mic + Core Audio process taps for system audio,
// captured as two separate tracks; FluidAudio (Parakeet) for transcription +
// diarization on the ANE, whisper.cpp fallback; enhancement through the
// tiered model system (bundled Gemma 4 via MLX → OpenAI-compatible endpoint
// [EndpointNotesEnhancer, done] → external CLI pipe).

struct MockTranscriber: Transcriber {
    func transcribe(meetingID: String) async -> TranscriptionResult {
        try? await Task.sleep(for: .seconds(2.5))
        let speakers = [Speaker(id: "s1", name: "Sarah", index: 0), Speaker(id: "s2", name: "Speaker 2", index: 1)]
        return TranscriptionResult(
            speakers: speakers,
            transcript: [
                TranscriptLine(time: "00:00:04", speakerID: "s1", text: "Okay, we're recording — let's get started."),
                TranscriptLine(time: "00:00:11", speakerID: "s2", text: "Great. First up: the roadmap review."),
            ],
            summary: MeetingSummary(
                highlights: ["Roadmap review kicked off."],
                decisions: [],
                nextSteps: []))
    }
}

struct MockNotesEnhancer: NotesEnhancer {
    func enhance(_ meeting: Meeting) async throws -> String {
        try await Task.sleep(for: .seconds(0.8))
        return "Meeting notes enhanced — key points structured and action items extracted into the AI Summary tab."
    }
}

// MARK: - Mock data (port of ui_kits/awesomeeting/data.js)

enum MockData {
    static let meetings: [Meeting] = [
        Meeting(
            id: "m1", title: "Weekly sync — Growth", dateLabel: "Today, 10:00", duration: "42 min",
            state: .done,
            speakers: [
                Speaker(id: "s1", name: "Sarah", index: 0),
                Speaker(id: "s2", name: "Marcus", index: 1),
                Speaker(id: "s3", name: "Speaker 3", index: 2),
            ],
            notes: [
                NoteBlock(kind: .user, text: "Q3 launch — need to lock the date today."),
                NoteBlock(kind: .user, text: "Onboarding revamp is the blocker. Design done, eng est. 1.5 wk."),
                NoteBlock(kind: .ai, text: "The team aligned on shipping the onboarding revamp before the Q3 launch. Engineering estimated 1.5 weeks of work; design is complete and handed off."),
                NoteBlock(kind: .user, text: "activation dip — cohort from the paid campaign"),
                NoteBlock(kind: .ai, text: "Sarah flagged an activation dip isolated to the paid-campaign cohort. Marcus will pull the funnel breakdown before the go/no-go call."),
            ],
            transcript: [
                TranscriptLine(time: "00:02:14", speakerID: "s1", text: "Let's lock the launch date before we leave today."),
                TranscriptLine(time: "00:02:20", speakerID: "s2", text: "Agreed. I'll own the go/no-go by Thursday."),
                TranscriptLine(time: "00:02:41", speakerID: "s1", text: "The onboarding revamp is the real blocker for me."),
                TranscriptLine(time: "00:03:02", speakerID: "s3", text: "Design's done — I handed the specs to eng on Monday."),
                TranscriptLine(time: "00:03:15", speakerID: "s2", text: "Eng came back with about a week and a half."),
                TranscriptLine(time: "00:04:38", speakerID: "s1", text: "One more thing — activation dipped last week."),
                TranscriptLine(time: "00:04:47", speakerID: "s1", text: "It's isolated to the paid-campaign cohort though."),
                TranscriptLine(time: "00:05:03", speakerID: "s2", text: "I'll pull the funnel breakdown before the call."),
            ],
            summary: MeetingSummary(
                highlights: [
                    "Q3 launch date to be locked pending the onboarding revamp.",
                    "Activation dip isolated to the paid-campaign cohort — not systemic.",
                ],
                decisions: [
                    "Ship the onboarding revamp before the Q3 launch.",
                    "Go/no-go decision owned by Marcus, due Thursday.",
                ],
                nextSteps: [
                    .init(who: "Marcus", by: "Thu", task: "Own the go/no-go decision"),
                    .init(who: "Marcus", by: "Wed", task: "Pull paid-cohort funnel breakdown"),
                    .init(who: "Sarah", by: "Fri", task: "Confirm launch date with leadership"),
                ])),
        Meeting(
            id: "m2", title: "1:1 — Priya", dateLabel: "Today, 09:15", duration: "18 min",
            state: .transcribing,
            speakers: [
                Speaker(id: "s1", name: "Sarah", index: 0),
                Speaker(id: "s4", name: "Priya", index: 3),
            ],
            notes: [NoteBlock(kind: .user, text: "career growth — wants more backend scope")],
            transcript: [], summary: nil),
        Meeting(
            id: "m3", title: "Design review — Recorder", dateLabel: "Yesterday, 16:30", duration: "55 min",
            state: .done,
            speakers: [
                Speaker(id: "s1", name: "Sarah", index: 0),
                Speaker(id: "s5", name: "Devon", index: 4),
                Speaker(id: "s6", name: "Speaker 6", index: 5),
            ],
            notes: [NoteBlock(kind: .user, text: "menu-bar waveform as state machine — approved")],
            transcript: [], summary: nil),
    ]
}
