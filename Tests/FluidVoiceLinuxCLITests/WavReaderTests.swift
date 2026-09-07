import Foundation
import XCTest
@testable import FluidVoiceLinuxCLICore

// Phase 4 (see issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md):
// WavReader.decode is pure buffer parsing (no file I/O), so it's tested here against
// in-memory WAV bytes built with the existing WavFormat.makeFile helper from Phase 3.
final class WavReaderTests: XCTestCase {
    override func invokeTest() {
        runWithTimeout { super.invokeTest() }
    }

    func testDecodesMonoSixteenKilohertzRoundTrip() throws {
        let samples: [Int16] = [0, 16384, -16384, 32767, -32768]
        let wavData = WavFormat.makeFile(samples: samples, sampleRate: 16000, channelCount: 1)

        let decoded = try WavReader.decode(wavData)

        XCTAssertEqual(decoded.sampleRate, 16000)
        XCTAssertEqual(decoded.channelCount, 1)
        XCTAssertEqual(decoded.monoSamples.count, samples.count)
        XCTAssertEqual(decoded.monoSamples[0], 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.monoSamples[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded.monoSamples[3], 1.0, accuracy: 0.001)
    }

    func testDownmixesStereoToMono() throws {
        // Interleaved stereo: (left, right) pairs.
        let samples: [Int16] = [10000, -10000, 20000, 20000]
        let wavData = WavFormat.makeFile(samples: samples, sampleRate: 16000, channelCount: 2)

        let decoded = try WavReader.decode(wavData)

        XCTAssertEqual(decoded.channelCount, 2)
        XCTAssertEqual(decoded.monoSamples.count, 2)
        XCTAssertEqual(decoded.monoSamples[0], 0, accuracy: 0.001)
        XCTAssertEqual(decoded.monoSamples[1], 20000.0 / 32768.0, accuracy: 0.001)
    }

    func testRejectsUnsupportedSampleRate() {
        let wavData = WavFormat.makeFile(samples: [0, 1, 2], sampleRate: 44100, channelCount: 1)

        XCTAssertThrowsError(try WavReader.decode(wavData)) { error in
            guard case WavReaderError.unsupportedSampleRate(let rate) = error else {
                return XCTFail("expected unsupportedSampleRate, got \(error)")
            }
            XCTAssertEqual(rate, 44100)
        }
    }

    func testRejectsNonRiffData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try WavReader.decode(garbage)) { error in
            guard case WavReaderError.notARiffFile = error else {
                return XCTFail("expected notARiffFile, got \(error)")
            }
        }
    }
}
