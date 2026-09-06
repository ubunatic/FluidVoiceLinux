# 002 — Linux migration Phase 2: hello swift canary CLI

**Status**: In Progress
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Infrastructure

---

## 1. Problem & Motivation

Phase 2 of `docs/LINUX_MIGRATION_BRANCH_PLAN.md`: the canary milestone.
`FluidVoiceLinuxCLI` currently exists only as a Phase 0 compile-gating
stub (`print("stub")`, see issue 001). This ticket turns it into the
actual canary deliverable — the go/no-go gate before investing in
Phase 3 (audio capture).

## 2. Technical Specification / Findings

- Target already exists: `Sources/FluidVoiceLinuxCLI/main.swift`,
  gated Linux-only in `Package.swift` via `#if os(macOS)`/`#else`.
- `make build`/`make run` already work end-to-end on this box
  (`swiftlang` 6.1.3 via apt, verified in issue 001).
- No macOS-only dependency (`AppUpdater`, `FluidAudio`, `PromiseKit`,
  `DynamicNotchKit`, `transcribe-cpp-swift`, `CoreAudioCaptureSupport`)
  may be referenced by this target — that's the whole point of the
  canary: prove a clean, dependency-free Linux CLI compiles and runs.

## 3. Implementation & Verification Plan

- Replace the stub with a real "hello swift" banner: program name,
  version placeholder, and confirmation it's running as a Linux CLI
  (e.g. platform/OS info via `Foundation`/`Glibc`, not a hardcoded
  string only).
- Keep it a single, simple entrypoint — no subcommand framework yet
  (that starts in Phase 3 with `record`/`transcribe`).
- Verify with `make build && make run` and, if a trivial assertion is
  feasible, add a first Linux-only test target under
  `Tests/FluidVoiceLinuxCLITests` wired into `Package.swift` alongside
  the `#else` branch, run via `make check`/`make test`.
- Update `docs/LINUX_MIGRATION_BRANCH_PLAN.md`'s Phase 2 status if the
  plan doc tracks per-phase completion (check first; don't invent a
  status format the doc doesn't already have).
