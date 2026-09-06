---
title: Linux Setup
weight: 63
---

# Linux Setup

Toolchain and dependency setup for the Linux CLI work stream (see
`docs/LINUX_MIGRATION_BRANCH_PLAN.md`). This is for `Sources/FluidVoiceLinuxCLI`
only — the macOS app keeps using `build.sh`/Xcode.

## Toolchain decision: apt package, not vendored

Checked `apt-cache policy swift` on this Ubuntu 26.04 ("resolute") box first: the
`swift` apt package is unrelated (OpenStack Swift object storage, version
`2.37.1`), which is the classic name collision to watch for on Debian/Ubuntu. The
real Apple Swift toolchain ships under a different name: `swiftlang` (currently
`6.1.3-4build1` in the `resolute` universe repo), with headers in
`swiftlang-dev`. `6.1.3` is well past this package's `swift-tools-version: 5.9`
floor, so no vendored `swift.org` tarball is needed — `make apt-deps` installs
the real thing directly.

If a future distro/release only ships an old or missing `swiftlang`, add a
`vendor-swift` Make target that downloads an official Linux toolchain tarball
from `https://swift.org/download/` into `./vendor/swift` (gitignored) and have
`preflight`/`build` prefer `./vendor/swift/usr/bin` on `PATH` when present. Not
needed today — don't build it speculatively.

## Install

```sh
make apt-deps   # Debian/Ubuntu (sudo)
make dnf-deps   # Fedora (sudo) — untested on this box, package names are best-effort
```

`apt-deps` installs:
- `swiftlang` / `swiftlang-dev` — the Swift compiler and toolchain libraries.
- `clang` — required by the Swift toolchain (C/C++ interop, `swift-frontend`
  driver).
- `libcurl4-openssl-dev`, `libicu-dev`, `libxml2-dev`, `zlib1g-dev`,
  `libsqlite3-dev`, `libncurses-dev`, `libedit-dev` — the standard
  swift.org Linux toolchain runtime/build dependency list (Foundation,
  swift-corelibs, REPL/lldb line editing).
- `libasound2-dev` — forward-looking for Phase 3 (ALSA-based audio capture);
  not used by the Phase 0/1 stub.
- `curl`, `git` — fetching SwiftPM dependencies and any future toolchain
  tarballs.

`dnf-deps` mirrors this with Fedora package names (`swift-lang`,
`*-devel` suffixes, `alsa-lib-devel`). Not verified on real Fedora hardware —
flag any package name drift back to this doc.

## Audio capture: ALSA, not PipeWire/PulseAudio (Phase 3)

Phase 3 (`docs/LINUX_MIGRATION_BRANCH_PLAN.md`, issue 003) needed to pick a
capture API for `Sources/LinuxAudioCaptureSupport`. Went with **ALSA**
(`libasound`/`<alsa/asoundlib.h>`) over PipeWire's or PulseAudio's native
client libraries:

- It's the lowest common denominator — present on essentially every Linux
  box, with or without a desktop session or PipeWire/PulseAudio daemon
  running, unlike the higher-level session-bus-dependent APIs.
- It mirrors this repo's existing `Sources/CoreAudioCaptureSupport` C-interop
  structure most directly (opaque capture handle, create/read/destroy
  lifecycle, `include/<Header>.h` + `.c` C target).
- On a modern desktop, ALSA's `"default"` PCM device still transparently
  routes through PipeWire's own ALSA plugin (`pipewire-alsa`) when present —
  so using plain ALSA does not mean bypassing PipeWire on systems that run
  it; opening `"default"` cooperates with whatever audio server owns the
  hardware instead of fighting it for exclusive access. Opening a raw
  `hw:`/`plughw:` device directly can conflict with PipeWire/WirePlumber if
  it currently holds that device (observed as a transient mic dropout in
  this dev sandbox during manual `arecord -D plughw:...` probing) — the CLI
  and `AlsaAudioRecorder` default to `"default"`, not a raw hw device, for
  exactly this reason. Pass `--device hw:CARD=...`/`plughw:CARD=...`
  explicitly only when you specifically need to bypass the sound server.

**Dependency check**: `libasound2-dev` (already added to `make apt-deps` in
issue 001) is sufficient — confirmed via `pkg-config --exists alsa` and the
presence of `/usr/include/alsa/asoundlib.h` on this Ubuntu 26.04 box, no
PipeWire client headers needed. `libasound2-dev` pulls in the runtime
library (`libasound2t64` on this Ubuntu release, the `t64` 64-bit-time_t
transition package) as a dependency, so no separate runtime package is
needed beyond what `apt-deps` already installs.

### Note: `apt install swiftlang` and the `/usr/bin/swift` symlink

The `swiftlang` package's real binaries live under
`/usr/libexec/swift/bin/` (e.g. `/usr/libexec/swift/bin/swift`). Its `postinst`
asks a debconf question (`swiftlang/link_swift`) and, if answered yes (the
default), symlinks `/usr/bin/swift -> /usr/libexec/swift/bin/swift`. A
non-interactive/unattended install (e.g. `DEBIAN_FRONTEND=noninteractive`)
still creates this symlink with the packaged default answer. If `swift` is
ever missing from `PATH` after `make apt-deps`, check for the symlink and
re-run `sudo dpkg-reconfigure swiftlang` or add
`/usr/libexec/swift/bin` to `PATH` directly.

## Verification performed for this ticket

`swiftlang`/`swiftlang-dev`/`libswiftlang` `.deb`s were downloaded with
`apt-get download` (no root needed) and extracted with `dpkg-deb -x` into a
scratch directory to confirm the toolchain actually works before committing to
this approach — `swift --version` reported `Swift version 6.1.3
(swift-6.1.3-RELEASE)`, and `make preflight`/`make build`/`make run`/`make
check` all passed against it. A real `sudo apt-get install` was not run in
this session (no interactive sudo available to the agent); a human running
`make apt-deps` on this machine gets the same package, installed the normal
way.

## STT backend: apt `libwhisper-dev` + ggml Vulkan, not `transcribe-cpp-swift` (Phase 4)

Phase 4 (`docs/LINUX_MIGRATION_BRANCH_PLAN.md`, issue 004) needed GPU-accelerated
whisper.cpp inference on this box's AMD Radeon 780M (Phoenix) iGPU. Two
candidate paths existed; went with the apt package + direct C interop:

- **`transcribe-cpp-swift`** (already a macOS-only dependency of `Sources/Fluid`,
  pinned `0.1.2` in the `#if os(macOS)` branch of `Package.swift`) is a thin
  Swift wrapper that vendors/builds whisper.cpp itself via SwiftPM plugin
  build steps targeting Apple platforms (Metal/Accelerate acceleration) — it
  is not declared Linux-portable, and adopting it here would mean either
  patching its build steps for a Vulkan backend or losing GPU acceleration
  entirely. Not investigated further than reading its declared platform
  support, since a strictly simpler path was already available (see below) —
  don't reach for it on Linux unless the direct-linking path below stops
  being viable.
- **Direct `libwhisper`/`libggml` linking** (chosen): Ubuntu's `universe` repo
  ships whisper.cpp itself as real, current apt packages —
  `whisper.cpp` 1.8.3+dfsg-2 (CLI tools: `whisper-cli`, `whisper-server`,
  etc.), `libwhisper-dev`/`libwhisper1` (the C API, `whisper.h`), and `ggml`
  (whisper.cpp's tensor library) as `libggml-dev`/`libggml0`, with **dynamically
  loaded compute backends** as separate packages:
  `libggml0-backend-vulkan` (already installed on this box, `0.9.11-1`) and
  `libggml0-backend-hip` (ROCm/HIP, available but not installed — Phoenix
  iGPUs are not on AMD's official ROCm support matrix, so Vulkan was tried
  first and turned out to be sufficient).

**Verified the apt package actually has GPU support before building anything**:
ran the extracted `whisper-cli` binary (`apt-get download` + `dpkg-deb -x`,
same no-root pattern as the toolchain check above — no interactive `sudo` in
this session) against `~/.config/fluidvoice/dev/samples/test.wav`. Its log
output on startup was unambiguous:
```
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = AMD Radeon 780M Graphics (RADV PHOENIX) (radv) | uma: 1 | fp16: 1 ...
load_backend: loaded Vulkan backend from /usr/lib/x86_64-linux-gnu/ggml/backends0/libggml-vulkan.so
...
whisper_backend_init_gpu: using Vulkan0 backend
```
This confirmed the apt package needs zero source rebuilding — it already
dynamically loads the Vulkan backend and picks up the iGPU via Mesa's RADV
driver (`mesa-vulkan-drivers`, `libvulkan1`, already installed on this box).
whisper.cpp upstream's own `GGML_VULKAN=1` CMake build was not needed.

**Swift interop**: `whisper.h` is a complete, pure C API (`extern "C"`,
`stdbool`/`stdint` only, no C++ leaking into the header) — no hand-written C
shim was needed (unlike `Sources/LinuxAudioCaptureSupport`'s ALSA shim). The
new `Sources/LinuxWhisperSupport` target is a SwiftPM `.systemLibrary` with a
`module.modulemap` (`module CWhisper [system] { header "shim.h"; link
"whisper"; link "ggml"; link "ggml-base"; export * }`) and `pkgConfig:
"whisper"` pointing at the apt package's own `whisper.pc`. `Sources/
FluidVoiceLinuxCLICore/WhisperTranscriber.swift` calls the C API directly
(`whisper_init_from_file_with_params`, `whisper_full`, etc.).

**Gotcha — dynamic backends need an explicit load call**: unlike `whisper-cli`
(which loads them in its own startup boilerplate), the whisper.cpp/ggml
*library* API does not automatically `dlopen()` the Vulkan/CPU backend
plugins under `/usr/lib/<arch>/ggml/backends0/`. Skipping this is silent and
nasty: `whisper_init_with_params_no_state` logs `devices = 0` / `backends =
0` and then **crashes** (`ggml-backend.cpp:508: GGML_ASSERT(device) failed`)
instead of cleanly erroring or falling back to CPU. The fix is one call
before initializing any whisper context: `ggml_backend_load_all()` (declared
in `ggml-backend.h`, transitively included via `whisper.h` -> `ggml-cpu.h`).
This is now the first thing `WhisperTranscriber.transcribe` does.

**CPU fallback is automatic at the library level**: with
`whisper_context_params.use_gpu = true` (the CLI's default, `.auto` backend),
if Vulkan device init fails for any reason, whisper.cpp/ggml falls back to
the CPU backend on its own — no extra code needed on the Swift side. Verified
for real (not just asserted) by forcing Vulkan init to fail with an invalid
ICD path: `VK_ICD_FILENAMES=/nonexistent/no_such_icd.json ./FluidVoiceLinuxCLI
transcribe --in test.wav` still produced the correct transcription, just
slower (CPU backend loaded, `whisper_backend_init_gpu: no GPU found`, no
crash). `transcribe --no-gpu` forces this path explicitly and deterministically
via `use_gpu = false`, for testing or for boxes without a GPU at all.

**Model file**: whisper GGML models (e.g. `ggml-tiny.en.bin`,
`ggml-base.en.bin`) are not packaged by apt — download from
`https://huggingface.co/ggerganov/whisper.cpp` (or whisper.cpp's own
`models/download-ggml-model.sh` if building from source) and pass the path
via `transcribe --model <path>`. `ggml-base.en.bin` (~148 MB) is what this
ticket's verification used.

**Default model lookup order** (issue 007, when `--model` isn't given —
see `Sources/FluidVoiceLinuxCLICore/ModelPathResolver.swift`):

1. Repo-relative `models/ggml-base.en.bin`, if it exists — the dev-workflow
   default, used by `make run` from the repo root (matches `whisper-cli`'s
   own default).
2. Otherwise `$XDG_DATA_HOME/fluidvoice/models/ggml-base.en.bin`, falling
   back to `~/.local/share/fluidvoice/models/ggml-base.en.bin` when
   `$XDG_DATA_HOME` is unset — the real default for the binary once
   installed (`make install` puts it on `PATH`) and invoked from an
   arbitrary directory. Place the downloaded model there for a normal
   installed-binary setup, e.g.:
   ```sh
   mkdir -p ~/.local/share/fluidvoice/models
   cp ggml-base.en.bin ~/.local/share/fluidvoice/models/ggml-base.en.bin
   ```

**Real transcription + GPU-vs-CPU timing evidence** (this box, `ggml-base.en.bin`,
`~/.config/fluidvoice/dev/samples/test.wav`, ground truth "a b c d e f g h i j k l m n"):

| Run | Output | Inference time | User CPU time |
|---|---|---|---|
| GPU (`transcribe`, default) | "A, B, C, D, E, F, G, H, I, J, K, L, M, N." | 0.231s | 0.162s |
| Forced CPU (`--no-gpu`) | "A, B, C, D, E, F, G, H, I, J, K, L, M, N." | 3.231s | 47.570s |
| Forced GPU-init-failure fallback (`VK_ICD_FILENAMES=/nonexistent/...`) | "A, B, C, D, E, F, G, H, I, J, K, L, M, N." | 1.163s | (CPU backend, no crash) |

The ~14x gap in user CPU time (0.16s vs 47.6s) between the GPU and
forced-CPU runs — not just a wall-clock difference — is the strongest signal
that the Vulkan path is actually offloading compute to the iGPU rather than
silently running on CPU with the GPU log line printed for show.

**Dependencies added to `make apt-deps`** (see Makefile): `libwhisper-dev`,
`libwhisper1`, `libggml-dev`, `libggml0-backend-vulkan`, `mesa-vulkan-drivers`,
`libvulkan1`. `whisper.cpp` (the CLI package) is not a build dependency of the
Swift CLI itself, but is useful for canary-testing this stack independently —
not added to `apt-deps` to keep the Swift build's own dependency list minimal,
mention it here for anyone re-verifying by hand.

**No-root verification note**: this session had no interactive `sudo`
available (same constraint as the toolchain check above), so
`libwhisper-dev`/`libwhisper1`/`libggml-dev` were downloaded with `apt-get
download` and extracted with `dpkg-deb -x` into a scratch prefix, with
`CPATH`/`PKG_CONFIG_PATH`/`-Xlinker -L<scratch lib dir>` pointing `swift
build`/`swift test` at the extracted headers/libraries instead of the system
paths a real `make apt-deps` install would use — `libggml0`/
`libggml0-backend-vulkan` themselves were already installed system-wide, so
only the `-dev` headers and `.so` symlinks needed this workaround. A human
running `make apt-deps` gets the same packages installed the normal way at
their real system paths, and the `Package.swift` `pkgConfig`/`providers`
declaration on `CWhisper` reflects that normal, real install layout — not
the scratch workaround.

## Cohere Transcribe backend: Conformer GGUF via `crispasr` (Issues 008-010)

Issues 008–010 brought **Cohere Transcribe** (`CohereLabs/cohere-transcribe-03-2026`, #1 on Hugging Face Open ASR Leaderboard) to Linux:

- **Model format**: Quantized GGUF (`cohere-transcribe-q4_k.gguf`, 1.51 GB) from `cstr/cohere-transcribe-03-2026-GGUF`.
- **Runtime architecture**: Managed via `crispasr` Python/ggml worker to avoid symbol collisions between older distro `libggml` (0.9.11) and modern `libggml` (0.17.0).
- **CLI Usage**:
  ```sh
  # Transcribe with Cohere Transcribe (auto-locates ~/.cache/crispasr/cohere-transcribe-q4_k.gguf)
  fluidvoice-linux transcribe --in sample.wav --backend cohere [--lang en]

  # Transcribe with Whisper (default)
  fluidvoice-linux transcribe --in sample.wav --backend whisper
  ```
- **Performance**: Transcribes 10s audio in ~2.2s on CPU with Conformer accuracy.

