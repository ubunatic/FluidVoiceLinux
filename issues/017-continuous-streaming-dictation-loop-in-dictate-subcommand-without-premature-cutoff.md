# 017 — Continuous streaming dictation loop in dictate subcommand without premature cutoff

**Status**: Closed — streaming dictation implemented and verified
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
- [x] `fluidvoice-linux dictate` (without `--seconds`) continuously streams microphone audio and does not exit after 5s or 10s of speech. (`AlsaAudioStream` + `StreamingDictationLoop` loop until end-of-stream/SIGINT/max-duration; no fixed-duration `record()` call remains in the `dictate` path.)
- [x] Utterances separated by natural pauses are segmented dynamically via VAD and transcribed incrementally. (`IncrementalSpeechSegmenter` tracks onset/sustain/trailing-silence across chunks; each completed utterance is transcribed as it completes.)
- [x] Transcribed text is output to stdout, clipboard, or typed via keystrokes as each speech chunk finishes. (`transcribeEnhanceAndEmit` runs per utterance inside the streaming loop, not after the session ends.)
- [x] If `--seconds` / `--duration` is specified, dictation runs up to the requested duration while still processing chunks incrementally. (`StreamingDictationLoop.run`'s `maxDurationSeconds` caps total ingested audio, flushing any in-progress utterance at the cap.)
- [x] Clean termination and resource cleanup (ALSA capture handle, transcription background tasks) on SIGINT / Ctrl+C. (SIGINT sets a static flag polled between chunk reads; `stream.stop()` in a `defer` closes the ALSA handle. Transcription runs inline per utterance, not as a separate background task, so there is nothing further to drain on exit -- see implementation note below.)
- [x] Unit tests for continuous streaming recorder and incremental VAD segmentation state machine. (`Tests/FluidVoiceLinuxCLITests/VoiceActivityDetectorTests.swift`: `IncrementalSpeechSegmenter` tests for multi-burst segmentation and stream-end flush, `StreamingDictationLoop` tests for chunk-driven callback mechanics, max-duration cap, and SIGINT-style stop-flag handling.)

**Implementation note**: transcription/enhancement/output run synchronously per utterance inside the same loop that reads audio (not as detached background tasks), because `AlsaAudioStream.readChunk` is deliberately single-threaded/pull-based -- ALSA's C read/close calls aren't documented safe to call concurrently. This still satisfies "incremental, not all at the end" (each utterance is emitted before the next one is even recorded) and avoids a Swift-concurrency footgun where a blocking synchronous call (`AIEnhancementService.enhanceBlocking`, which itself semaphore-waits on a nested `Task`) run from inside an unstructured `Task` could starve the cooperative thread pool. A real ALSA capture device was not available in this sandboxed environment to verify live end-to-end SIGINT behavior; verified instead via the pure-Swift `StreamingDictationLoop`/`IncrementalSpeechSegmenter` unit tests plus code review of the SIGINT-handling code path.

### Verification Plan
1. **Unit & Pipeline Tests**:
   - Test streaming audio recorder mock / callback mechanics.
   - Test incremental VAD segmentation with streaming audio frames containing multiple speech bursts separated by silence.
2. **End-to-End Dictation Test**:
   - Run `dictate` with multi-utterance audio / live input and verify multiple transcribed segments are produced in succession without premature termination.
