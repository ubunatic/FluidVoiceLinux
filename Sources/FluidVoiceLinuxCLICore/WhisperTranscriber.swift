import CWhisper
import Foundation

/// Phase 4 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md): a thin Swift
/// wrapper around whisper.cpp's C API (`CWhisper`, see
/// Sources/LinuxWhisperSupport). Real model load / inference only happens here — kept
/// separate from `TranscribeCommand`'s argument parsing so the parsing stays
/// unit-testable without a model file or a GPU.
public enum WhisperBackend: String {
    /// `whisper_context_params.use_gpu = true`. whisper.cpp/ggml auto-detects and
    /// initializes a Vulkan (or other) GPU backend if one is available at runtime,
    /// and transparently falls back to CPU if GPU backend init fails (e.g. no
    /// compatible Vulkan device found) — this is upstream library behavior, verified
    /// for real in this ticket by forcing `VK_ICD_FILENAMES` to a bogus path (see
    /// docs/LINUX_SETUP.md and issue 004's Resolution section).
    case auto
    /// `whisper_context_params.use_gpu = false`. Forces CPU-only inference,
    /// regardless of GPU availability — used by `transcribe --no-gpu` and by tests
    /// that want a deterministic CPU baseline.
    case cpuOnly
}

public struct TranscriptionResult {
    public let text: String
    public let usedBackend: WhisperBackend
    public let modelLoadSeconds: Double
    public let inferenceSeconds: Double
}

public enum WhisperTranscriberError: Error, CustomStringConvertible {
    case modelFileNotFound(String)
    case modelLoadFailed(String)
    case inferenceFailed(Int32)

    public var description: String {
        switch self {
        case .modelFileNotFound(let path):
            return "model file not found: \(path)"
        case .modelLoadFailed(let path):
            return "failed to load whisper model from '\(path)' (corrupt file or unsupported format?)"
        case .inferenceFailed(let code):
            return "whisper_full() failed with code \(code)"
        }
    }
}

public enum WhisperTranscriber {
    /// Runs whisper.cpp inference on already-decoded mono 16kHz Float32 PCM samples.
    /// `backend` controls whether GPU use is requested (`.auto`, with library-level
    /// CPU fallback on init failure) or explicitly disabled (`.cpuOnly`).
    public static func transcribe(
        samples: [Float],
        modelPath: String,
        backend: WhisperBackend,
        language: String = "en"
    ) throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperTranscriberError.modelFileNotFound(modelPath)
        }

        // ggml ships its CPU/Vulkan/etc. compute backends as separate dynamically
        // loaded plugins (Ubuntu's libggml0-backend-vulkan package installs
        // libggml-vulkan.so under /usr/lib/<arch>/ggml/backends0/, see
        // docs/LINUX_SETUP.md), and — unlike whisper.cpp's own `whisper-cli` binary,
        // which does this in its startup boilerplate — the whisper.cpp *library* API
        // does not load them automatically. Skipping this call is silent: whisper
        // reports zero devices/backends and later asserts inside ggml-backend.cpp
        // rather than falling back to CPU, which is how this was discovered while
        // building this wrapper (see issue 004's Resolution section).
        ggml_backend_load_all()

        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = (backend == .auto)

        let loadStart = Date()
        guard let context = modelPath.withCString({ whisper_init_from_file_with_params($0, contextParams) }) else {
            throw WhisperTranscriberError.modelLoadFailed(modelPath)
        }
        defer { whisper_free(context) }
        let modelLoadSeconds = Date().timeIntervalSince(loadStart)

        var fullParams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        fullParams.print_progress = false
        fullParams.print_special = false
        fullParams.print_realtime = false
        fullParams.print_timestamps = false
        fullParams.translate = false
        fullParams.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount))

        let inferenceStart = Date()
        let status: Int32 = language.withCString { languageCString in
            fullParams.language = languageCString
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, fullParams, buffer.baseAddress, Int32(buffer.count))
            }
        }
        let inferenceSeconds = Date().timeIntervalSince(inferenceStart)

        guard status == 0 else {
            throw WhisperTranscriberError.inferenceFailed(status)
        }

        let segmentCount = whisper_full_n_segments(context)
        var pieces: [String] = []
        pieces.reserveCapacity(Int(segmentCount))
        for index in 0..<segmentCount {
            if let cText = whisper_full_get_segment_text(context, index) {
                pieces.append(String(cString: cText))
            }
        }
        let text = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)

        return TranscriptionResult(
            text: text,
            usedBackend: backend,
            modelLoadSeconds: modelLoadSeconds,
            inferenceSeconds: inferenceSeconds
        )
    }
}
