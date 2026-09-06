---
title: Swift Development on Linux
weight: 64
---

# Swift Development on Linux

> **Who this is for** — anyone (agent or human) picking up the Linux CLI
> work stream cold. Read this before touching `Package.swift`,
> `Sources/FluidVoiceLinuxCLI*`, or `Tests/FluidVoiceLinuxCLI*`.
>
> **Context**: `docs/LINUX_MIGRATION_BRANCH_PLAN.md` (the phased plan),
> `docs/LINUX_SETUP.md` (toolchain/package details), `docs/Make.md`
> (Makefile conventions used here). This doc is the "how Swift-on-Linux
> actually behaves" reference distilled from doing Phases 0-4 (issues
> 001-004) plus the model-path follow-up (issue 007).

---

## TL;DR

```sh
make apt-deps       # once, installs the real toolchain (see gotcha below)
make build          # swift build -c release --product FluidVoiceLinuxCLI
make run            # build + run the Linux CLI binary
make test           # swift test — Linux-eligible tests only
```

This repo builds a macOS SwiftUI app (`Sources/Fluid/**`) and, as a
separate work stream, a headless Linux CLI (`Sources/FluidVoiceLinuxCLI*`).
One `Package.swift` serves both platforms — see below for how.

## 1. Toolchain: name collisions on Debian/Ubuntu

**`apt install swift` installs the wrong thing.** On Debian/Ubuntu, the
`swift` package is OpenStack Swift (object storage), version `2.x` —
completely unrelated. The real Apple Swift toolchain package is
**`swiftlang`** (`swiftlang-dev` for headers). Always verify with
`apt-cache policy swift swiftlang` before assuming either name.

Fedora uses `swift-lang` instead (untested by this project so far —
verify package names for real before trusting `make dnf-deps` blindly).

Once installed, `swift --version` should report something like:
```
Swift version 6.1.3 (swift-6.1.3-RELEASE)
Target: x86_64-pc-linux-gnu
```

**`swift` binary location and the postinst symlink**: `swiftlang`'s real
binaries live under `/usr/libexec/swift/bin/` (`swift` there is itself a
symlink to `swift-driver`). The package's `postinst` asks a debconf
question and, by default, symlinks `/usr/bin/swift ->
/usr/libexec/swift/bin/swift` so it's just on `PATH`. If `swift` is
missing from `PATH` after install, check for that symlink first
(`dpkg-reconfigure swiftlang`) before assuming the install failed.

**No vendored toolchain needed (for now).** `swift-tools-version: 5.9` in
this `Package.swift` is comfortably satisfied by apt's `6.1.3`. Don't
build a `vendor/swift` download-and-unpack path speculatively — only add
it if/when a target distro's packaged Swift is genuinely too old or
missing. See `docs/LINUX_SETUP.md` for the deferred plan.

**Testing any apt package without root** (recurred for the toolchain in
issue 001 and for `libwhisper-dev`/`libggml-dev` in issue 004 — this is
a general technique, not toolchain-specific): if a session has no
interactive `sudo`, you can still validate a candidate package set
without installing system-wide: `apt-get download <pkg>` (no root
required) followed by `dpkg-deb -x <pkg>.deb <scratchdir>`, then point
`PATH`/`CPATH`/`PKG_CONFIG_PATH`/linker `-L` flags at `<scratchdir>`'s
extracted layout to build/run for real before committing to a decision.
The real `make apt-deps` a human runs installs the same packages at
their normal system paths — the scratch-dir dance is a dev-session-only
verification step, never a substitute for the real install in the
Makefile.

## 2. One `Package.swift`, two platforms

SwiftPM does not support per-platform *inclusion* of whole targets or
dependencies declaratively inside the `targets:`/`dependencies:` array
literals. But `Package.swift` is plain Swift, executed by the host's
own toolchain when SwiftPM loads the manifest — so `#if os(macOS)` /
`#else` around **array-building code** works perfectly and is the
standard trick:

```swift
var dependencies: [Package.Dependency] = []
var targets: [Target] = []

#if os(macOS)
dependencies += [ /* AppUpdater, FluidAudio, ... */ ]
targets += [ /* CoreAudioCaptureSupport, FluidVoice, FluidDictationIntegrationTests */ ]
#else
targets += [ /* FluidVoiceLinuxCLI, FluidVoiceLinuxCLICore, FluidVoiceLinuxCLITests */ ]
#endif

let package = Package(name: "FluidVoice", platforms: [.macOS("15.0")],
                       dependencies: dependencies, targets: targets)
```

Consequences of this pattern:
- Running `swift build`/`swift test`/`swift package resolve` **on Linux**
  never even attempts to compile or resolve macOS-only code or
  dependencies (AppKit/SwiftUI/Cocoa/CoreAudio/AVFoundation imports,
  CoreAudio linker settings, Sparkle-based `AppUpdater`, etc.).
- The macOS Xcode project (`Fluid.xcodeproj`)/`build.sh` flow is
  untouched — it still sees the full macOS target list when built on
  macOS.
- **Gotcha — `Package.resolved` churn**: any `swift build`/`test`/
  `resolve` invocation on Linux re-resolves against the *Linux-only*
  (currently empty) dependency graph and rewrites `Package.resolved`,
  which would silently drop the macOS-pinned dependency versions if
  committed. **Always run `git diff Package.resolved` after any Linux
  Swift command and `git checkout -- Package.resolved` before
  committing** unless you specifically intend to change pinned
  versions.

## 3. Executable vs. library targets — the testability split

A `.executableTarget` whose entrypoint is a bare `main.swift` (top-level
executable code, no `@main` type) **cannot be imported by a test
target** — there's no module surface for XCTest/swift-testing to `import`.
The pattern used here (see `Sources/FluidVoiceLinuxCLICore/Banner.swift`):

- Put real logic in a plain `.target` (library), e.g.
  `FluidVoiceLinuxCLICore`.
- The `.executableTarget` (`FluidVoiceLinuxCLI`) depends on it and its
  `main.swift` is a one-liner: `print(FluidVoiceLinuxCLIBanner.banner())`.
- The `.testTarget` (`FluidVoiceLinuxCLITests`) depends on the library
  target, not the executable, and imports it normally.

Apply this split from the start for any new Linux CLI feature —
subcommands in Phase 3+ should each get their logic in
`FluidVoiceLinuxCLICore` (or a similarly-named library target) with the
executable staying a thin dispatcher, so everything stays unit-testable.

**Recurring sub-pattern — injectable side effects for pure-function
tests.** Every subcommand built so far (`RecordCommand`,
`TranscribeCommand`, `ModelPathResolver`) separates a pure decision
function from the code that actually touches the filesystem/environment:
`parseArguments` takes `[String]` and returns a `Result`/options struct
with no I/O; `ModelPathResolver.resolve(explicit:fileExists:xdgDataHome:home:)`
takes closures for "does this path exist" and "what is $XDG_DATA_HOME"
instead of calling `FileManager`/`ProcessInfo` directly. The real
`FileManager.default.fileExists`/`ProcessInfo` calls are wired in exactly
once, at the `run()` call site, right before the pure function's result is
used. This is the single reason `make test`'s 27 tests all run with zero
hardware/model/filesystem dependencies — keep doing it for every new
subcommand rather than reaching for a mocking framework or `#if TESTING`
branches.

## 4. Makefile conventions in play

See `docs/Make.md` for the full `⚙️`/`🤖` sentinel convention. Swift-specific
notes:
- `preflight` target checks `command -v swift` and prints a hint
  (`make apt-deps`/`make dnf-deps`) instead of a raw Make error when
  missing — always run this before assuming a build failure is a code bug.
- `build` = `swift build -c release --product $(BINARY)`; the binary
  lands at `.build/release/$(BINARY)`.
- `check`/`test` = `swift test`. `swift test` prints both classic
  XCTest-style output *and* a trailing Swift Testing summary line
  (`◇ Test run started...✔ Test run with 0 tests passed`) even when all
  tests are XCTest-based — that's the swift-testing library being
  scanned with zero tests in it, not an error, don't chase it.
- `.build/` is gitignored (already in `.gitignore`); a future
  `vendor/swift` (if ever added) should be too.

## 5. Verified environment (as of this writing)

- Ubuntu 26.04 "resolute", `swiftlang` 6.1.3-4build1 via apt (universe repo).
- `swift build`/`swift run`/`swift test` confirmed working end-to-end for
  `FluidVoiceLinuxCLI` and its test suite, including as an *installed*
  binary (`make install` → `~/.local/bin/FluidVoiceLinuxCLI`, on `PATH`,
  runnable from any directory — issue 007).
- `record`/`transcribe` subcommands both human-verified on real hardware:
  ALSA capture via the default (PipeWire-mediated) device, whisper.cpp
  transcription GPU-accelerated on this box's AMD Radeon 780M (Phoenix)
  iGPU via a Vulkan backend, with a verified real CPU fallback on GPU-init
  failure. See issues 003/004 for the transcripts and timing evidence.
- Fedora/`dnf-deps` package names are best-effort, **not verified on real
  hardware** — treat with suspicion until someone runs it on Fedora and
  updates this doc + `docs/LINUX_SETUP.md`.

## 6. Where to look next

- `docs/LINUX_MIGRATION_BRANCH_PLAN.md` — phase-by-phase roadmap. Phases
  0-4 are done; Phase 5+ (config persistence, packaging, CI) is open
  backlog (issue 005).
- `issues/README.md` — current ticket status; each phase/fix gets its own
  issue, closed with a `## Resolution` section documenting real
  verification output (follow that pattern for new tickets). Issue 006
  (a click/pop transient at recording start, found in real captured PCM
  data — not just assumed external) is open and unfixed; ignore it for
  unrelated work unless asked.

## 7. A second C-interop pattern: `.systemLibrary` (Phase 4)

Phase 4 (`Sources/LinuxWhisperSupport`, wrapping the apt `libwhisper-dev`
package — see `docs/LINUX_SETUP.md` for the backend decision) uses a
different SwiftPM target type than Phase 3's ALSA target
(`Sources/LinuxAudioCaptureSupport`, a plain `.target` with a hand-written
C shim `.c` file): a `.systemLibrary` target, whose whole content is a
`module.modulemap` + a one-line `shim.h` that just `#include`s the vendor's
own C header (`<whisper.h>`) and a `pkgConfig:` field pointing at the
package's shipped `.pc` file. Use `.systemLibrary` instead of a hand-written
shim when the system library's own public header is *already* a clean,
directly-Swift-importable C API (`extern "C"`, no C++ types, no macros the
Clang importer chokes on) — check this first (`grep -n
'#ifdef __cplusplus' <header>.h`) before writing a shim you don't need.
`Sources/LinuxAudioCaptureSupport` still needed its shim because ALSA's
own API surface (`snd_pcm_*`) isn't the shape this CLI wants exposed
(blocking read loop, error code translation, opaque handle) — that's a
judgment call about API design, not just C-vs-C++ header compatibility.

## 8. Where an installed CLI should look for its own data files

A repo-relative default (`models/ggml-base.en.bin`, resolved against
CWD) works fine for `make run` during development but silently breaks
the moment the binary is installed and invoked from an arbitrary
directory (`make install` → `~/.local/bin/FluidVoiceLinuxCLI`, on
`PATH`) — issue 007. The macOS app's own convention
(`Sources/Fluid/Persistence/**`) is `FileManager`'s
`.applicationSupportDirectory` for durable data and `.cachesDirectory`
for disposable data; the Linux/XDG equivalents are `$XDG_DATA_HOME`
(default `~/.local/share`) and `$XDG_CACHE_HOME` (default `~/.cache`)
respectively. `ModelPathResolver` (`Sources/FluidVoiceLinuxCLICore/
ModelPathResolver.swift`) is the reference implementation: try, in
order, (1) an explicit flag/argument, (2) the repo-relative dev default
if it exists (don't regress the existing dev loop), (3) the real
`$XDG_DATA_HOME/fluidvoice/...` default. Follow this same order/pattern
for any future feature that reads a file the user or an installer
placed on disk (config, cached data, models) — don't invent a
project-specific location per feature.

Note: this session also created an informal `~/.config/fluidvoice/dev/
samples/` directory by hand, for storing test recordings during Phase
3/4 development. That is **not** an XDG-correct location for anything
(recordings aren't "config"), and no code in this repo creates or reads
it — it's a human/agent scratch convention, not a pattern to follow in
actual CLI code. Don't confuse it with the `$XDG_DATA_HOME` default
above.
