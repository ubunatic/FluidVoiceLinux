# 011 — NVIDIA Parakeet TDT & Nemotron Speech STT support on Linux

**Status**: Closed — resolved in `TranscribeCommand.swift` & human-verified end-to-end
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/010-cohere-transcribe-linux-phase-3-cli-integration-benchmark-verification.md`, `Sources/Fluid/Services/ASRService.swift`

---

## 1. Problem & Motivation

The macOS version of FluidVoice uses **NVIDIA Parakeet TDT v3** (25 European languages, fast Token-and-Duration Transducer) as its default transcription model and **Nemotron Speech 3.5** for ultra-fast low-latency streaming. On macOS, these run via Apple Neural Engine / CoreML (`FluidAudio`). 

With our managed GGUF runtime layer established in issue 010, we brought both **Parakeet TDT v3** and **Nemotron Speech 3.5** to Linux natively.

## 2. Technical Specification / Findings

- **Models Integrated**:
  - `parakeet-tdt-0.6b-v3-q4_k.gguf` (467 MB, #1 default model on macOS)
  - `nemotron-3.5-asr-streaming-0.6b-q4_k.gguf` (458 MB, ultra-fast low latency streaming)
- **Benchmark Evidence on Real Hardware (`chunks.wav`, 10.0s)**:
  - **Parakeet TDT v3**: Transcribed in **1.04s** (RTF: **0.104x**). Transcript: `"This is a recording of one chunk and another chunk."`
  - **Nemotron Speech 3.5**: Transcribed in **2.06s** (RTF: **0.206x**). Transcript: `"This is a recording of Vanchunk and another chunk. <en-US>"`
- **Supported CLI Flags**:
  - `fluidvoice-linux transcribe --in <file.wav> --backend parakeet`
  - `fluidvoice-linux transcribe --in <file.wav> --backend nemotron`

## 3. Implementation & Verification Plan

1. **Model Cache & Resolution**: Added `resolveParakeet` & `resolveNemotron` in `ModelPathResolver.swift`.
2. **Backend Dispatch**: Added `.parakeet` and `.nemotron` cases to `STTEngineBackend` and `TranscribeCommand.swift`.
3. **Unit Tests**: Added argument & path resolution tests (31 unit tests pass).
4. **Verification**: Live end-to-end verified via `make run`.


