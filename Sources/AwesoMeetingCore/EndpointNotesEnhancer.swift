// Tier 1 NotesEnhancer: sends the user's notes + transcript to an
// OpenAI-compatible endpoint and returns the enhanced text. The "AI never
// overwrites raw notes" invariant lives in AppModel (it appends a distinct
// block) — this just returns text.

import Foundation

public struct EndpointNotesEnhancer: NotesEnhancer {
    let client: OpenAICompatibleClient

    public init(client: OpenAICompatibleClient) {
        self.client = client
    }

    public init(config: EndpointConfig) {
        self.init(client: OpenAICompatibleClient(config: config))
    }

    public func enhance(_ meeting: Meeting) async throws -> String {
        try await client.chatCompletion(messages: Self.promptMessages(for: meeting))
    }

    /// Compact prompt: the user's own notes plus the speaker-labeled
    /// transcript, with a strict "don't invent content" instruction.
    // ponytail: transcript is unbounded and can overflow a local model's
    // context window; truncation/chunking strategy pending research (2026-07-06).
    static func promptMessages(for meeting: Meeting) -> [ChatMessage] {
        let notes = meeting.notes.filter { $0.kind == .user }
            .map { "- \($0.text)" }
            .joined(separator: "\n")
        let transcript = meeting.transcript
            .map { "[\($0.time)] \(meeting.speakerName(for: $0)): \($0.text)" }
            .joined(separator: "\n")

        let system = """
            You clean up and structure a user's own meeting notes. Use only \
            information present in their notes and the transcript. Never invent \
            facts, names, dates, or action items that are not there. Reply with \
            the enhanced notes as plain Markdown only, no preamble or commentary. \
            If you use headings, use level 3 (###) or deeper, and never skip \
            levels. Use hyphen bullets for lists.
            """
        var user = "Meeting: \(meeting.title)\n\nMy raw notes:\n\(notes)"
        if !transcript.isEmpty {
            user += "\n\nTranscript:\n\(transcript)"
        }
        user += "\n\nRewrite my raw notes as clear, structured Markdown."
        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: user),
        ]
    }
}
