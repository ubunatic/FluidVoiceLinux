import Foundation

/// Phase 4 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md): a minimal
/// RIFF/WAVE reader for the `transcribe` subcommand. whisper.cpp's `whisper_full()`
/// wants mono, 16 kHz, `Float32` PCM in [-1, 1] — this reader parses the `fmt `/`data`
/// chunks of a canonical PCM WAV file (as produced by `WavFormat.makeFile` in Phase 3,
/// or any standard 16-bit PCM WAV) and converts to that shape. Kept dependency-free
/// (no AVFoundation on Linux) and independent of any real file I/O in its parsing
/// logic, so `WavReader.decode(data:)` is unit-testable against an in-memory buffer.
public enum WavReaderError: Error, CustomStringConvertible {
    case notARiffFile
    case notAWaveFile
    case missingFormatChunk
    case missingDataChunk
    case unsupportedFormat(audioFormat: UInt16, bitsPerSample: UInt16)
    case unsupportedSampleRate(UInt32)
    case truncatedData

    public var description: String {
        switch self {
        case .notARiffFile:
            return "not a RIFF file"
        case .notAWaveFile:
            return "not a WAVE file"
        case .missingFormatChunk:
            return "missing 'fmt ' chunk"
        case .missingDataChunk:
            return "missing 'data' chunk"
        case .unsupportedFormat(let audioFormat, let bitsPerSample):
            return "unsupported WAV format (audioFormat=\(audioFormat), bitsPerSample=\(bitsPerSample)); only 16-bit PCM is supported"
        case .unsupportedSampleRate(let rate):
            return "unsupported sample rate \(rate) Hz; whisper.cpp requires 16000 Hz mono audio — resample the input first"
        case .truncatedData:
            return "truncated or malformed WAV data"
        }
    }
}

public struct DecodedWav {
    public let sampleRate: UInt32
    public let channelCount: UInt16
    /// Mono Float32 PCM samples in [-1, 1], downmixed from `channelCount` channels if
    /// necessary (simple average across channels — adequate for the mono/near-mono
    /// dictation inputs this CLI targets; not a proper resampler).
    public let monoSamples: [Float]
}

public enum WavReader {
    /// Parses a canonical PCM WAV file's bytes and returns mono Float32 samples ready
    /// for `whisper_full()`. Requires 16-bit PCM at 16000 Hz (whisper.cpp's fixed
    /// input rate) — multi-channel input is downmixed to mono, but sample-rate
    /// conversion is out of scope for this MVP.
    public static func decode(_ data: Data) throws -> DecodedWav {
        var offset = 0
        func readBytes(_ count: Int) throws -> Data {
            guard offset + count <= data.count else { throw WavReaderError.truncatedData }
            defer { offset += count }
            return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + count))
        }
        func readU32() throws -> UInt32 {
            let bytes = try readBytes(4)
            return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        }
        func readU16() throws -> UInt16 {
            let bytes = try readBytes(2)
            return bytes.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        }
        func readTag() throws -> String {
            let bytes = try readBytes(4)
            return String(decoding: bytes, as: UTF8.self)
        }

        guard try readTag() == "RIFF" else { throw WavReaderError.notARiffFile }
        _ = try readU32() // RIFF chunk size, unused
        guard try readTag() == "WAVE" else { throw WavReaderError.notAWaveFile }

        var sampleRate: UInt32?
        var channelCount: UInt16?
        var bitsPerSample: UInt16?
        var audioFormat: UInt16?
        var pcmData: Data?

        while offset + 8 <= data.count {
            let chunkID = try readTag()
            let chunkSize = try Int(readU32())
            let chunkStart = offset
            switch chunkID {
            case "fmt ":
                audioFormat = try readU16()
                channelCount = try readU16()
                sampleRate = try readU32()
                _ = try readU32() // byte rate
                _ = try readU16() // block align
                bitsPerSample = try readU16()
                // Skip any extra format bytes (e.g. WAVE_FORMAT_EXTENSIBLE).
                let consumed = offset - chunkStart
                if chunkSize > consumed {
                    offset += (chunkSize - consumed)
                }
            case "data":
                pcmData = try readBytes(chunkSize)
            default:
                offset += chunkSize
            }
            // Chunks are word-aligned; skip the pad byte if chunkSize is odd.
            if chunkSize % 2 == 1, offset < data.count {
                offset += 1
            }
        }

        guard let format = audioFormat, let channels = channelCount, let bits = bitsPerSample,
              let rate = sampleRate
        else {
            throw WavReaderError.missingFormatChunk
        }
        guard let rawData = pcmData else { throw WavReaderError.missingDataChunk }
        guard format == 1, bits == 16 else {
            throw WavReaderError.unsupportedFormat(audioFormat: format, bitsPerSample: bits)
        }
        guard rate == 16000 else {
            throw WavReaderError.unsupportedSampleRate(rate)
        }

        let sampleCount = rawData.count / 2
        var interleaved = [Int16](repeating: 0, count: sampleCount)
        rawData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<sampleCount {
                interleaved[index] = Int16(littleEndian: int16Buffer[index])
            }
        }

        let channelCountInt = Int(channels)
        let frameCount = channelCountInt > 0 ? interleaved.count / channelCountInt : 0
        var mono = [Float](repeating: 0, count: frameCount)
        if channelCountInt <= 1 {
            for frame in 0..<frameCount {
                mono[frame] = Float(interleaved[frame]) / 32768.0
            }
        } else {
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCountInt {
                    sum += Float(interleaved[frame * channelCountInt + channel]) / 32768.0
                }
                mono[frame] = sum / Float(channelCountInt)
            }
        }

        return DecodedWav(sampleRate: rate, channelCount: channels, monoSamples: mono)
    }
}
