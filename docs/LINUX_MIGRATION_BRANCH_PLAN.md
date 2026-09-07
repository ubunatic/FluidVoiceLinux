# Linux Migration Plan (Separate Branch / 2nd Work Stream)

## Goal
Stand up a Linux-native, headless CLI build of FluidVoice as a second work
stream that runs alongside the macOS app, without disturbing macOS
release work. Not a UI port — Linux target is CLI-only.

## Status (as of 2026-09-07)
Phases 0-6 are **done** — canary, `record`, GPU-accelerated `transcribe`
(Whisper on Vulkan, NVIDIA Parakeet TDT v3, Cohere Transcribe, Nemotron Speech 3.5),
Silero VAD segmentation, LLM AI post-enhancement (`--enhance` via Ollama/Claude/Gemini/OpenAI),
and live `dictate` with clipboard/typing output drivers all work end-to-end on real
hardware and pass 55/55 unit/integration tests.

See `issues/001`-`004`, `007`-`015` (all closed).
Open backlog:
- `issues/005` (Phase 5+ packaging/config persistence)
- `issues/006` (transient click/pop at recording start)
- `issues/016` (Wayland virtual keyboard protocol fallback on GNOME/Mutter)
- `issues/017` (continuous streaming dictation loop in `dictate` subcommand)

`docs/SwiftLinux.md` has the accumulated "how Swift-on-Linux actually behaves"
reference distilled from this work; read it before starting new Linux CLI work.

## Branch Strategy
- **Correction, actual practice**: despite the branch name below,
  Phases 0-4 (and issue 007) were all committed directly to `main`, per
  this repo's `docs/Git.md` convention of working on the default branch —
  `B/linux-migration` was never created. Update this section if a real
  separate branch is adopted later; until then, treat `main` as where
  this work lives.
- Original plan (kept for reference): branch name `B/linux-migration`,
  based off `main`, not merged until the canary milestone builds green
  on Linux.
- macOS `Sources/Fluid/**` stays untouched by this branch except for
  `#if os(macOS)` guards needed to keep a shared `Package.swift` buildable
  on both platforms (see Phase 0).
- GitHub Actions: already fully disabled by the user — no CI wiring in
  this plan. All milestones are validated with local `make` targets only.

## Scope
- New Linux CLI target that builds and runs with `swift build` on Linux.
- A `Makefile` per `~/.claude/docs/Make.md` conventions for fast
  build/install/test loops.
- Incremental milestones: canary -> record audio -> run STT model on AMD
  iGPU -> (later) full pipeline parity.

## Out of Scope
- Any GUI/menu-bar/overlay UI on Linux — target is CLI-only.
- Feature parity with macOS FluidVoice in this branch.
- Packaging/distribution (deb/rpm/AppImage) until after MVP2.
- Windows or other platforms.

## Phase 0: Disable macOS-only stuff and tests
- Audit `Sources/Fluid/**` (144 files, 77 import AppKit/SwiftUI/Cocoa/
  CoreAudio/AVFoundation) and `Sources/CoreAudioCaptureSupport/**` —
  these do not build on Linux at all.
- Do **not** try to compile the existing macOS app on Linux. Instead:
  - Keep the existing `FluidVoice` executable target macOS-only in
    `Package.swift` via `.target(..., condition: .when(platforms: [.macOS]))`
    or by wrapping platform-specific target declarations in
    `#if os(macOS)` at the `Package.swift` level (SwiftPM supports
    per-platform target conditions on dependencies/sources, not whole
    targets — confirm exact mechanism when Phase 0 starts; fallback is
    two `Package.swift` files selected by symlink/Makefile if needed).
  - Mark `Tests/FluidDictationIntegrationTests` macOS-only (depends on
    the macOS app) — exclude from the Linux build/test graph entirely.
- Confirm GH Actions are disabled (user-confirmed, done) — no further
  action needed here.
- Deliverable: `swift build` (or the new Makefile's `build` target) does
  not attempt to compile macOS-only code when run on Linux.

## Phase 1: Build tooling (Make.md conventions)
Add a root `Makefile` (Linux-focused; macOS keeps using `build.sh`/
Xcode) following `~/.claude/docs/Make.md`:
- `⚙️` phony sentinel, `help` as default goal, self-documenting targets.
- Vars: `BINARY := fluidvoice-linux`, `PREFIX ?= /usr/local`,
  `SWIFT_BUILD_FLAGS := -c release`.
- `build: ⚙️` — `swift build $(SWIFT_BUILD_FLAGS) --product $(BINARY)`
- `run: ⚙️ build` — runs the freshly built binary
- `test: ⚙️` — `swift test` (Linux-eligible test targets only)
- `install: ⚙️ build` — local (`~/.local/bin` or `swift build` artifact
  copy) + best-effort `sudo install` to `$(PREFIX)/bin`, degrading
  gracefully like the Go pattern in Make.md.
- Document required Linux Swift toolchain setup (swift.org Linux
  toolchain or distro package) in a short `docs/LINUX_SETUP.md` since
  `swift` is not currently installed on this machine (verified: `swift
  not found`).
- Deliverable: `make help`, `make build`, `make test`, `make install`
  all work on a clean Linux machine with only the Swift toolchain
  installed.

## Phase 2: Canary — "hello swift"
- New executable target in `Package.swift`, e.g. `FluidVoiceLinuxCLI`,
  `path: Sources/FluidVoiceLinuxCLI`, with a single `main.swift` that
  prints a version/hello banner and exits 0.
- No dependency on any macOS-only target (`CoreAudioCaptureSupport`,
  `AppUpdater`, `DynamicNotchKit` — all suspected macOS-only; confirm
  during this phase and drop/gate them from the Linux target's
  dependency list).
- Deliverable: `make build && make run` prints "FluidVoice Linux CLI
  vX — hello swift" on a Linux box. This is the go/no-go gate before
  investing in Phase 3.

## Phase 3: MVP — "I can record audio"
- Replace `CoreAudioCaptureSupport` (CoreAudio, macOS-only) with a
  Linux audio capture module, e.g. `Sources/LinuxAudioCaptureSupport`
  wrapping ALSA (`libasound`) or PulseAudio/PipeWire via a C shim,
  mirroring the existing `CoreAudioCaptureSupport` C-interop pattern.
- CLI subcommand: `fluidvoice-linux record --seconds N --out out.wav`.
- Verify with `make test` (unit test around the capture buffer/format)
  and a manual `make run -- record` producing a playable WAV.
- Deliverable: recorded WAV file is playable and has correct
  sample rate/channel count.

## Phase 4: MVP2 — "run the model on the AMD iGPU" — done, see issue 004
- **Resolved differently than originally planned**: rather than
  `transcribe-cpp-swift` (already a macOS-only dependency), Ubuntu's
  `universe` repo ships whisper.cpp itself as apt packages
  (`libwhisper-dev`/`libwhisper1`) with a dynamically-loaded ggml Vulkan
  backend (`libggml0-backend-vulkan`) that already picks up the AMD iGPU
  via Mesa's RADV driver with zero source rebuilding — see
  `docs/LINUX_SETUP.md` "STT backend" section for the full decision and
  verification evidence, and `Sources/LinuxWhisperSupport` for the
  resulting `.systemLibrary` C-interop target.
- `FluidAudio` (CoreML-based diarization/VAD) is very likely macOS-only
  — plan to drop it from the Linux target and either skip
  diarization/VAD for MVP2 or find a portable replacement later.
- CLI subcommand: `fluidvoice-linux transcribe --in out.wav [--model
  path] [--no-gpu]` — GPU-backed by default via ggml's own automatic
  CPU fallback on GPU-init failure (verified for real, not just coded),
  `--no-gpu` forces CPU-only explicitly.
- Deliverable: transcribing the Phase 3 WAV produces text, and logs
  confirm GPU (not CPU) execution on the AMD iGPU — done; see issue
  004's Resolution section for the transcript + timing evidence.

## Phase 5+ (and so on)
- Config/settings persistence (headless equivalent of `Persistence/`)
- Hotkey-free CLI UX polish (flags, `--daemon` mode, JSON output, etc.)
- Packaging (deb/AppImage) once MVP2 is stable
- Re-evaluate CI (even if only a local/self-hosted Linux runner) once
  GH Actions story is revisited

## Directory Layout (proposed)
```
Sources/
  Fluid/                        # macOS app, untouched
  CoreAudioCaptureSupport/      # macOS app, untouched
  FluidVoiceLinuxCLI/           # new: Linux CLI entrypoint + subcommands
  LinuxAudioCaptureSupport/     # new: ALSA/PipeWire C interop
Tests/
  FluidDictationIntegrationTests/  # macOS-only, excluded from Linux build
  FluidVoiceLinuxCLITests/         # new: Linux-only tests
Makefile                        # new: Linux build/run/test/install
docs/
  LINUX_SETUP.md                 # new: toolchain install instructions
  LINUX_MIGRATION_BRANCH_PLAN.md # this file
```

## Definition of Done (per milestone)
1. Canary: `make build run` on Linux prints hello banner, zero macOS
   deps pulled in.
2. MVP: `make run -- record` produces a valid WAV on Linux hardware.
3. MVP2: `make run -- transcribe` produces text using AMD iGPU
   acceleration, with a CPU fallback path verified.
4. Each milestone is its own commit/PR onto `B/linux-migration`, kept
   independently revertable.

## Open Questions to Resolve Early (Phase 0/2)
- Can `Package.swift` cleanly express "these targets/deps are
  macOS-only" without breaking `swift build` on Linux, or do we need a
  second manifest?
- Do `AppUpdater`, `DynamicNotchKit`, `FluidAudio` fail to *resolve*
  on Linux (network/manifest level) or only fail to *compile*? This
  determines whether Phase 0 needs a dependency-level split too, not
  just a target-level one.
- ~~Confirm actual Vulkan/ROCm support status in the pinned
  `transcribe-cpp-swift@0.1.2` before committing to Phase 4 approach.~~
  Resolved: not needed — apt's own `libwhisper-dev` + ggml Vulkan backend
  worked directly, see Phase 4 above and `docs/LINUX_SETUP.md`.
