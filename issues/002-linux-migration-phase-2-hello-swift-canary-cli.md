# 002 — Linux migration Phase 2: hello swift canary CLI

**Status**: Closed — resolved in `0f1f585`
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

## 4. Resolution

Resolved in commit `0f1f585`.

- `Sources/FluidVoiceLinuxCLICore/Banner.swift` (new library target,
  Linux-only): `FluidVoiceLinuxCLIBanner` holds `programName`
  (`"FluidVoiceLinuxCLI"`) and `version`
  (`"0.1.0-linux-canary"` placeholder) and a `banner()` function that
  builds the hello-swift banner using
  `ProcessInfo.processInfo.operatingSystemVersionString` (live
  platform info, not a hardcoded string).
- `Sources/FluidVoiceLinuxCLI/main.swift`: now a single-line
  entrypoint, `print(FluidVoiceLinuxCLIBanner.banner())` — no
  subcommand/argument-parsing framework (that's Phase 3). No
  macOS-only target or dependency referenced.
- `Package.swift`'s Linux `#else` branch gained the
  `FluidVoiceLinuxCLICore` library target, the `FluidVoiceLinuxCLI`
  executable target now depending on it, and a new
  `FluidVoiceLinuxCLITests` test target depending on
  `FluidVoiceLinuxCLICore`.
- `Tests/FluidVoiceLinuxCLITests/FluidVoiceLinuxCLIBannerTests.swift`:
  first Linux-only test target, two real assertions — the banner
  contains the program name/version, and it contains the live
  `ProcessInfo` OS version string (regression guard against silently
  reverting to a hardcoded platform string).
- No `Makefile` change was needed: `check`/`test` already ran
  `swift test` unconditionally with a graceful no-op fallback; it now
  runs the real suite.
- `Package.resolved` was touched by `swift build`/`swift test`
  re-resolving the Linux-only (empty) dependency graph, exactly as
  seen in issue 001; restored via `git checkout --` before committing
  so macOS-pinned dependency versions are untouched.
- Verified for real on this box (`swiftlang` 6.1.3 via apt):
  - `make build && make run` →
    ```
    FluidVoiceLinuxCLI v0.1.0-linux-canary — hello swift
    Running on: Ubuntu 26.04.1 LTS
    ```
  - `make test` → built and ran the new suite for real:
    ```
    Test Suite 'FluidVoiceLinuxCLIBannerTests' started ...
    Test Case 'FluidVoiceLinuxCLIBannerTests.testBannerContainsProgramNameAndVersion' passed (0.001 seconds)
    Test Case 'FluidVoiceLinuxCLIBannerTests.testBannerIncludesLiveOSVersionInfo' passed (0.0 seconds)
    Test Suite 'FluidVoiceLinuxCLIBannerTests' passed at 2026-09-06 23:19:36.034
        Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
    ```
- `docs/LINUX_MIGRATION_BRANCH_PLAN.md` was checked for a per-phase
  status mechanism (checkboxes, a status line per phase, etc.) —
  it has none; left as-is per the ticket's own instruction not to
  invent one. This ticket file is the source of truth for Phase 2
  status.
- Out of scope (per ticket, untouched): `Sources/Fluid/**`,
  `Sources/CoreAudioCaptureSupport/**`, `.github/workflows/**`,
  `build.sh`, and Phase 3's subcommand/argument-parsing framework.
