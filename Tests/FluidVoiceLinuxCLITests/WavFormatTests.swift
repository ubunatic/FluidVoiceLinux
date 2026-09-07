import Foundation
import XCTest
@testable import FluidVoiceLinuxCLICore

// Phase 3 (see issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md):
// exercises the RIFF/WAVE header-building logic against a fixed input buffer — no
// ALSA device needed, per docs/SwiftLinux.md §3's testability split.
final class WavFormatTests: XCTestCase {
    override func invokeTest() {
        runWithTimeout { super.invokeTest() }
    }

    func testHeaderFieldsForMonoSixteenBit() {
        let header = WavFormat.header(
            sampleRate: 16000,
            channelCount: 1,
            bitsPerSample: 16,
            dataByteCount: 200
        )

        XCTAssertEqual(header.count, 44)
        XCTAssertEqual(Array(header[0..<4]), Array("RIFF".utf8))
        XCTAssertEqual(Array(header[8..<12]), Array("WAVE".utf8))
        XCTAssertEqual(Array(header[12..<16]), Array("fmt ".utf8))
        XCTAssertEqual(Array(header[36..<40]), Array("data".utf8))

        // RIFF chunk size = 36 + dataByteCount.
        XCTAssertEqual(littleEndianUInt32(header, at: 4), 236)
        // fmt chunk size (PCM) is always 16.
        XCTAssertEqual(littleEndianUInt32(header, at: 16), 16)
        // audio format 1 == PCM.
        XCTAssertEqual(littleEndianUInt16(header, at: 20), 1)
        XCTAssertEqual(littleEndianUInt16(header, at: 22), 1) // channels
        XCTAssertEqual(littleEndianUInt32(header, at: 24), 16000) // sample rate
        // byte rate = sampleRate * blockAlign = 16000 * 2 = 32000.
        XCTAssertEqual(littleEndianUInt32(header, at: 28), 32000)
        // block align = channels * bitsPerSample/8 = 1 * 2 = 2.
        XCTAssertEqual(littleEndianUInt16(header, at: 32), 2)
        XCTAssertEqual(littleEndianUInt16(header, at: 34), 16) // bits per sample
        XCTAssertEqual(littleEndianUInt32(header, at: 40), 200) // data chunk size
    }

    func testHeaderFieldsForStereo() {
        let header = WavFormat.header(
            sampleRate: 44100,
            channelCount: 2,
            bitsPerSample: 16,
            dataByteCount: 1000
        )

        XCTAssertEqual(littleEndianUInt16(header, at: 22), 2) // channels
        XCTAssertEqual(littleEndianUInt32(header, at: 24), 44100) // sample rate
        // block align = 2 * 2 = 4; byte rate = 44100 * 4 = 176400.
        XCTAssertEqual(littleEndianUInt16(header, at: 32), 4)
        XCTAssertEqual(littleEndianUInt32(header, at: 28), 176_400)
    }

    func testMakeFileProducesHeaderPlusRawSampleBytes() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768]
        let data = WavFormat.makeFile(samples: samples, sampleRate: 8000, channelCount: 1)

        let expectedDataBytes = samples.count * MemoryLayout<Int16>.size
        XCTAssertEqual(data.count, 44 + expectedDataBytes)

        let bytes = [UInt8](data)
        XCTAssertEqual(littleEndianUInt32(bytes, at: 40), UInt32(expectedDataBytes))

        // First sample (0) should be two zero bytes right after the 44-byte header.
        XCTAssertEqual(bytes[44], 0)
        XCTAssertEqual(bytes[45], 0)
        // Second sample (1) little-endian.
        XCTAssertEqual(bytes[46], 1)
        XCTAssertEqual(bytes[47], 0)
        // -1 as UInt16 bit pattern is 0xFFFF.
        XCTAssertEqual(bytes[48], 0xFF)
        XCTAssertEqual(bytes[49], 0xFF)
    }

    private func littleEndianUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
