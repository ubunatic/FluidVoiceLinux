# 014 — End-to-End Live Dictation pipeline (dictate subcommand with typing output)

**Status**: Closed — implemented in `DictateCommand.swift` & `TextOutputDriver.swift` and live verified end-to-end
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/011-nvidia-parakeet-tdt-nemotron-speech-stt-support-on-linux.md`, `issues/012-real-time-voice-activity-detection-silero-vad-audio-segmentation.md`, `issues/013-llm-ai-post-enhancement-prompt-formatting-ollama-claude-gemini-openai.md`

---

## 1. Problem & Motivation

The ultimate goal of FluidVoice on Linux is a unified, real-time dictation engine that listens continuously, detects speech boundaries via VAD, transcribes via GPU/CPU STT models (Whisper/Cohere/Parakeet/Nemotron), applies AI post-enhancement, and outputs text directly into the active window (or clipboard).

## 2. Technical Specification / Findings

- **CLI Subcommand**: `fluidvoice-linux dictate [--backend whisper|cohere|parakeet|nemotron] [--enhance] [--type] [--clipboard] [--seconds N]`
- **Keystroke & Clipboard Simulation (`TextOutputDriver`)**:
  - Direct typing into active application windows via `wtype` (Wayland native), `xdotool` (X11), or `ydotool`.
  - Clipboard copy via `wl-copy` (Wayland) or `xclip` / `xsel` (X11).
- **Full Pipeline Architecture**:
  $$\text{ALSA Stream} \longrightarrow \text{VAD Segmentation} \longrightarrow \text{ASR Worker (Parakeet/Cohere/Whisper)} \longrightarrow \text{LLM Filter (Ollama/Claude/Gemini/OpenAI)} \longrightarrow \text{Output Driver (Type/Copy/Print)}$$

## 3. Implementation & Verification Plan

1. **Dictate Subcommand**: Implemented `DictateCommand.swift` with pure argument parsing and dynamic model resolution.
2. **Output Drivers**: Implemented `TextOutputDriver.swift` supporting Wayland & X11 typing and clipboard integration.
3. **CLI Integration**: Wired `dictate` subcommand into `main.swift`.
4. **Unit Tests**: Added unit tests in `DictateCommandArgumentTests.swift` (`49/49` total tests pass).
5. **Live Verification**: Verified end-to-end live ALSA capture $\to$ VAD $\to$ Parakeet pipeline via `make run ARGS="dictate --seconds 1.0 --backend parakeet"`.


