// Unit tests for the parts of the capture core that don't need TCC:
// WAV writing / format-conversion round-trips, track-state derivation,
// process-tree enumeration, session file guards, and harness arg parsing.

import AVFoundation
@testable import AwesoMeeting
@testable import AwesoMeetingCore
import Foundation
import Testing

struct CaptureCoreTests {
    private func tempWAV() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("awm-test-\(UUID().uuidString).wav")
    }

    /// Builds a float sine buffer in the shape a tap/mic delivers.
    private func sineBuffer(rate: Double, channels: AVAudioChannelCount, seconds: Double,
                            amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                samples[i] = sinf(2 * .pi * 440 * Float(i) / Float(rate)) * amplitude
            }
        }
        return buffer
    }

    @Test func wavRoundTripIs16kMonoInt16() throws {
        let url = tempWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try TrackWriter(url: url)
        writer.append(sineBuffer(rate: 48_000, channels: 2, seconds: 1.0))
        let state = writer.state()
        writer.close()

        #expect(state.everFlowed)
        #expect(abs(state.level - 0.5) < 0.02) // peak of the input sine

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        // close() flushes the converter tail, so the duration is no longer
        // trimmed by the converter's ~60 ms priming/latency delay.
        #expect(abs(Double(file.length) / 16_000 - 1.0) < 0.02)

        // The sine survives conversion: read back and check the peak.
        let readBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: readBuffer)
        var peak: Float = 0
        let samples = readBuffer.floatChannelData![0]
        for i in 0..<Int(readBuffer.frameLength) { peak = max(peak, abs(samples[i])) }
        #expect(peak > 0.4 && peak < 0.6)
    }

    @Test func inputFormatChangeMidStreamKeepsAppending() throws {
        // A default-device switch changes the tap format mid-recording; the
        // writer must rebuild its converter and keep appending to the file.
        let url = tempWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try TrackWriter(url: url)
        writer.append(sineBuffer(rate: 48_000, channels: 2, seconds: 0.5))
        writer.append(sineBuffer(rate: 44_100, channels: 1, seconds: 0.5))
        let state = writer.state()
        writer.close()

        #expect(state.health != .dead)
        #expect(abs(state.seconds - 1.0) < 0.1)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
    }

    @Test func deadTrackIgnoresBuffersAndKeepsReason() throws {
        let url = tempWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try TrackWriter(url: url)
        writer.append(sineBuffer(rate: 48_000, channels: 1, seconds: 0.1))
        let framesBefore = writer.state().framesWritten
        writer.markDead("simulated device death")
        writer.markDead("later reason must not win")
        writer.append(sineBuffer(rate: 48_000, channels: 1, seconds: 0.1))
        let state = writer.state()
        writer.close()

        #expect(state.health == .dead)
        #expect(state.error == "simulated device death")
        #expect(state.framesWritten == framesBefore) // no writes after death
    }

    @Test func stalledIsDistinctFromSilent() throws {
        let url = tempWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try TrackWriter(url: url)
        defer { writer.close() }

        // No buffer ever, more than 2 s after creation: stalled, not silent.
        #expect(writer.state(now: Date().addingTimeInterval(3)).health == .stalled)
        // Buffers arriving but with zero level: silent.
        writer.append(sineBuffer(rate: 48_000, channels: 1, seconds: 0.1, amplitude: 0))
        #expect(writer.state().health == .silent)
        // Audible buffer: flowing.
        writer.append(sineBuffer(rate: 48_000, channels: 1, seconds: 0.1))
        #expect(writer.state().health == .flowing)
        // Buffers stop for more than 2 s while not dead: stalled again.
        #expect(writer.state(now: Date().addingTimeInterval(3)).health == .stalled)
    }

    @Test func levelComesFromConvertedOutputForInt16Input() throws {
        // An Int16 source has no floatChannelData; a level computed from the
        // input would read as permanent silence. The level must come from the
        // converted output instead.
        let url = tempWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try TrackWriter(url: url)
        defer { writer.close() }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: true)!
        let frames = AVAudioFrameCount(4800)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.int16ChannelData![0]
        for i in 0..<Int(frames) {
            samples[i] = Int16(sinf(2 * .pi * 440 * Float(i) / 48_000) * 0.5 * Float(Int16.max))
        }
        writer.append(buffer)
        let state = writer.state()
        #expect(abs(state.level - 0.5) < 0.05)
        #expect(state.sessionPeak > 0.4)
    }

    @Test func sessionRefusesExistingWAV() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awm-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("system.wav").path, contents: Data())

        #expect(throws: CaptureError.self) { try CaptureSession(directory: dir) }
    }

    @Test func sessionRefusesSymlinkAtTargetPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awm-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("mic.wav"),
            withDestinationURL: URL(fileURLWithPath: "/dev/null"))

        #expect(throws: CaptureError.self) { try CaptureSession(directory: dir) }
    }

    @Test func processTreeVisitedSetSurvivesPPIDCycle() {
        // A racing pid-table scan can hand back a stale ppid that forms a
        // cycle; the walk must terminate and not duplicate entries.
        let tree = ProcessTree.pids(rootedAt: 1, childrenByParent: [1: [2], 2: [3, 1], 3: [3]])
        #expect(tree.sorted() == [1, 2, 3])
    }

    // MARK: - capture-check argument parsing

    @Test func captureCheckParsesValidTargets() throws {
        let base = ["AwesoMeeting", "--capture-check", "5", "--out", "/tmp/x"]
        let pid = try #require(try CaptureCheck.parse(base + ["--pid", "123"]))
        guard case .pid(123) = pid.target else { Issue.record("expected .pid(123)"); return }
        #expect(pid.seconds == 5)
        #expect(pid.outDir == "/tmp/x")

        let app = try #require(try CaptureCheck.parse(base + ["--app", "Music"]))
        guard case .app(named: "Music") = app.target else { Issue.record("expected .app(Music)"); return }

        let everything = try #require(try CaptureCheck.parse(base + ["--everything"]))
        guard case .everything = everything.target else { Issue.record("expected .everything"); return }

        // No --capture-check flag at all: not our run mode.
        #expect(try CaptureCheck.parse(["AwesoMeeting", "--snapshot", "/tmp"]) == nil)
    }

    @Test(arguments: [
        // bad pid values
        ["--capture-check", "5", "--pid", "abc", "--out", "/tmp/x"],
        ["--capture-check", "5", "--pid", "-4", "--out", "/tmp/x"],
        // missing values (next token is another flag, or nothing)
        ["--capture-check", "5", "--pid", "--out", "/tmp/x"],
        ["--capture-check", "5", "--app", "--out", "/tmp/x"],
        ["--capture-check", "5", "--everything", "--out", "/tmp/x", "--app"],
        // --pid and --app together
        ["--capture-check", "5", "--pid", "123", "--app", "Music", "--out", "/tmp/x"],
        // no target: record-everything must never be a silent fallback
        ["--capture-check", "5", "--out", "/tmp/x"],
        // bad or missing duration / missing --out
        ["--capture-check", "abc", "--everything", "--out", "/tmp/x"],
        ["--capture-check", "0", "--everything", "--out", "/tmp/x"],
        ["--capture-check", "5", "--everything"],
    ])
    func captureCheckRejectsMalformedArgs(_ args: [String]) {
        #expect(throws: CaptureError.self) { try CaptureCheck.parse(["AwesoMeeting"] + args) }
    }

    @Test func processTreeFindsSpawnedChild() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["10"]
        try child.run()
        defer { child.terminate() }

        let root = getpid()
        let tree = ProcessTree.pids(rootedAt: root)
        #expect(tree.contains(root))
        #expect(tree.contains(child.processIdentifier))
        // Unrelated process (launchd) must not appear.
        #expect(!tree.contains(1))
    }
}
