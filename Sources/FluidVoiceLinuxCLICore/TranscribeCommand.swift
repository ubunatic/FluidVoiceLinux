import Foundation

/// Phase 4 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md): the
/// `transcribe --in <path>.wav [--model <path>] [--no-gpu]` CLI subcommand. Same
/// argument-parsing/execution split as `RecordCommand` (docs/SwiftLinux.md §3) —
/// `parseArguments` is unit-testable without a model file, real WAV data, or a GPU.
public struct TranscribeOptions: Equatable {
    public let inputPath: String
    /// `nil` when `--model` wasn't passed, meaning the caller should resolve
    /// the actual path via `ModelPathResolver.resolve` (issue 007) — this
    /// struct/`parseArguments` stay pure and don't touch the filesystem or
    /// environment, per docs/SwiftLinux.md §3.
    public let modelPath: String?
    public let noGPU: Bool

    /// Kept for reference/help text: the repo-relative dev-workflow default,
    /// also exposed as `ModelPathResolver.repoRelativeModelPath`.
    public static let defaultModelPath = ModelPathResolver.repoRelativeModelPath

    public init(
        inputPath: String,
        modelPath: String? = nil,
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
    /// (optional — when omitted, `TranscribeCommand.run` resolves the real default
    /// via `ModelPathResolver`, issue 007: repo-relative `models/ggml-base.en.bin`
    /// if present, else `$XDG_DATA_HOME/fluidvoice/models/ggml-base.en.bin`),
    /// `--no-gpu` (optional, forces CPU-only inference).
    public static func parseArguments(_ arguments: [String]) throws -> TranscribeOptions {
        var inputPath: String?
        var modelPath: String?
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

        // Issue 007: resolve the real model path here (real filesystem/env
        // access), not in parseArguments — see ModelPathResolver's doc comment
        // for the three-way resolution order.
        let modelPath = ModelPathResolver.resolve(
            explicit: options.modelPath,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            xdgDataHome: ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
            home: ProcessInfo.processInfo.environment["HOME"]
        )

        let backend: WhisperBackend = options.noGPU ? .cpuOnly : .auto
        print(
            "Transcribing '\(options.inputPath)' (\(decoded.monoSamples.count) samples @ "
                + "\(decoded.sampleRate) Hz) with model '\(modelPath)' "
                + "(backend: \(backend == .auto ? "gpu-if-available" : "cpu-only"))"
        )

        let result: TranscriptionResult
        do {
            result = try WhisperTranscriber.transcribe(
                samples: decoded.monoSamples,
                modelPath: modelPath,
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
