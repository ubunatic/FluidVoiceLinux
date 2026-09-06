#ifndef LINUX_WHISPER_SUPPORT_SHIM_H
#define LINUX_WHISPER_SUPPORT_SHIM_H

/// Linux migration Phase 4 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md and
/// issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md).
///
/// whisper.cpp's own `whisper.h` (from the apt `libwhisper-dev` package,
/// see docs/LINUX_SETUP.md) is already a complete, pure-C API (extern "C",
/// stdbool/stdint only — no C++ features leak into the public header), so
/// unlike Sources/LinuxAudioCaptureSupport (which needed a hand-written
/// shim over ALSA's snd_pcm_* API) this target does not need any custom C
/// glue code — it just re-exports the system header as a Clang module for
/// Swift to import directly as `CWhisper`.
#include <whisper.h>

#endif
