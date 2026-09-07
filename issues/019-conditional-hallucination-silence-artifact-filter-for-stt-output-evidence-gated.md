# 019 — Conditional hallucination/silence-artifact filter for STT output (evidence-gated)

**Status**: Open
**Priority**: P3 (Low)
**Severity**: Minor
**Category**: Enhancement
**Related**: `issues/018-adopt-streaming-vad-typing-techniques-from-voxi-linux-dictation-project.md` (section 2.2, voxi's `feedback.IsSilenceArtifact` acceptance-gate finding), `Sources/FluidVoiceLinuxCLICore/WhisperTranscriber.swift`, `Sources/FluidVoiceLinuxCLICore/CohereTranscriber.swift`, `Sources/FluidVoiceLinuxCLICore/DictateCommand.swift`, `docs/Canary.md`

---

## 1. Problem & Motivation

Whisper models — especially variants trained/fine-tuned on noisy, YouTube-style scraped audio — are documented to hallucinate on silence or low-SNR input: emitting stock captions or filler like "Thanks for watching", "Subscribe", "you", or repeated phrases, instead of correctly recognizing there is no real speech. Issue 018 found that the sibling project `voxi` (same author) already runs a multi-stage acceptance gate before typing output, including a dedicated `feedback.IsSilenceArtifact` hallucination filter — something FluidVoiceLinux currently has no equivalent of, in any of its STT engine paths (`WhisperTranscriber.swift`, `CohereTranscriber.swift`, and the Parakeet/Nemotron paths wired up in `DictateCommand.swift`).

This ticket is explicitly **not** "fix this now." FluidVoiceLinux is actively moving toward newer/better engines (Parakeet TDT v3, Nemotron Speech 3.5, newer Whisper variants) that are plausibly less prone to this failure mode than the older YouTube-trained Whisper checkpoints that motivated voxi's filter. The ask is to have a ticket ready to pick up cheaply **if and when evidence shows our currently-configured engine(s) still exhibit this behavior** — not to build speculative filtering infrastructure against a problem that may not materialize with the new models.

## 2. Proposal & Scope

Per this repo's canary-first convention (`docs/Canary.md`: probe external mechanisms before building features on them), this ticket proceeds in two gated steps. **Do not start Step 2 until Step 1's canary shows the problem is real for our current engine configuration.**

### Step 1 — Canary/evaluation (required first)
- Run representative silence and low-SNR test audio (e.g. a few seconds of near-silence, room tone, or quiet background noise) through each currently-configured STT engine (Whisper, Cohere Transcribe, Parakeet, Nemotron) via the existing `record`/`transcribe`/`dictate` CLI paths.
- Record what each engine actually outputs on that input: correct empty/near-empty transcript, or a hallucinated stock phrase/repeated n-gram.
- If none of the currently-used engines exhibit the issue: close this ticket as "not needed," noting the canary result and date, so future re-evaluation (e.g. after adopting a different model) knows this was checked.

### Step 2 — Filter (only if Step 1 shows a real, reproducible issue)
Build the **simplest filter that delivers good value** — explicitly do not scope this into ML-based/confidence-model hallucination detection. Candidates, in order of simplicity:
- Known stock-phrase blocklist (exact/near-exact match on the small set of documented Whisper hallucination strings, e.g. "thank you", "thanks for watching", "subscribe", bare "you").
- Repeated-phrase/n-gram detection (reject or truncate output that is the same short phrase repeated back-to-back beyond a small threshold).
- If available cheaply from the engine, a confidence/no-speech-probability gate (e.g. Whisper's `no_speech_prob`) to suppress output below a threshold, combined with the existing VAD silence/energy gate.

Wire the accepted filter into the shared acceptance path before output is typed/copied (mirroring voxi's non-empty + stop-word + hallucination multi-stage gate from issue 018, section 2.2), not duplicated per-engine.

## 3. Acceptance Criteria

- [ ] Step 1 canary executed and its outcome (pass/fail per engine, with example input/output) recorded in this ticket or a linked note before any filter code is written.
- [ ] If Step 1 shows no reproducible hallucination on current engines: ticket closed with the canary result as the resolution, no filter code required.
- [ ] If Step 1 shows a reproducible issue: a simple filter (blocklist and/or repeated-n-gram and/or confidence gate — no heavier ML-based detection) is implemented, applied uniformly across engines at the output-acceptance layer, and demonstrably suppresses the reproduced hallucination case(s) from Step 1 without suppressing legitimate short transcripts.
- [ ] No regression to legitimate short/quiet-but-real speech being incorrectly filtered (verify against existing integration test audio from issue 015).

## 4. Verification Plan

- Step 1 is itself the verification gate — a manual/scripted run of each engine against silence/low-SNR test clips, with actual output captured and compared against expected (empty/near-empty).
- If Step 2 proceeds: add or extend an automated test (alongside issue 015's integration tests) asserting the filter suppresses the specific reproduced hallucinated string(s)/pattern(s) and does not alter output for the existing >=60s real-speech test audio.
