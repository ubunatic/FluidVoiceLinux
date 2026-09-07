# 018 — Adopt streaming/VAD/typing techniques from voxi (Linux dictation project)

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Enhancement
**Related**: `issues/017-continuous-streaming-dictation-loop-in-dictate-subcommand-without-premature-cutoff.md`, `Sources/FluidVoiceLinuxCLICore/AudioRecorder.swift`, `Sources/FluidVoiceLinuxCLICore/VoiceActivityDetector.swift`, `Sources/FluidVoiceLinuxCLICore/TextOutputDriver.swift`, `Sources/FluidVoiceLinuxCLICore/DictateCommand.swift`

---

## 1. Problem & Motivation

`codeberg.org/ubunatic/voxi` is another Linux-focused, privacy-first, continuous-streaming voice dictation project by the same author (Go, AGPL-3.0). It solves almost exactly the problem in issue 017 (continuous streaming dictation with VAD-based utterance segmentation) and has apparently already shipped and iterated on it (references an "issue 057 fix" in its own history). This ticket captures concrete, citable techniques worth reviewing against FluidVoiceLinux's Swift implementation — not a suggestion to depend on or port voxi wholesale (different language/runtime, GPL-family license consideration for any literal code reuse).

## 2. Findings

### 2.1 Segmentation parameters (`internal/eager/eager.go`, `internal/audio/audio.go`)
voxi's `audio.NewAudioSegmenter` uses a small, named parameter struct with concrete defaults, all tuned from real usage:
- `ThresholdRMS` — energy threshold, default 150 (its unit scale differs from ours; not directly transferable as a number, but confirms energy-RMS gating is workable at this granularity)
- `SilenceMs` — post-speech silence to finalize an utterance, default **800ms**
- `PreRollMs` — audio *kept before* detected speech onset, default **500ms**, explicitly to "preserve initial phonemes"
- `MinSpeechMs` — minimum utterance duration, default 200ms
- `MaxWindowMs` — a hard ceiling on utterance length, default **8000ms**, to bound worst-case transcription latency/memory when a user talks continuously without pausing

Frame size is 20ms (`frameBytes = sampleRate*frameMs/1000*2`), fed via `segmenter.ProcessFrame(buf) -> (candidate, speechStarted, isSpeaking)`, plus an explicit `segmenter.Flush()` called on context cancellation to capture trailing in-progress speech before shutdown.

**Comparison to our current `EnergyVoiceActivityDetector`** (`VoiceActivityDetector.swift`): we already have `minSpeechDurationMs` (250), `minSilenceDurationMs` (300), `speechPadMs` (100 — pre/post both), `frameSizeMs` (30) as a batch/offline detector over a full sample array. We have **no `MaxWindowMs` cap** and no live streaming `processFrame`-style incremental API — issue 017 needs to add exactly that. Recommend issue 017's incremental VAD state machine adopt an explicit max-utterance-duration cap (voxi's 8000ms is a reasonable starting point) so a user who never pauses doesn't grow one unbounded buffer/transcription job. Our `minSilenceDurationMs` of 300 is more aggressive than voxi's 800ms silence-to-finalize; worth a quick empirical check during 017's verification pass on whether 300ms clips words versus voxi's more conservative 800ms.

### 2.2 Pipeline architecture (`internal/eager/eager.go`)
- Bounded job channel (`chan TranscribeJob, 10`) decouples the audio/VAD loop from a single sequential transcription worker goroutine — avoids spawning unbounded concurrent STT processes while still not blocking capture.
- Each transcription subprocess call is wrapped in its own timeout (`context.WithTimeout`, 30s) so a stalled model invocation can't wedge the pipeline or leak a zombie process — directly applicable to issue 017's requirement for clean resource cleanup.
- `eagerSessionManager.Stop()` is explicitly documented to wait only for audio capture to stop (subprocess killed/reaped), *not* for pending transcription to drain — i.e. SIGINT/stop tears down the capture handle immediately and lets in-flight transcriptions finish or be abandoned independently, rather than blocking shutdown on STT. Issue 017's acceptance criteria call for "clean termination... on SIGINT" — worth being explicit in the implementation about which of these two voxi shutdown semantics we want (immediate capture teardown vs. waiting on the last transcription), since conflating them was apparently itself a past bug in voxi.
- A multi-stage acceptance gate before typing output: transcript must be non-empty, pass a stop-word/safety check (`asr.IsSafeToType`), and pass a Whisper-hallucination/silence-artifact filter (`feedback.IsSilenceArtifact`) before being emitted. We don't currently filter Whisper's well-known silence-hallucination artifacts (e.g. "Thank you.", "you" on silent/near-silent input) anywhere in our pipeline — worth a small follow-up ticket if this turns out to be an issue with our energy-VAD + Whisper/Parakeet combination, since energy-based VAD alone won't reliably prevent it on quiet/low-SNR segments.

### 2.3 Typing/output driver (`internal/typing/typing.go`)
- Two-tier keystroke injection: prefers a persistent `dotool` daemon via named pipe (`dotoolc`) for lower per-keystroke latency, falls back to direct `dotool` subprocess invocation if the daemon isn't running. Our `TextOutputDriver.typeText` (`TextOutputDriver.swift:96`) always spawns a fresh `wtype`/`xdotool`/`ydotool` process per call — fine for our current one-shot `record`→`transcribe`→type flow, but for issue 017's incremental per-utterance typing (potentially many chunks per session), a daemon-mode fallback pattern for `ydotool` (which does have a daemon, `ydotoold`) could reduce per-chunk process-spawn latency. Not blocking for 017; flagging as a possible follow-up if per-chunk typing latency proves noticeable.
- Explicit **physical modifier gating**: before injecting keystrokes, voxi reads live kernel evdev state and waits up to 5s for the user to release any held Ctrl/Alt/Super before typing, to avoid accidentally triggering a hotkey combo mid-dictation. We have no equivalent safety check. Low priority (evdev access needs permissions we may not want to require), but worth a note if we ever see reports of dictation triggering hotkeys.
- No XKB layout-specific handling — it relies entirely on `dotool`/`wtype` to interpret raw text, same as our current approach. Nothing to adopt here; confirms our approach is not missing something voxi solved.

### 2.4 Not applicable / no action
- voxi's GNOME Shell extension, terminal monitoring dashboard, systemd units, and model-spec/hallucination-filter spec format are Go/GNOME-specific tooling with no direct Swift equivalent to port; noted for awareness only, not proposed as work here.

## 3. Recommendation

- **For issue 017 (in flight as of this ticket)**: consider adding an explicit max-utterance-duration cap to the incremental VAD segmenter (informational pointer only — 017 owns its own scope/implementation decisions).
- **New follow-up candidates** (not created as separate tickets yet, listed here for future triage):
  1. Evaluate whether our Whisper/Parakeet output needs a silence-hallucination filter similar to voxi's `feedback.IsSilenceArtifact`.
  2. Consider a persistent-daemon fallback for `ydotool` typing if per-chunk typing latency is observed to be a problem after 017 ships.
- No license-encumbered code was copied; this ticket documents techniques/parameters observed in voxi's public repo, described in our own words, for independent reimplementation in Swift.

## 4. Verification Plan

This is a research ticket, not a code change — no build/test verification applies. Close once findings have been reviewed (and any accepted follow-ups filed as their own tickets).
