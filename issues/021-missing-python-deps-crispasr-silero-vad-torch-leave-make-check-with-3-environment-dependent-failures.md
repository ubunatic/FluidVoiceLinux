# 021 — Missing Python deps (crispasr/silero_vad/torch) leave make check with 3 environment-dependent failures

**Status**: Open
**Priority**: P3 (Low)
**Severity**: Minor
**Category**: Infrastructure
**Related**: `issues/020-per-test-and-test-suite-timeouts-to-prevent-silent-hangs-swift-test-make-check.md` (failures discovered while verifying its `make check` baseline), `docs/LINUX_SETUP.md`, `Tests/FluidVoiceLinuxCLITests/ConcatenatedAudioDictationTests.swift`, `Tests/FluidVoiceLinuxCLITests/VoiceActivityDetectorTests.swift`, `Makefile`

---

## 1. Problem & Motivation

`make check` on a fresh dev box currently completes with 3 pre-existing failures out of 61 tests, all caused by missing Python packages rather than code defects:

- `ConcatenatedAudioDictationTests.testCohereTranscriptionOn60sAudio` — fails with a `crispasr` `ImportError`.
- `ConcatenatedAudioDictationTests.testParakeetTranscriptionOn60sAudio` — also fails with a `crispasr` `ImportError` (see the oddity noted in §3 below).
- `VoiceActivityDetectorTests.testSileroVADOnRealAudioSample` — fails with a `silero_vad`/`torch` `ImportError`.

These were flagged as out-of-scope while implementing/verifying issue 020 (per-test/suite timeouts), which explicitly did not touch this. `docs/LINUX_SETUP.md` documents the `crispasr` runtime architecture (§"Cohere Transcribe backend") but **no install step for it, `silero_vad`, or `torch` exists anywhere** — not in `docs/LINUX_SETUP.md`, not in the `Makefile` (`apt-deps`/`dnf-deps` only install the Swift toolchain + C build deps), not in any `scripts/`. So these are dev-environment setup gaps, not a regression.

The user's ask is explicitly either/or — this ticket should scope both options, not pick one:

> add deps pull target for crispasr/silero_vad/torch to make test suite clean OR remove the deps if not needed and disable the tests

## 2. Current State (investigated this session)

- `Makefile` targets: `apt-deps`/`dnf-deps` install the Swift toolchain and C build deps (ALSA, whisper/ggml headers) only — no Python/pip step of any kind exists in the repo.
- `docs/LINUX_SETUP.md` §"Cohere Transcribe backend: Conformer GGUF via `crispasr`" documents that Cohere/Parakeet transcription is "Managed via `crispasr` Python/ggml worker" and gives CLI usage, but has no "how to install `crispasr`" section.
- No mention of `silero_vad` or `torch` anywhere in `docs/`.
- All 3 failing tests already guard on model-file presence before running (`guard FileManager.default.fileExists(atPath: ...) else { return }`), so they're not unconditionally exercising the backend — the failure only happens when the model file *is* present but the Python worker's import fails. This means these tests are meant to run as real integration checks on a fully-provisioned box, not to be skipped outright when models are absent.

## 3. Oddity worth investigating (found during triage, not yet root-caused)

`testParakeetTranscriptionOn60sAudio` (in `ConcatenatedAudioDictationTests.swift`) fails with a **`crispasr`** ImportError — the same error as the Cohere test — rather than a Parakeet/silero-flavored one. Reading the test body: it resolves a Parakeet model path via `ModelPathResolver.resolveParakeet(...)`, guards on that file's existence, then calls `CohereTranscriber.transcribe(...)` (not a Parakeet-specific transcriber) with that path. This looks like it may be a copy-paste bug in the test itself (Parakeet test invoking the Cohere transcriber), separate from the missing-deps problem — worth a quick look when this ticket is worked, but out of scope to fix here without further investigation of whether `CohereTranscriber` is intentionally shared across backends.

## 4. Proposal & Scope — pick one before implementing

### Option A — add a deps-pull target

- Add a `Makefile` target (e.g. `python-deps` or fold into `apt-deps`) that creates/uses a venv and `pip install`s `crispasr`, `silero-vad`, `torch` (CPU wheel — `torch` GPU wheels are large; confirm CPU-only is sufficient for this repo's use, matching the existing "CPU with Conformer accuracy" performance note in `docs/LINUX_SETUP.md`).
- Document the new target in `docs/LINUX_SETUP.md` next to the existing `crispasr` runtime section.
- Verify `make check` goes fully green (0 pre-existing failures) after running it on a clean box or fresh container.

### Option B — remove/disable if not needed

- If Cohere/Parakeet transcription and Silero VAD are not required for this repo's near-term roadmap (check `docs/LINUX_MIGRATION_BRANCH_PLAN.md` for current phase/backend priorities before deciding), mark the 3 tests as intentionally skipped (e.g. `throw XCTSkip("requires crispasr/silero_vad/torch — see issue 021")`) instead of letting them fail, and note in `docs/LINUX_SETUP.md` that these backends are optional/unsupported without manual Python setup.
- This does not require removing the backend code itself, only decoupling `make check`'s "clean" bar from an optional runtime dependency.

## 5. Acceptance Criteria

- [ ] One of Option A or Option B is chosen and implemented (not both).
- [ ] `make check` completes with 0 unexplained failures (either genuinely 0 failures under Option A, or explicit skips with a clear reason under Option B — not silent `guard ... return` early-outs, which look identical to "nothing to test" in output).
- [ ] `docs/LINUX_SETUP.md` reflects whichever choice was made (install steps, or a documented "optional, unsupported without manual setup" note).
- [ ] The `testParakeetTranscriptionOn60sAudio` / `CohereTranscriber` oddity (§3) is at least looked at and either fixed or explicitly noted as intentional with a one-line comment in the test file.

## 6. Verification

- Fresh `make check` run after the change, comparing failure count against this ticket's baseline (61 tests, 3 pre-existing failures, ~2s wall time on a warm build).
