# 010 — Cohere Transcribe Linux Phase 3: CLI integration & benchmark verification

**Status**: Closed — resolved in `TranscribeCommand.swift` & human-verified end-to-end
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/008-cohere-transcribe-linux-phase-1-canary-probe-runtime-selection.md`, `issues/009-cohere-transcribe-linux-phase-2-engine-bridge-model-caching.md`

---

## 1. Problem & Motivation

With the engine bridge and model manager ready (issue 009), we needed to wire Cohere Transcribe into the CLI subcommands (`transcribe`), expose backend selection (`--backend cohere|whisper`), language selection flags (`--lang <code|auto>`), and verify end-to-end performance on real audio samples.

## 2. Technical Specification / Findings

- Implemented `--backend whisper|cohere` and `--lang <code>` in `TranscribeCommand.swift`.
- Added unit tests in `TranscribeCommandArgumentTests.swift` (30 tests pass green).
- Verified end-to-end via `make run ARGS="transcribe --in ~/.config/fluidvoice/dev/samples/test.wav --backend cohere"` and `chunks.wav`:
  - `test.wav`: `"A, B, C, D, E, F, G, H, I, J, K, L, L, N."` (Load: 0.15s, Infer: 2.28s)
  - `chunks.wav`: `"This is a recording of one chunk and another chunk."` (Load: 0.15s, Infer: 2.26s)
- Both Whisper (Vulkan iGPU) and Cohere Transcribe (Conformer GGUF) work side-by-side with zero regressions.

## 3. Implementation & Verification Plan

1. **CLI Flag & Dispatch**: Updated `TranscribeCommand.swift`.
2. **Integration Verification**: Verified `make run` with real hardware audio samples.
3. **Doc & Setup Updates**: Updated `docs/LINUX_SETUP.md`.


