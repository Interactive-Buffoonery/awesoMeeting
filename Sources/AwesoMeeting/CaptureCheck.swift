// Headless capture diagnostic, run before any UI starts (the --snapshot idea):
//
//   AwesoMeeting --capture-check <seconds> (--pid <pid> | --app <name> | --everything) --out <dir>
//
// Starts a CaptureSession, prints per-track status once per second, stops
// after N seconds (or on Ctrl-C / SIGTERM), prints the WAV paths/durations/
// peaks, and exits nonzero if a track never flowed. Must run from the bundled
// .app (see AGENTS.md) so TCC attributes the System Audio Recording and
// Microphone prompts to the app. Kept thin on purpose: all real logic lives
// in AwesoMeetingCore.

import AwesoMeetingCore
import Foundation

enum CaptureCheck {
    struct Config: Sendable {
        let seconds: Int
        let target: CaptureTarget
        let outDir: String
    }

    static let usage = """
        usage: AwesoMeeting --capture-check <seconds> (--pid <pid> | --app <name> | --everything) --out <dir>

        """

    /// nil when `--capture-check` isn't present. Throws (with a message for
    /// stderr) on malformed usage; kept throwing rather than exiting so tests
    /// can cover the rejections.
    static func parse(_ args: [String]) throws -> Config? {
        guard let i = args.firstIndex(of: "--capture-check") else { return nil }
        // A following "--flag" token is a missing value, not a value.
        func value(after flag: String) -> String? {
            guard let f = args.firstIndex(of: flag), args.indices.contains(f + 1),
                  !args[f + 1].hasPrefix("--") else { return nil }
            return args[f + 1]
        }
        guard args.indices.contains(i + 1), let seconds = Int(args[i + 1]), seconds > 0 else {
            throw CaptureError("--capture-check needs a positive duration in seconds")
        }
        guard let outDir = value(after: "--out") else {
            throw CaptureError("--out <dir> is required")
        }
        // Exactly one target, always explicit: recording everything is an
        // opt-in flag, never a fallback for a mistyped --pid/--app.
        let hasPID = args.contains("--pid")
        let hasApp = args.contains("--app")
        let hasEverything = args.contains("--everything")
        switch (hasPID, hasApp, hasEverything) {
        case (true, false, false):
            guard let raw = value(after: "--pid"), let pid = pid_t(raw), pid > 0 else {
                throw CaptureError("--pid needs a positive numeric process id")
            }
            return Config(seconds: seconds, target: .pid(pid), outDir: outDir)
        case (false, true, false):
            guard let app = value(after: "--app") else {
                throw CaptureError("--app needs an app name")
            }
            return Config(seconds: seconds, target: .app(named: app), outDir: outDir)
        case (false, false, true):
            return Config(seconds: seconds, target: .everything, outDir: outDir)
        case (false, false, false):
            throw CaptureError("no capture target: pass --pid <pid>, --app <name>, or --everything")
        default:
            throw CaptureError("pass exactly one of --pid, --app, --everything")
        }
    }

    /// nil when `--capture-check` isn't present; prints the error and usage to
    /// stderr and exits(2) on malformed usage.
    static func parseOrExit(_ args: [String]) -> Config? {
        do {
            return try parse(args)
        } catch {
            FileHandle.standardError.write(Data("capture-check: \(error.localizedDescription)\n\(usage)".utf8))
            exit(2)
        }
    }

    static func run(_ config: Config) async -> Int32 {
        let dir = URL(fileURLWithPath: config.outDir)
        let session: CaptureSession
        do {
            session = try CaptureSession(directory: dir)
        } catch {
            FileHandle.standardError.write(Data("capture-check: \(error.localizedDescription)\n".utf8))
            return 2
        }
        await session.start(target: config.target)

        // Ctrl-C / kill must still leave two playable WAVs: stop the session
        // (which finalizes both WAV headers), print the epilogue, exit 130.
        let signalSources = [SIGINT, SIGTERM].map { sig in
            signal(sig, SIG_IGN) // the DispatchSource replaces default delivery
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                session.stop()
                _ = epilogue(session, dir: dir)
                exit(130)
            }
            source.activate()
            return source
        }
        defer { signalSources.forEach { $0.cancel() } }

        for second in 1...config.seconds {
            try? await Task.sleep(for: .seconds(1))
            for (name, state) in [("system", session.systemState), ("mic", session.micState)] {
                let error = state.error.map { " (\($0))" } ?? ""
                print("[\(second)s] \(name): \(state.health.rawValue) level=\(fmt(state.level))\(error)")
            }
        }
        session.stop()
        return epilogue(session, dir: dir)
    }

    private static func epilogue(_ session: CaptureSession, dir: URL) -> Int32 {
        var failed = false
        for (name, state) in [("system", session.systemState), ("mic", session.micState)] {
            let path = dir.appendingPathComponent("\(name).wav").path
            print("\(name).wav: \(String(format: "%.1f", state.seconds))s peak=\(fmt(state.sessionPeak)) \(path)")
            if !state.everFlowed {
                failed = true
                print("\(name): never flowed: \(neverFlowedReason(state))")
            }
        }
        return failed ? 1 : 0
    }

    /// Best diagnosis the track state supports for a track that never flowed.
    private static func neverFlowedReason(_ state: TrackState) -> String {
        if let error = state.error { return error }
        if state.framesWritten == 0 {
            return "no buffers ever arrived, the tap or engine never delivered audio"
        }
        return "buffers arrived but were pure silence: System Audio Recording may be denied "
            + "(System Settings > Privacy & Security > Screen & System Audio Recording), "
            + "or the target made no sound"
    }

    private static func fmt(_ level: Float) -> String { String(format: "%.4f", level) }
}
