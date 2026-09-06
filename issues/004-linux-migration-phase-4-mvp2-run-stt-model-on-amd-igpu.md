# 004 — Linux migration Phase 4: MVP2 run STT model on AMD iGPU

**Status**: Closed — resolved in 9f50d18
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Feature

---

## 1. Problem & Motivation

Phase 4 of `docs/LINUX_MIGRATION_BRANCH_PLAN.md`. Depends on issue 003
(need a recorded WAV to transcribe). Goal: "I can also run the model on
the AMD iGPU" — GPU-accelerated speech-to-text on Linux without
requiring a full ROCm install if avoidable.

## 2. Technical Specification / Findings

- `transcribe-cpp-swift` (whisper.cpp Swift wrapper, pinned `0.1.2`) is
  already a dependency for the macOS app — **investigate first**
  whether it's usable at all on Linux (does it resolve/compile outside
  `#if os(macOS)`?) and whether the pinned version has a Vulkan or
  ROCm backend compiled in. whisper.cpp upstream has Vulkan support,
  which is the most portable path for AMD iGPU acceleration without a
  full ROCm stack — confirm this is actually wired up in the pinned
  dependency version before committing to the approach; don't assume.
- `FluidAudio` (CoreML-based VAD/diarization) is very likely
  unportable to Linux (CoreML is Apple-only) — plan to skip
  diarization/VAD for this MVP rather than trying to port it.
- CPU fallback is required: if Vulkan/ROCm isn't available at runtime,
  transcription must still work (slower) rather than fail.

## 3. Implementation & Verification Plan

- Canary-first (per `docs/Canary.md`): before wiring a full
  `transcribe` subcommand, write the smallest possible probe that
  loads a whisper model and runs one inference via
  `transcribe-cpp-swift` on Linux, and confirms in logs whether it
  actually executed on GPU or fell back to CPU.
- CLI subcommand: `fluidvoice-linux transcribe --in out.wav`, logic in
  `FluidVoiceLinuxCLICore` per the executable/library split described
  in `docs/SwiftLinux.md` §3.
- Verify for real: transcribe the Phase 3 WAV, confirm correct text
  output, and confirm (via logs or a GPU utilization check, e.g.
  `radeontop`/`rocm-smi` if applicable) that the AMD iGPU path was
  actually exercised, not silently running on CPU.
- Update `docs/SwiftLinux.md`/`docs/LINUX_SETUP.md` with whatever
  Vulkan/ROCm runtime packages turn out to be required
  (`mesa-vulkan-drivers`, `vulkan-tools`, etc. — verify exact names).

## 4. Resolution

**The original findings section's assumption was superseded**: rather than
investigating `transcribe-cpp-swift` (the existing macOS-only whisper.cpp
Swift wrapper), host-side hardware/package discovery found a much more
direct path — Ubuntu's `universe` repo ships whisper.cpp itself as apt
packages (`whisper.cpp` 1.8.3+dfsg-2 CLI tools, `libwhisper-dev`/
`libwhisper1` C API) with ggml's Vulkan compute backend
(`libggml0-backend-vulkan`) already installed on this box. `transcribe-cpp-swift`
was not investigated beyond confirming it's declared macOS-only — not
needed once the apt path proved viable. Full reasoning and verification
evidence: `docs/LINUX_SETUP.md` "STT backend: apt `libwhisper-dev` + ggml
Vulkan" section.

**Canary-first verification (before writing any Swift code)**: downloaded
`libwhisper-dev`/`libwhisper1`/`libggml-dev` with `apt-get download` (no
root available in this session — same no-sudo constraint as issue 001/003)
and extracted with `dpkg-deb -x`. Ran the extracted `whisper-cli` binary
directly against `~/.config/fluidvoice/dev/samples/test.wav`
(`ggml-base.en.bin`, downloaded from
`https://huggingface.co/ggerganov/whisper.cpp`). Its own startup log
confirmed real GPU backend usage with zero source rebuilding required:
```
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = AMD Radeon 780M Graphics (RADV PHOENIX) (radv) | uma: 1 | fp16: 1 ...
load_backend: loaded Vulkan backend from /usr/lib/x86_64-linux-gnu/ggml/backends0/libggml-vulkan.so
whisper_backend_init_gpu: using Vulkan0 backend
```
Transcription output: `A, B, C, D, E, F, G, H, I, J, K, L, M, N.` — matches
the ground truth ("a b c d e f g h i j k l m n") from `test.jsonl`.

**Swift integration built**:
- `Sources/LinuxWhisperSupport/` — new `.systemLibrary` target (`CWhisper`),
  gated into `Package.swift`'s Linux `#else` branch. `whisper.h` is already
  a pure C API (`extern "C"`, no C++ leakage), so unlike
  `Sources/LinuxAudioCaptureSupport`'s hand-written ALSA shim, this needed
  only a `module.modulemap` (`link "whisper"`, `link "ggml"`, `link
  "ggml-base"`, `pkgConfig: "whisper"`) and a one-line `shim.h` including
  `<whisper.h>`. See `docs/SwiftLinux.md` §7 for when to use this pattern
  vs. a hand-written shim.
- `Sources/FluidVoiceLinuxCLICore/WhisperTranscriber.swift` — calls the C
  API directly (`whisper_init_from_file_with_params`, `whisper_full`,
  segment extraction). Discovered and fixed a real gotcha here: the
  whisper.cpp/ggml *library* API does not automatically load the
  dynamically-linked Vulkan/CPU backend plugins the way `whisper-cli`'s own
  startup code does — skipping `ggml_backend_load_all()` before context
  init is silent (`devices = 0` / `backends = 0` logged) and then crashes
  (`ggml-backend.cpp:508: GGML_ASSERT(device) failed`) rather than cleanly
  falling back to CPU. Fixed by calling `ggml_backend_load_all()` first.
- `Sources/FluidVoiceLinuxCLICore/WavReader.swift` — minimal RIFF/WAVE
  parser (16-bit PCM, 16 kHz required, multi-channel downmixed to mono)
  converting to the `Float32` PCM whisper.cpp's API expects; dependency-free
  and unit-testable against in-memory buffers built with the existing
  `WavFormat.makeFile` helper from issue 003.
- `Sources/FluidVoiceLinuxCLICore/TranscribeCommand.swift` — `transcribe
  --in <path>.wav [--model <path>] [--no-gpu]` subcommand, same
  parse/run split as `RecordCommand` (docs/SwiftLinux.md §3). `--model`
  defaults to `models/ggml-base.en.bin` (matching `whisper-cli`'s own
  default). `--no-gpu` forces `whisper_context_params.use_gpu = false`.
- `Sources/FluidVoiceLinuxCLI/main.swift` — dispatcher gained the
  `transcribe` case alongside `record`.

**Tests** (`Tests/FluidVoiceLinuxCLITests/`, no model/GPU needed):
- `TranscribeCommandArgumentTests.swift` — required/optional flag parsing,
  missing `--in`, unknown flag, dangling flag with no value.
- `WavReaderTests.swift` — mono round-trip decode, stereo downmix,
  unsupported-sample-rate rejection, non-RIFF-data rejection.
- `swift test`: all 21 tests pass (12 from issues 002/003 + 5 transcribe
  argument tests + 4 WavReader tests).

**Real end-to-end verification** (this box, `ggml-base.en.bin`,
`.build/release/FluidVoiceLinuxCLI transcribe`):

| Run | Command | Output | Inference time | User CPU time |
|---|---|---|---|---|
| GPU (default) | `transcribe --in test.wav --model .../ggml-base.en.bin` | `A, B, C, D, E, F, G, H, I, J, K, L, M, N.` | 0.231s | 0.162s |
| Forced CPU | `transcribe --in test.wav ... --no-gpu` | `A, B, C, D, E, F, G, H, I, J, K, L, M, N.` | 3.231s | 47.570s |
| Forced GPU-init failure (`VK_ICD_FILENAMES=/nonexistent/no_such_icd.json`) | `transcribe --in test.wav ...` | `A, B, C, D, E, F, G, H, I, J, K, L, M, N.` | 1.163s | CPU backend loaded, no crash |
| GPU (default), second sample | `transcribe --in chunks.wav ...` | `This is a recording of one chunk and another chunk.` | 0.165s | 0.140s |

Both sample WAVs transcribed correctly (matching `test.jsonl`/`chunks.jsonl`
ground truth, modulo capitalization/punctuation whisper naturally adds).
The GPU run's log confirmed `whisper_backend_init_gpu: using Vulkan0
backend` in all "default" runs. The ~14x gap in **user CPU time** (0.16s
GPU vs. 47.6s forced-CPU, not just wall-clock) is strong evidence the
Vulkan path is actually offloading compute to the iGPU, not silently
running on CPU with the GPU log line printed for show. The forced-ICD-failure
run proves the CPU fallback is real (library-level automatic fallback on
GPU init failure, not just the explicit `--no-gpu` flag) — confirmed by
forcing an actual failure rather than only asserting the fallback code path
exists.

**Known limitation carried into Phase 5+, out of scope here**: issue 006's
click/pop transient (t≈1.1-1.2s in both sample WAVs) was explicitly
out-of-scope per this ticket's brief and did not need any workaround —
whisper.cpp transcribed cleanly around it in every run above.

**No-root verification note** (same constraint as issues 001/003): no
interactive `sudo` was available in this session, so `libwhisper-dev`/
`libwhisper1`/`libggml-dev` were downloaded with `apt-get download` and
extracted with `dpkg-deb -x` into a scratch prefix for building/testing
(`CPATH`/`PKG_CONFIG_PATH`/`-Xlinker -L<scratch>` pointed at the extracted
files); `libggml0`/`libggml0-backend-vulkan` were already installed
system-wide on this box. `Package.swift`'s `CWhisper` target declares the
normal `pkgConfig`/`apt` provider a real `make apt-deps` install resolves
against system paths — the scratch workaround was dev-session-only. A
human running `make apt-deps` gets the same packages at their real,
normal install paths.

This is a genuine, GPU-accelerated, end-to-end working `transcribe`
subcommand with a verified automatic CPU fallback — closing this ticket.
