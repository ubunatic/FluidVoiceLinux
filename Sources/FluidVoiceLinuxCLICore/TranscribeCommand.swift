import Foundation

/// Phase 4 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md): the
/// `transcribe --in <path>.wav [--model <path>] [--no-gpu]` CLI subcommand. Same
/// argument-parsing/execution split as `RecordCommand` (docs/SwiftLinux.md §3) —
/// `parseArguments` is unit-testable without a model file, real WAV data, or a GPU.
public enum STTEngineBackend: String, Equatable {
    case whisper
    case cohere
    case parakeet
    case nemotron
}

public struct TranscribeOptions: Equatable {
    public let inputPath: String
    /// `nil` when `--model` wasn't passed, meaning the caller should resolve
    /// the actual path via `ModelPathResolver` — this struct/`parseArguments`
    /// stay pure and don't touch the filesystem or environment.
    public let modelPath: String?
    public let noGPU: Bool
    public let backend: STTEngineBackend
    public let language: String
    public let enhance: Bool
    public let aiProvider: AIProvider
    public let aiModel: String?
    public let aiAPIKey: String?
    public let aiEndpoint: String?
    public let outputTarget: TextOutputTarget

    public static let defaultModelPath = ModelPathResolver.repoRelativeModelPath

    public init(
        inputPath: String,
        modelPath: String? = nil,
        noGPU: Bool = false,
        backend: STTEngineBackend = .whisper,
        language: String = "en",
        enhance: Bool = false,
        aiProvider: AIProvider = .ollama,
        aiModel: String? = nil,
        aiAPIKey: String? = nil,
        aiEndpoint: String? = nil,
        outputTarget: TextOutputTarget = .stdout
    ) {
        self.inputPath = inputPath
        self.modelPath = modelPath
        self.noGPU = noGPU
        self.backend = backend
        self.language = language
        self.enhance = enhance
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.aiAPIKey = aiAPIKey
        self.aiEndpoint = aiEndpoint
        self.outputTarget = outputTarget
    }
}

public enum TranscribeArgumentError: Error, CustomStringConvertible, Equatable {
    case missingValue(flag: String)
    case missingRequired(flag: String)
    case unknownArgument(String)
    case unknownBackend(String)
    case unknownAIProvider(String)

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .missingRequired(let flag):
            return "missing required argument \(flag)"
        case .unknownArgument(let argument):
            return "unknown argument '\(argument)'"
        case .unknownBackend(let backend):
            return "unknown STT backend '\(backend)' (expected 'whisper', 'cohere', 'parakeet', or 'nemotron')"
        case .unknownAIProvider(let provider):
            return "unknown AI provider '\(provider)' (expected 'ollama', 'openai', 'anthropic', 'gemini', 'groq', 'openrouter', or 'custom')"
        }
    }
}

public enum TranscribeCommand {
    /// Parses `transcribe` subcommand arguments. Supported flags:
    /// `--in path` (required), `--model path` (optional),
    /// `--backend whisper|cohere|parakeet|nemotron` (optional, default: whisper),
    /// `--lang <code>` (optional, default: en), `--no-gpu` (optional),
    /// `--enhance` (optional, default: false),
    /// `--ai-provider ollama|openai|anthropic|gemini|groq|openrouter|custom` (optional, default: ollama),
    /// `--ai-model <name>` (optional), `--ai-api-key <key>` (optional), `--ai-endpoint <url>` (optional),
    /// `--clipboard` / `--copy`, `--type` / `--type-keystrokes`, `--stdout`.
    public static func parseArguments(_ arguments: [String]) throws -> TranscribeOptions {
        var inputPath: String?
        var modelPath: String?
        var noGPU = false
        var backend: STTEngineBackend = .whisper
        var language: String = "en"
        var enhance = false
        var aiProvider: AIProvider = .ollama
        var aiModel: String?
        var aiAPIKey: String?
        var aiEndpoint: String?
        var outputTarget: TextOutputTarget = .stdout

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
                if let matched = STTEngineBackend(rawValue: val) {
                    backend = matched
                } else {
                    throw TranscribeArgumentError.unknownBackend(val)
                }
            case "--lang", "--language":
                language = try nextValue()
            case "--enhance":
                enhance = true
            case "--ai-provider", "--provider":
                let val = try nextValue().lowercased()
                if let matched = AIProvider(rawValue: val) {
                    aiProvider = matched
                } else {
                    throw TranscribeArgumentError.unknownAIProvider(val)
                }
            case "--ai-model":
                aiModel = try nextValue()
            case "--ai-api-key":
                aiAPIKey = try nextValue()
            case "--ai-endpoint":
                aiEndpoint = try nextValue()
            case "--type", "--type-keystrokes":
                outputTarget = .typing
            case "--clipboard", "--copy":
                outputTarget = .clipboard
            case "--stdout":
                outputTarget = .stdout
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
            language: language,
            enhance: enhance,
            aiProvider: aiProvider,
            aiModel: aiModel,
            aiAPIKey: aiAPIKey,
            aiEndpoint: aiEndpoint,
            outputTarget: outputTarget
        )
    }

    /// Runs the full `transcribe` subcommand.
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
            var finalText = result.text
            if options.enhance {
                let aiConfig = AIEnhancementConfiguration(
                    provider: options.aiProvider,
                    model: options.aiModel,
                    baseURL: options.aiEndpoint,
                    apiKey: options.aiAPIKey
                )
                print("Enhancing transcription with \(options.aiProvider.rawValue)...")
                do {
                    finalText = try AIEnhancementService.enhanceBlocking(text: result.text, config: aiConfig)
                } catch {
                    FileHandle.standardError.write(Data("transcribe: AI enhancement warning: \(error)\n".utf8))
                }
            }

            do {
                try TextOutputDriver.emit(finalText, target: options.outputTarget)
            } catch {
                FileHandle.standardError.write(Data("transcribe: output failed: \(error)\n".utf8))
                print(finalText)
            }
            return 0

        case .cohere, .parakeet, .nemotron:
            let modelPath: String
            let modelLabel: String
            switch options.backend {
            case .cohere:
                modelPath = ModelPathResolver.resolveCohere(
                    explicit: options.modelPath,
                    fileExists: fileExists,
                    xdgDataHome: xdgDataHome,
                    home: home
                )
                modelLabel = "Cohere Transcribe"
            case .parakeet:
                modelPath = ModelPathResolver.resolveParakeet(
                    explicit: options.modelPath,
                    fileExists: fileExists,
                    xdgDataHome: xdgDataHome,
                    home: home
                )
                modelLabel = "Parakeet TDT v3"
            case .nemotron:
                modelPath = ModelPathResolver.resolveNemotron(
                    explicit: options.modelPath,
                    fileExists: fileExists,
                    xdgDataHome: xdgDataHome,
                    home: home
                )
                modelLabel = "Nemotron Speech 3.5"
            case .whisper:
                fatalError("unreachable")
            }

            print(
                "Transcribing '\(options.inputPath)' (\(decoded.monoSamples.count) samples @ "
                    + "\(decoded.sampleRate) Hz) with \(modelLabel) model '\(modelPath)' "
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

            var finalText = result.text
            if options.enhance {
                let aiConfig = AIEnhancementConfiguration(
                    provider: options.aiProvider,
                    model: options.aiModel,
                    baseURL: options.aiEndpoint,
                    apiKey: options.aiAPIKey
                )
                print("Enhancing transcription with \(options.aiProvider.rawValue)...")
                do {
                    finalText = try AIEnhancementService.enhanceBlocking(text: result.text, config: aiConfig)
                } catch {
                    FileHandle.standardError.write(Data("transcribe: AI enhancement warning: \(error)\n".utf8))
                }
            }

            do {
                try TextOutputDriver.emit(finalText, target: options.outputTarget)
            } catch {
                FileHandle.standardError.write(Data("transcribe: output failed: \(error)\n".utf8))
                print(finalText)
            }
            return 0
        }
    }
}
