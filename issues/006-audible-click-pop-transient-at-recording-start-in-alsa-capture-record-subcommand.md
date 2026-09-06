# 006 — Audible click/pop transient at recording start in ALSA capture (record subcommand)

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Moderate
**Category**: Bug

---

## 1. Problem & Motivation

Phase 3's `record` CLI subcommand (issue 003, closed) was human-verified
end-to-end on real hardware via `make run ARGS="record --seconds 10 --out
/tmp/test.wav"`, run twice. Both times the user reported: **"both
recordings start with a harsh click sound, a hardware artifact I guess
when a recording starts. I did not make any such loud sound."** The two
samples were copied to `~/.config/fluidvoice/dev/samples/` as
`test.wav`/`test.jsonl` (transcript: "a b c d e f g h i j k l m n",
individual letters) and `chunks.wav`/`chunks.jsonl` (transcript: "This is
a recording of one chunk. And another chunk", two speech chunks with a
pause and trailing silence).

An earlier, coarse check (recorded in both `.jsonl` files'
`known_artifacts` field) only looked at the first 300ms of each file,
found it to be pure digital silence (all-zero PCM), and concluded the
click was "likely an audible codec/device-open artifact on the
playback/monitor side, not a defect in the recorded WAV itself." That
check was too coarse — it never looked for a short, sharp transient
later in the first ~1.5s, and never rigorously distinguished the loudest
sample in `test.wav` (at t≈1.108s) from a natural speech onset. This
ticket redoes that analysis at sample resolution and **reverses that
conclusion**: the anomalous transient IS present in the captured PCM
data.

## 2. Technical Specification / Findings

Analyzed both WAV files sample-by-sample with Python (`wave` + `numpy`)
around t=0.7s–1.6s (16-bit mono PCM, 16000 Hz, 160000 frames/10.000s
each).

**`test.wav`** (transcript starts with spoken letter "a"):
- Samples 0–17456 (t=0–1.091s) are exact digital silence (all zero),
  confirming the earlier 300ms-only check but showing the silence
  actually extends much further, to ~1.09s.
- A transient begins at sample 17722 (t=1.1076s): `76 -> 458 -> -1032 ->
  3602 -> 9767` over samples 17722–17726 — i.e. from near-zero to the
  peak of `9767` (≈30% of full-scale int16 `32767`) in **4 samples
  (0.25ms)**. The 10%→90%-of-peak rise measured backward from the peak
  spans only **2 samples (0.125ms)**.
- The pulse then decays (with a brief polarity reversal down to `-1905`
  at t=1.110s) back to near-silence by t≈1.150s — a total pulse duration
  of roughly **45–60ms**.
- This is followed by **~210ms of renewed pure silence** (t≈1.150s to
  t≈1.360s).
- Only then does the actual spoken "a" begin, at t≈1.360–1.375s, with a
  much lower peak (~89, vs. 9767 for the pulse — two orders of magnitude
  quieter) and a smooth envelope build over ~15–20ms (`1, 2, 9, 68, 89,
  43, 45, 38, ...`), consistent with a natural vowel onset.
- Peak amplitude over the whole first 2s is the `9767` pulse, not the
  spoken letter.

**`chunks.wav`** (transcript starts with "This"):
- Same shape, shifted ~100ms later: silence through sample 19061
  (t=1.191s), then a pulse at samples 19325–19332 (t=1.208s) rising
  `-64 -> 453 -> -11 -> 553 -> -696 -> 1100 -> 8594 -> 9052` — peak
  `9052` reached from near-zero within ~7 samples (~0.44ms), still far
  faster than a vocal onset.
- Pulse decays back to silence by t≈1.245s (duration ~45–55ms), followed
  by **~265ms of renewed silence** (t≈1.245s–1.510s).
- Real speech (the spoken word "This") then begins at t≈1.510–1.520s,
  peak amplitude only ~48 at first buildup, ramping smoothly (`3, 9, 48,
  26, 23, 20, 21, ...`) — again two orders of magnitude quieter than the
  pulse and much slower to rise.

**Interpretation, explicitly caveated (nobody has listened to the
audio):**
- The pulse's rise time (2–7 samples, 0.1–0.4ms) is far faster than any
  physically plausible vowel onset — human speech onsets (this data's
  own real "a"/"This" onsets included) ramp over 15–30ms, roughly
  40–100x slower. A single-digit-sample attack followed by a decaying
  ring and a return to full silence, isolated from the real speech by a
  ~200–265ms silent gap, is the textbook shape of a click/pop transient,
  not a spoken sound.
- Both independent recordings (different days, different spoken
  content) show this same pulse shape, closely matching relative
  amplitude (~9000–9800 of 32767, i.e. ~28–30% full scale) and duration
  (~45–60ms), at a similar-but-not-identical position in the stream
  (t≈1.11s vs. t≈1.21s — roughly 100ms apart, not fixed-latency exact,
  but both consistently ~1–1.2s after `record` presumably begins
  capturing). That consistency across independent takes argues against
  it being coincidental noise in what the user said, and is consistent
  with (but does not prove) a mechanical/device-side artifact tied to
  stream start rather than something in the user's speech.
- **This reverses the earlier `known_artifacts` conclusion**: the click
  is not purely an external/playback-side artifact outside the captured
  PCM — a genuine, sharp, anomalous transient distinguishable from
  speech by its attack time and isolation is present in the recorded
  data of both files, at a consistent relative time in the first ~1.5s
  of capture (not at t=0, where the earlier 300ms-window check looked).
- What the data **cannot** tell us: whether the transient originates in
  the ALSA capture path itself (e.g. an unprimed/settling hardware
  buffer, a `snd_pcm_open`/`snd_pcm_set_params` startup transient being
  captured as real samples), or is an actual acoustic event (e.g. a
  relay/codec click from the audio hardware itself, physically picked
  up by the microphone at that moment) that ALSA faithfully captured.
  Only playback/listening (not attempted here) or a hardware-level trace
  could distinguish "artifact injected by the capture code path" from
  "artifact injected by the audio hardware but genuinely present as
  sound in the room and thus correctly captured."

`Sources/LinuxAudioCaptureSupport/LinuxAudioCaptureSupport.c` was read
as part of this investigation: `fv_alsa_capture_open` calls
`snd_pcm_open` then `snd_pcm_set_params` (which implicitly allocates
hardware/software params and calls `snd_pcm_prepare` internally) with no
explicit warm-up read or discard of initial frames; `fv_alsa_capture_read`
is a single blocking `snd_pcm_readi` per chunk with one `snd_pcm_recover`
retry on error. There is no code path today that would deliberately
discard early frames, so if the transient is a device-settling artifact
it would flow straight into the WAV output uncontested.

## 3. Implementation & Verification Plan

Because the data now shows a real, sample-resolvable anomaly (not
"assumed external"), this is scoped as a capture-path investigation, not
a documentation-only close:

1. **Try to reproduce with a discard-first-N-ms mitigation as a probe,
   not yet a committed fix**: temporarily patch `AudioRecorder.swift`
   (Swift-side, above the C shim) to discard the first ~150–200ms of
   frames read from `fv_alsa_capture_read` before appending to the
   output buffer, and re-record 2–3 new samples on the same hardware.
   If the pulse disappears at a consistent position rather than just
   shifting later, that's strong evidence it's a fixed-count
   device/driver settling transient inherent to stream start.
2. **Try `snd_pcm_prepare` + a short delay before the first real read**,
   or reading and discarding one throwaway period's worth of frames
   right after `snd_pcm_set_params` succeeds in
   `LinuxAudioCaptureSupport.c`, as an alternative/complementary probe —
   isolates whether the transient is emitted during device
   startup/settling versus something continuously present that a fixed
   discard would just delay.
3. **If a fix reliably removes the pulse**: land the discard (Swift-side
   in `AudioRecorder.swift` is preferable to C, to keep
   `LinuxAudioCaptureSupport.c` a thin, allocation-free shim per its
   existing style) as a small, fixed, documented warm-up discard (e.g.
   "discard first 200ms of captured audio to avoid a device-start
   transient"), with a unit test asserting the discard count/logic
   (pure, no hardware needed) and a real-hardware re-verification
   (`make run ARGS="record --seconds 5 --out /tmp/click-check.wav"`,
   re-run the same sample-level Python analysis from this ticket against
   the new file, confirm no comparable pulse in the first 1.5s).
4. **If the pulse persists identically regardless of any capture-side
   discard/delay** (i.e. it moves in lockstep with wall-clock time, not
   with frames-read), that points to an actual acoustic event at the
   hardware/environment level (e.g. a relay click when PipeWire/ALSA
   opens the device) outside this Swift/C code's control — in that case,
   downgrade this ticket to documentation-only: record the finding in
   `docs/LINUX_SETUP.md` next to the existing ALSA-vs-PipeWire writeup,
   update both `.jsonl` `known_artifacts` fields to reflect the
   corrected (data-confirmed-but-external) conclusion, and close without
   a code change.
5. Either way, correct the two `known_artifacts` fields in
   `~/.config/fluidvoice/dev/samples/test.jsonl` and
   `chunks.jsonl` — their current text ("verified NOT present in the
   captured PCM data") is superseded by this ticket's findings and would
   mislead future Phase 4 STT/VAD work using these samples as ground
   truth.
6. Do **not** re-run the earlier session's raw `hw:`/`plughw:` ALSA
   probes on this machine — per issue 003's resolution notes, that
   destabilized the host's PipeWire session once already; use the
   default `"default"` PipeWire-mediated device for all re-recording in
   this investigation, exactly as `AlsaAudioRecorder`'s default already
   does.
