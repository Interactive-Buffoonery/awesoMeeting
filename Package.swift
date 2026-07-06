// swift-tools-version: 6.0
import PackageDescription

// SPM drives logic/tests/fast iteration; the xcodegen-generated .app bundle
// (see project.yml) covers anything needing TCC, e.g. audio capture.
let package = Package(
    name: "awesoMeeting",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "AwesoMeetingCore"),
        .executableTarget(
            name: "AwesoMeeting",
            dependencies: ["AwesoMeetingCore"],
            path: "Sources/AwesoMeeting"
        ),
        .testTarget(name: "AwesoMeetingTests", dependencies: ["AwesoMeeting", "AwesoMeetingCore"]),
    ]
)
