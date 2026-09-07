# 021 — Missing Python deps (crispasr/silero_vad/torch) leave make check with 3 environment-dependent failures

**Status**: Closed — Won't fix (Option A, deps-pull target); Option B (disable tests) implemented instead — all 3 tests now `throw XCTSkip(...)` with a reason citing this ticket. `make check`: 61 tests, 3 skipped, 0 failures. User's context: sibling Go project `voxi` now has Cohere support, reducing the case for investing further Python-dependency plumbing in this repo.
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

- [x] One of Option A or Option B is chosen and implemented (not both). — Option B: `testCohereTranscriptionOn60sAudio`, `testParakeetTranscriptionOn60sAudio` (`ConcatenatedAudioDictationTests.swift`), and `testSileroVADOnRealAudioSample` (`VoiceActivityDetectorTests.swift`) now each `throw XCTSkip(...)` unconditionally, citing this ticket.
- [x] `make check` completes with 0 unexplained failures. — Verified: 61 tests, 3 skipped, 0 failures, 1.3s.
- [ ] `docs/LINUX_SETUP.md` reflects whichever choice was made. — Not done: closing as won't-fix without doc updates since the underlying backend code/docs are unchanged (only test execution was disabled); revisit if this repo remains active.
- [ ] The `testParakeetTranscriptionOn60sAudio` / `CohereTranscriber` oddity (§3) is at least looked at and either fixed or explicitly noted as intentional. — Not investigated; left as dead weight now that the test body is a bare skip. Note for any future reopen: the pre-existing test body called `CohereTranscriber.transcribe` from the Parakeet test, which is why both tests shared the same crispasr error message.

## 6. Verification

- `make check`, warm build: `Executed 61 tests, with 3 tests skipped and 0 failures (0 unexpected) in 1.303 seconds` — matches this ticket's baseline test count exactly, now clean.

## 7. Won't-fix rationale

Closed without implementing Option A (deps-pull target) because the user's sibling Go project `voxi` recently added Cohere transcription support, reducing the value of investing further Python-dependency plumbing (crispasr/silero_vad/torch install automation) in this Swift/Linux repo. Option B (disable the tests) was implemented instead since it's a small, low-risk change that gets `make check` to a clean baseline regardless of whether this repo sees further active investment.
