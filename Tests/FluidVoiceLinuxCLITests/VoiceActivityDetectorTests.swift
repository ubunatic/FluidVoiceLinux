import XCTest
import Foundation
@testable import FluidVoiceLinuxCLICore

final class VoiceActivityDetectorTests: XCTestCase {
    override func invokeTest() {
        runWithTimeout { super.invokeTest() }
    }

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

    // MARK: - IncrementalSpeechSegmenter (issue 017)

    private func makeToneBurst(sampleRate: Int, durationSeconds: Double, amplitude: Float = 0.4) -> [Float] {
        let count = Int(durationSeconds * Double(sampleRate))
        return (0..<count).map { i in
            Float(sin(Double(i) * 0.2)) * amplitude
        }
    }

    func testIncrementalSegmenterEmitsNothingForPureSilence() {
        let sampleRate = 16000
        let segmenter = IncrementalSpeechSegmenter(
            config: VADConfiguration(minSpeechDurationMs: 200, minSilenceDurationMs: 300, speechPadMs: 50, sampleRate: sampleRate)
        )

        let silence = [Float](repeating: 0.0, count: sampleRate * 2)
        // Feed in small streaming-sized chunks, as a live ALSA stream would.
        var completed: [[Float]] = []
        for chunkStart in stride(from: 0, to: silence.count, by: 1600) {
            let chunkEnd = min(chunkStart + 1600, silence.count)
            completed.append(contentsOf: segmenter.ingest(Array(silence[chunkStart..<chunkEnd])))
        }

        XCTAssertTrue(completed.isEmpty)
        XCTAssertNil(segmenter.flush())
    }

    func testIncrementalSegmenterSegmentsMultipleBurstsSeparatedBySilence() {
        let sampleRate = 16000
        let config = VADConfiguration(minSpeechDurationMs: 200, minSilenceDurationMs: 300, speechPadMs: 30, sampleRate: sampleRate)
        let segmenter = IncrementalSpeechSegmenter(config: config)

        // Structure: 0.4s silence, 0.6s speech, 0.5s silence, 0.7s speech, 0.4s silence.
        var fullStream: [Float] = []
        fullStream.append(contentsOf: [Float](repeating: 0.0, count: Int(0.4 * Double(sampleRate))))
        fullStream.append(contentsOf: makeToneBurst(sampleRate: sampleRate, durationSeconds: 0.6))
        fullStream.append(contentsOf: [Float](repeating: 0.0, count: Int(0.5 * Double(sampleRate))))
        fullStream.append(contentsOf: makeToneBurst(sampleRate: sampleRate, durationSeconds: 0.7))
        fullStream.append(contentsOf: [Float](repeating: 0.0, count: Int(0.4 * Double(sampleRate))))

        // Feed in small streaming-sized chunks (100ms), as `StreamingDictationLoop` would
        // via `AlsaAudioStream.readChunk`, to exercise the incremental/cross-call state
        // machine rather than the whole-buffer batch detector.
        var completed: [[Float]] = []
        let chunkSize = 1600
        for chunkStart in stride(from: 0, to: fullStream.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, fullStream.count)
            completed.append(contentsOf: segmenter.ingest(Array(fullStream[chunkStart..<chunkEnd])))
        }
        if let flushed = segmenter.flush() {
            completed.append(flushed)
        }

        XCTAssertEqual(completed.count, 2, "expected exactly two utterances, one per speech burst")
        // Each utterance should be roughly the burst duration (plus pad), not the whole
        // 2.6s stream and not just a sliver of one frame.
        for utterance in completed {
            let durationSeconds = Double(utterance.count) / Double(sampleRate)
            XCTAssertGreaterThan(durationSeconds, 0.3)
            XCTAssertLessThan(durationSeconds, 1.2)
        }
    }

    func testIncrementalSegmenterFlushesInProgressUtteranceAtStreamEnd() {
        let sampleRate = 16000
        let config = VADConfiguration(minSpeechDurationMs: 200, minSilenceDurationMs: 500, speechPadMs: 30, sampleRate: sampleRate)
        let segmenter = IncrementalSpeechSegmenter(config: config)

        // Speech that never reaches a full trailing silence pad before the stream ends
        // (e.g. session terminated by SIGINT or --seconds elapsing mid-utterance).
        var fullStream: [Float] = []
        fullStream.append(contentsOf: [Float](repeating: 0.0, count: Int(0.3 * Double(sampleRate))))
        fullStream.append(contentsOf: makeToneBurst(sampleRate: sampleRate, durationSeconds: 0.8))

        let completedDuringIngest = segmenter.ingest(fullStream)
        XCTAssertTrue(completedDuringIngest.isEmpty, "no trailing silence pad yet, nothing should complete mid-stream")

        guard let flushed = segmenter.flush() else {
            return XCTFail("expected the in-progress utterance to flush at stream end")
        }
        XCTAssertGreaterThan(Double(flushed.count) / Double(sampleRate), 0.5)

        // A second flush (e.g. called defensively twice) must not resurrect state.
        XCTAssertNil(segmenter.flush())
    }

    // MARK: - StreamingDictationLoop (issue 017)

    func testStreamingDictationLoopEmitsUtterancesFromChunkedSource() throws {
        let sampleRate = 16000
        var fullStream: [Float] = []
        fullStream.append(contentsOf: [Float](repeating: 0.0, count: Int(0.3 * Double(sampleRate))))
        fullStream.append(contentsOf: makeToneBurst(sampleRate: sampleRate, durationSeconds: 0.5))
        fullStream.append(contentsOf: [Float](repeating: 0.0, count: Int(0.5 * Double(sampleRate))))
        fullStream.append(contentsOf: makeToneBurst(sampleRate: sampleRate, durationSeconds: 0.5))
        fullStream.append(contentsOf: [Float](repeating: 0.0, count: Int(0.5 * Double(sampleRate))))

        let int16Stream: [Int16] = fullStream.map { sample in
            Int16(max(-1.0, min(1.0, sample)) * 32767.0)
        }

        // Simulate a callback-driven audio source (like `AlsaAudioStream.readChunk`)
        // handing over fixed-size PCM chunks until the recorded audio is exhausted.
        var offset = 0
        let chunkSize = 1600
        func nextChunk() -> [Int16]? {
            guard offset < int16Stream.count else { return nil }
            let end = min(offset + chunkSize, int16Stream.count)
            let chunk = Array(int16Stream[offset..<end])
            offset = end
            return chunk
        }

        var emittedUtterances: [[Float]] = []
        try StreamingDictationLoop.run(
            sampleRate: sampleRate,
            vadConfig: VADConfiguration(minSpeechDurationMs: 200, minSilenceDurationMs: 300, speechPadMs: 30, sampleRate: sampleRate),
            maxDurationSeconds: nil,
            shouldStop: { false },
            nextChunk: { nextChunk() },
            onUtterance: { emittedUtterances.append($0) }
        )

        XCTAssertEqual(emittedUtterances.count, 2, "two speech bursts separated by silence should yield two utterances")
    }

    func testStreamingDictationLoopStopsAtMaxDuration() throws {
        let sampleRate = 16000
        // An effectively endless supply of continuous tone -- without a max-duration cap
        // this source would never signal end-of-stream via `nil`.
        func nextChunk() -> [Int16]? {
            [Int16](repeating: 12000, count: 1600)
        }

        var totalEmittedSamples = 0
        try StreamingDictationLoop.run(
            sampleRate: sampleRate,
            vadConfig: VADConfiguration(minSpeechDurationMs: 100, minSilenceDurationMs: 200, speechPadMs: 20, sampleRate: sampleRate),
            maxDurationSeconds: 0.5,
            shouldStop: { false },
            nextChunk: { nextChunk() },
            onUtterance: { totalEmittedSamples += $0.count }
        )

        // The loop must terminate (the test itself would hang otherwise) once
        // maxDurationSeconds worth of audio has been ingested, flushing the still-speaking
        // utterance rather than requiring a trailing silence pad it will never see.
        XCTAssertGreaterThan(totalEmittedSamples, 0)
    }

    func testStreamingDictationLoopStopsWhenShouldStopBecomesTrue() throws {
        let sampleRate = 16000
        var chunksServed = 0
        func nextChunk() -> [Int16]? {
            chunksServed += 1
            return [Int16](repeating: 12000, count: 1600)
        }

        var stopNow = false
        var utteranceCount = 0
        try StreamingDictationLoop.run(
            sampleRate: sampleRate,
            vadConfig: VADConfiguration(minSpeechDurationMs: 100, minSilenceDurationMs: 200, speechPadMs: 20, sampleRate: sampleRate),
            maxDurationSeconds: nil,
            shouldStop: { stopNow },
            nextChunk: {
                if chunksServed >= 5 {
                    stopNow = true // simulate a SIGINT flag flipping mid-session
                }
                return nextChunk()
            },
            onUtterance: { _ in utteranceCount += 1 }
        )

        XCTAssertLessThanOrEqual(chunksServed, 6, "loop should stop shortly after shouldStop() flips true, not run indefinitely")
        XCTAssertEqual(utteranceCount, 1, "the in-progress utterance should be flushed once the loop stops")
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
