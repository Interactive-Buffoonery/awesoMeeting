// Domain value types + backend seams, moved out of the app target so the
// headless core (and a future CLI) can consume them. SwiftUI-facing bits
// (e.g. PipelineState colors) live as extensions in the app target.

import Foundation

public enum PipelineState: String, Sendable {
    case recording, transcribing, diarizing, done, error, idle

    public var label: String {
        switch self {
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .diarizing: "Diarizing"
        case .done: "Done"
        case .error: "Error"
        case .idle: "Idle"
        }
    }
}

public struct Speaker: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public let index: Int

    public init(id: String, name: String, index: Int) {
        self.id = id
        self.name = name
        self.index = index
    }
}

public struct NoteBlock: Identifiable, Sendable {
    public enum Kind: Sendable { case user, ai }
    public let id = UUID()
    public let kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct TranscriptLine: Identifiable, Sendable {
    public let id = UUID()
    public let time: String
    public let speakerID: String
    public var speakerNameOverride: String? // "just this line" rename scope
    public let text: String

    public init(time: String, speakerID: String, speakerNameOverride: String? = nil, text: String) {
        self.time = time
        self.speakerID = speakerID
        self.speakerNameOverride = speakerNameOverride
        self.text = text
    }
}

public struct MeetingSummary: Sendable {
    public struct NextStep: Sendable {
        public let who: String
        public let by: String
        public let task: String

        public init(who: String, by: String, task: String) {
            self.who = who
            self.by = by
            self.task = task
        }
    }

    public var highlights: [String]
    public var decisions: [String]
    public var nextSteps: [NextStep]

    public init(highlights: [String], decisions: [String], nextSteps: [NextStep]) {
        self.highlights = highlights
        self.decisions = decisions
        self.nextSteps = nextSteps
    }
}

public struct Meeting: Identifiable, Sendable {
    public let id: String
    public var title: String
    public var dateLabel: String // ponytail: display string like the design's mock data; make it a Date when real recordings land
    public var duration: String
    public var state: PipelineState
    public var speakers: [Speaker]
    public var notes: [NoteBlock]
    public var transcript: [TranscriptLine]
    public var summary: MeetingSummary?

    public init(
        id: String, title: String, dateLabel: String, duration: String,
        state: PipelineState, speakers: [Speaker], notes: [NoteBlock],
        transcript: [TranscriptLine], summary: MeetingSummary?
    ) {
        self.id = id
        self.title = title
        self.dateLabel = dateLabel
        self.duration = duration
        self.state = state
        self.speakers = speakers
        self.notes = notes
        self.transcript = transcript
        self.summary = summary
    }

    public var isProcessing: Bool {
        state == .recording || state == .transcribing || state == .diarizing
    }

    public func speakerName(for line: TranscriptLine) -> String {
        line.speakerNameOverride ?? speakers.first { $0.id == line.speakerID }?.name ?? "Speaker"
    }

    public func speaker(id: String) -> Speaker? {
        speakers.first { $0.id == id }
    }

    // Markdown-first: notes, transcript & summary export as plain Markdown.
    public var markdown: String {
        var out = "# \(title)\n\n`\(dateLabel) · \(duration) · \(speakers.count) speakers · recorded on-device`\n"
        if !notes.isEmpty {
            out += "\n## Notes\n\n"
            for block in notes {
                switch block.kind {
                case .user: out += "\(block.text)\n\n"
                case .ai: out += "> **AI:** \(block.text)\n\n"
                }
            }
        }
        if let summary {
            out += "## Summary\n\n### Highlights\n\n"
            out += summary.highlights.map { "- \($0)\n" }.joined()
            out += "\n### Decisions\n\n"
            out += summary.decisions.map { "- \($0)\n" }.joined()
            out += "\n### Next steps\n\n"
            out += summary.nextSteps.map { "- [ ] \($0.task) (@\($0.who), \($0.by))\n" }.joined()
            out += "\n"
        }
        if !transcript.isEmpty {
            out += "## Transcript\n\n"
            for line in transcript {
                out += "**[\(line.time)] \(speakerName(for: line)):** \(line.text)\n\n"
            }
        }
        return out
    }
}

// MARK: - Backend seams

public struct TranscriptionResult: Sendable {
    public let speakers: [Speaker]
    public let transcript: [TranscriptLine]
    public let summary: MeetingSummary?

    public init(speakers: [Speaker], transcript: [TranscriptLine], summary: MeetingSummary?) {
        self.speakers = speakers
        self.transcript = transcript
        self.summary = summary
    }
}

public protocol Transcriber: Sendable {
    func transcribe(meetingID: String) async -> TranscriptionResult
}

/// Errors must never become notes: implementations throw, and the caller
/// decides how to surface the failure.
public protocol NotesEnhancer: Sendable {
    func enhance(_ meeting: Meeting) async throws -> String
}
