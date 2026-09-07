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

/// Issue 017 (see issues/017-continuous-streaming-dictation-loop-in-dictate-subcommand-without-premature-cutoff.md):
/// a continuous ALSA capture session for the `dictate` subcommand's streaming loop, as an
/// alternative to `AlsaAudioRecorder.record(seconds:)`'s fixed-duration one-shot capture.
///
/// Deliberately single-threaded/pull-based (`readChunk` is a blocking call driven by the
/// caller's own loop, e.g. `StreamingDictationLoop.run`) rather than a push callback running
/// on a background thread: the underlying `fv_alsa_capture_read`/`fv_alsa_capture_close` C
/// calls are not documented as safe to invoke concurrently from different threads, so keeping
/// all ALSA calls on one thread avoids a close-while-reading race entirely rather than
/// guarding against it with locks.
public final class AlsaAudioStream {
    public let sampleRate: UInt32
    public let channelCount: UInt16

    /// `nil` once `stop()` has closed the ALSA handle.
    private var capture: FVAlsaCaptureRef?

    private init(capture: FVAlsaCaptureRef, sampleRate: UInt32, channelCount: UInt16) {
        self.capture = capture
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// Opens the named ALSA capture device for continuous streaming reads. Mirrors
    /// `AlsaAudioRecorder.record`'s open/negotiate logic but keeps the handle open for
    /// repeated `readChunk` calls instead of reading a fixed duration up front.
    public static func open(
        sampleRate: UInt32 = 16000,
        channelCount: UInt16 = 1,
        deviceName: String = AlsaAudioRecorder.defaultDeviceName
    ) throws -> AlsaAudioStream {
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

        return AlsaAudioStream(
            capture: capture,
            sampleRate: actualSampleRate,
            channelCount: UInt16(actualChannels)
        )
    }

    /// Blocking read of up to `framesPerChunk` interleaved frames. Returns an empty array on
    /// a transient zero-frame read (e.g. a signal-interrupted `read` recovered by the C
    /// shim) so the caller's loop can simply re-check its own stop condition and try again.
    /// Returns `nil` once `stop()` has been called -- including if `stop()` runs from a
    /// SIGINT handler while this call is blocked in the underlying ALSA read, in which case
    /// the in-flight read is allowed to finish (or gets interrupted and recovers to zero
    /// frames) before this returns `nil` on the next call.
    public func readChunk(framesPerChunk: UInt32 = 1600) throws -> [Int16]? {
        guard let capture else { return nil }

        var buffer = [Int16](repeating: 0, count: Int(framesPerChunk) * Int(channelCount))
        let framesRead: Int32 = buffer.withUnsafeMutableBufferPointer { pointer in
            fv_alsa_capture_read(capture, pointer.baseAddress, framesPerChunk)
        }

        // stop() may have run while the read above was blocked; treat that as end-of-stream
        // rather than surfacing a spurious read result.
        guard self.capture != nil else { return nil }

        if framesRead < 0 {
            let reason = String(cString: fv_alsa_capture_strerror(framesRead))
            throw AudioRecorderError("ALSA read failed: \(reason) (code \(framesRead))")
        }
        if framesRead == 0 {
            return []
        }
        let sampleCount = Int(framesRead) * Int(channelCount)
        return Array(buffer[0..<sampleCount])
    }

    /// Stops the stream and releases the ALSA capture handle. Idempotent, and only ever
    /// touches the handle from whichever thread calls it first -- callers should call this
    /// from the same thread driving `readChunk` (e.g. a loop's cleanup/defer) rather than
    /// concurrently with an in-flight read.
    public func stop() {
        guard let capture else { return }
        self.capture = nil
        fv_alsa_capture_close(capture)
    }

    deinit {
        stop()
    }
}
