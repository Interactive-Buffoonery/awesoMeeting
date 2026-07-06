// Microphone capture via AVAudioEngine's input-node tap. installTapOnBus
// signals misuse with NSException (uncatchable from Swift), so every install
// goes through the CAudioShim Obj-C bridge.

@preconcurrency import AVFoundation
import CAudioShim
import Foundation

/// Bridges an NSException raised inside `body` to a throwable Swift error.
func catchingNSException(_ body: () -> Void) throws {
    if let error = awm_tryBlock(body) { throw error }
}

public final class MicCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "awm.mic")
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private var writer: TrackWriter?

    public init() {}

    // Plain teardown(), NOT queue.sync: deinit can only run once nothing else
    // holds self, so the queued restart hop (which captures self weakly) can
    // never race it, and queue.sync here could deadlock against a scheduled
    // block on `queue`.
    deinit { teardown() }

    public func start(into writer: TrackWriter) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw CaptureError("microphone permission denied. Enable it in System Settings > Privacy & Security > Microphone, then try again.")
        }
        // queue.sync from an async context parks one cooperative-pool thread
        // while the engine starts; capture start is rare and quick, so this is
        // an accepted tradeoff. Upgrade path: make MicCapture an actor and let
        // the engine work hop to it instead of a dispatch queue.
        try queue.sync {
            guard engine == nil else { throw CaptureError("mic already started") }
            self.writer = writer
            let engine = AVAudioEngine()
            self.engine = engine
            try installTapAndStart(engine)
            // Default-device switch (e.g. AirPods connecting): the engine stops
            // and posts a configuration change; restart on the new device and
            // keep appending to the same file. Weak hop so a queued restart
            // never holds the last strong reference to self.
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                self?.queue.async { [weak self] in self?.restart() }
            }
        }
    }

    public func stop() {
        queue.sync { teardown() }
    }

    private func teardown() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        writer = nil
    }

    // MARK: - Internals (all on `queue`)

    private func installTapAndStart(_ engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A device switch can briefly expose a 0 Hz format; installing a tap
        // with it raises (and a converter from it is meaningless).
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError("mic input format unavailable (rate \(format.sampleRate))")
        }
        let writer = self.writer
        try catchingNSException {
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                writer?.append(buffer)
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func restart() {
        guard let engine, writer != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTapAndStart(engine)
        } catch {
            // ponytail: one-shot restart, no retry — a switching device can
            // expose a transient bad format and this gives up immediately.
            // Upgrade path: bounded retry-with-backoff before declaring death.
            writer?.markDead("mic restart failed: \(error.localizedDescription)")
        }
    }
}
