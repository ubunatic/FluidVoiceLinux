import Foundation

public enum CohereTranscriberError: Error, CustomStringConvertible {
    case modelFileNotFound(String)
    case pythonNotFound
    case workerFailed(String)
    case invalidWorkerOutput(String)

    public var description: String {
        switch self {
        case .modelFileNotFound(let path):
            return "cohere model file not found at '\(path)'"
        case .pythonNotFound:
            return "python runtime with crispasr not found. Ensure crispasr is installed."
        case .workerFailed(let msg):
            return "cohere inference worker failed: \(msg)"
        case .invalidWorkerOutput(let out):
            return "invalid worker output format: \(out)"
        }
    }
}

public enum CohereTranscriber {
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

    /// Transcribes an audio file or PCM samples using Cohere Transcribe GGUF model.
    public static func transcribeFile(
        audioPath: String,
        modelPath: String,
        language: String = "en"
    ) throws -> (text: String, modelLoadSeconds: Double, inferenceSeconds: Double) {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw CohereTranscriberError.modelFileNotFound(modelPath)
        }

        guard let pythonPath = findPythonBinary() else {
            throw CohereTranscriberError.pythonNotFound
        }

        let script = """
        import sys, json, time
        try:
            import crispasr
        except ImportError:
            sys.stderr.write("ImportError: crispasr package missing\\n")
            sys.exit(2)

        model_path = sys.argv[1]
        audio_path = sys.argv[2]
        lang = sys.argv[3] if len(sys.argv) > 3 else "en"

        t0 = time.time()
        with crispasr.Session(model_path) as s:
            load_time = time.time() - t0
            pcm = crispasr.CrispASR._load_audio(audio_path)
            t1 = time.time()
            segs = s.transcribe(pcm, language=lang)
            infer_time = time.time() - t1
            text = " ".join(seg.text for seg in segs).strip()
            print(json.dumps({
                "text": text,
                "modelLoadSeconds": load_time,
                "inferenceSeconds": infer_time
            }))
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", script, modelPath, audioPath, language]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CohereTranscriberError.workerFailed(error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw CohereTranscriberError.workerFailed("exit code \(process.terminationStatus): \(stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        struct WorkerResult: Decodable {
            let text: String
            let modelLoadSeconds: Double
            let inferenceSeconds: Double
        }

        guard let jsonData = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let parsed = try? JSONDecoder().decode(WorkerResult.self, from: jsonData) else {
            throw CohereTranscriberError.invalidWorkerOutput(stdoutText)
        }

        return (text: parsed.text, modelLoadSeconds: parsed.modelLoadSeconds, inferenceSeconds: parsed.inferenceSeconds)
    }

    /// Overload for raw float samples: writes a temporary WAV and delegates to transcribeFile
    public static func transcribe(
        samples: [Float],
        sampleRate: Int = 16000,
        modelPath: String,
        language: String = "en"
    ) throws -> (text: String, modelLoadSeconds: Double, inferenceSeconds: Double) {
        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("cohere_temp_\(UUID().uuidString).wav")
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * 32767.0)
        }
        let wavData = WavFormat.makeFile(samples: int16Samples, sampleRate: UInt32(sampleRate), channelCount: 1)
        try wavData.write(to: tempWavURL)
        defer { try? FileManager.default.removeItem(at: tempWavURL) }

        return try transcribeFile(audioPath: tempWavURL.path, modelPath: modelPath, language: language)
    }
}
