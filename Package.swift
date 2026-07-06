// swift-tools-version: 6.0
import PackageDescription

// ponytail: SPM executable, run with `swift run`. Upgrade to an .app bundle
// (Xcode project or xcodegen) when we need entitlements for real audio capture.
let package = Package(
    name: "awesoMeeting",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "AwesoMeeting", path: "Sources/AwesoMeeting"),
        .testTarget(name: "AwesoMeetingTests", dependencies: ["AwesoMeeting"]),
    ]
)
