import Foundation
import XCTest
@testable import FluidVoiceLinuxCLICore

// First Linux-only test target (Phase 2, see
// issues/002-linux-migration-phase-2-hello-swift-canary-cli.md). Wired into
// Package.swift's Linux-only #else branch and run via `make check`/`make test`.
final class FluidVoiceLinuxCLIBannerTests: XCTestCase {
    override func invokeTest() {
        runWithTimeout { super.invokeTest() }
    }

    func testBannerContainsProgramNameAndVersion() {
        let output = FluidVoiceLinuxCLIBanner.banner()

        XCTAssertTrue(
            output.contains(FluidVoiceLinuxCLIBanner.programName),
            "banner should mention the program name: \(output)"
        )
        XCTAssertTrue(
            output.contains(FluidVoiceLinuxCLIBanner.version),
            "banner should mention the version placeholder: \(output)"
        )
    }

    func testBannerIncludesLiveOSVersionInfo() {
        // Regression guard for the canary's actual purpose: prove this is really
        // running as a Linux CLI via live platform info, not a hardcoded string.
        let output = FluidVoiceLinuxCLIBanner.banner()
        let liveOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        XCTAssertTrue(
            output.contains(liveOSVersion),
            "banner should include the live OS version string: \(output)"
        )
    }
}
