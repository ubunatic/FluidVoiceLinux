# 010 — Cohere Transcribe Linux Phase 3: CLI integration & benchmark verification

**Status**: In Progress
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/008-cohere-transcribe-linux-phase-1-canary-probe-runtime-selection.md`, `issues/009-cohere-transcribe-linux-phase-2-engine-bridge-model-caching.md`

---

## 1. Problem & Motivation

With the engine bridge and model manager ready (issue 009), we must wire Cohere Transcribe into the CLI subcommands (`transcribe`), expose backend selection (`--backend cohere|whisper`), language selection flags (`--lang <code|auto>`), and verify end-to-end performance on real audio samples.

## 2. Technical Specification / Findings

- **CLI Interface**:
  - `fluidvoice-linux transcribe --in <file.wav> --backend cohere [--model <name-or-path>] [--lang <code|auto>]`
- **Supported Languages**: English, French, German, Italian, Spanish, Portuguese, Greek, Dutch, Polish, Chinese, Japanese, Korean, Vietnamese, Arabic.
- **Benchmarks**: Compare transcript quality and RTF against Whisper on `~/.config/fluidvoice/dev/samples/test.wav` and `chunks.wav`.

## 3. Implementation & Verification Plan

1. **CLI Flag & Dispatch**: Update `TranscribeCommand.swift` to support `--backend` flag.
2. **Integration Verification**: Run `make run ARGS="transcribe --in ~/.config/fluidvoice/dev/samples/test.wav --backend cohere"` and verify word-for-word accuracy.
3. **Doc & Setup Updates**: Document any system dependencies in `docs/LINUX_SETUP.md`.

