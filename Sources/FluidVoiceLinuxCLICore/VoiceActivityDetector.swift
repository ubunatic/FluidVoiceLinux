import Foundation

public struct SpeechInterval: Equatable, Codable {
    public let startSample: Int
    public let endSample: Int
    public let startTime: Double
    public let endTime: Double

    public var duration: Double {
        endTime - startTime
    }

    public init(startSample: Int, endSample: Int, sampleRate: Int = 16000) {
        self.startSample = startSample
        self.endSample = endSample
        let rate = Double(sampleRate)
        self.startTime = Double(startSample) / rate
        self.endTime = Double(endSample) / rate
    }
}

public struct VADConfiguration: Equatable {
    public var threshold: Float
    public var minSpeechDurationMs: Int
    public var minSilenceDurationMs: Int
    public var speechPadMs: Int
    public var sampleRate: Int

    public init(
        threshold: Float = 0.5,
        minSpeechDurationMs: Int = 250,
        minSilenceDurationMs: Int = 300,
        speechPadMs: Int = 100,
        sampleRate: Int = 16000
    ) {
        self.threshold = threshold
        self.minSpeechDurationMs = minSpeechDurationMs
        self.minSilenceDurationMs = minSilenceDurationMs
        self.speechPadMs = speechPadMs
        self.sampleRate = sampleRate
    }
}

public struct AudioChunk: Equatable {
    public let index: Int
    public let interval: SpeechInterval
    public let samples: [Float]
}

public enum VADError: Error, CustomStringConvertible {
    case modelNotFound(String)
    case pythonNotFound
    case processFailed(String)
    case invalidOutput(String)

    public var description: String {
        switch self {
        case .modelNotFound(let path):
            return "VAD model file not found at '\(path)'"
        case .pythonNotFound:
            return "Python runtime not found. Ensure silero-vad / onnxruntime is installed."
        case .processFailed(let msg):
            return "VAD process failed: \(msg)"
        case .invalidOutput(let out):
            return "Invalid VAD process output: \(out)"
        }
    }
}

/// Pure Swift Energy-based VAD for unit testing, fast lightweight fallback,
/// and low-latency frame evaluation without external dependencies.
public enum EnergyVoiceActivityDetector {
    public static func detectIntervals(
        samples: [Float],
        config: VADConfiguration = VADConfiguration(),
        frameSizeMs: Int = 30,
        energyThreshold: Float = 0.015
    ) -> [SpeechInterval] {
        guard !samples.isEmpty else { return [] }

        let frameLength = max(1, config.sampleRate * frameSizeMs / 1000)
        let minSpeechFrames = max(1, config.minSpeechDurationMs / frameSizeMs)
        let minSilenceFrames = max(1, config.minSilenceDurationMs / frameSizeMs)
        let padSamples = config.sampleRate * config.speechPadMs / 1000

        var speechFramesCount = 0
        var silenceFramesCount = 0
        var isSpeaking = false
        var speechStartSample = 0
        var intervals: [SpeechInterval] = []

        var i = 0
        while i < samples.count {
            let chunkEnd = min(i + frameLength, samples.count)
            let frame = samples[i..<chunkEnd]

            var sumSq: Float = 0.0
            for sample in frame {
                sumSq += sample * sample
            }
            let rms = sqrt(sumSq / Float(frame.count))
            let isFrameActive = rms >= energyThreshold

            if isFrameActive {
                speechFramesCount += 1
                silenceFramesCount = 0

                if !isSpeaking && speechFramesCount >= minSpeechFrames {
                    isSpeaking = true
                    speechStartSample = max(0, i - (speechFramesCount * frameLength) - padSamples)
                }
            } else {
                silenceFramesCount += 1
                if isSpeaking {
                    if silenceFramesCount >= minSilenceFrames {
                        let speechEndSample = min(samples.count, i + padSamples)
                        intervals.append(SpeechInterval(
                            startSample: speechStartSample,
                            endSample: speechEndSample,
                            sampleRate: config.sampleRate
                        ))
                        isSpeaking = false
                        speechFramesCount = 0
                    }
                } else {
                    speechFramesCount = 0
                }
            }

            i += frameLength
        }

        if isSpeaking {
            let speechEndSample = samples.count
            intervals.append(SpeechInterval(
                startSample: speechStartSample,
                endSample: speechEndSample,
                sampleRate: config.sampleRate
            ))
        }

        return intervals
    }
}

public enum SileroVoiceActivityDetector {
    private static func findPythonBinary() -> String? {
        let candidatePaths: [String] = [
            "/tmp/canary_venv/bin/python",
            "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.local/share/fluidvoice/venv/bin/python",
            "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.venv/bin/python",
            "/usr/bin/python3"
        ]

        for p in candidatePaths {
            if FileManager.default.fileExists(atPath: p) {
                return p
            }
        }
        return nil
    }

    public static func detectIntervals(
        samples: [Float],
        config: VADConfiguration = VADConfiguration(),
        modelPath: String? = nil
    ) throws -> [SpeechInterval] {
        guard !samples.isEmpty else { return [] }

        guard let pythonPath = findPythonBinary() else {
            throw VADError.pythonNotFound
        }

        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("vad_\(UUID().uuidString).wav")
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * 32767.0)
        }
        let wavData = WavFormat.makeFile(samples: int16Samples, sampleRate: UInt32(config.sampleRate), channelCount: 1)
        try wavData.write(to: tempWavURL)
        defer { try? FileManager.default.removeItem(at: tempWavURL) }

        let script = """
        import sys, json, wave, numpy as np
        try:
            import silero_vad, torch
        except ImportError:
            sys.stderr.write("ImportError: silero_vad or torch missing\\n")
            sys.exit(2)

        wav_path = sys.argv[1]
        threshold = float(sys.argv[2])
        min_speech_ms = int(sys.argv[3])
        min_silence_ms = int(sys.argv[4])
        speech_pad_ms = int(sys.argv[5])
        sr = int(sys.argv[6])

        with wave.open(wav_path, 'rb') as wf:
            n_frames = wf.getnframes()
            data = wf.readframes(n_frames)
            samples = np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
            wav_tensor = torch.from_numpy(samples)

        model = silero_vad.load_silero_vad(onnx=True)
        timestamps = silero_vad.get_speech_timestamps(
            wav_tensor,
            model,
            threshold=threshold,
            sampling_rate=sr,
            min_speech_duration_ms=min_speech_ms,
            min_silence_duration_ms=min_silence_ms,
            speech_pad_ms=speech_pad_ms,
            return_seconds=False
        )

        res = []
        for t in timestamps:
            res.append({"startSample": int(t["start"]), "endSample": int(t["end"])})

        print(json.dumps(res))
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-c", script,
            tempWavURL.path,
            "\(config.threshold)",
            "\(config.minSpeechDurationMs)",
            "\(config.minSilenceDurationMs)",
            "\(config.speechPadMs)",
            "\(config.sampleRate)"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw VADError.processFailed(error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw VADError.processFailed("exit code \(process.terminationStatus): \(stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        struct RawInterval: Decodable {
            let startSample: Int
            let endSample: Int
        }

        guard let jsonData = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let parsed = try? JSONDecoder().decode([RawInterval].self, from: jsonData) else {
            throw VADError.invalidOutput(stdoutText)
        }

        return parsed.map {
            SpeechInterval(startSample: $0.startSample, endSample: $0.endSample, sampleRate: config.sampleRate)
        }
    }
}

public enum AudioSegmenter {
    /// Segments audio into discrete chunks given speech intervals.
    public static func segment(
        samples: [Float],
        intervals: [SpeechInterval],
        sampleRate: Int = 16000
    ) -> [AudioChunk] {
        var chunks: [AudioChunk] = []

        for (idx, interval) in intervals.enumerated() {
            let clampedStart = max(0, min(samples.count, interval.startSample))
            let clampedEnd = max(clampedStart, min(samples.count, interval.endSample))
            guard clampedEnd > clampedStart else { continue }

            let slice = Array(samples[clampedStart..<clampedEnd])
            chunks.append(AudioChunk(index: idx, interval: interval, samples: slice))
        }

        return chunks
    }
}
