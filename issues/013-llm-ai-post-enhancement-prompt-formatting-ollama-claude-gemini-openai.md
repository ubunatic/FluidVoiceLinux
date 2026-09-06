# 013 — LLM AI Post-Enhancement & Prompt Formatting (Ollama / Claude / Gemini / OpenAI)

**Status**: Open
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `Sources/Fluid/Services/ModelRepository.swift`, `issues/014-end-to-end-live-dictation-pipeline-dictate-subcommand-with-typing-output.md`

---

## 1. Problem & Motivation

FluidVoice on macOS features rich AI post-processing (punctuation fixing, context-aware grammar repair, list formatting, command execution, and rewrite modes) driven by local LLMs (Ollama, LM Studio) or cloud APIs (OpenAI, Anthropic, Google Gemini, Groq). 

We need a headless AI enhancement engine in Linux CLI that can take raw ASR transcriptions and clean/format them seamlessly.

## 2. Technical Specification / Findings

- **Provider Support**:
  - Local: Ollama (`http://localhost:11434/v1/chat/completions`)
  - Cloud: Anthropic, OpenAI, Google Gemini, Groq, OpenRouter
- **Modes**:
  - Dictation cleanup (formatting, punctuation, disfluency removal)
  - Custom system prompts / command mode
- **CLI Options**:
  - `fluidvoice-linux transcribe --in sample.wav --enhance [--provider ollama|openai|anthropic|gemini] [--ai-model <name>]`

## 3. Implementation & Verification Plan

1. **AI Client Engine**: Implement `AIEnhancementService.swift` using `URLSession` async networking.
2. **System Prompt Templates**: Port prompt templates from macOS app.
3. **Unit Tests**: Mock HTTP responses to verify prompt assembly and error handling.
4. **Verification**: Verify against local Ollama instance or cloud API.

