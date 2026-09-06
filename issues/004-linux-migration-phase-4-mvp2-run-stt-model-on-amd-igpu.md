# 004 — Linux migration Phase 4: MVP2 run STT model on AMD iGPU

**Status**: In Progress
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Feature

---

## 1. Problem & Motivation

Phase 4 of `docs/LINUX_MIGRATION_BRANCH_PLAN.md`. Depends on issue 003
(need a recorded WAV to transcribe). Goal: "I can also run the model on
the AMD iGPU" — GPU-accelerated speech-to-text on Linux without
requiring a full ROCm install if avoidable.

## 2. Technical Specification / Findings

- `transcribe-cpp-swift` (whisper.cpp Swift wrapper, pinned `0.1.2`) is
  already a dependency for the macOS app — **investigate first**
  whether it's usable at all on Linux (does it resolve/compile outside
  `#if os(macOS)`?) and whether the pinned version has a Vulkan or
  ROCm backend compiled in. whisper.cpp upstream has Vulkan support,
  which is the most portable path for AMD iGPU acceleration without a
  full ROCm stack — confirm this is actually wired up in the pinned
  dependency version before committing to the approach; don't assume.
- `FluidAudio` (CoreML-based VAD/diarization) is very likely
  unportable to Linux (CoreML is Apple-only) — plan to skip
  diarization/VAD for this MVP rather than trying to port it.
- CPU fallback is required: if Vulkan/ROCm isn't available at runtime,
  transcription must still work (slower) rather than fail.

## 3. Implementation & Verification Plan

- Canary-first (per `docs/Canary.md`): before wiring a full
  `transcribe` subcommand, write the smallest possible probe that
  loads a whisper model and runs one inference via
  `transcribe-cpp-swift` on Linux, and confirms in logs whether it
  actually executed on GPU or fell back to CPU.
- CLI subcommand: `fluidvoice-linux transcribe --in out.wav`, logic in
  `FluidVoiceLinuxCLICore` per the executable/library split described
  in `docs/SwiftLinux.md` §3.
- Verify for real: transcribe the Phase 3 WAV, confirm correct text
  output, and confirm (via logs or a GPU utilization check, e.g.
  `radeontop`/`rocm-smi` if applicable) that the AMD iGPU path was
  actually exercised, not silently running on CPU.
- Update `docs/SwiftLinux.md`/`docs/LINUX_SETUP.md` with whatever
  Vulkan/ROCm runtime packages turn out to be required
  (`mesa-vulkan-drivers`, `vulkan-tools`, etc. — verify exact names).
