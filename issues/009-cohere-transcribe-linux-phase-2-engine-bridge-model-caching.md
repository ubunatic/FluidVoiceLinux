# 009 — Cohere Transcribe Linux Phase 2: Engine bridge & model caching

**Status**: In Progress
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/008-cohere-transcribe-linux-phase-1-canary-probe-runtime-selection.md`

---

## 1. Problem & Motivation

Once the Canary probe in issue 008 determines the optimal runtime and validates model accuracy on Linux, we need a clean engine bridge and model artifact manager in Swift/C. This enables `FluidVoiceLinuxCLICore` to download/cache the required weights from Hugging Face and invoke Cohere Transcribe natively.

## 2. Technical Specification / Findings

- **Engine Bridge Target**: `Sources/LinuxCohereSupport` (C shim / shared library linkage) or direct runtime integration.
- **Model Downloader & Caching**: Cache model artifacts in `~/.config/fluidvoice/models/cohere/` (or `~/.cache/huggingface/hub/` / XDG cache directory) with integrity checks.
- **Transcriber Protocol**: Implement a `CohereTranscriber` conforming to the existing audio processing interfaces in `FluidVoiceLinuxCLICore`.

## 3. Implementation & Verification Plan

1. **Model Cache Manager**: Implement download and local artifact verification in Swift.
2. **C / Swift Interop Layer**: Build `LinuxCohereSupport` C shim and Swift wrapper `CohereTranscriber.swift`.
3. **Unit Tests**: Add unit tests in `Tests/FluidVoiceLinuxCLITests` validating tokenization, prompt formatting, and error handling.

