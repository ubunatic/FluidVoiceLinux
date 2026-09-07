import Foundation
import XCTest
@testable import FluidVoiceLinuxCLICore

// Phase 3 (see issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md):
// argument parsing is split from execution (RecordCommand.run) specifically so it is
// unit-testable without a real ALSA capture device — see docs/SwiftLinux.md §3.
final class RecordCommandArgumentTests: XCTestCase {
    override func invokeTest() {
        runWithTimeout { super.invokeTest() }
    }

    func testParsesRequiredArguments() throws {
        let options = try RecordCommand.parseArguments(["--seconds", "3", "--out", "/tmp/x.wav"])

        XCTAssertEqual(options.seconds, 3)
        XCTAssertEqual(options.outputPath, "/tmp/x.wav")
        XCTAssertEqual(options.deviceName, AlsaAudioRecorder.defaultDeviceName)
        XCTAssertEqual(options.sampleRate, 16000)
        XCTAssertEqual(options.channelCount, 1)
    }

    func testParsesAllOptionalArguments() throws {
        let options = try RecordCommand.parseArguments([
            "--seconds", "1.5",
            "--out", "/tmp/y.wav",
            "--device", "plughw:CARD=Generic_1,DEV=0",
            "--sample-rate", "44100",
            "--channels", "2",
        ])

        XCTAssertEqual(options.seconds, 1.5)
        XCTAssertEqual(options.outputPath, "/tmp/y.wav")
        XCTAssertEqual(options.deviceName, "plughw:CARD=Generic_1,DEV=0")
        XCTAssertEqual(options.sampleRate, 44100)
        XCTAssertEqual(options.channelCount, 2)
    }

    func testMissingSecondsThrows() {
        XCTAssertThrowsError(try RecordCommand.parseArguments(["--out", "/tmp/x.wav"])) { error in
            guard case RecordArgumentError.missingRequired(let flag) = error else {
                return XCTFail("expected missingRequired, got \(error)")
            }
            XCTAssertEqual(flag, "--seconds")
        }
    }

    func testMissingOutThrows() {
        XCTAssertThrowsError(try RecordCommand.parseArguments(["--seconds", "3"])) { error in
            guard case RecordArgumentError.missingRequired(let flag) = error else {
                return XCTFail("expected missingRequired, got \(error)")
            }
            XCTAssertEqual(flag, "--out")
        }
    }

    func testZeroOrNegativeSecondsIsInvalid() {
        XCTAssertThrowsError(
            try RecordCommand.parseArguments(["--seconds", "0", "--out", "/tmp/x.wav"])
        ) { error in
            guard case RecordArgumentError.invalidValue(let flag, let value) = error else {
                return XCTFail("expected invalidValue, got \(error)")
            }
            XCTAssertEqual(flag, "--seconds")
            XCTAssertEqual(value, "0")
        }
    }

    func testUnknownArgumentThrows() {
        XCTAssertThrowsError(
            try RecordCommand.parseArguments(["--seconds", "3", "--out", "/tmp/x.wav", "--bogus"])
        ) { error in
            guard case RecordArgumentError.unknownArgument(let argument) = error else {
                return XCTFail("expected unknownArgument, got \(error)")
            }
            XCTAssertEqual(argument, "--bogus")
        }
    }

    func testDanglingFlagWithNoValueThrows() {
        XCTAssertThrowsError(
            try RecordCommand.parseArguments(["--seconds", "3", "--out"])
        ) { error in
            guard case RecordArgumentError.missingValue(let flag) = error else {
                return XCTFail("expected missingValue, got \(error)")
            }
            XCTAssertEqual(flag, "--out")
        }
    }
}
