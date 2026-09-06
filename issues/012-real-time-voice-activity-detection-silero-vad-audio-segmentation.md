# 012 — Real-time Voice Activity Detection (Silero VAD) & audio segmentation

**Status**: Closed — implemented in `VoiceActivityDetector.swift` & unit/sample verified
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md`, `issues/014-end-to-end-live-dictation-pipeline-dictate-subcommand-with-typing-output.md`

---

## 1. Problem & Motivation

Currently, recording audio on Linux (`record` subcommand) requires passing a fixed time (`--seconds N`). In real-world dictation, the user speaks continuously with natural pauses, and transcription should trigger automatically when speech begins and ends without manual timer cutoffs.

## 2. Technical Specification / Findings

- **VAD Engines**:
  - `SileroVoiceActivityDetector`: Silero VAD (v5/v6) running via ONNX Runtime (`silero_vad.onnx`, 2.3 MB cached at `~/.cache/crispasr/silero_vad.onnx`). Execution speed: **~33ms** for a 10s audio segment.
  - `EnergyVoiceActivityDetector`: Fast, pure Swift zero-dependency RMS energy thresholding with dynamic frame hangover for low-latency offline fallback and headless test suites.
- **Chunking Pipeline (`AudioSegmenter`)**:
  - Evaluates audio frames.
  - Detects speech start (threshold $\ge$ 0.5 for $\ge$ 250ms).
  - Detects speech pause/end (silence $\ge$ 300ms).
  - Padds speech segments with `speechPadMs` (100ms) to ensure leading/trailing consonants are preserved.
  - Emits discrete `[AudioChunk]` ready for STT backends.
- **Model Path Resolution**: Added `ModelPathResolver.resolveSileroVAD` supporting explicit `--vad-model`, repo-relative `models/silero_vad.onnx`, `~/.cache/crispasr/silero_vad.onnx`, and XDG paths.

## 3. Implementation & Verification Plan

1. **VAD Module**: Implemented `VoiceActivityDetector.swift` in `Sources/FluidVoiceLinuxCLICore`.
2. **Path Resolution**: Added `resolveSileroVAD` in `ModelPathResolver.swift`.
3. **Unit Tests**: Added 7 comprehensive test suites in `VoiceActivityDetectorTests.swift` covering silence, synthetic tones, multi-utterance segmentation, and real-audio Silero VAD detection (`38/38` tests pass).


