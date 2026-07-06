// One track = one WAV file. Buffers arrive in whatever format the source
// delivers (tap format, mic hardware format, and that format can change
// mid-recording when the default device switches); every buffer is converted
// at capture time to 16 kHz mono Int16 and written incrementally through
// AVAudioFile, so the file on disk is always a real WAV.

import Accelerate
@preconcurrency import AVFoundation
import Foundation

/// Snapshot of a track's health: the UI's "audio flowing" signal, and the
/// TCC-denial detector (a denied permission shows up as dead or never-flowing).
public struct TrackState: Sendable {
    public enum Health: String, Sendable {
        /// Recent buffers with audible level.
        case flowing
        /// Recent buffers, but pure silence (target quiet, or TCC denial).
        case silent
        /// No buffer for over 2 s while not dead: the source stopped
        /// delivering (device switch in flight, tap waiting for the target
        /// to become audio-capable, engine wedged).
        case stalled
        case dead
    }

    public let health: Health
    /// Peak of the most recent buffer, 0...1.
    public let level: Float
    /// Maximum level seen over the whole session.
    public let sessionPeak: Float
    /// Frames written at 16 kHz.
    public let framesWritten: Int64
    public let lastBufferAt: Date?
    public let error: String?

    public var seconds: Double { Double(framesWritten) / TrackWriter.outputFormat.sampleRate }
    public var everFlowed: Bool { framesWritten > 0 && sessionPeak > 0.001 }
}

public final class TrackWriter: @unchecked Sendable {
    /// Locked decision: capture-time conversion to 16 kHz mono Int16 WAV.
    public static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    public let url: URL

    private let lock = NSLock()
    private let createdAt = Date()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var outBuffer: AVAudioPCMBuffer?
    private var levelScratch: [Float] = []
    private var lastBufferAt: Date?
    private var lastLevel: Float = 0
    private var sessionPeak: Float = 0
    private var framesWritten: Int64 = 0
    private var deadReason: String?

    public init(url: URL) throws {
        self.url = url
        self.file = try AVAudioFile(
            forWriting: url, settings: Self.outputFormat.settings,
            commonFormat: .pcmFormatInt16, interleaved: true)
    }

    /// Called from the audio IO thread. Converts and appends; any failure
    /// marks this track dead without touching the other track.
    public func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard deadReason == nil, let file else { return }

        // Rebuild the converter when the input format changes (e.g. AirPods
        // becoming the default mic); the file just keeps appending.
        if converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.outputFormat)
            converterInputFormat = buffer.format
            outBuffer = nil // capacity math depends on the input rate
        }
        guard let converter else {
            deadReason = "no converter from \(buffer.format)"
            return
        }

        // Reuse the output buffer across calls; rebuild only when the
        // converter rebuilt or the needed capacity grew (no per-buffer
        // allocation on the IO path).
        let ratio = Self.outputFormat.sampleRate / buffer.format.sampleRate
        let needed = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        if outBuffer == nil || outBuffer!.frameCapacity < needed {
            outBuffer = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: needed)
        }
        guard let out = outBuffer else { return }
        out.frameLength = 0

        // The input block runs synchronously inside convert(); the Sendable
        // annotation on AVAudioConverterInputBlock is stricter than reality.
        nonisolated(unsafe) var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: out, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow // keep converter state warm for the next buffer
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            deadReason = "conversion failed: \(conversionError?.localizedDescription ?? "unknown")"
            return
        }
        if out.frameLength > 0 {
            do {
                try file.write(from: out)
            } catch {
                deadReason = "write failed: \(error.localizedDescription)"
                return
            }
            framesWritten += Int64(out.frameLength)
            // Level from the CONVERTED Int16 output: the format is ours by
            // construction, so a non-float source can never fake silence
            // (floatChannelData on an Int16 input buffer is nil).
            lastLevel = peakOfInt16Locked(out)
            sessionPeak = max(sessionPeak, lastLevel)
        }
        lastBufferAt = Date()
    }

    /// A dead track stops accepting buffers but keeps its file and stats; the
    /// first recorded reason wins.
    public func markDead(_ reason: String) {
        lock.lock()
        defer { lock.unlock() }
        if deadReason == nil { deadReason = reason }
    }

    /// Flushes the converter tail, then finalizes the WAV header.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        // The converter runs one buffer behind by its priming/latency delay
        // (~60 ms): flush it with .endOfStream so the final words before Stop
        // reach the file, THEN close.
        if deadReason == nil, let converter, let file,
           let tail = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: 8192) {
            var flushError: NSError?
            let status = converter.convert(to: tail, error: &flushError) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }
            if status != .error, tail.frameLength > 0, (try? file.write(from: tail)) != nil {
                framesWritten += Int64(tail.frameLength)
            }
        }
        // ponytail: an unclean death (kill -9, panic, power loss) leaves the
        // WAV header unfinalized because AVAudioFile patches it here on close.
        // Upgrade path: periodically patch the header in place, or record to
        // CAF (headerless-tolerant) and convert on finalize.
        file?.close()
        file = nil
        converter = nil
        outBuffer = nil
    }

    /// `now` is injectable for tests of the stalled-vs-silent derivation.
    public func state(now: Date = Date()) -> TrackState {
        lock.lock()
        defer { lock.unlock() }
        let sinceLastBuffer = now.timeIntervalSince(lastBufferAt ?? createdAt)
        let health: TrackState.Health
        if deadReason != nil {
            health = .dead
        } else if sinceLastBuffer > 2 {
            health = .stalled
        } else if lastBufferAt != nil, lastLevel > 0.001 {
            health = .flowing
        } else {
            health = .silent
        }
        return TrackState(
            health: health, level: lastLevel, sessionPeak: sessionPeak,
            framesWritten: framesWritten, lastBufferAt: lastBufferAt, error: deadReason)
    }

    /// Peak magnitude of a mono interleaved Int16 buffer, 0...1. Vectorized:
    /// vDSP_vflt16 into a reused scratch array, then vDSP_maxmgv.
    private func peakOfInt16Locked(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.int16ChannelData, buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        if levelScratch.count < count {
            levelScratch = [Float](repeating: 0, count: count)
        }
        var peak: Float = 0
        levelScratch.withUnsafeMutableBufferPointer { scratch in
            vDSP_vflt16(data[0], 1, scratch.baseAddress!, 1, vDSP_Length(count))
            vDSP_maxmgv(scratch.baseAddress!, 1, &peak, vDSP_Length(count))
        }
        return peak / Float(Int16.max)
    }
}
