# 014 — End-to-End Live Dictation pipeline (dictate subcommand with typing output)

**Status**: Open
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/011-nvidia-parakeet-tdt-nemotron-speech-stt-support-on-linux.md`, `issues/012-real-time-voice-activity-detection-silero-vad-audio-segmentation.md`, `issues/013-llm-ai-post-enhancement-prompt-formatting-ollama-claude-gemini-openai.md`

---

## 1. Problem & Motivation

The ultimate goal of FluidVoice on Linux is a unified, real-time dictation engine that listens continuously, detects speech boundaries via VAD, transcribes via GPU/CPU STT models (Whisper/Cohere/Parakeet), applies AI post-enhancement, and outputs text directly into the active window (or clipboard).

## 2. Technical Specification / Findings

- **CLI Subcommand**: `fluidvoice-linux dictate [--backend whisper|cohere|parakeet] [--enhance] [--type-keystrokes] [--clipboard]`
- **Keystroke Simulation**: Support `ydotool` (Wayland/generic), `wtype` (Wayland), or `xdotool` (X11) for direct typing into any text box.
- **Pipeline Architecture**:
  $$\text{ALSA Stream} \longrightarrow \text{VAD Segmentation} \longrightarrow \text{ASR Worker} \longrightarrow \text{LLM Filter} \longrightarrow \text{Output Driver}$$

## 3. Implementation & Verification Plan

1. **Dictate Subcommand**: Implement `DictateCommand.swift`.
2. **Output Drivers**: Add clipboard and simulated keystroke injectors.
3. **Integration Verification**: Test live microphone dictation end-to-end.

