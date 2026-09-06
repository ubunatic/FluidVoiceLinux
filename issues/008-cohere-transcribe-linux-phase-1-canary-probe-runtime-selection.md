# 008 — Cohere Transcribe Linux Phase 1: Canary probe & runtime selection

**Status**: In Progress
**Priority**: P1 (High)
**Severity**: Major
**Category**: Feature
**Related**: `issues/004-linux-migration-phase-4-mvp2-run-stt-model-on-amd-igpu.md`, `Sources/Fluid/Services/ExternalCoreMLModelRegistry.swift`

---

## 1. Problem & Motivation

Cohere Transcribe (`CohereLabs/cohere-transcribe-03-2026`) is one of the highest-scoring open ASR models on multilingual benchmarks, beating Whisper on accuracy across 14 languages. The macOS app supports it via CoreML (`Sources/Fluid/Services/ExternalCoreMLModelRegistry.swift`), but CoreML is unavailable on Linux.

To bring Cohere Transcribe to FluidVoice on Linux with hardware acceleration (AMD iGPU Vulkan/ROCm or fast CPU inference), we need a canary probe to evaluate runtime feasibility, inspect model artifacts, verify dependencies, and benchmark transcription on our baseline audio sample (`~/.config/fluidvoice/dev/samples/test.wav`).

## 2. Technical Specification / Findings

- **Model Identity**: `CohereLabs/cohere-transcribe-03-2026` (2B parameters Conformer encoder + Transformer decoder).
- **Runtime Options to Probe**:
  1. `transformers` / PyTorch (Vulkan/ROCm or CPU / TorchDynamo / ONNX / Torch-TRT).
  2. ONNX Runtime / `sherpa-onnx` / `vLLM` / C++ runtime.
  3. Direct C++ / GGML / CTranslate2 port or lightweight runtime wrapper.
- **Probe Target**:
  - Run a standalone canary script on the Linux host against `~/.config/fluidvoice/dev/samples/test.wav`.
  - Validate output transcript: `a b c d e f g h i j k l m n`.
  - Measure memory footprint, warm-up time, and real-time factor (RTF).
  - Select the optimal runtime for Swift C-interop integration in Phase 2.

## 3. Implementation & Verification Plan

1. **Canary Script**: Create a minimal runner script to load model weights and transcribe `test.wav`.
2. **Execution & Profiling**: Run against AMD iGPU (or CPU) on this Linux host, measuring VRAM/RAM and latency.
3. **Runtime Decision**: Document exact engine/shared library requirements and interop interface for Phase 2.
4. **Verification**: Confirm accurate transcription output and stable execution.
