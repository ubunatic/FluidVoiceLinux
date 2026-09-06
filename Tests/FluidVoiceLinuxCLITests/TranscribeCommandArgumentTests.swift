import Foundation
import XCTest
@testable import FluidVoiceLinuxCLICore

// Phase 4 (see issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md):
// argument parsing is split from execution (TranscribeCommand.run) specifically so it
// is unit-testable without a real whisper model file or a GPU — see
// docs/SwiftLinux.md §3.
final class TranscribeCommandArgumentTests: XCTestCase {
    func testParsesRequiredArgumentOnly() throws {
        let options = try TranscribeCommand.parseArguments(["--in", "/tmp/x.wav"])

        XCTAssertEqual(options.inputPath, "/tmp/x.wav")
        // Issue 007: unset --model means "not explicit" — resolution to a real
        // default path happens in TranscribeCommand.run via ModelPathResolver,
        // not here. See ModelPathResolutionTests.swift for that logic.
        XCTAssertNil(options.modelPath)
        XCTAssertFalse(options.noGPU)
    }

    func testParsesAllOptionalArguments() throws {
        let options = try TranscribeCommand.parseArguments([
            "--in", "/tmp/y.wav",
            "--model", "/opt/models/ggml-tiny.en.bin",
            "--no-gpu",
        ])

        XCTAssertEqual(options.inputPath, "/tmp/y.wav")
        XCTAssertEqual(options.modelPath, "/opt/models/ggml-tiny.en.bin")
        XCTAssertTrue(options.noGPU)
    }

    func testMissingInThrows() {
        XCTAssertThrowsError(try TranscribeCommand.parseArguments([])) { error in
            guard case TranscribeArgumentError.missingRequired(let flag) = error else {
                return XCTFail("expected missingRequired, got \(error)")
            }
            XCTAssertEqual(flag, "--in")
        }
    }

    func testUnknownArgumentThrows() {
        XCTAssertThrowsError(
            try TranscribeCommand.parseArguments(["--in", "/tmp/x.wav", "--bogus"])
        ) { error in
            guard case TranscribeArgumentError.unknownArgument(let argument) = error else {
                return XCTFail("expected unknownArgument, got \(error)")
            }
            XCTAssertEqual(argument, "--bogus")
        }
    }

    func testDanglingFlagWithNoValueThrows() {
        XCTAssertThrowsError(
            try TranscribeCommand.parseArguments(["--in", "/tmp/x.wav", "--model"])
        ) { error in
            guard case TranscribeArgumentError.missingValue(let flag) = error else {
                return XCTFail("expected missingValue, got \(error)")
            }
            XCTAssertEqual(flag, "--model")
        }
    }
}
