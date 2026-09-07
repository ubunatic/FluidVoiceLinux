import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct DictateOptions: Equatable {
    public let backend: STTEngineBackend
    public let modelPath: String?
    public let language: String
    public let enhance: Bool
    public let aiProvider: AIProvider
    public let aiModel: String?
    public let aiAPIKey: String?
    public let aiEndpoint: String?
    public let outputTarget: TextOutputTarget
    public let deviceName: String
    public let maxDurationSeconds: Double?
    public let noGPU: Bool

    public init(
        backend: STTEngineBackend = .parakeet,
        modelPath: String? = nil,
        language: String = "en",
        enhance: Bool = false,
        aiProvider: AIProvider = .ollama,
        aiModel: String? = nil,
        aiAPIKey: String? = nil,
        aiEndpoint: String? = nil,
        outputTarget: TextOutputTarget = .stdout,
        deviceName: String = AlsaAudioRecorder.defaultDeviceName,
        maxDurationSeconds: Double? = nil,
        noGPU: Bool = false
    ) {
        self.backend = backend
        self.modelPath = modelPath
        self.language = language
        self.enhance = enhance
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.aiAPIKey = aiAPIKey
        self.aiEndpoint = aiEndpoint
        self.outputTarget = outputTarget
        self.deviceName = deviceName
        self.maxDurationSeconds = maxDurationSeconds
        self.noGPU = noGPU
    }
}

public enum DictateArgumentError: Error, CustomStringConvertible, Equatable {
    case missingValue(flag: String)
    case unknownArgument(String)
    case unknownBackend(String)
    case unknownAIProvider(String)
    case invalidDuration(String)

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .unknownArgument(let arg):
            return "unknown argument '\(arg)'"
        case .unknownBackend(let b):
            return "unknown STT backend '\(b)' (expected 'whisper', 'cohere', 'parakeet', or 'nemotron')"
        case .unknownAIProvider(let p):
            return "unknown AI provider '\(p)'"
        case .invalidDuration(let d):
            return "invalid duration '\(d)' (expected positive number)"
        }
    }
}

public enum DictateCommand {
    public static func parseArguments(_ arguments: [String]) throws -> DictateOptions {
        var backend: STTEngineBackend = .parakeet
        var modelPath: String?
        var language = "en"
        var enhance = false
        var aiProvider: AIProvider = .ollama
        var aiModel: String?
        var aiAPIKey: String?
        var aiEndpoint: String?
        var outputTarget: TextOutputTarget = .stdout
        var deviceName = AlsaAudioRecorder.defaultDeviceName
        var maxDurationSeconds: Double?
        var noGPU = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() throws -> String {
                let nextIdx = index + 1
                guard nextIdx < arguments.count else {
                    throw DictateArgumentError.missingValue(flag: argument)
                }
                index = nextIdx
                return arguments[nextIdx]
            }

            switch argument {
            case "--backend":
                let val = try nextValue().lowercased()
                if let b = STTEngineBackend(rawValue: val) {
                    backend = b
                } else {
                    throw DictateArgumentError.unknownBackend(val)
                }
            case "--model":
                modelPath = try nextValue()
            case "--lang", "--language":
                language = try nextValue()
            case "--enhance":
                enhance = true
            case "--ai-provider", "--provider":
                let val = try nextValue().lowercased()
                if let p = AIProvider(rawValue: val) {
                    aiProvider = p
                } else {
                    throw DictateArgumentError.unknownAIProvider(val)
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
            case "--device":
                deviceName = try nextValue()
            case "--seconds", "--duration":
                let val = try nextValue()
                guard let d = Double(val), d > 0 else {
                    throw DictateArgumentError.invalidDuration(val)
                }
                maxDurationSeconds = d
            case "--no-gpu":
                noGPU = true
            default:
                throw DictateArgumentError.unknownArgument(argument)
            }
            index += 1
        }

        return DictateOptions(
            backend: backend,
            modelPath: modelPath,
            language: language,
            enhance: enhance,
            aiProvider: aiProvider,
            aiModel: aiModel,
            aiAPIKey: aiAPIKey,
            aiEndpoint: aiEndpoint,
            outputTarget: outputTarget,
            deviceName: deviceName,
            maxDurationSeconds: maxDurationSeconds,
            noGPU: noGPU
        )
    }

    public static func run(arguments: [String]) -> Int32 {
        let options: DictateOptions
        do {
            options = try parseArguments(arguments)
        } catch {
            FileHandle.standardError.write(Data("dictate: \(error)\n".utf8))
            return 1
        }

        let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        let home = ProcessInfo.processInfo.environment["HOME"]
        let fileExists = { FileManager.default.fileExists(atPath: $0) }

        let resolvedModelPath: String
        let modelLabel: String

        switch options.backend {
        case .whisper:
            resolvedModelPath = ModelPathResolver.resolve(
                explicit: options.modelPath,
                fileExists: fileExists,
                xdgDataHome: xdgDataHome,
                home: home
            )
            modelLabel = "Whisper"
        case .cohere:
            resolvedModelPath = ModelPathResolver.resolveCohere(
                explicit: options.modelPath,
                fileExists: fileExists,
                xdgDataHome: xdgDataHome,
                home: home
            )
            modelLabel = "Cohere Transcribe"
        case .parakeet:
            resolvedModelPath = ModelPathResolver.resolveParakeet(
                explicit: options.modelPath,
                fileExists: fileExists,
                xdgDataHome: xdgDataHome,
                home: home
            )
            modelLabel = "Parakeet TDT v3"
        case .nemotron:
            resolvedModelPath = ModelPathResolver.resolveNemotron(
                explicit: options.modelPath,
                fileExists: fileExists,
                xdgDataHome: xdgDataHome,
                home: home
            )
            modelLabel = "Nemotron Speech 3.5"
        }

        print("🎙️ FluidVoice Dictation Active [\(modelLabel)] (output: \(options.outputTarget.rawValue), lang: \(options.language))")
        if let maxSec = options.maxDurationSeconds {
            print("Listening for up to \(maxSec)s (press Ctrl+C to stop early)...")
        } else {
            print("Speak into your microphone (press Ctrl+C to stop)...")
        }

        // Issue 017: stream continuously from ALSA instead of capturing one fixed-duration
        // buffer, segmenting/transcribing/emitting each utterance as it completes rather
        // than only after the whole session ends.
        let stream: AlsaAudioStream
        do {
            stream = try AlsaAudioStream.open(
                sampleRate: 16000,
                channelCount: 1,
                deviceName: options.deviceName
            )
        } catch {
            FileHandle.standardError.write(Data("dictate: audio capture failed: \(error)\n".utf8))
            return 1
        }

        installSIGINTHandler()
        defer {
            restoreDefaultSIGINTHandler()
            stream.stop()
        }

        var utteranceCount = 0
        do {
            try StreamingDictationLoop.run(
                sampleRate: 16000,
                vadConfig: VADConfiguration(minSpeechDurationMs: 200, minSilenceDurationMs: 400, sampleRate: 16000),
                maxDurationSeconds: options.maxDurationSeconds,
                shouldStop: { interruptRequested },
                nextChunk: { try stream.readChunk(framesPerChunk: 1600) },
                onUtterance: { samples in
                    utteranceCount += 1
                    transcribeEnhanceAndEmit(
                        samples: samples,
                        options: options,
                        resolvedModelPath: resolvedModelPath
                    )
                }
            )
        } catch {
            FileHandle.standardError.write(Data("dictate: audio capture failed: \(error)\n".utf8))
            return 1
        }

        if utteranceCount == 0 {
            print("No speech detected.")
        }

        return 0
    }

    /// Transcribes one segmented utterance, runs `--enhance` AI post-processing if
    /// requested, and emits the result via the configured output driver. Errors are
    /// reported to stderr per-utterance rather than aborting the whole streaming session --
    /// one bad chunk (e.g. a transient transcription failure) shouldn't kill dictation.
    private static func transcribeEnhanceAndEmit(
        samples: [Float],
        options: DictateOptions,
        resolvedModelPath: String
    ) {
        var rawText = ""
        do {
            if options.backend == .whisper {
                let whisperBackend: WhisperBackend = options.noGPU ? .cpuOnly : .auto
                let res = try WhisperTranscriber.transcribe(
                    samples: samples,
                    modelPath: resolvedModelPath,
                    backend: whisperBackend,
                    language: options.language
                )
                rawText = res.text
            } else {
                let res = try CohereTranscriber.transcribe(
                    samples: samples,
                    sampleRate: 16000,
                    modelPath: resolvedModelPath,
                    language: options.language
                )
                rawText = res.text
            }
        } catch {
            FileHandle.standardError.write(Data("dictate: transcription failed: \(error)\n".utf8))
            return
        }

        let cleanedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedRaw.isEmpty else {
            return
        }

        var finalText = cleanedRaw
        if options.enhance {
            let aiConfig = AIEnhancementConfiguration(
                provider: options.aiProvider,
                model: options.aiModel,
                baseURL: options.aiEndpoint,
                apiKey: options.aiAPIKey
            )
            do {
                finalText = try AIEnhancementService.enhanceBlocking(text: cleanedRaw, config: aiConfig)
            } catch {
                FileHandle.standardError.write(Data("dictate: AI enhancement warning: \(error)\n".utf8))
            }
        }

        do {
            try TextOutputDriver.emit(finalText, target: options.outputTarget)
        } catch {
            FileHandle.standardError.write(Data("dictate: output failed: \(error)\n".utf8))
            print(finalText)
        }
    }

    /// Set from the SIGINT handler installed in `installSIGINTHandler` (running
    /// synchronously on the same thread it interrupts, since the streaming loop below is
    /// single-threaded) and polled by `StreamingDictationLoop.run`'s `shouldStop` closure --
    /// the same signal-sets-a-static-flag pattern `FileLogger`'s crash handlers use
    /// elsewhere in this codebase.
    fileprivate static var interruptRequested = false

    private static func installSIGINTHandler() {
        interruptRequested = false
        signal(SIGINT) { _ in
            DictateCommand.interruptRequested = true
        }
    }

    private static func restoreDefaultSIGINTHandler() {
        signal(SIGINT, SIG_DFL)
    }
}
