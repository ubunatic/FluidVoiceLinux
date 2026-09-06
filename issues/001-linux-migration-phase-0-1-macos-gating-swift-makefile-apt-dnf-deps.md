# 001 — Linux migration Phase 0+1: macOS gating, Swift Makefile, apt/dnf deps

**Status**: In Progress
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
