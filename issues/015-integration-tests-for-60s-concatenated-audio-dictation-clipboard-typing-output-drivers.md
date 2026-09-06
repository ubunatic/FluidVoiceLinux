# 015 — Integration tests for >=60s concatenated audio dictation & clipboard/typing output drivers

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Normal
**Category**: Testing
**Related**: `issues/011-nvidia-parakeet-tdt-nemotron-speech-stt-support-on-linux.md`, `issues/014-end-to-end-live-dictation-pipeline-dictate-subcommand-with-typing-output.md`

---

## 1. Problem & Motivation

Short sample files (~1–10s) verify basic engine initialization and single-phrase inference, but do not validate long-form dictation stability, memory behavior, drift, or multi-chunk audio processing across sustained speech sessions.

We need automated extended integration tests that:
1. Concatenate reference audio samples (`test.wav` / "abc" and `chunks.wav` / "chunks" from `~/.config/fluidvoice/dev/samples/`) into a $\ge 60$-second simulated speech session.
2. Transcribe the multi-chunk long audio across all supported STT models (**Parakeet TDT v3**, **Cohere Transcribe**, **Whisper**).
3. Verify that models produce correct transcript content, expected length, and accurate repetitions.
4. Verify output routing to `--clipboard` (via `wl-copy` / `xclip`) and `--type` (via `wtype` / `xdotool` / `ydotool`).

## 2. Scope & Acceptance Criteria

- **Test Fixture Generation**:
  - Script or harness to programmatically concatenate `test.wav` and `chunks.wav` into a repeatable $\ge 60$-second WAV file with appropriate audio headers and sample rates (16kHz mono).
- **Multi-Model Transcription Verification**:
  - Run `fluidvoice-linux transcribe` (and/or `dictate`) with `--in <concatenated_60s.wav>` against:
    - **Parakeet TDT v3** (`--backend parakeet`)
    - **Cohere Transcribe** (`--backend cohere`)
    - **Whisper** (`--backend whisper`)
  - Assert that transcripts contain all expected phrases with accurate repetition counts and no premature cutoffs.
- **Output Driver Integration**:
  - Verify `--clipboard` flag properly invokes system clipboard tools (`wl-copy` or `xclip`) and places the resulting text into the clipboard buffer.
  - Verify `--type` flag properly triggers active window typing drivers (`wtype`, `xdotool`, or `ydotool`) without crashing or dropping characters.
- **Test Automation**:
  - Integrate test execution into standard test workflows (e.g. `make test-integration` or automated test runner).

## 3. Verification Guidance

1. **Audio Synthesis**: Concatenate sample WAVs to $\ge 60\text{s}$ duration (e.g., using `sox`, `ffmpeg`, or a Swift test helper).
2. **Model Matrix Run**:
   ```bash
   fluidvoice-linux transcribe --in /tmp/concat_60s.wav --backend parakeet
   fluidvoice-linux transcribe --in /tmp/concat_60s.wav --backend cohere
   fluidvoice-linux transcribe --in /tmp/concat_60s.wav --backend whisper
   ```
3. **Driver Output Verification**:
   ```bash
   fluidvoice-linux transcribe --in /tmp/concat_60s.wav --backend parakeet --clipboard
   wl-paste # or xclip -o -> verify transcript matches
   ```
4. **Typing Output Verification**:
   ```bash
   fluidvoice-linux transcribe --in /tmp/concat_60s.wav --backend parakeet --type
   ```

