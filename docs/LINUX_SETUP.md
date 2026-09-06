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
