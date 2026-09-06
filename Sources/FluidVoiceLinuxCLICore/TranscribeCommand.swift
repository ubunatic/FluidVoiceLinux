import Foundation

/// Phase 4 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md): the
/// `transcribe --in <path>.wav [--model <path>] [--no-gpu]` CLI subcommand. Same
/// argument-parsing/execution split as `RecordCommand` (docs/SwiftLinux.md §3) —
/// `parseArguments` is unit-testable without a model file, real WAV data, or a GPU.
public enum STTEngineBackend: String, Equatable {
    case whisper
    case cohere
}

public struct TranscribeOptions: Equatable {
    public let inputPath: String
    /// `nil` when `--model` wasn't passed, meaning the caller should resolve
    /// the actual path via `ModelPathResolver.resolve` / `resolveCohere` (issue 007 & 010) — this
    /// struct/`parseArguments` stay pure and don't touch the filesystem or
    /// environment, per docs/SwiftLinux.md §3.
    public let modelPath: String?
    public let noGPU: Bool
    public let backend: STTEngineBackend
    public let language: String

    /// Kept for reference/help text: the repo-relative dev-workflow default,
    /// also exposed as `ModelPathResolver.repoRelativeModelPath`.
    public static let defaultModelPath = ModelPathResolver.repoRelativeModelPath

    public init(
        inputPath: String,
        modelPath: String? = nil,
        noGPU: Bool = false,
        backend: STTEngineBackend = .whisper,
        language: String = "en"
    ) {
        self.inputPath = inputPath
        self.modelPath = modelPath
        self.noGPU = noGPU
        self.backend = backend
        self.language = language
    }
}

public enum TranscribeArgumentError: Error, CustomStringConvertible, Equatable {
    case missingValue(flag: String)
    case missingRequired(flag: String)
    case unknownArgument(String)
    case unknownBackend(String)

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .missingRequired(let flag):
            return "missing required argument \(flag)"
        case .unknownArgument(let argument):
            return "unknown argument '\(argument)'"
        case .unknownBackend(let backend):
            return "unknown STT backend '\(backend)' (expected 'whisper' or 'cohere')"
        }
    }
}

public enum TranscribeCommand {
    /// Parses `transcribe` subcommand arguments (everything after the "transcribe"
    /// token itself). Supported flags: `--in path` (required), `--model path`
    /// (optional), `--backend whisper|cohere` (optional, default: whisper),
    /// `--lang <code>` (optional, default: en), `--no-gpu` (optional).
    public static func parseArguments(_ arguments: [String]) throws -> TranscribeOptions {
        var inputPath: String?
        var modelPath: String?
        var noGPU = false
        var backend: STTEngineBackend = .whisper
        var language: String = "en"

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
            case "--backend":
                let val = try nextValue().lowercased()
                if val == "cohere" {
                    backend = .cohere
                } else if val == "whisper" {
                    backend = .whisper
                } else {
                    throw TranscribeArgumentError.unknownBackend(val)
                }
            case "--lang", "--language":
                language = try nextValue()
            default:
                throw TranscribeArgumentError.unknownArgument(argument)
            }
            index += 1
        }

        guard let resolvedInputPath = inputPath else {
            throw TranscribeArgumentError.missingRequired(flag: "--in")
        }

        return TranscribeOptions(
            inputPath: resolvedInputPath,
            modelPath: modelPath,
            noGPU: noGPU,
            backend: backend,
            language: language
        )
    }

    /// Runs the full `transcribe` subcommand: parses arguments, reads+decodes the
    /// WAV file, and runs STT inference (Whisper or Cohere). Returns exit code.
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

        let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        let home = ProcessInfo.processInfo.environment["HOME"]
        let fileExists = { FileManager.default.fileExists(atPath: $0) }

        switch options.backend {
        case .whisper:
            let modelPath = ModelPathResolver.resolve(
                explicit: options.modelPath,
                fileExists: fileExists,
                xdgDataHome: xdgDataHome,
                home: home
            )

            let whisperBackend: WhisperBackend = options.noGPU ? .cpuOnly : .auto
            print(
                "Transcribing '\(options.inputPath)' (\(decoded.monoSamples.count) samples @ "
                    + "\(decoded.sampleRate) Hz) with Whisper model '\(modelPath)' "
                    + "(backend: \(whisperBackend == .auto ? "gpu-if-available" : "cpu-only"), lang: \(options.language))"
            )

            let result: TranscriptionResult
            do {
                result = try WhisperTranscriber.transcribe(
                    samples: decoded.monoSamples,
                    modelPath: modelPath,
                    backend: whisperBackend,
                    language: options.language
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

        case .cohere:
            let modelPath = ModelPathResolver.resolveCohere(
                explicit: options.modelPath,
                fileExists: fileExists,
                xdgDataHome: xdgDataHome,
                home: home
            )

            print(
                "Transcribing '\(options.inputPath)' (\(decoded.monoSamples.count) samples @ "
                    + "\(decoded.sampleRate) Hz) with Cohere Transcribe model '\(modelPath)' "
                    + "(lang: \(options.language))"
            )

            let result: (text: String, modelLoadSeconds: Double, inferenceSeconds: Double)
            do {
                result = try CohereTranscriber.transcribeFile(
                    audioPath: options.inputPath,
                    modelPath: modelPath,
                    language: options.language
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
}
