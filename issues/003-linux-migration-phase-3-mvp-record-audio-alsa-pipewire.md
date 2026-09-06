# 003 — Linux migration Phase 3: MVP record audio (ALSA/PipeWire)

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Feature

---

## 1. Problem & Motivation

Phase 3 of `docs/LINUX_MIGRATION_BRANCH_PLAN.md`. The canary (issue 002,
closed) proved the Linux CLI builds and runs cleanly with zero macOS
dependencies. This ticket is the first real capability: "I can record
audio" on Linux, replacing the macOS-only `CoreAudioCaptureSupport`
(CoreAudio, `Sources/CoreAudioCaptureSupport/**` — do not touch, it
stays macOS-only and gated out per Phase 0).

## 2. Technical Specification / Findings

- Before writing this ticket's plan doc content in stone, read
  `docs/SwiftLinux.md` — it captures the Package.swift platform-gating
  pattern, the executable/library testability split, and the
  `Package.resolved` churn gotcha that will all apply here.
- `libasound2-dev` (Debian/Ubuntu) / `alsa-lib-devel` (Fedora) are
  already installed by `make apt-deps`/`make dnf-deps` (added
  forward-looking in issue 001) — confirm they're sufficient, or note
  what's missing (e.g. PipeWire client headers) and update
  `docs/LINUX_SETUP.md` + the Makefile's dep lists accordingly.
- Decide ALSA (`libasound`) vs. PipeWire/PulseAudio client API — ALSA
  is the lower-level, more universally-available option and mirrors
  the existing `CoreAudioCaptureSupport` C-interop pattern most
  directly (a C target with a `module.modulemap`, similar structure);
  PipeWire is more "modern Linux desktop" but higher-level and more
  distro-dependent. Canary-first: probe whichever you pick with a tiny
  standalone capture-to-buffer test before building the full feature.

## 3. Implementation & Verification Plan

- New C-interop target (e.g. `Sources/LinuxAudioCaptureSupport`),
  mirroring `Sources/CoreAudioCaptureSupport`'s structure, gated into
  the Linux `#else` branch of `Package.swift`.
- CLI subcommand: `fluidvoice-linux record --seconds N --out out.wav`
  (put subcommand logic in `FluidVoiceLinuxCLICore` per the
  executable/library split in `docs/SwiftLinux.md` §3, so it's
  testable without spawning a real audio device in unit tests).
- Add a unit test for the WAV-header/format-writing logic that doesn't
  require real hardware; if a real-device smoke test is added, keep it
  separate and clearly marked as requiring an actual audio input
  device (not part of `make test`'s default run).
- Verify for real: `make build && make run -- record --seconds 3 --out
  /tmp/test.wav` on real hardware, confirm the WAV is playable
  (`aplay`/`ffprobe`) with correct sample rate/channel count.
- Document the ALSA-vs-PipeWire decision and any new dependency in
  `docs/LINUX_SETUP.md`, mirroring the toolchain-decision writeup
  already there from issue 001.
