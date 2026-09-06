# 007 — Default whisper model path is CWD-relative, breaks when installed

**Status**: In Progress
**Priority**: P3 (Low)
**Severity**: Minor
**Category**: Bug

---

## 1. Problem & Motivation

`TranscribeCommand.defaultModelPath` (`Sources/FluidVoiceLinuxCLICore/
TranscribeCommand.swift`) is the literal string `"models/ggml-base.en.bin"`,
resolved relative to the process's current working directory. This works
fine when running via `make run` from the repo root (issue 004's
verification), but breaks as soon as the binary is used the way `make
install` (issue 001) actually intends it to be used: installed to
`~/.local/bin/FluidVoiceLinuxCLI` and invoked from an arbitrary directory
with no `--model` flag. Confirmed live: after `make install`,
`FluidVoiceLinuxCLI` is correctly on `PATH`, but running `transcribe`
from outside the repo without `--model` fails to find the model file,
since `models/` doesn't exist relative to wherever the user happens to be.

## 2. Technical Specification / Findings

- Repo-relative `models/ggml-base.en.bin` (gitignored, see issue 004's
  resolution) is the right place for it during development, but a
  standalone installed binary should default to a real per-user
  location, not implicitly depend on being run from a specific
  directory.
- Reasonable candidates: `$XDG_DATA_HOME/fluidvoice/models/` (falling
  back to `~/.local/share/fluidvoice/models/` per the XDG base
  directory spec) or, to match the sample-storage convention already
  established this session (`~/.config/fluidvoice/dev/samples/`),
  `~/.config/fluidvoice/models/`. Pick one and be consistent — check if
  `Sources/Fluid/Persistence/**` (the macOS app's own settings/data
  storage) already has a project convention for where FluidVoice keeps
  its own data on the user's machine, and mirror it if so, rather than
  inventing an unrelated new location.
- Should still fall back to `models/ggml-base.en.bin` (repo-relative)
  if present, to avoid breaking the existing `make run`-from-repo-root
  workflow used throughout issues 001-004's verification.

## 3. Implementation & Verification Plan

- Change `TranscribeCommand.defaultModelPath` resolution to a small
  function trying, in order: (1) explicit `--model` flag (unchanged),
  (2) repo-relative `models/ggml-base.en.bin` if it exists (dev
  convenience, unchanged behavior for `make run`), (3) the chosen
  per-user data directory. Keep this logic pure/testable per the
  existing `docs/SwiftLinux.md` §3 executable/library split — no
  filesystem access needed to unit-test the *ordering* of candidate
  paths, only to confirm which one currently exists.
- Add a unit test for the path-resolution order (using injectable
  "does this path exist" / "what is $XDG_DATA_HOME" checks rather than
  real filesystem/env state, so it's deterministic in `make test`).
- Verify for real: `make install`, then from a directory outside the
  repo (e.g. `cd /tmp && FluidVoiceLinuxCLI transcribe --in
  ~/.config/fluidvoice/dev/samples/test.wav`) with the model placed in
  the new default location and no `models/` directory in `/tmp`,
  confirm it finds the model and transcribes correctly.
- Update `docs/LINUX_SETUP.md`/any user-facing help text
  (`transcribe --help` if it exists) to document the new default
  location.
