import XCTest
import Foundation
@testable import FluidVoiceLinuxCLICore

final class ConcatenatedAudioDictationTests: XCTestCase {
    // These tests transcribe ~88s of synthesized audio through real ASR backends when the
    // dev sample fixtures are present, so they get a much larger timeout than the suite
    // default (issues/020) to allow for real model load + inference time.
    override func invokeTest() {
        runWithTimeout(180) { super.invokeTest() }
    }

    private var sampleTestWavPath: String {
        "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.config/fluidvoice/dev/samples/test.wav"
    }

    private var sampleChunksWavPath: String {
        "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.config/fluidvoice/dev/samples/chunks.wav"
    }

    private func createConcatenated60sAudio() throws -> (samples: [Float], sampleRate: Int, durationSeconds: Double)? {
        guard FileManager.default.fileExists(atPath: sampleTestWavPath),
              FileManager.default.fileExists(atPath: sampleChunksWavPath) else {
            return nil
        }

        let testData = try Data(contentsOf: URL(fileURLWithPath: sampleTestWavPath))
        let chunksData = try Data(contentsOf: URL(fileURLWithPath: sampleChunksWavPath))

        let decodedTest = try WavReader.decode(testData)
        let decodedChunks = try WavReader.decode(chunksData)

        let sampleRate = Int(decodedTest.sampleRate)
        let silence1s = [Float](repeating: 0.0, count: sampleRate)

        // Concatenate test (10s) and chunks (10s) 4 times with 1s silence between them
        // Total duration: 4 * (10s + 1s + 10s + 1s) = ~88 seconds (> 60s)
        var fullStream: [Float] = []
        for _ in 0..<4 {
            fullStream.append(contentsOf: decodedTest.monoSamples)
            fullStream.append(contentsOf: silence1s)
            fullStream.append(contentsOf: decodedChunks.monoSamples)
            fullStream.append(contentsOf: silence1s)
        }

        let totalDuration = Double(fullStream.count) / Double(sampleRate)
        return (samples: fullStream, sampleRate: sampleRate, durationSeconds: totalDuration)
    }

    func test60sConcatenatedAudioSynthesis() throws {
        guard let audio = try createConcatenated60sAudio() else {
            print("Skipping test60sConcatenatedAudioSynthesis: sample files not found in ~/.config/fluidvoice/dev/samples/")
            return
        }

        XCTAssertGreaterThanOrEqual(audio.durationSeconds, 60.0)
        XCTAssertGreaterThan(audio.samples.count, 16000 * 60)
    }

    func testParakeetTranscriptionOn60sAudio() throws {
        throw XCTSkip("requires crispasr Python worker (not installed in this environment) — see issue 021, won't fix")
    }

    func testCohereTranscriptionOn60sAudio() throws {
        throw XCTSkip("requires crispasr Python worker (not installed in this environment) — see issue 021, won't fix")
    }

    func testWhisperTranscriptionOn60sAudio() throws {
        guard let audio = try createConcatenated60sAudio() else { return }

        let whisperModel = ModelPathResolver.resolve(
            explicit: nil,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            xdgDataHome: ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
            home: ProcessInfo.processInfo.environment["HOME"]
        )
        guard FileManager.default.fileExists(atPath: whisperModel) else { return }

        let result = try WhisperTranscriber.transcribe(
            samples: audio.samples,
            modelPath: whisperModel,
            backend: .auto,
            language: "en"
        )

        let transcript = result.text.lowercased()
        print("Whisper 60s+ transcript (\(transcript.count) chars, took \(result.inferenceSeconds)s): \(transcript)")

        XCTAssertGreaterThan(transcript.count, 100)
        XCTAssertTrue(transcript.contains("chunk"))
    }

    func testClipboardOutputDriverRoundTrip() throws {
        let uniqueID = "fluidvoice-test-\(UUID().uuidString)"
        let testString = "FluidVoice transcription output test: \(uniqueID)"

        try TextOutputDriver.copyToClipboard(testString)
        Thread.sleep(forTimeInterval: 0.1)

        // Verify clipboard readback
        let process = Process()
        let isWayland = ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil
        process.executableURL = URL(fileURLWithPath: isWayland ? "/usr/bin/wl-paste" : "/usr/bin/xclip")
        if !isWayland {
            process.arguments = ["-o", "-selection", "clipboard"]
        }

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let pasted = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(pasted.contains(uniqueID))
            }
        } catch {
            print("Clipboard readback test skipped: \(error)")
        }
    }
}
