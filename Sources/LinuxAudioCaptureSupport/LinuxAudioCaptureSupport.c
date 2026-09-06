#include "include/LinuxAudioCaptureSupport.h"

#include <alsa/asoundlib.h>
#include <stdlib.h>

typedef struct {
    snd_pcm_t *pcm;
    unsigned int channels;
} FVAlsaCapture;

int32_t fv_alsa_capture_open(
    const char *deviceName,
    unsigned int requestedSampleRate,
    unsigned int requestedChannels,
    FVAlsaCaptureRef *outCapture,
    unsigned int *outActualSampleRate,
    unsigned int *outActualChannels
) {
    if (deviceName == NULL || outCapture == NULL || requestedChannels == 0) {
        return FV_ALSA_CAPTURE_ERR_INVALID_ARGUMENT;
    }
    *outCapture = NULL;

    snd_pcm_t *pcm = NULL;
    int status = snd_pcm_open(&pcm, deviceName, SND_PCM_STREAM_CAPTURE, 0);
    if (status < 0) {
        return (int32_t) status;
    }

    unsigned int sampleRate = requestedSampleRate;
    unsigned int channels = requestedChannels;
    status = snd_pcm_set_params(
        pcm,
        SND_PCM_FORMAT_S16_LE,
        SND_PCM_ACCESS_RW_INTERLEAVED,
        channels,
        sampleRate,
        1, /* allow resampling */
        500000 /* 0.5s latency */
    );
    if (status < 0) {
        snd_pcm_close(pcm);
        return (int32_t) status;
    }

    snd_pcm_hw_params_t *hwParams = NULL;
    snd_pcm_hw_params_alloca(&hwParams);
    status = snd_pcm_hw_params_current(pcm, hwParams);
    if (status < 0) {
        snd_pcm_close(pcm);
        return (int32_t) status;
    }
    unsigned int negotiatedRate = sampleRate;
    snd_pcm_hw_params_get_rate(hwParams, &negotiatedRate, 0);
    unsigned int negotiatedChannels = channels;
    snd_pcm_hw_params_get_channels(hwParams, &negotiatedChannels);

    FVAlsaCapture *capture = (FVAlsaCapture *) calloc(1, sizeof(FVAlsaCapture));
    if (capture == NULL) {
        snd_pcm_close(pcm);
        return FV_ALSA_CAPTURE_ERR_ALLOCATION;
    }
    capture->pcm = pcm;
    capture->channels = negotiatedChannels;

    if (outActualSampleRate != NULL) {
        *outActualSampleRate = negotiatedRate;
    }
    if (outActualChannels != NULL) {
        *outActualChannels = negotiatedChannels;
    }

    *outCapture = (FVAlsaCaptureRef) capture;
    return FV_ALSA_CAPTURE_OK;
}

int32_t fv_alsa_capture_read(
    FVAlsaCaptureRef captureRef,
    int16_t *buffer,
    uint32_t frameCount
) {
    FVAlsaCapture *capture = (FVAlsaCapture *) captureRef;
    if (capture == NULL || buffer == NULL) {
        return FV_ALSA_CAPTURE_ERR_INVALID_ARGUMENT;
    }
    if (frameCount == 0) {
        return 0;
    }

    snd_pcm_sframes_t framesRead = snd_pcm_readi(capture->pcm, buffer, frameCount);
    if (framesRead < 0) {
        // Try to recover once from a common transient error (buffer overrun /
        // suspended device) rather than surfacing a spurious failure for the
        // MVP record loop.
        int recovered = snd_pcm_recover(capture->pcm, (int) framesRead, 1);
        if (recovered < 0) {
            return (int32_t) recovered;
        }
        return 0;
    }
    return (int32_t) framesRead;
}

void fv_alsa_capture_close(FVAlsaCaptureRef captureRef) {
    FVAlsaCapture *capture = (FVAlsaCapture *) captureRef;
    if (capture == NULL) {
        return;
    }
    if (capture->pcm != NULL) {
        snd_pcm_drain(capture->pcm);
        snd_pcm_close(capture->pcm);
    }
    free(capture);
}

const char *fv_alsa_capture_strerror(int32_t errorCode) {
    if (errorCode == FV_ALSA_CAPTURE_ERR_INVALID_ARGUMENT) {
        return "invalid argument";
    }
    if (errorCode == FV_ALSA_CAPTURE_ERR_ALLOCATION) {
        return "allocation failure";
    }
    return snd_strerror((int) errorCode);
}
