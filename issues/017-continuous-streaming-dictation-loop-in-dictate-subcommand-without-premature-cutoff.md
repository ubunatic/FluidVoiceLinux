# 017 — Continuous streaming dictation loop in dictate subcommand without premature cutoff

**Status**: Open
**Priority**: P1 (High)
**Severity**: Major
**Category**: Bug
**Related**: `Sources/FluidVoiceLinuxCLICore/DictateCommand.swift`, `Sources/FluidVoiceLinuxCLICore/AudioRecorder.swift`, `Sources/FluidVoiceLinuxCLICore/VoiceActivityDetector.swift`, `issues/014-end-to-end-live-dictation-pipeline-dictate-subcommand-with-typing-output.md`

---

## 1. Problem & Motivation

When running `fluidvoice-linux dictate`, the command prematurely terminates after 5–10 seconds of speaking even if the user continues speaking.

### Root Cause
In `DictateCommand.swift`, audio recording is currently performed via a single fixed-duration call:
```swift
let recordDuration = options.maxDurationSeconds ?? 5.0
let recording = try AlsaAudioRecorder.record(
    seconds: recordDuration,
    sampleRate: 16000,
    channelCount: 1,
    deviceName: options.deviceName
)
```
After capturing this single buffer of `recordDuration` (defaulting to 5.0s if `--seconds` is not provided), `DictateCommand` runs VAD and STT transcription on the buffer, outputs the resulting text, and immediately exits.

### User Expectation
Users expect `dictate` to behave as a continuous dictation session:
1. Stream audio continuously from ALSA in real time.
2. Continually evaluate speech frames with voice activity detection (VAD).
3. Split audio into utterance chunks on natural speech pauses/endpoints (e.g. 300–500ms of silence).
4. Transcribe completed utterances incrementally in the background and immediately emit text to stdout, clipboard, or virtual keystrokes.
5. Keep listening and processing subsequent speech until interrupted (e.g. via SIGINT / Ctrl+C, or until reaching `--seconds` / `--duration` if explicitly specified).

---

## 2. Technical Specification & Proposed Solution

### 1. Continuous Streaming Capture Support in `AlsaAudioRecorder`
- Extend `AlsaAudioRecorder` (or add a streaming interface) to support continuous audio capture without requiring a pre-allocated fixed buffer length.
- Support reading frames in a loop and streaming chunks/buffers via a callback, delegate, or Swift concurrency `AsyncStream<[Int16]>`.
- Ensure cancellation / stop signals (e.g. signal handlers, Task cancellation, or explicit stop triggers) cleanly close the ALSA capture handle (`fv_alsa_capture_close`).

### 2. Incremental VAD State Machine & Segmentation
- Provide a streaming / incremental VAD processor using `EnergyVoiceActivityDetector` or `SileroVoiceActivityDetector`.
- Ingest audio frames incrementally, tracking speech onset, sustained speech, and silence trailing pad.
- Slice completed utterance segments when a silence boundary threshold (e.g. 300–500ms) is reached after speech, yielding an audio chunk ready for transcription.

### 3. Continuous Transcription & Incremental Output Dispatch
- In `DictateCommand.swift`, maintain a continuous loop that:
  - Continuously streams audio from `AlsaAudioRecorder`.
  - Dispatches segmented utterance audio chunks to the configured STT engine (Parakeet, Whisper, Cohere, or Nemotron).
  - Processes AI enhancement (if `--enhance` is enabled) per chunk or on punctuation boundaries.
  - Emits transcribed text incrementally to the target output driver (`stdout`, `clipboard`, or `typing`) as each chunk finishes, avoiding latency or premature cutoff.
  - Terminates gracefully when `--seconds` is provided and elapsed time expires, or upon receiving `SIGINT` (Ctrl+C).

---

## 3. Scope & Acceptance Criteria

### Acceptance Criteria
- [ ] `fluidvoice-linux dictate` (without `--seconds`) continuously streams microphone audio and does not exit after 5s or 10s of speech.
- [ ] Utterances separated by natural pauses are segmented dynamically via VAD and transcribed incrementally.
- [ ] Transcribed text is output to stdout, clipboard, or typed via keystrokes as each speech chunk finishes.
- [ ] If `--seconds` / `--duration` is specified, dictation runs up to the requested duration while still processing chunks incrementally.
- [ ] Clean termination and resource cleanup (ALSA capture handle, transcription background tasks) on SIGINT / Ctrl+C.
- [ ] Unit tests for continuous streaming recorder and incremental VAD segmentation state machine.

### Verification Plan
1. **Unit & Pipeline Tests**:
   - Test streaming audio recorder mock / callback mechanics.
   - Test incremental VAD segmentation with streaming audio frames containing multiple speech bursts separated by silence.
2. **End-to-End Dictation Test**:
   - Run `dictate` with multi-utterance audio / live input and verify multiple transcribed segments are produced in succession without premature termination.
