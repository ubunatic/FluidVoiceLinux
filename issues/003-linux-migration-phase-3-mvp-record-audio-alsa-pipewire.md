# 003 — Linux migration Phase 3: MVP record audio (ALSA/PipeWire)

**Status**: Blocked — real hardware capture end-to-end not verified in this sandbox
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Feature

---

## 1. Problem & Motivation

Phase 3 of `docs/LINUX_MIGRATION_BRANCH_PLAN.md`. The canary (issue 002,
closed) proved the Linux CLI builds and runs cleanly with zero macOS
dependencies. This ticket is the first real capability: "I can record
audio" on Linux, replacing the macOS-only `CoreAudioCaptureSupport`
(CoreAudio, `Sources/CoreAudioCaptureSupport/**` — do not touch, it
stays macOS-only and gated out per Phase 0).

## 2. Technical Specification / Findings

- Before writing this ticket's plan doc content in stone, read
  `docs/SwiftLinux.md` — it captures the Package.swift platform-gating
  pattern, the executable/library testability split, and the
  `Package.resolved` churn gotcha that will all apply here.
- `libasound2-dev` (Debian/Ubuntu) / `alsa-lib-devel` (Fedora) are
  already installed by `make apt-deps`/`make dnf-deps` (added
  forward-looking in issue 001) — confirm they're sufficient, or note
  what's missing (e.g. PipeWire client headers) and update
  `docs/LINUX_SETUP.md` + the Makefile's dep lists accordingly.
- Decide ALSA (`libasound`) vs. PipeWire/PulseAudio client API — ALSA
  is the lower-level, more universally-available option and mirrors
  the existing `CoreAudioCaptureSupport` C-interop pattern most
  directly (a C target with a `module.modulemap`, similar structure);
  PipeWire is more "modern Linux desktop" but higher-level and more
  distro-dependent. Canary-first: probe whichever you pick with a tiny
  standalone capture-to-buffer test before building the full feature.

## 3. Implementation & Verification Plan

- New C-interop target (e.g. `Sources/LinuxAudioCaptureSupport`),
  mirroring `Sources/CoreAudioCaptureSupport`'s structure, gated into
  the Linux `#else` branch of `Package.swift`.
- CLI subcommand: `fluidvoice-linux record --seconds N --out out.wav`
  (put subcommand logic in `FluidVoiceLinuxCLICore` per the
  executable/library split in `docs/SwiftLinux.md` §3, so it's
  testable without spawning a real audio device in unit tests).
- Add a unit test for the WAV-header/format-writing logic that doesn't
  require real hardware; if a real-device smoke test is added, keep it
  separate and clearly marked as requiring an actual audio input
  device (not part of `make test`'s default run).
- Verify for real: `make build && make run -- record --seconds 3 --out
  /tmp/test.wav` on real hardware, confirm the WAV is playable
  (`aplay`/`ffprobe`) with correct sample rate/channel count.
- Document the ALSA-vs-PipeWire decision and any new dependency in
  `docs/LINUX_SETUP.md`, mirroring the toolchain-decision writeup
  already there from issue 001.

## 4. Resolution

Went with **ALSA** (`<alsa/asoundlib.h>`), as the plan leaned — see
`docs/LINUX_SETUP.md`'s new "Audio capture: ALSA, not PipeWire/PulseAudio"
section for the full reasoning. Summary: universally available without a
desktop session, mirrors `CoreAudioCaptureSupport`'s C-interop structure
directly, and ALSA's `"default"` PCM still cooperates with PipeWire when
present (routes through `pipewire-alsa`) rather than fighting it for the
device.

**New target**: `Sources/LinuxAudioCaptureSupport` (C, gated into
`Package.swift`'s Linux `#else` branch, `linkerSettings: [.linkedLibrary
("asound")]`):
- `include/LinuxAudioCaptureSupport.h` — opaque `FVAlsaCaptureRef`,
  `fv_alsa_capture_open`/`_read`/`_close`/`_strerror`, mirroring
  `CoreAudioCaptureSupport`'s create/read/destroy + error-code pattern but
  deliberately simpler: a blocking `snd_pcm_readi` loop (no realtime
  ring buffer/IOProc — not needed for "record N seconds to a WAV file").
  Fixed sample format: signed 16-bit little-endian, interleaved.
- `LinuxAudioCaptureSupport.c` — `snd_pcm_open` + `snd_pcm_set_params`
  against the requested device/rate/channels, reporting back what ALSA
  actually negotiated; `snd_pcm_readi` with one `snd_pcm_recover` retry on
  a transient error (overrun/suspend) before surfacing a hard failure.

**CLI subcommand**: `record --seconds N --out path.wav` (plus optional
`--device`, `--sample-rate`, `--channels`), hand-rolled parsing per the
plan (no new SwiftPM dependency):
- `Sources/FluidVoiceLinuxCLICore/WavWriter.swift` — pure `WavFormat`
  enum, no ALSA/file-IO dependency: builds the 44-byte canonical
  RIFF/WAVE PCM header and a full in-memory WAV file from an `[Int16]`
  sample buffer.
- `Sources/FluidVoiceLinuxCLICore/AudioRecorder.swift` — `AlsaAudioRecorder`
  drives the C shim: opens the device (default `"default"`, deliberately
  not a raw `hw:`/`plughw:` device — see `docs/LINUX_SETUP.md`), reads in
  4096-frame chunks until the requested duration is captured, returns the
  samples plus the negotiated sample rate/channel count.
- `Sources/FluidVoiceLinuxCLICore/RecordCommand.swift` — `RecordCommand`:
  `parseArguments` (pure, no ALSA calls — unit-testable) and `run`
  (real I/O: parse -> record -> `WavFormat.makeFile` -> write to disk),
  split per `docs/SwiftLinux.md` §3 specifically so argument handling is
  testable without a capture device.
- `Sources/FluidVoiceLinuxCLI/main.swift` — thin dispatcher: `record`
  subcommand routes to `RecordCommand.run`, no args falls back to the
  Phase 2 banner, anything else is an "unknown subcommand" error on
  stderr with exit code 1.
- `Makefile`'s `run` target now passes through `$(ARGS)` (e.g.
  `make run ARGS="record --seconds 3 --out /tmp/test.wav"`).

**Tests** (`Tests/FluidVoiceLinuxCLITests/`, no hardware needed):
- `WavFormatTests.swift` — asserts every RIFF/WAVE header field byte
  offset (chunk sizes, PCM format tag, channel count, sample rate, byte
  rate, block align, bits per sample) for mono and stereo cases, plus
  that `makeFile` emits header + correct little-endian sample bytes.
- `RecordCommandArgumentTests.swift` — required/optional flag parsing,
  missing `--seconds`/`--out`, invalid (`0`) seconds, unknown flag,
  dangling flag with no value.
- `make test` (`swift test`): all 12 tests pass (2 Phase 2 banner tests
  + 3 WAV format tests + 7 argument-parsing tests).

**Dependency check**: `libasound2-dev` (already in `make apt-deps` from
issue 001) is sufficient — `pkg-config --exists alsa` succeeds and
`/usr/include/alsa/asoundlib.h` is present; no PipeWire client headers
needed. `docs/LINUX_SETUP.md` updated accordingly.

**Hardware verification — honest status, partial only**:

This sandbox unexpectedly does have real ALSA capture hardware
(`/proc/asound/cards`: two HDA-Intel devices plus a USB webcam mic;
`arecord -l` lists working capture subdevices), so a real capture was
technically possible here, unlike the "may not have a mic" assumption
in the task brief. However, full end-to-end verification through this
CLI was **not** completed, for two independent reasons hit during this
session, in order:

1. Manual `arecord -D plughw:CARD=...` probes (run to confirm ALSA
   capture works at all, before writing any Swift/C code) opened raw
   hardware devices directly and produced two valid, non-silent PCM WAV
   files (`/tmp/probe.wav`, `/tmp/probe2.wav`, 64044 bytes each,
   confirming `arecord -l`'s devices are real and capture-able) — but
   this briefly caused the host's real microphone to disappear from
   GNOME Settings, visible in the system journal as PipeWire/WirePlumber
   "link failed to activate"/"out of buffers" errors from contending
   with PipeWire for the same hardware device. It self-recovered with no
   lasting effect, but the coordinator flagged it mid-session and
   instructed: no more raw `hw:`/`plughw:` opens on this machine, prefer
   PipeWire-mediated access (ALSA's `"default"` device) if attempting
   further real capture, or explicitly not verify end-to-end and say so.
   This is exactly why `AlsaAudioRecorder`'s default device is
   `"default"`, not a raw `hw:` device — but per that instruction, this
   ticket does not repeat a real capture against the actual hardware to
   "get it working," even through `"default"`.
2. Independently, a later attempt to invoke this CLI's own
   `record --seconds N --out ...` for a real capture through the built
   `FluidVoiceLinuxCLI` binary (default device, not a raw `hw:` device)
   was blocked by this sandbox's own action-classifier layer as a
   sensitive action, before it reached ALSA at all.

What **was** verified for real on this box:
- `swiftlang` 6.1.3, `swift build -c release --product
  FluidVoiceLinuxCLI` succeeds cleanly.
- `swift test` (`make test`): all 12 tests pass, including the
  hardware-free WAV header and argument-parsing suites.
- `.build/release/FluidVoiceLinuxCLI` (no args) still prints the Phase 2
  banner — the dispatcher change didn't regress it.
- `.build/release/FluidVoiceLinuxCLI record --seconds 1 --out /tmp/x.wav`
  (missing `--out` in one run, bogus `--device nonexistent-device-xyz` in
  another) both exercise the real code path through `snd_pcm_open`
  against libasound and fail cleanly with a clear stderr message and
  exit code 1 — no crash, no UB — proving the ALSA open/error-handling
  path is wired correctly, without touching a live device.
- Separately, standalone `arecord` (not this CLI) proved real ALSA
  capture from this machine's actual hardware produces valid, non-silent
  WAV data (see point 1 above) — strong indirect evidence the same
  `snd_pcm_readi`/`SND_PCM_FORMAT_S16_LE` path this C shim uses works on
  this hardware, but that is not the same as this CLI having produced
  and played back its own WAV file end-to-end.

**What a human needs to do to close this out**: on a real machine (or
this one, outside the current sandbox's action-classifier and with care
around any other application currently holding the mic), run
`make build && make run ARGS="record --seconds 3 --out /tmp/test.wav"`
using the default ALSA device, then verify the resulting file with
`ffprobe /tmp/test.wav` or `aplay /tmp/test.wav` — confirm it's a valid,
playable, non-silent WAV with the expected ~3s duration, 16000 Hz, mono,
16-bit fields, and update this ticket's Status to
`Closed — resolved in <sha>` once that's done.
