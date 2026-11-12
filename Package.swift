// swift-tools-version:5.9
import PackageDescription
import Foundation

// Embed Info.plist in the CLI binary so TCC can read NSAudioCaptureUsageDescription.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Info.plist").path

let package = Package(
    name: "claude-tap",
    platforms: [.macOS("14.2")],
    targets: [
        // Shared capture engine: process tap, 48 kHz mono framing, WebSocket server.
        .target(name: "TapCore", path: "Sources/TapCore"),

        // Phase 1 command-line tool.
        .executableTarget(
            name: "claude-tap",
            dependencies: ["TapCore"],
            path: "Sources/claude-tap",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),

        // Phase 3 window app (packaged into an .app by build-app.sh).
        .executableTarget(
            name: "ClaudeAvatar",
            dependencies: ["TapCore"],
            path: "Sources/ClaudeAvatar"
        ),
    ]
)
