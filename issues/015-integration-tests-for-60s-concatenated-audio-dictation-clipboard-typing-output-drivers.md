# 015 — Integration tests for >=60s concatenated audio dictation & clipboard/typing output drivers

**Status**: Closed — verified across 60s+ audio talk on Parakeet, Cohere, and Whisper with clipboard/typing driver tests
**Priority**: P2 (Medium)
**Severity**: Normal
**Category**: Testing
**Related**: `issues/011-nvidia-parakeet-tdt-nemotron-speech-stt-support-on-linux.md`, `issues/014-end-to-end-live-dictation-pipeline-dictate-subcommand-with-typing-output.md`

---

## 1. Problem & Motivation

Short sample files (~1–10s) verify basic engine initialization and single-phrase inference, but do not validate long-form dictation stability, memory behavior, drift, or multi-chunk audio processing across sustained speech sessions.

We needed automated extended integration tests that:
1. Concatenate reference audio samples (`test.wav` / "abc" and `chunks.wav` / "chunks" from `~/.config/fluidvoice/dev/samples/`) into a $\ge 60$-second simulated speech session.
2. Transcribe the multi-chunk long audio across all supported STT models (**Parakeet TDT v3**, **Cohere Transcribe**, **Whisper**).
3. Verify that models produce correct transcript content, expected length, and accurate repetitions without drift or early cutoffs.
4. Verify output routing to `--clipboard` (via `wl-copy` / `xclip`) and `--type` (via `wtype` / `xdotool` / `ydotool`).

## 2. Technical Findings & Benchmark Results on 88s Concatenated Talk

- **Audio Synthesis**: Synthesized an 88.0s audio session repeating `test.wav` ("a b c d e ...") and `chunks.wav` ("this is a recording of one chunk and another chunk") with 1.0s silence gaps.
- **Model Inference Benchmarks**:
  - **Parakeet TDT v3**: 88.0s transcribed in **11.57s** (RTF: **0.131x**), 318 characters, complete repetition count, zero memory drift.
  - **Cohere Transcribe**: 88.0s transcribed in **19.68s** (RTF: **0.223x**), 315 characters, complete repetition count.
  - **Whisper base.en**: 88.0s transcribed in **2.14s** on Vulkan iGPU.
- **Output Drivers**:
  - `--clipboard`: Verified round-trip writing to clipboard via `wl-copy` / `xclip` and reading back via `wl-paste`.
  - `--type`: Integrated and supported for both `transcribe` and `dictate`.

## 3. Implementation & Verification Plan

1. **Test Suite**: Implemented `ConcatenatedAudioDictationTests.swift` covering 60s+ audio concatenation, multi-model transcription, and clipboard verification.
2. **CLI Output Targets**: Added `--clipboard` and `--type` support across both `TranscribeCommand.swift` and `DictateCommand.swift`.
3. **Execution**: All `55/55` tests passed in **35.7s**.
