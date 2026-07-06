# awesoMeeting

A local-first macOS meeting recorder / transcriber / notes app — native SwiftUI,
Apple-Silicon only. Sibling of [awesoMux](https://github.com/Interactive-Buffoonery/awesomux) - an open source, visually pleasing terminal that works well with your agents and is based on libghostty. 

Our goal with awesoMeeting is to allow you to take meeting notes with local AI, freeing you up to pay attention to the call. You can type notes during a call while audio is
captured and transcribed on-device; a local LLM enhances them into a structured
summary at meeting end. Transcript + diarization of the meeting can then happen once the meeting is complete. 

In short: meeting software that's not ugly.

## Local by default

All AI models used with awesoMeeting are local-only unless you bring your own API key and/or AI provider, and specifically ask awesoMeeting to send your data to that provider. 

You own your notes and the audio files. Everything is saved locally and notes are all in Markdown. Your notes, transcript, and summary all export as `.md` files. 

### AI models — three tiers of escalating control

- **Tier 0 — bundled, the default.** awesoMeeting ships with a small local model
  (Gemma 4 E4B via Apple MLX; E2B on low-RAM Macs) so notes and summaries work
  out of the box with zero setup. It loads on demand for an enhancement pass and
  unloads afterward — it never sits resident in memory.
- **Tier 1 — bring your own endpoint.** Point awesoMeeting at LM Studio, Ollama,
  or any OpenAI-compatible URL — a bigger local model or a cloud provider with
  your API key. If you already have an endpoint running, awesoMeeting prefers it
  instead of loading its own.
- **Tier 2 — pipe to external tools.** Send a transcript or your notes to any
  CLI that reads stdin (`claude -p`, `codex exec`, `pi`, …) for the heaviest or
  agentic processing. Everything is files and stdout, so it composes.

### iCloud sync (planned)

A future release will add optional sync of your meetings across your Macs via
CloudKit, which will include the following privacy guidelines: 

- **Off by default.** If you never turn it on, nothing ever leaves your Mac.
- **Your iCloud, not our servers.** Synced meetings live in your iCloud
  account's private database, encrypted in transit and at rest. awesoMeeting
  runs no servers, and we cannot read your data.
- **AI stays on-device either way.** Sync moves your finished notes and
  transcripts between your machines; recording, transcription, and enhancement
  still happen locally.

## Status & roadmap

Early development. The full UI runs today on mock data (see it with
`swift run`). Our next step is to build the backend, including: 

- [x] Design system + three-column app shell (notes, transcript, AI summary)
- [ ] Audio capture — mic (AVAudioEngine) + system audio (Core Audio process
      taps), recorded as two separate tracks so "you" vs "everyone else" comes
      free before diarization even runs
- [ ] On-device transcription — FluidAudio running Parakeet, on the Neural
      Engine (whisper.cpp as the fallback for languages Parakeet doesn't cover)
- [ ] Speaker diarization — FluidAudio, feeding the in-app correction flow
      (rename a speaker on one line or across the whole meeting)
- [ ] Note enhancement through the three model tiers above
- [ ] CLI add-on — the same core, scriptable:
      `awesomeeting transcribe meeting.wav | claude -p "…"`
- [ ] Optional iCloud sync (CloudKit)

## Terminal workflow (no Xcode GUI needed)

```sh
swift run                          # launch the app
swift test                         # run the checks
swift run AwesoMeeting --snapshot <dir>   # design review: writes Mocha + Latte
                                          # PNGs of the main window, no
                                          # screen-recording permission needed
```

## Development notes

### Layout

- `Sources/AwesoMeeting/DesignSystem/` — the token port (`AwTokens`: Catppuccin ×
  4 appearances resolved live per NSAppearance incl. Increase Contrast; semantic
  roles only — never the raw ramp) and the components: `StatusDot`, `AwPill`,
  `KBD`, `Waveform`, `SpeakerTag`, `AwButtonStyle`, `SegmentedTabs`.
- `Sources/AwesoMeeting/Model.swift` — domain types, the `AppModel` store, mock
  data, and the backend seams: `Transcriber`, `NotesEnhancer` protocols with mock
  implementations. The real backend (AVAudioEngine + Core Audio process taps,
  FluidAudio for Parakeet transcription + diarization, MLX-hosted Gemma for
  enhancement) plugs in here without touching a view.
- `Sources/AwesoMeeting/Views/` — the Mail-style three-column app: sidebar with
  the record footer, notes-primary center column (AI blocks lavender-distinct,
  never overwriting raw notes), tabbed Transcript / AI Summary detail with the
  first-class speaker-rename flow, plus the menu-bar recording controller
  (appearance + accent switching lives there).

Accent (peach / mauve / sapphire / green) and appearance (System / Mocha / Latte)
persist via UserDefaults. `⌘⇧R` records from anywhere via the Meeting menu.
