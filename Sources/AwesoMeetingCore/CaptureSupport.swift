// Shared plumbing for the capture core: error type, process-tree enumeration,
// and the few Core Audio HAL property reads the tap sequence needs.

import AudioToolbox
import Darwin
import Foundation

public struct CaptureError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

// MARK: - Process tree

public enum ProcessTree {
    /// Root plus every descendant PID. Electron-style apps (Teams, Slack,
    /// Discord) play call audio from helper/renderer children, not the shell
    /// process; a tap must cover the whole tree or it records silence.
    public static func pids(rootedAt root: pid_t) -> [pid_t] {
        var childrenByParent: [pid_t: [pid_t]] = [:]
        for pid in allPIDs() {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { continue }
            childrenByParent[pid_t(info.pbi_ppid), default: []].append(pid)
        }
        return pids(rootedAt: root, childrenByParent: childrenByParent)
    }

    /// Seam for tests. The visited set matters: the pid table is scanned while
    /// processes churn, so a stale ppid can form a cycle; without it the walk
    /// would hang (and duplicates would inflate the result).
    static func pids(rootedAt root: pid_t, childrenByParent: [pid_t: [pid_t]]) -> [pid_t] {
        var visited: Set<pid_t> = [root]
        var result = [root]
        var frontier = [root]
        while let parent = frontier.popLast() {
            for child in childrenByParent[parent] ?? [] where visited.insert(child).inserted {
                result.append(child)
                frontier.append(child)
            }
        }
        return result
    }

    private static func allPIDs() -> [pid_t] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<pid_t>.size + 32)
        let bytes = pids.withUnsafeMutableBufferPointer {
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }
}

// MARK: - Core Audio property reads

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

/// `kAudioHardwarePropertyTranslatePIDToProcessObject`; fails for processes
/// the HAL has never seen produce audio.
func translatePIDToAudioObject(_ pid: pid_t) throws -> AudioObjectID {
    var address = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var qualifier = pid
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let err = AudioObjectGetPropertyData(
        systemObject, &address, UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &object)
    guard err == noErr, object != kAudioObjectUnknown else {
        throw CaptureError("no audio process object for pid \(pid) (err \(err))")
    }
    return object
}

/// UID of the default system output device (what the aggregate device wraps).
func defaultSystemOutputDeviceUID() throws -> String {
    var address = propertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var err = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device)
    guard err == noErr, device != kAudioObjectUnknown else {
        throw CaptureError("no default system output device (err \(err))")
    }
    var uidAddress = propertyAddress(kAudioDevicePropertyDeviceUID)
    // The HAL hands back a +1 CFString; take it through Unmanaged so ARC
    // does not double-manage a reference it never created.
    var unmanagedUID: Unmanaged<CFString>?
    size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    err = withUnsafeMutablePointer(to: &unmanagedUID) {
        AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size, $0)
    }
    guard err == noErr, let uid = unmanagedUID?.takeRetainedValue() else {
        throw CaptureError("cannot read output device UID (err \(err))")
    }
    return uid as String
}

/// `kAudioDevicePropertyActualSampleRate`: the measured rate of a RUNNING
/// device; nil before AudioDeviceStart or on error.
func deviceActualSampleRate(_ deviceID: AudioObjectID) -> Double? {
    var address = propertyAddress(kAudioDevicePropertyActualSampleRate)
    var rate: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
    guard err == noErr, rate > 0 else { return nil }
    return rate
}

/// Snaps a measured rate (which jitters around the true clock) to the nearest
/// standard audio sample rate.
func snapToStandardRate(_ raw: Double) -> Double {
    let standard: [Double] = [
        8000, 11025, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 176_400, 192_000,
    ]
    return standard.min { abs($0 - raw) < abs($1 - raw) }!
}

/// `kAudioTapPropertyFormat`: must be read from the TAP itself, before the
/// aggregate device is created.
func tapStreamDescription(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
    var address = propertyAddress(kAudioTapPropertyFormat)
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let err = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
    guard err == noErr else { throw CaptureError("cannot read tap stream format (err \(err))") }
    return asbd
}
