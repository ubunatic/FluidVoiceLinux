# 008 — Cohere Transcribe Linux Phase 1: Canary probe & runtime selection

**Status**: Closed — resolved with CrispASR ggml runtime (RTF 0.136x)
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md`, `issues/009-cohere-transcribe-linux-phase-2-engine-bridge-model-caching.md`, `Sources/Fluid/Services/ExternalCoreMLModelRegistry.swift`

---

## 1. Problem & Motivation

Cohere Transcribe (`CohereLabs/cohere-transcribe-03-2026`) is one of the highest-scoring open ASR models on multilingual benchmarks, beating Whisper on accuracy across 14 languages. The macOS app supports it via CoreML (`Sources/Fluid/Services/ExternalCoreMLModelRegistry.swift`), but CoreML is unavailable on Linux.

To bring Cohere Transcribe to FluidVoice on Linux with hardware acceleration (AMD iGPU Vulkan/ROCm or fast CPU inference), we need a canary probe to evaluate runtime feasibility, inspect model artifacts, verify dependencies, and benchmark transcription on our baseline audio sample (`~/.config/fluidvoice/dev/samples/test.wav`).

## 2. Technical Specification / Findings

- **Model Identity**: `CohereLabs/cohere-transcribe-03-2026` / GGUF quantization `cstr/cohere-transcribe-03-2026-GGUF/cohere-transcribe-q4_k.gguf` (1.51 GB).
- **Runtime Selected**: `libcrispasr` (ggml-based native C++ ASR library with unified C-ABI).
- **Benchmark Results on Host**:
  - `test.wav` (10.0s spoken letters): Transcribed in **1.36s** (RTF: **0.136x**).
    - Transcript: `"A, B, C, D, E, F, G, H, I, J, K, L, L, N."`
  - `chunks.wav` (10.0s speech chunks): Transcribed in **1.44s** (RTF: **0.144x**).
    - Transcript: `"This is a recording of one chunk and another chunk."`
- **C-ABI Exported Symbols**:
  - `crispasr_session_open(path, n_threads)`
  - `crispasr_session_transcribe_lang(session, samples, n_samples, lang)`
  - `crispasr_session_result_n_segments(result)`
  - `crispasr_session_result_segment_text(result, i)`
  - `crispasr_session_result_segment_t0(result, i)` / `t1`
  - `crispasr_session_result_free(result)`
  - `crispasr_session_close(session)`

## 3. Implementation & Verification Plan

1. **Canary Script**: Created standalone runner verifying weights download and transcription of `test.wav` & `chunks.wav`.
2. **Execution & Profiling**: Verified 0.136x RTF and flawless transcription text.
3. **Runtime Decision**: Standardize on `libcrispasr` C-ABI for Phase 2 Swift C-interop.

