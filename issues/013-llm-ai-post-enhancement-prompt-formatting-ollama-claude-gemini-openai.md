# 013 — LLM AI Post-Enhancement & Prompt Formatting (Ollama / Claude / Gemini / OpenAI)

**Status**: Closed — implemented in `AIEnhancementService.swift` & `TranscribeCommand.swift` with full mock test suite
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
  - Cloud: Anthropic (`https://api.anthropic.com/v1/messages`), OpenAI (`https://api.openai.com/v1/chat/completions`), Google Gemini (`https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`), Groq, OpenRouter, and Custom endpoints.
- **Modes**:
  - Dictation cleanup (formatting, punctuation, disfluency removal, list formatting)
  - Custom system prompts & temperature control.
- **CLI Options**:
  - `fluidvoice-linux transcribe --in sample.wav --enhance [--ai-provider ollama|openai|anthropic|gemini|groq|openrouter|custom] [--ai-model <name>] [--ai-api-key <key>] [--ai-endpoint <url>]`

## 3. Implementation & Verification Plan

1. **AI Client Engine**: Implemented `AIEnhancementService.swift` supporting both OpenAI-compatible and Anthropic message formats with `URLSession` async networking and sync blocking wrapper.
2. **System Prompt Templates**: Ported dictation cleanup system prompt from macOS app.
3. **CLI Integration**: Wired `--enhance` and AI provider flags into `TranscribeCommand.swift`.
4. **Unit Tests**: Added 9 tests in `TranscribeCommandArgumentTests.swift` and mock HTTP protocol tests in `AIEnhancementServiceTests.swift` (`44/44` tests pass).


