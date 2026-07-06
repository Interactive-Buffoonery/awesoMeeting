import Testing
@testable import AwesoMeeting

@MainActor
struct AwesoMeetingTests {
    @Test func markdownExportHasAllSections() {
        let meeting = MockData.meetings[0]
        let md = meeting.markdown
        #expect(md.hasPrefix("# Weekly sync — Growth"))
        #expect(md.contains("## Notes"))
        #expect(md.contains("> **AI:**")) // AI blocks stay distinct in the export
        #expect(md.contains("## Summary"))
        #expect(md.contains("- [ ] Own the go/no-go decision — @Marcus, Thu"))
        #expect(md.contains("**[00:02:14] Sarah:** Let's lock the launch date"))
    }

    @Test func speakerTintIsStableAndCycles() {
        #expect(speakerTint(0) == .mauve)
        #expect(speakerTint(6) == .pink)
        #expect(speakerTint(7) == .mauve) // wraps
        #expect(speakerTint(3) == speakerTint(3))
    }

    @Test func renameScopes() {
        let model = AppModel()
        let meeting = MockData.meetings[0]
        let sarahLines = meeting.transcript.filter { $0.speakerID == "s1" }

        // "just this line" — only that line shows the new name
        model.renameSpeaker(meetingID: meeting.id, lineID: sarahLines[0].id, to: "S. Wolff", scope: .line)
        let afterLine = model.meetings[0]
        #expect(afterLine.speakerName(for: afterLine.transcript[0]) == "S. Wolff")
        #expect(afterLine.speakerName(for: sarahLines[1]) == "Sarah")

        // "all lines" — speaker renamed everywhere, line overrides cleared
        model.renameSpeaker(meetingID: meeting.id, lineID: sarahLines[1].id, to: "Sarah W", scope: .all)
        let afterAll = model.meetings[0]
        for line in afterAll.transcript where line.speakerID == "s1" {
            #expect(afterAll.speakerName(for: line) == "Sarah W")
        }
    }

    @Test func enhanceAppendsAndNeverOverwrites() async {
        let model = AppModel(enhancer: MockNotesEnhancer())
        let before = model.meetings[0].notes
        model.enhanceNotes()
        try? await Task.sleep(for: .seconds(1.2))
        let after = model.meetings[0].notes
        #expect(after.count == before.count + 1)
        #expect(after.last?.kind == .ai)
        for (a, b) in zip(before, after) { #expect(a.text == b.text) } // raw notes untouched
    }
}
