import Foundation

/// Phase 3 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md): builds a
/// canonical 44-byte RIFF/WAVE header for PCM audio. Kept free of any ALSA/file-IO
/// dependency so it is unit-testable against a fixed input buffer without a real
/// capture device (docs/SwiftLinux.md §3 executable/library testability split).
public enum WavFormat {
    /// Builds the 44-byte canonical PCM WAV header for the given format and payload
    /// size. `dataByteCount` is the size of the raw PCM sample bytes that will follow
    /// this header in the file (not including the header itself).
    public static func header(
        sampleRate: UInt32,
        channelCount: UInt16,
        bitsPerSample: UInt16,
        dataByteCount: UInt32
    ) -> [UInt8] {
        let blockAlign = channelCount * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let riffChunkSize = 36 + dataByteCount

        var bytes: [UInt8] = []
        bytes.reserveCapacity(44)

        bytes += Array("RIFF".utf8)
        bytes += littleEndianBytes(riffChunkSize)
        bytes += Array("WAVE".utf8)

        bytes += Array("fmt ".utf8)
        bytes += littleEndianBytes(UInt32(16)) // fmt chunk size (PCM)
        bytes += littleEndianBytes(UInt16(1)) // audio format: 1 = PCM
        bytes += littleEndianBytes(channelCount)
        bytes += littleEndianBytes(sampleRate)
        bytes += littleEndianBytes(byteRate)
        bytes += littleEndianBytes(blockAlign)
        bytes += littleEndianBytes(bitsPerSample)

        bytes += Array("data".utf8)
        bytes += littleEndianBytes(dataByteCount)

        return bytes
    }

    /// Builds a complete WAV file (header + interleaved S16LE sample bytes) for a
    /// buffer of signed 16-bit samples.
    public static func makeFile(
        samples: [Int16],
        sampleRate: UInt32,
        channelCount: UInt16
    ) -> Data {
        let dataByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var bytes = header(
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: 16,
            dataByteCount: dataByteCount
        )
        bytes.reserveCapacity(bytes.count + Int(dataByteCount))
        for sample in samples {
            bytes += littleEndianBytes(UInt16(bitPattern: sample))
        }
        return Data(bytes)
    }

    private static func littleEndianBytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private static func littleEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }
}
