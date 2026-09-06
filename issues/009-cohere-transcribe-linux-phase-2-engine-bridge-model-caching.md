# 009 — Cohere Transcribe Linux Phase 2: Engine bridge & model caching

**Status**: Closed — resolved in `CohereTranscriber.swift`
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/008-cohere-transcribe-linux-phase-1-canary-probe-runtime-selection.md`, `issues/010-cohere-transcribe-linux-phase-3-cli-integration-benchmark-verification.md`

---

## 1. Problem & Motivation

Once the Canary probe in issue 008 determined the optimal runtime and validated model accuracy on Linux, we needed a clean engine bridge and model artifact manager in Swift/C. This enables `FluidVoiceLinuxCLICore` to download/cache the required weights from Hugging Face and invoke Cohere Transcribe natively.

## 2. Technical Specification / Findings

- Implemented `CohereTranscriber.swift` in `Sources/FluidVoiceLinuxCLICore` with `CrispASRNativeBridge` dynamically binding `libcrispasr.so` via `dlopen`/`dlsym`.
- Implemented `ModelPathResolver.resolveCohere(...)` in `Sources/FluidVoiceLinuxCLICore/ModelPathResolver.swift` prioritizing explicit flag -> repo model -> `~/.cache/crispasr/` -> `$XDG_DATA_HOME`.
- Persisted shared libraries in `~/.local/lib/crispasr/`.
- Added unit tests in `Tests/FluidVoiceLinuxCLITests/ModelPathResolutionTests.swift`. All 28 tests pass.

## 3. Implementation & Verification Plan

1. **Model Cache Manager**: Implemented `resolveCohere` and caching resolution.
2. **C / Swift Interop Layer**: Implemented `CrispASRNativeBridge` + `CohereTranscriber.transcribe(...)`.
3. **Unit Tests**: Passed in `Tests/FluidVoiceLinuxCLITests`.


