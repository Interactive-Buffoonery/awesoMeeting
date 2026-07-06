// A recording = one system-audio track + one mic track, written as
// <dir>/system.wav and <dir>/mic.wav. Hard rule: one track dying never stops
// the other — a dead track is marked dead and the session continues.

import Darwin
import Foundation

public final class CaptureSession: Sendable {
    public let directory: URL
    public let systemTrack: TrackWriter
    public let micTrack: TrackWriter

    private let systemTap = SystemAudioTap()
    private let mic = MicCapture()

    public init(directory: URL) throws {
        self.directory = directory
        // Recordings are private conversations: owner-only directory and files.
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var wavURLs: [URL] = []
        for name in ["system.wav", "mic.wav"] {
            let url = directory.appendingPathComponent(name)
            // Refuse to clobber an existing recording, and refuse a symlink at
            // the target path (lstat, so a link is seen as itself, not what it
            // points to; opening through one would write wherever it points).
            var status = stat()
            if lstat(url.path, &status) == 0 {
                let kind = (status.st_mode & S_IFMT) == S_IFLNK ? "a symlink" : "a file"
                throw CaptureError("refusing to record into \(url.path): \(kind) already exists there")
            }
            wavURLs.append(url)
        }
        self.systemTrack = try TrackWriter(url: wavURLs[0])
        self.micTrack = try TrackWriter(url: wavURLs[1])
        for url in wavURLs {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Starts both tracks independently; a failed start marks that track dead
    /// (with the reason — e.g. a TCC denial) and the other keeps recording.
    public func start(target: CaptureTarget) async {
        do {
            try systemTap.start(target: target, into: systemTrack)
        } catch {
            systemTrack.markDead(error.localizedDescription)
        }
        do {
            try await mic.start(into: micTrack)
        } catch {
            micTrack.markDead(error.localizedDescription)
        }
    }

    public func stop() {
        systemTap.stop()
        mic.stop()
        systemTrack.close()
        micTrack.close()
    }

    /// Per-track health for the UI (and the harness): flowing/silent/dead plus
    /// last-buffer time and level — this is also the TCC-denial detector.
    public var systemState: TrackState { systemTrack.state() }
    public var micState: TrackState { micTrack.state() }

    // ponytail: a track that dies mid-session just ends early, so the two WAVs
    // can desync against wall clock. Upgrade path: timeline-anchor silence
    // insertion — anchor frame 0 to host time and pad device-death gaps with
    // zeros so both files stay the same length.
    // ponytail: no sample-rate drift detection; ceiling is audible desync on
    // very long recordings when a device's real clock runs off-nominal.
    // Upgrade path: compare frames written against host-time elapsed and
    // correct when the ratio diverges.
    // ponytail: no engine/tap resurrection — a dead track stays dead for the
    // session; ceiling is losing the rest of a meeting to a transient failure.
    // Upgrade path: retry-with-backoff restart that reuses the same TrackWriter
    // (combined with the silence insertion above to bridge the gap).
}
