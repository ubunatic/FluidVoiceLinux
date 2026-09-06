import Foundation

/// Phase 4 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md): the
/// `transcribe --in <path>.wav [--model <path>] [--no-gpu]` CLI subcommand. Same
/// argument-parsing/execution split as `RecordCommand` (docs/SwiftLinux.md §3) —
/// `parseArguments` is unit-testable without a model file, real WAV data, or a GPU.
public struct TranscribeOptions: Equatable {
    public let inputPath: String
    public let modelPath: String
    public let noGPU: Bool

    public static let defaultModelPath = "models/ggml-base.en.bin"

    public init(
        inputPath: String,
        modelPath: String = TranscribeOptions.defaultModelPath,
        noGPU: Bool = false
    ) {
        self.inputPath = inputPath
        self.modelPath = modelPath
        self.noGPU = noGPU
    }
}

public enum TranscribeArgumentError: Error, CustomStringConvertible {
    case missingValue(flag: String)
    case missingRequired(flag: String)
    case unknownArgument(String)

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .missingRequired(let flag):
            return "missing required argument \(flag)"
        case .unknownArgument(let argument):
            return "unknown argument '\(argument)'"
        }
    }
}

public enum TranscribeCommand {
    /// Parses `transcribe` subcommand arguments (everything after the "transcribe"
    /// token itself). Supported flags: `--in path` (required), `--model path`
    /// (optional, defaults to `models/ggml-base.en.bin`, matching whisper.cpp's own
    /// CLI default), `--no-gpu` (optional, forces CPU-only inference).
    public static func parseArguments(_ arguments: [String]) throws -> TranscribeOptions {
        var inputPath: String?
        var modelPath = TranscribeOptions.defaultModelPath
        var noGPU = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() throws -> String {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw TranscribeArgumentError.missingValue(flag: argument)
                }
                index = valueIndex
                return arguments[valueIndex]
            }

            switch argument {
            case "--in":
                inputPath = try nextValue()
            case "--model":
                modelPath = try nextValue()
            case "--no-gpu":
                noGPU = true
            default:
                throw TranscribeArgumentError.unknownArgument(argument)
            }
            index += 1
        }

        guard let resolvedInputPath = inputPath else {
            throw TranscribeArgumentError.missingRequired(flag: "--in")
        }

        return TranscribeOptions(inputPath: resolvedInputPath, modelPath: modelPath, noGPU: noGPU)
    }

    /// Runs the full `transcribe` subcommand: parses arguments, reads+decodes the
    /// WAV file, and runs whisper.cpp inference. Returns a process exit code (0
    /// success). Real file I/O and model inference only happen here, not in
    /// `parseArguments`.
    public static func run(arguments: [String]) -> Int32 {
        let options: TranscribeOptions
        do {
            options = try parseArguments(arguments)
        } catch {
            FileHandle.standardError.write(Data("transcribe: \(error)\n".utf8))
            return 1
        }

        let wavData: Data
        do {
            wavData = try Data(contentsOf: URL(fileURLWithPath: options.inputPath))
        } catch {
            FileHandle.standardError.write(
                Data("transcribe: failed to read '\(options.inputPath)': \(error)\n".utf8)
            )
            return 1
        }

        let decoded: DecodedWav
        do {
            decoded = try WavReader.decode(wavData)
        } catch {
            FileHandle.standardError.write(
                Data("transcribe: failed to decode '\(options.inputPath)': \(error)\n".utf8)
            )
            return 1
        }

        let backend: WhisperBackend = options.noGPU ? .cpuOnly : .auto
        print(
            "Transcribing '\(options.inputPath)' (\(decoded.monoSamples.count) samples @ "
                + "\(decoded.sampleRate) Hz) with model '\(options.modelPath)' "
                + "(backend: \(backend == .auto ? "gpu-if-available" : "cpu-only"))"
        )

        let result: TranscriptionResult
        do {
            result = try WhisperTranscriber.transcribe(
                samples: decoded.monoSamples,
                modelPath: options.modelPath,
                backend: backend
            )
        } catch {
            FileHandle.standardError.write(Data("transcribe: \(error)\n".utf8))
            return 1
        }

        print(
            String(
                format: "Loaded model in %.3fs, ran inference in %.3fs",
                result.modelLoadSeconds,
                result.inferenceSeconds
            )
        )
        print(result.text)
        return 0
    }
}
