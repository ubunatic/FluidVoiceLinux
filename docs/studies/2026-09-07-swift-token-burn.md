# The Swift Token Burn

## 1. Header & Context

- **Date**: 2026-09-07
- **Scope**: `/fresh-sprint 017` — implement continuous streaming dictation
  (issue 017: replace `dictate`'s fixed-duration record-then-transcribe
  with real-time streaming ALSA capture + incremental VAD segmentation).
- **Starting state**: clean `main`, issue 017 open (P1/Major).
- **Goal**: one fresh subagent implements 017 end-to-end, self-verifies
  with `make check`, commits, closes the ticket.

## 2. Executive Summary

The subagent delivered a correct, independently-verified fix, but the
session cost **202k tokens / ~35 min / 103 tool calls** — almost entirely
spent chasing one bug: a `wl-copy` clipboard subprocess that inherited
stdio from its parent and stayed resident, so `swift test` blocked
forever waiting for a pipe EOF that would never arrive. Nothing in the
toolchain (no per-test timeout, no suite-level timeout) caught this; a
human had to ask "is this stuck?" 20 minutes in. The coordinator then
made it worse by intervening a second time on stale information — the
subagent had already fixed and 4x-reverified the bug — and it correctly
refused to revert based on the coordinator's say-so alone.

## 3. What Worked Well

- **Root-causing over guessing**: the subagent used `/proc/<pid>/task/*/wchan`
  to confirm the hang was a blocked pipe read, then reproduced the *same*
  hang on a stashed clean `main` before its own changes — proving the bug
  was pre-existing, not something it introduced. That's the right standard
  of evidence, not "tests pass now, ship it."
- **Coordinator diagnosis (first intervention)**: killing the zombie
  `swift-test`/`wl-copy` processes and handing the subagent a concrete
  root-cause hypothesis (pipe inheritance, not a VAD/streaming deadlock)
  saved it from re-deriving that from scratch.
- **Ticket hygiene under pressure**: despite the token burn, the subagent
  still filed/updated issue 020's checkbox correctly and left 017's status
  honest rather than padding a "done" claim.
- **Fast independent re-verification**: after the fact, confirming the fix
  cost one `make check` run (2.4s) — the eventual fix is tiny and cheap to
  validate; nearly all the cost was in *finding* it, not applying it.

## 4. Honest Post-Mortem (Failures, Bugs & Near-Misses)

- **The bug itself** (pre-existing, not introduced this session):
  `TextOutputDriver.copyToClipboard`'s `wl-copy` branch inherited the
  caller's `standardOutput`/`standardError`. `wl-copy` is designed to stay
  resident after returning (it keeps serving the Wayland selection), so
  the inherited pipe's write end never closed, and any later `swift test`
  subprocess-output capture on that pipe blocked indefinitely. Caught by:
  a human noticing 20 minutes of silence and asking; confirmed via `ps`/
  `/proc` inspection showing a zombie XCTest runner plus a live orphaned
  `wl-copy`. Fixed by: routing `wl-copy`'s stdio to `FileHandle.nullDevice`
  and explicitly `.terminate()`-ing the previous instance before starting
  a new one.
- **Coordinator near-miss #1 (self-inflicted, low-severity)**: mid-session
  the coordinator spawned a *fresh* agent to relay the diagnosis instead
  of `SendMessage`-ing the existing subagent — which would have thrown
  away all its accumulated context and duplicated work. Caught immediately
  by reviewing the tool result before the fresh agent did anything; killed
  it and sent the message to the right target instead.
- **Coordinator near-miss #2 (more serious)**: after the subagent had
  fixed the bug and reverified it 4x (including the clean-`main` repro),
  the coordinator sent a second message telling it to stop and *not*
  consider the issue resolved, based on an earlier, now-stale read of the
  process table. The subagent held its ground, cited its own `/proc`
  evidence and before/after comparison, and did not revert. Independent
  post-hoc verification (fresh `make check` run, diff review) confirmed
  the subagent was right and the coordinator's second escalation was
  wrong. No damage done — but only because the subagent pushed back
  instead of complying.
- **No damage/data loss**: all git operations were additive commits on a
  clean working tree; no force-pushes, resets, or discarded work.

## 5. Quality & Invariants Audit

| Axis | Assessment |
|---|---|
| Architecture / module separation | Clean — new `AlsaAudioStream` / `IncrementalSpeechSegmenter` / `StreamingDictationLoop` types added alongside (not replacing) the existing fixed-duration path; `record`/`transcribe` untouched. |
| Idempotency | `make check` re-run 4x post-fix with identical results (61 tests, same 3 pre-existing environment-only failures). |
| Backward compatibility | `--seconds` preserved as an optional hard cap; existing `AlsaAudioRecorder.record` API untouched. |
| Test coverage | New segmenter/streaming-loop unit tests added; clipboard fix has no dedicated regression test yet (verified by manual repro, not an automated case) — a gap. |
| Verification | Independently re-run by the coordinator post-hoc: `make check` completes in 2.4s, no hang, 0 new failures. |

## 6. Efficiency & Velocity Assessment

- 202k tokens / 103 tool calls / ~35 min for one ticket is high for a
  "lean fresh-handoff" — but the actual code diff is small; essentially
  all of the cost was diagnostic (bisecting an intermittent-looking hang
  with no timeout anywhere to bound the search).
- The single biggest cost multiplier was environmental, not agent
  behavior: **no per-test or suite-level timeout existed**, so every
  hang cost a full manual kill-and-diagnose cycle instead of failing fast
  with a stack/wchan dump. This is exactly issue 020's scope.
- Coordinator overhead added, not removed, cost here: one wasted fresh-agent
  spawn, and one incorrect stop-and-revert instruction that the subagent
  had to spend a reply defending against instead of just finishing.

## 7. Key Learnings & Evergreen Upstream

1. **Timeouts are not optional infrastructure for this stack.** A hang in
   `swift test` is currently invisible until a human notices elapsed wall
   time. Ship issue 020 (per-test + suite-level timeouts) before the next
   ticket that touches subprocess-spawning code (`Process()`, ALSA, any
   CLI shell-out) — this class of bug (child inherits a pipe, never exits)
   is a recurring Swift/Foundation footgun, not a one-off.
2. **A subagent's own fresh, cited evidence outranks the coordinator's
   stale snapshot.** When a coordinator escalation conflicts with the
   worker's already-verified state, the worker should hold its position
   and show its evidence rather than comply by default — this session is
   a concrete example where that was the correct call. Worth stating
   explicitly in `AgenticLoop.md`'s guidance for both roles.
3. **Always `SendMessage` a running subagent to continue it; never spawn
   a fresh one to "relay" something to it.** A fresh agent has zero
   context and duplicates work — this is already documented tool
   guidance, but it's easy to fumble under time pressure; this session
   is a live example to point to.
4. **Diagnostic cost belongs to the environment, not just the task.**
   Before estimating token/time budget for future Swift subprocess work
   on this repo, assume hangs are possible and expensive to diagnose
   until issue 020 lands.

## 8. File & Diff Summary

**Commits this session (chronological):**
- `92a7c73` — start issue 017 (fresh-sprint)
- `bb401fe` — file issue 018 (voxi research findings)
- `7a0ec60` — file issue 019 (conditional hallucination filter, evidence-gated)
- `385cd7d` — file issue 020 (per-test/suite timeouts)
- `7b5845c` — **feat(dictate): stream continuous ALSA capture with incremental VAD segmentation**
  (`AudioRecorder.swift`, `VoiceActivityDetector.swift`, `DictateCommand.swift`,
  `TextOutputDriver.swift` — includes the `wl-copy` stdio fix — plus new
  tests in `VoiceActivityDetectorTests.swift`)
- `672fce9` — close issue 017
- `3c429f0` — check off the wl-copy fix criterion in issue 020

**Key files touched by the implementation commit:**
- `Sources/FluidVoiceLinuxCLICore/AudioRecorder.swift` — new `AlsaAudioStream`
- `Sources/FluidVoiceLinuxCLICore/VoiceActivityDetector.swift` — new
  `IncrementalSpeechSegmenter`, `StreamingDictationLoop`
- `Sources/FluidVoiceLinuxCLICore/DictateCommand.swift` — SIGINT handling,
  continuous streaming loop, incremental transcribe/enhance/emit
- `Sources/FluidVoiceLinuxCLICore/TextOutputDriver.swift` — the actual bug fix
- `Tests/FluidVoiceLinuxCLITests/VoiceActivityDetectorTests.swift` — new
  segmenter and streaming-loop unit tests
