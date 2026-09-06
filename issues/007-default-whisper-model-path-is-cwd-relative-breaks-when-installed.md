# 007 — Default whisper model path is CWD-relative, breaks when installed

**Status**: Closed — resolved in a43c481
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

## 4. Resolution

Went with `$XDG_DATA_HOME/fluidvoice/models/` (falling back to
`~/.local/share/fluidvoice/models/` when `$XDG_DATA_HOME` is unset), per
the findings section's reasoning: a downloaded model is application-support
data, not disposable cache, and this mirrors the macOS app's own
`Sources/Fluid/Persistence/**` use of `.applicationSupportDirectory` for
persistent data vs. `.cachesDirectory` for cache. The unrelated
`~/.config/fluidvoice/dev/samples/` convention (informal dev-only WAV
storage from earlier this session) was not treated as precedent — it's
not XDG-correct for config either and isn't referenced anywhere in code.

**Implementation**:
- `Sources/FluidVoiceLinuxCLICore/ModelPathResolver.swift` (new) —
  `ModelPathResolver.resolve(explicit:fileExists:xdgDataHome:home:)`, a
  pure function taking injectable file-existence and env-lookup closures
  (docs/SwiftLinux.md §3), trying in order: (1) `explicit` (the `--model`
  flag, if given), (2) repo-relative `models/ggml-base.en.bin` if
  `fileExists` says it's there, (3) `$XDG_DATA_HOME/fluidvoice/models/
  ggml-base.en.bin`, else `$HOME/.local/share/fluidvoice/models/
  ggml-base.en.bin`, else (no `$HOME` either — should not happen in
  practice) the same suffix as a bare relative path.
- `Sources/FluidVoiceLinuxCLICore/TranscribeCommand.swift` —
  `TranscribeOptions.modelPath` changed from a non-optional `String`
  defaulting to the literal path, to an optional `String?` defaulting to
  `nil` ("not explicit"). `parseArguments` stays pure and untouched
  otherwise. `TranscribeCommand.run` now calls `ModelPathResolver.resolve`
  with the real `FileManager.default.fileExists`, `ProcessInfo`'s
  `XDG_DATA_HOME`/`HOME` env vars, immediately before using the model
  path, so the resolution only happens where real filesystem/env access
  already occurs (matches the existing `parseArguments`/`run` split).
  `TranscribeOptions.defaultModelPath` is kept (now aliasing
  `ModelPathResolver.repoRelativeModelPath`) for any external references
  to the repo-relative dev default.

**Tests** (`Tests/FluidVoiceLinuxCLITests/`):
- `ModelPathResolutionTests.swift` (new) — 6 cases covering all three
  branches deterministically via injected closures: explicit flag wins
  even when the repo-relative file "exists", repo-relative wins over the
  XDG default when it exists, XDG default used when repo-relative is
  missing, `$HOME`-based fallback used when `$XDG_DATA_HOME` is unset or
  empty, and a last-resort relative path when neither is set.
- `TranscribeCommandArgumentTests.swift` — updated the "required argument
  only" case to assert `options.modelPath == nil` instead of the old
  literal-default equality, reflecting that resolution now happens in
  `run`, not `parseArguments`.
- `make test`: all 27 tests pass (21 prior + 6 new `ModelPathResolutionTests`).

**Real verification, installed binary from outside the repo** (this box):
```sh
mkdir -p ~/.local/share/fluidvoice/models
cp /home/uwe/projects/FluidVoiceLinux/models/ggml-base.en.bin \
   ~/.local/share/fluidvoice/models/ggml-base.en.bin
make install   # -> ~/.local/bin/FluidVoiceLinuxCLI
cd /tmp        # no models/ dir here
~/.local/bin/FluidVoiceLinuxCLI transcribe --in ~/.config/fluidvoice/dev/samples/test.wav
```
Output (no `--model` flag passed):
```
whisper_init_from_file_with_params_no_state: loading model from '/home/uwe/.local/share/fluidvoice/models/ggml-base.en.bin'
...
Transcribing '/home/uwe/.config/fluidvoice/dev/samples/test.wav' (160000 samples @ 16000 Hz) with model '/home/uwe/.local/share/fluidvoice/models/ggml-base.en.bin' (backend: gpu-if-available)
Loaded model in 0.114s, ran inference in 0.241s
A, B, C, D, E, F, G, H, I, J, K, L, M, N.
```
Confirms branch (3) resolved correctly and matches the ground truth
("a b c d e f g h i j k l m n" from `test.jsonl`).

**Real verification, repo-root `make run` unaffected (regression check)**:
```sh
cd /home/uwe/projects/FluidVoiceLinux
make run ARGS="transcribe --in ~/.config/fluidvoice/dev/samples/test.wav"
```
Output:
```
Transcribing '/home/uwe/.config/fluidvoice/dev/samples/test.wav' (160000 samples @ 16000 Hz) with model 'models/ggml-base.en.bin' (backend: gpu-if-available)
Loaded model in 0.105s, ran inference in 0.227s
A, B, C, D, E, F, G, H, I, J, K, L, M, N.
```
Confirms branch (2), repo-relative `models/ggml-base.en.bin`, still wins
when present — the issues 001-004 dev workflow is unchanged.

`Package.resolved` was checked after each Linux `swift build`/`test`/
`install` invocation and reverted with `git checkout -- Package.resolved`
per docs/SwiftLinux.md's gotcha — no macOS pin drift committed.

`docs/LINUX_SETUP.md` updated with the new default lookup order and a
copy-paste snippet for placing the model at the XDG default location.

Both workflows verified for real end to end — closing.
