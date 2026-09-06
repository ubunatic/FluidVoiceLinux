// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Phase 0 (Linux migration, see docs/LINUX_MIGRATION_BRANCH_PLAN.md): the macOS app
// (Sources/Fluid, Sources/CoreAudioCaptureSupport) and its dependencies do not build
// on Linux (AppKit/SwiftUI/Cocoa/CoreAudio/AVFoundation imports, CoreAudio linking).
// SwiftPM does not support per-platform target *inclusion* in the targets/dependencies
// arrays directly, but the manifest is plain Swift executed by the host toolchain, so
// #if os(macOS) around the array contents reliably gates macOS-only targets and
// dependencies out of `swift build`/`swift package resolve` on Linux without needing a
// second manifest file.

var dependencies: [Package.Dependency] = []
var targets: [Target] = []

#if os(macOS)
dependencies += [
    .package(url: "https://github.com/mxcl/AppUpdater.git", from: "1.0.0"),
    .package(url: "https://github.com/altic-dev/FluidAudio.git", branch: "main"),
    .package(url: "https://github.com/mxcl/PromiseKit", from: "6.0.0"),
    .package(url: "https://github.com/altic-dev/DynamicNotchKit.git", branch: "main"),
    .package(url: "https://github.com/altic-dev/transcribe-cpp-swift.git", exact: "0.1.2"),
]

targets += [
    .target(
        name: "CoreAudioCaptureSupport",
        path: "Sources/CoreAudioCaptureSupport",
        linkerSettings: [
            .linkedFramework("CoreAudio"),
        ]
    ),
    .executableTarget(
        name: "FluidVoice",
        dependencies: [
            "AppUpdater",
            "CoreAudioCaptureSupport",
            "FluidAudio",
            "PromiseKit",
            "DynamicNotchKit",
            .product(name: "TranscribeCpp", package: "transcribe-cpp-swift"),
        ],
        linkerSettings: [
            .linkedLibrary("sqlite3"),
        ]
    ),
    // macOS-only: depends on the FluidVoice app target above.
    .testTarget(
        name: "FluidDictationIntegrationTests",
        dependencies: ["FluidVoice"],
        path: "Tests/FluidDictationIntegrationTests"
    ),
]
#else
targets += [
    // Phase 0 compile-gating placeholder only — Phase 2 owns the real canary content.
    .executableTarget(
        name: "FluidVoiceLinuxCLI",
        path: "Sources/FluidVoiceLinuxCLI"
    ),
]
#endif

let package = Package(
    name: "FluidVoice",
    platforms: [
        .macOS("15.0"),
    ],
    dependencies: dependencies,
    targets: targets
)
