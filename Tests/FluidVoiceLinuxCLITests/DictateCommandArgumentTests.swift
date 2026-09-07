import XCTest
import Foundation
@testable import FluidVoiceLinuxCLICore

final class DictateCommandArgumentTests: XCTestCase {
    override func invokeTest() {
        runWithTimeout { super.invokeTest() }
    }

    func testParsesDefaultArguments() throws {
        let opts = try DictateCommand.parseArguments([])
        XCTAssertEqual(opts.backend, .parakeet)
        XCTAssertEqual(opts.language, "en")
        XCTAssertFalse(opts.enhance)
        XCTAssertEqual(opts.outputTarget, .stdout)
        XCTAssertNil(opts.maxDurationSeconds)
    }

    func testParsesFullCustomFlags() throws {
        let opts = try DictateCommand.parseArguments([
            "--backend", "cohere",
            "--model", "/custom/model.gguf",
            "--lang", "de",
            "--enhance",
            "--ai-provider", "anthropic",
            "--ai-model", "claude-3-5-sonnet",
            "--ai-api-key", "test_key",
            "--type",
            "--seconds", "10.5",
            "--device", "hw:0,0"
        ])

        XCTAssertEqual(opts.backend, .cohere)
        XCTAssertEqual(opts.modelPath, "/custom/model.gguf")
        XCTAssertEqual(opts.language, "de")
        XCTAssertTrue(opts.enhance)
        XCTAssertEqual(opts.aiProvider, .anthropic)
        XCTAssertEqual(opts.aiModel, "claude-3-5-sonnet")
        XCTAssertEqual(opts.aiAPIKey, "test_key")
        XCTAssertEqual(opts.outputTarget, .typing)
        XCTAssertEqual(opts.maxDurationSeconds, 10.5)
        XCTAssertEqual(opts.deviceName, "hw:0,0")
    }

    func testParsesClipboardTarget() throws {
        let opts = try DictateCommand.parseArguments(["--clipboard"])
        XCTAssertEqual(opts.outputTarget, .clipboard)
    }

    func testUnknownBackendThrows() {
        XCTAssertThrowsError(
            try DictateCommand.parseArguments(["--backend", "unknown_engine"])
        ) { error in
            guard case DictateArgumentError.unknownBackend(let b) = error else {
                return XCTFail("expected unknownBackend, got \(error)")
            }
            XCTAssertEqual(b, "unknown_engine")
        }
    }

    func testInvalidSecondsThrows() {
        XCTAssertThrowsError(
            try DictateCommand.parseArguments(["--seconds", "abc"])
        ) { error in
            guard case DictateArgumentError.invalidDuration(let val) = error else {
                return XCTFail("expected invalidDuration, got \(error)")
            }
            XCTAssertEqual(val, "abc")
        }
    }
}
