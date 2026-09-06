# 001 — Linux migration Phase 0+1: macOS gating, Swift Makefile, apt/dnf deps

**Status**: Closed — resolved in 9b114a4
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Infrastructure

---

## 1. Problem & Motivation

Second work stream: migrate FluidVoice to a headless Linux CLI (see
`docs/LINUX_MIGRATION_BRANCH_PLAN.md`). Phase 0 (disable macOS-only
targets/tests) and Phase 1 (Swift-flavored Makefile for fast build/
install) are the first concrete steps before the "hello swift" canary.

## 2. Technical Specification / Findings

- 144 Swift files in `Sources/Fluid/**`, 77 import AppKit/SwiftUI/Cocoa/
  CoreAudio/AVFoundation — cannot and should not be built on Linux.
- `harnez init` already scaffolded a Go-flavored `Makefile` at repo root
  that needs adapting to Swift per `docs/Make.md` (⚙️/🤖 sentinels).
- `swift` is not installed on this dev machine yet (Ubuntu 26.04
  "resolute"). apt-based install vs. vendored toolchain in `vendor/` is
  an open decision for whichever gives a working, reasonably current
  Swift toolchain.

## 3. Implementation & Verification Plan

- Gate macOS-only targets/deps out of the Linux build graph in
  `Package.swift` (or document why SwiftPM can't express it cleanly).
- Exclude `Tests/FluidDictationIntegrationTests` from Linux test runs.
- Rewrite `Makefile` for Swift: `help`, `preflight`, `build`, `run`,
  `install`, `check`/`test`, `clean`, plus new `apt-deps` and
  `dnf-deps` targets installing everything needed to build on Ubuntu/
  Debian and Fedora respectively.
- Decide apt-package vs. vendored-toolchain approach for `swift`
  itself; implement whichever is verified to actually work here.
- Verify for real: install a toolchain, run `make preflight` and
  `make build` (even if `build` only compiles a stub/canary target at
  this point), don't just write the Makefile.

## 4. Resolution

Resolved in commit `9b114a4`.

- `Package.swift`: `#if os(macOS)` gates the macOS dependency list,
  `CoreAudioCaptureSupport`/`FluidVoice` targets, and
  `Tests/FluidDictationIntegrationTests` out of Linux resolve/build
  entirely — no second manifest needed. Added
  `Sources/FluidVoiceLinuxCLI/main.swift` as a Phase 0 compile-gating
  stub (`print("stub")`), Linux-only via the same `#else` branch.
- `Makefile`: rewritten for Swift per `docs/Make.md` conventions
  (`help`/`preflight`/`build`/`run`/`install`/`uninstall`/`check`/
  `test`/`clean`/`apt-deps`/`dnf-deps`).
- Toolchain decision: apt package, not vendored. Ubuntu 26.04's `swift`
  apt package is an unrelated OpenStack Swift package (`2.37.1`); the
  real Apple Swift toolchain is `swiftlang` (`6.1.3-4build1`), well
  past the `swift-tools-version: 5.9` floor. `make apt-deps` installs
  it directly; `docs/LINUX_SETUP.md` documents this and a fallback
  `vendor-swift` plan if a future distro ships an inadequate
  `swiftlang`.
- `dnf-deps` mirrors this for Fedora (`swift-lang` + `*-devel`
  packages) — plausible but **not verified** on real Fedora hardware
  (no such machine available in this session).
- Verified for real on this box: no interactive `sudo` was available
  to the agent session, so `swiftlang`/`swiftlang-dev`/`libswiftlang`
  `.deb`s were fetched with `apt-get download` (no root required) and
  extracted with `dpkg-deb -x` into a scratch dir. Against that
  extracted toolchain: `swift package resolve`, `make preflight`,
  `make build`, `make run` (prints `stub`), and `make check` (reports
  "no Linux test target yet" gracefully, per Phase 5) all passed.
  `Package.resolved` was restored via `git checkout --` after
  `swift package resolve` rewrote it for the Linux-only (empty)
  dependency graph, so the macOS-pinned dependency versions are
  untouched.
- Out of scope (per ticket): Phase 2 canary content, Phase 3/4 audio
  capture and transcription, `.github/workflows/**`, and any change to
  `Sources/Fluid/**`/`Sources/CoreAudioCaptureSupport/**`/`build.sh`.
  A real (non-extracted, sudo-installed) `apt-deps` run on this
  machine, and any Fedora verification of `dnf-deps`, are left to a
  human or a future session with interactive sudo/Fedora access.
