# 011 — NVIDIA Parakeet TDT & Nemotron Speech STT support on Linux

**Status**: In Progress
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/010-cohere-transcribe-linux-phase-3-cli-integration-benchmark-verification.md`, `Sources/Fluid/Services/ASRService.swift`

---

## 1. Problem & Motivation

The macOS version of FluidVoice uses **NVIDIA Parakeet TDT v3** (25 European languages, fast Token-and-Duration Transducer) as its default transcription model and **Nemotron Speech 3.5** for ultra-fast low-latency streaming. On macOS, these run via Apple Neural Engine / CoreML (`FluidAudio`). 

With our managed GGUF runtime layer established in issue 010, we can bring both **Parakeet TDT** (`parakeet-tdt-1.1b`) and **Nemotron** to Linux natively.

## 2. Technical Specification / Findings

- **Models**:
  - `parakeet-tdt-1.1b` (GGUF from `cstr/parakeet-tdt-1.1b-GGUF` or ONNX)
  - `nemotron-speech-3.5` (GGUF / streaming conformer)
- **Supported Languages**: 25 European languages with auto language detection for Parakeet TDT v3.
- **CLI Options**:
  - `fluidvoice-linux transcribe --in sample.wav --backend parakeet`
  - `fluidvoice-linux transcribe --in sample.wav --backend nemotron`

## 3. Implementation & Verification Plan

1. **Model Cache & Resolution**: Wire `ModelPathResolver.resolveParakeet` and `resolveNemotron`.
2. **Backend Dispatch**: Support `--backend parakeet` and `--backend nemotron` in `TranscribeCommand.swift` and `CohereTranscriber.swift`/runtime runner.
3. **Unit Tests**: Add test cases for argument parsing and path resolution.
4. **Verification**: Run `make run ARGS="transcribe --in ~/.config/fluidvoice/dev/samples/chunks.wav --backend parakeet"` on real hardware.

