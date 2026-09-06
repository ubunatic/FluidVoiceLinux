import Foundation

/// Phase 3 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md): the
/// `record --seconds N --out path.wav` CLI subcommand. No argument-parsing
/// dependency is pulled in (docs/LINUX_MIGRATION_BRANCH_PLAN.md Phase 3 explicitly
/// keeps this hand-rolled) — parsing is split out from execution so
/// `parseRecordArguments` is unit-testable without touching a real ALSA device.
public struct RecordOptions: Equatable {
    public let seconds: Double
    public let outputPath: String
    public let deviceName: String
    public let sampleRate: UInt32
    public let channelCount: UInt16

    public init(
        seconds: Double,
        outputPath: String,
        deviceName: String = AlsaAudioRecorder.defaultDeviceName,
        sampleRate: UInt32 = 16000,
        channelCount: UInt16 = 1
    ) {
        self.seconds = seconds
        self.outputPath = outputPath
        self.deviceName = deviceName
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

public enum RecordArgumentError: Error, CustomStringConvertible {
    case missingValue(flag: String)
    case invalidValue(flag: String, value: String)
    case missingRequired(flag: String)
    case unknownArgument(String)

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .invalidValue(let flag, let value):
            return "invalid value '\(value)' for \(flag)"
        case .missingRequired(let flag):
            return "missing required argument \(flag)"
        case .unknownArgument(let argument):
            return "unknown argument '\(argument)'"
        }
    }
}

public enum RecordCommand {
    /// Parses `record` subcommand arguments (everything after the "record" token
    /// itself). Supported flags: `--seconds N` (required, > 0), `--out path`
    /// (required), `--device name` (optional, defaults to "default"),
    /// `--sample-rate N` (optional, defaults to 16000), `--channels N` (optional,
    /// defaults to 1).
    public static func parseArguments(_ arguments: [String]) throws -> RecordOptions {
        var seconds: Double?
        var outputPath: String?
        var deviceName = AlsaAudioRecorder.defaultDeviceName
        var sampleRate: UInt32 = 16000
        var channelCount: UInt16 = 1

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() throws -> String {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw RecordArgumentError.missingValue(flag: argument)
                }
                index = valueIndex
                return arguments[valueIndex]
            }

            switch argument {
            case "--seconds":
                let value = try nextValue()
                guard let parsed = Double(value), parsed > 0 else {
                    throw RecordArgumentError.invalidValue(flag: argument, value: value)
                }
                seconds = parsed
            case "--out":
                outputPath = try nextValue()
            case "--device":
                deviceName = try nextValue()
            case "--sample-rate":
                let value = try nextValue()
                guard let parsed = UInt32(value), parsed > 0 else {
                    throw RecordArgumentError.invalidValue(flag: argument, value: value)
                }
                sampleRate = parsed
            case "--channels":
                let value = try nextValue()
                guard let parsed = UInt16(value), parsed > 0 else {
                    throw RecordArgumentError.invalidValue(flag: argument, value: value)
                }
                channelCount = parsed
            default:
                throw RecordArgumentError.unknownArgument(argument)
            }
            index += 1
        }

        guard let resolvedSeconds = seconds else {
            throw RecordArgumentError.missingRequired(flag: "--seconds")
        }
        guard let resolvedOutputPath = outputPath else {
            throw RecordArgumentError.missingRequired(flag: "--out")
        }

        return RecordOptions(
            seconds: resolvedSeconds,
            outputPath: resolvedOutputPath,
            deviceName: deviceName,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    /// Runs the full `record` subcommand: parses arguments, captures audio from
    /// ALSA, and writes a WAV file. Returns a process exit code (0 success).
    /// Real ALSA I/O only happens here, not in `parseArguments`, so argument
    /// handling stays unit-testable without a capture device.
    public static func run(arguments: [String]) -> Int32 {
        let options: RecordOptions
        do {
            options = try parseArguments(arguments)
        } catch {
            FileHandle.standardError.write(Data("record: \(error)\n".utf8))
            return 1
        }

        print(
            "Recording \(options.seconds)s from '\(options.deviceName)' "
                + "(\(options.sampleRate) Hz, \(options.channelCount) ch) -> \(options.outputPath)"
        )

        let result: AudioRecordingResult
        do {
            result = try AlsaAudioRecorder.record(
                seconds: options.seconds,
                sampleRate: options.sampleRate,
                channelCount: options.channelCount,
                deviceName: options.deviceName
            )
        } catch {
            FileHandle.standardError.write(Data("record: \(error)\n".utf8))
            return 1
        }

        let wavData = WavFormat.makeFile(
            samples: result.samples,
            sampleRate: result.sampleRate,
            channelCount: result.channelCount
        )

        do {
            try wavData.write(to: URL(fileURLWithPath: options.outputPath))
        } catch {
            FileHandle.standardError.write(
                Data("record: failed to write '\(options.outputPath)': \(error)\n".utf8)
            )
            return 1
        }

        print(
            "Wrote \(wavData.count) bytes (\(result.samples.count) samples @ "
                + "\(result.sampleRate) Hz, \(result.channelCount) ch) to \(options.outputPath)"
        )
        return 0
    }
}
