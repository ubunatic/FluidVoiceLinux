import Foundation
import LinuxAudioCaptureSupport

/// Phase 3 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md,
/// issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md): drives the
/// LinuxAudioCaptureSupport C shim to record a fixed duration of audio into memory as
/// signed 16-bit interleaved samples. Kept separate from WavWriter (pure formatting,
/// no ALSA dependency) and from the CLI argument parsing in RecordCommand, per the
/// executable/library split in docs/SwiftLinux.md §3.
public struct AudioRecordingResult {
    public let samples: [Int16]
    public let sampleRate: UInt32
    public let channelCount: UInt16
}

public struct AudioRecorderError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
    public var description: String { message }
}

public enum AlsaAudioRecorder {
    /// Default capture device name. ALSA's "default" PCM resolves through
    /// whatever the system's default audio backend is (PipeWire/PulseAudio's ALSA
    /// plugin, or a raw hardware device on a minimal system) — the same name
    /// `arecord`/`aplay` use without extra flags.
    public static let defaultDeviceName = "default"

    private static let framesPerChunk: UInt32 = 4096

    /// Opens the named ALSA capture device and records `seconds` of audio,
    /// returning the captured samples and the sample rate/channel count the
    /// device actually negotiated (which can differ from the request).
    ///
    /// Throws `AudioRecorderError` if the device cannot be opened or a
    /// non-recoverable read error occurs.
    public static func record(
        seconds: Double,
        sampleRate: UInt32 = 16000,
        channelCount: UInt16 = 1,
        deviceName: String = defaultDeviceName
    ) throws -> AudioRecordingResult {
        guard seconds > 0 else {
            throw AudioRecorderError("seconds must be greater than 0 (got \(seconds))")
        }
        guard channelCount > 0 else {
            throw AudioRecorderError("channelCount must be greater than 0 (got \(channelCount))")
        }

        var captureRef: FVAlsaCaptureRef?
        var actualSampleRate: UInt32 = 0
        var actualChannels: UInt32 = 0
        let openStatus = deviceName.withCString { cDeviceName in
            fv_alsa_capture_open(
                cDeviceName,
                sampleRate,
                UInt32(channelCount),
                &captureRef,
                &actualSampleRate,
                &actualChannels
            )
        }
        guard openStatus == FV_ALSA_CAPTURE_OK, let capture = captureRef else {
            let reason = String(cString: fv_alsa_capture_strerror(openStatus))
            throw AudioRecorderError(
                "failed to open ALSA capture device '\(deviceName)': \(reason) (code \(openStatus))"
            )
        }
        defer { fv_alsa_capture_close(capture) }

        let negotiatedChannels = UInt16(actualChannels)
        let totalFrames = UInt32((seconds * Double(actualSampleRate)).rounded(.up))
        var samples: [Int16] = []
        samples.reserveCapacity(Int(totalFrames) * Int(negotiatedChannels))

        var chunk = [Int16](repeating: 0, count: Int(framesPerChunk) * Int(negotiatedChannels))
        var framesCaptured: UInt32 = 0
        while framesCaptured < totalFrames {
            let framesRemaining = totalFrames - framesCaptured
            let framesToRead = min(framesPerChunk, framesRemaining)
            let framesRead: Int32 = chunk.withUnsafeMutableBufferPointer { buffer in
                fv_alsa_capture_read(capture, buffer.baseAddress, framesToRead)
            }
            if framesRead < 0 {
                let reason = String(cString: fv_alsa_capture_strerror(framesRead))
                throw AudioRecorderError("ALSA read failed: \(reason) (code \(framesRead))")
            }
            if framesRead == 0 {
                continue
            }
            let sampleCount = Int(framesRead) * Int(negotiatedChannels)
            samples.append(contentsOf: chunk[0..<sampleCount])
            framesCaptured += UInt32(framesRead)
        }

        return AudioRecordingResult(
            samples: samples,
            sampleRate: actualSampleRate,
            channelCount: negotiatedChannels
        )
    }
}
