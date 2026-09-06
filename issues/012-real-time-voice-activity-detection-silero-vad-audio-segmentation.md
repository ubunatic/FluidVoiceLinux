# 012 — Real-time Voice Activity Detection (Silero VAD) & audio segmentation

**Status**: Open
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md`, `issues/014-end-to-end-live-dictation-pipeline-dictate-subcommand-with-typing-output.md`

---

## 1. Problem & Motivation

Currently, recording audio on Linux (`record` subcommand) requires passing a fixed time (`--seconds N`). In real-world dictation, the user speaks continuously with natural pauses, and transcription should trigger automatically when speech begins and ends without manual timer cutoffs.

## 2. Technical Specification / Findings

- **VAD Engine**: Silero VAD (v5) via ONNX Runtime / GGUF VAD or lightweight C++ frame evaluator.
- **Chunking Pipeline**:
  - Evaluate 30ms audio frames from ALSA stream.
  - Detect speech start (threshold > 0.5 for > 250ms).
  - Detect speech end / pause (silence > 500ms).
  - Emit discrete speech chunks for transcription without losing trailing consonants.

## 3. Implementation & Verification Plan

1. **VAD Module**: Implement `VoiceActivityDetector.swift` in `Sources/FluidVoiceLinuxCLICore`.
2. **Streaming Chunker**: Feed ALSA frames into VAD and verify chunk boundaries against speech test samples.
3. **Unit Tests**: Test synthetic silence vs speech transitions.

