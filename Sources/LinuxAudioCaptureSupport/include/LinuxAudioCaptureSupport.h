#ifndef LINUX_AUDIO_CAPTURE_SUPPORT_H
#define LINUX_AUDIO_CAPTURE_SUPPORT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Linux migration Phase 3 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md and
/// issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md).
/// Thin C shim over ALSA's PCM capture API (`<alsa/asoundlib.h>`), mirroring
/// the structural pattern of Sources/CoreAudioCaptureSupport (opaque
/// reference type, create/read/destroy lifecycle, int32_t error codes) but
/// deliberately simpler: MVP recording is a blocking, synchronous capture
/// loop (no realtime ring buffer / IOProc callback needed for "record N
/// seconds to a WAV file").
///
/// Sample format is fixed to signed 16-bit little-endian, interleaved —
/// the most universally supported ALSA capture format and a natural fit
/// for a canonical PCM WAV file.
typedef void *FVAlsaCaptureRef;

/// Negative return values are ALSA error codes (see fv_alsa_capture_strerror);
/// zero/positive values indicate success or a frame count.
enum {
    FV_ALSA_CAPTURE_OK = 0,
    FV_ALSA_CAPTURE_ERR_INVALID_ARGUMENT = -1000,
    FV_ALSA_CAPTURE_ERR_ALLOCATION = -1001,
};

/// Opens a capture stream on the named ALSA PCM device (e.g. "default",
/// "plughw:CARD=Generic_1,DEV=0"). On success, `outCapture` is populated and
/// `outActualSampleRate`/`outActualChannels` report what the device actually
/// negotiated (ALSA may pick the nearest supported rate/channel count).
/// Returns FV_ALSA_CAPTURE_OK on success or a negative ALSA error code.
int32_t fv_alsa_capture_open(
    const char *deviceName,
    unsigned int requestedSampleRate,
    unsigned int requestedChannels,
    FVAlsaCaptureRef *outCapture,
    unsigned int *outActualSampleRate,
    unsigned int *outActualChannels
);

/// Blocking read of up to `frameCount` interleaved S16LE frames into `buffer`
/// (caller-allocated, at least frameCount * channelCount * sizeof(int16_t)
/// bytes). Returns the number of frames actually read (>= 0) or a negative
/// ALSA error code.
int32_t fv_alsa_capture_read(
    FVAlsaCaptureRef capture,
    int16_t *buffer,
    uint32_t frameCount
);

/// Closes the PCM device and releases the capture handle. Safe to call with
/// NULL.
void fv_alsa_capture_close(FVAlsaCaptureRef capture);

/// Returns a human-readable ALSA error string for a negative error code
/// returned by the functions above (via snd_strerror).
const char *fv_alsa_capture_strerror(int32_t errorCode);

#ifdef __cplusplus
}
#endif

#endif
