import XCTest
import Foundation
@testable import FluidVoiceLinuxCLICore

final class VoiceActivityDetectorTests: XCTestCase {
    func testVADConfigurationDefaults() {
        let config = VADConfiguration()
        XCTAssertEqual(config.threshold, 0.5)
        XCTAssertEqual(config.minSpeechDurationMs, 250)
        XCTAssertEqual(config.minSilenceDurationMs, 300)
        XCTAssertEqual(config.speechPadMs, 100)
        XCTAssertEqual(config.sampleRate, 16000)
    }

    func testEmptySamplesReturnsNoIntervals() {
        let empty: [Float] = []
        let intervals = EnergyVoiceActivityDetector.detectIntervals(samples: empty)
        XCTAssertTrue(intervals.isEmpty)

        let chunks = AudioSegmenter.segment(samples: empty, intervals: intervals)
        XCTAssertTrue(chunks.isEmpty)
    }

    func testPureSilenceReturnsNoIntervals() {
        let silence = [Float](repeating: 0.0, count: 16000 * 2) // 2s of silence
        let intervals = EnergyVoiceActivityDetector.detectIntervals(samples: silence)
        XCTAssertTrue(intervals.isEmpty)
    }

    func testSyntheticToneDetectsSpeechInterval() {
        let sampleRate = 16000
        let totalSamples = sampleRate * 3 // 3s total: 1s silence, 1s tone (440Hz), 1s silence
        var samples = [Float](repeating: 0.0, count: totalSamples)

        // 1.0s to 2.0s is a 440Hz sine wave
        for i in sampleRate..<(sampleRate * 2) {
            let t = Double(i) / Double(sampleRate)
            samples[i] = Float(sin(2.0 * .pi * 440.0 * t) * 0.5)
        }

        let intervals = EnergyVoiceActivityDetector.detectIntervals(
            samples: samples,
            config: VADConfiguration(minSpeechDurationMs: 200, minSilenceDurationMs: 200, speechPadMs: 50, sampleRate: sampleRate)
        )

        XCTAssertEqual(intervals.count, 1)
        guard let first = intervals.first else { return }

        // Start time should be around ~1.0s and end time around ~2.0s
        XCTAssertGreaterThanOrEqual(first.startTime, 0.8)
        XCTAssertLessThanOrEqual(first.startTime, 1.2)
        XCTAssertGreaterThanOrEqual(first.endTime, 1.9)
        XCTAssertLessThanOrEqual(first.endTime, 2.3)

        let chunks = AudioSegmenter.segment(samples: samples, intervals: intervals, sampleRate: sampleRate)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].index, 0)
        XCTAssertGreaterThan(chunks[0].samples.count, sampleRate / 2)
    }

    func testMultipleUtterancesWithSilenceSegments() {
        let sampleRate = 16000
        // Structure: 0.5s silence, 0.6s speech, 0.6s silence, 0.6s speech, 0.5s silence (total 2.8s)
        var samples = [Float](repeating: 0.0, count: Int(Double(sampleRate) * 2.8))

        // Utterance 1: 0.5s to 1.1s
        let start1 = Int(0.5 * Double(sampleRate))
        let end1 = Int(1.1 * Double(sampleRate))
        for i in start1..<end1 {
            samples[i] = Float(sin(Double(i) * 0.1) * 0.4)
        }

        // Utterance 2: 1.7s to 2.3s
        let start2 = Int(1.7 * Double(sampleRate))
        let end2 = Int(2.3 * Double(sampleRate))
        for i in start2..<end2 {
            samples[i] = Float(sin(Double(i) * 0.2) * 0.4)
        }

        let intervals = EnergyVoiceActivityDetector.detectIntervals(
            samples: samples,
            config: VADConfiguration(minSpeechDurationMs: 200, minSilenceDurationMs: 200, speechPadMs: 30, sampleRate: sampleRate)
        )

        XCTAssertEqual(intervals.count, 2)
        let chunks = AudioSegmenter.segment(samples: samples, intervals: intervals, sampleRate: sampleRate)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].index, 0)
        XCTAssertEqual(chunks[1].index, 1)
    }

    func testSileroVADPathResolutionPriority() {
        XCTAssertEqual(
            ModelPathResolver.resolveSileroVAD(
                explicit: "/custom/silero.onnx",
                fileExists: { _ in true },
                xdgDataHome: "/data",
                home: "/home/user"
            ),
            "/custom/silero.onnx"
        )

        XCTAssertEqual(
            ModelPathResolver.resolveSileroVAD(
                explicit: nil,
                fileExists: { $0 == "/home/user/.cache/crispasr/silero_vad.onnx" },
                xdgDataHome: "/data",
                home: "/home/user"
            ),
            "/home/user/.cache/crispasr/silero_vad.onnx"
        )
    }

    func testSileroVADOnRealAudioSample() throws {
        let samplePath = "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.config/fluidvoice/dev/samples/chunks.wav"
        guard FileManager.default.fileExists(atPath: samplePath) else { return }

        let wavData = try Data(contentsOf: URL(fileURLWithPath: samplePath))
        let decoded = try WavReader.decode(wavData)

        let intervals = try SileroVoiceActivityDetector.detectIntervals(
            samples: decoded.monoSamples,
            config: VADConfiguration(threshold: 0.5, minSpeechDurationMs: 250, minSilenceDurationMs: 300, speechPadMs: 100, sampleRate: Int(decoded.sampleRate))
        )

        // chunks.wav has 2 distinct utterances: "This is a recording of one chunk" and "and another chunk."
        XCTAssertEqual(intervals.count, 2)
        XCTAssertGreaterThan(intervals[0].startTime, 1.5)
        XCTAssertLessThan(intervals[0].endTime, 5.0)
        XCTAssertGreaterThan(intervals[1].startTime, 5.0)
        XCTAssertLessThan(intervals[1].endTime, 8.0)
    }
}
