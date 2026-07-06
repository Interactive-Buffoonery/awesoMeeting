// Core Audio process tap: CATapDescription -> private aggregate device
// wrapping the default system output -> IO proc delivering PCM buffers.
// Sequence and teardown order follow Apple's sanctioned pattern (AudioCap).

import AppKit
import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

public enum CaptureTarget: Sendable {
    /// Tap one app by its root PID; the whole process tree is tapped.
    case pid(pid_t)
    /// Tap a running app by (localized) name; resolved to its PID, then tree.
    case app(named: String)
    /// Tap all system audio except our own process.
    case everything
}

public final class SystemAudioTap: @unchecked Sendable {
    private let ioQueue = DispatchQueue(label: "awm.system-tap.io")
    /// Control-plane work that must stay off the IO path: the default-output
    /// device listener and the process-tree re-resolve timer run here.
    private let controlQueue = DispatchQueue(label: "awm.system-tap.control")

    // Everything below is guarded by `lock` (start/stop/rebuild/deinit).
    // The IO block NEVER takes the lock: it works only from local copies
    // captured when the pipeline is built.
    private let lock = NSLock()
    private var started = false
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var writer: TrackWriter?
    private var target: CaptureTarget?
    /// Root of the tapped process tree; nil for .everything.
    private var rootPID: pid_t?
    private var tappedObjects: Set<AudioObjectID> = []
    private var resolveTimer: DispatchSourceTimer?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var loggedEmptyExclusion = false

    public init() {}

    deinit { stop() }

    public func start(target: CaptureTarget, into writer: TrackWriter) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { throw CaptureError("tap already started") }
        self.writer = writer
        self.target = target
        self.rootPID = try Self.rootPID(for: target)
        started = true

        tappedObjects = rootPID.map { Set(Self.audioObjects(inTreeOf: $0)) } ?? []
        if let rootPID, tappedObjects.isEmpty {
            // Record-then-join: the target is running but has no audio-capable
            // process YET (has not played audio, or its Electron helpers have
            // not spawned). Do not kill the track; leave it waiting (it reads
            // as stalled) and let the re-resolve timer attach the tap once a
            // process in the tree becomes audio-capable.
            fputs("awesoMeeting: no audio-capable process in the tree of pid \(rootPID) yet; waiting and re-resolving\n", stderr)
        } else {
            do {
                try buildPipelineLocked()
            } catch {
                stopLocked()
                throw error
            }
        }
        installDeviceListenerLocked()
        if rootPID != nil { startResolveTimerLocked() }
    }

    /// Full teardown; safe to call on a partially constructed pipeline.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    // MARK: - Pipeline (all with `lock` held)

    private func buildPipelineLocked() throws {
        guard let writer, let target else { return }

        let description: CATapDescription
        switch target {
        case .everything:
            // Inverse tap: everything except us (so playback of our own
            // recordings never feeds back into a capture).
            let own = (try? translatePIDToAudioObject(getpid())).map { [$0] } ?? []
            if own.isEmpty, !loggedEmptyExclusion {
                loggedEmptyExclusion = true
                fputs("awesoMeeting: self-exclusion list is empty (this process has never played audio); recording everything without excluding ourselves\n", stderr)
            }
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: own)
        case .pid, .app:
            // Stereo mixdown of every audio-capable process in the tree.
            description = CATapDescription(stereoMixdownOfProcesses: Array(tappedObjects))
        }
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(description, &newTapID)
        guard err == noErr, newTapID != kAudioObjectUnknown else {
            throw CaptureError("process tap creation failed (err \(err)); System Audio Recording permission missing or denied?")
        }
        tapID = newTapID

        // Read the tap's format from the TAP, before creating the aggregate.
        // Every failure past tap creation must unwind what exists so far.
        var asbd: AudioStreamBasicDescription
        do {
            asbd = try tapStreamDescription(newTapID)
        } catch {
            stopPipelineLocked()
            throw error
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            stopPipelineLocked()
            throw CaptureError("tap produced an unusable stream format")
        }
        let outputUID: String
        do {
            outputUID = try defaultSystemOutputDeviceUID()
        } catch {
            stopPipelineLocked()
            throw error
        }
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "awesoMeeting-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard err == noErr else {
            stopPipelineLocked()
            throw CaptureError("aggregate device creation failed (err \(err))")
        }
        aggregateID = newAggregateID

        // The tap's nominal format can lie about the delivered rate: AirPods
        // report a 48 kHz tap but deliver 24 kHz once the mic engages
        // Bluetooth HFP (observed on hardware: half-length, double-speed
        // audio). The running aggregate's measured rate is authoritative, so
        // poll it on a host-time cadence of about one second; the first
        // callback checks immediately to catch taps that start already in
        // HFP. A new snapped rate is adopted only when two consecutive polls
        // agree, so a measured rate hovering near a snap midpoint cannot flap
        // the converter. All three vars are confined to ioQueue (the IO
        // proc's serial queue); the block never takes `lock`.
        nonisolated(unsafe) var currentFormat = format
        nonisolated(unsafe) var nextRateCheck = DispatchTime.now()
        nonisolated(unsafe) var pendingRate: Double?
        let aggregate = newAggregateID
        err = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregate, ioQueue) { _, inInputData, _, _, _ in
            if DispatchTime.now() >= nextRateCheck {
                nextRateCheck = DispatchTime.now() + .seconds(1)
                if let measured = deviceActualSampleRate(aggregate) {
                    // ponytail: snapping to a standard rate ignores fine clock
                    // drift (e.g. a measured 24000.3 Hz); ceiling is slow
                    // desync on very long recordings, upgrade path is the
                    // drift correction noted in CaptureSession.
                    let snapped = snapToStandardRate(measured)
                    if snapped == currentFormat.sampleRate {
                        pendingRate = nil
                    } else if pendingRate == snapped {
                        pendingRate = nil
                        var changed = currentFormat.streamDescription.pointee
                        changed.mSampleRate = snapped
                        if let newFormat = AVAudioFormat(streamDescription: &changed) {
                            currentFormat = newFormat
                        }
                    } else {
                        pendingRate = snapped
                    }
                }
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: currentFormat, bufferListNoCopy: inInputData, deallocator: nil) else { return }
            writer.append(buffer)
        }
        guard err == noErr else {
            stopPipelineLocked()
            throw CaptureError("IO proc creation failed (err \(err))")
        }
        err = AudioDeviceStart(aggregate, ioProcID)
        guard err == noErr else {
            stopPipelineLocked()
            throw CaptureError("aggregate device start failed (err \(err))")
        }
    }

    /// Teardown order matters: stop -> destroy IO proc -> destroy aggregate ->
    /// destroy tap. Leaves writer/target/timers alone so a rebuild can reuse
    /// them.
    private func stopPipelineLocked() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
                self.ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func stopLocked() {
        resolveTimer?.cancel()
        resolveTimer = nil
        if let deviceListener {
            var address = propertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, controlQueue, deviceListener)
            self.deviceListener = nil
        }
        stopPipelineLocked()
        writer = nil
        target = nil
        rootPID = nil
        tappedObjects = []
        started = false
    }

    // MARK: - Default-output-device switch

    private func installDeviceListenerLocked() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultOutputChange()
        }
        var address = propertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let err = AudioObjectAddPropertyListenerBlock(systemObject, &address, controlQueue, listener)
        if err == noErr {
            deviceListener = listener
        } else {
            // ponytail: listener install failure is nonfatal; a device switch
            // then stalls the track for the rest of the session, exactly the
            // pre-listener behavior.
            fputs("awesoMeeting: cannot watch for output-device changes (err \(err))\n", stderr)
        }
    }

    /// The aggregate wraps the OLD default output; when the user switches
    /// devices (AirPods connect, display audio) it can stop pulling data.
    /// Rebuild the aggregate and tap association into the SAME TrackWriter
    /// (it survives format changes). Runs on controlQueue, off the IO path;
    /// while the swap is in flight the track reads as stalled, not dead.
    private func handleDefaultOutputChange() {
        lock.lock()
        defer { lock.unlock() }
        guard started, aggregateID != kAudioObjectUnknown else { return }
        stopPipelineLocked()
        do {
            try buildPipelineLocked()
        } catch {
            writer?.markDead("rebuild after default-output switch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Record-then-join re-resolution (.pid/.app targets)

    private func startResolveTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in self?.reResolve() }
        timer.activate()
        resolveTimer = timer
    }

    /// Electron helper children spawn late, and a quiet target only becomes
    /// audio-capable after it first plays sound. Walk the tree again (off the
    /// IO queue and off the lock) and rebuild the tap into the same writer
    /// whenever membership changed.
    private func reResolve() {
        lock.lock()
        let root = started ? rootPID : nil
        lock.unlock()
        guard let root else { return }
        let objects = Set(Self.audioObjects(inTreeOf: root)) // the slow walk, unlocked

        lock.lock()
        defer { lock.unlock() }
        guard started, objects != tappedObjects else { return }
        tappedObjects = objects
        stopPipelineLocked()
        guard !objects.isEmpty else { return } // tree went quiet; back to waiting
        do {
            try buildPipelineLocked()
        } catch {
            writer?.markDead("tap rebuild after process-tree change failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Target resolution

    private static func rootPID(for target: CaptureTarget) throws -> pid_t? {
        switch target {
        case .everything:
            return nil
        case .pid(let pid):
            return pid
        case .app(let name):
            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                throw CaptureError("no running app named \"\(name)\"")
            }
            return app.processIdentifier
        }
    }

    /// Every audio-capable process in the target's tree; empty when the HAL
    /// has never seen any of them produce audio.
    /// ponytail: pid-reuse TOCTOU: a walked pid can die and be reassigned
    /// before the tap attaches. The window is milliseconds and the periodic
    /// re-resolve corrects the membership on the next pass; accepted.
    private static func audioObjects(inTreeOf pid: pid_t) -> [AudioObjectID] {
        ProcessTree.pids(rootedAt: pid).compactMap { try? translatePIDToAudioObject($0) }
    }
}
