.PHONY: ⚙️ 🤖  # ⚙️ = manual/once, 🤖 = managed

_prim := \033[36m
_rst  := \033[0m

# Linux CLI work stream only — see docs/LINUX_MIGRATION_BRANCH_PLAN.md.
# The macOS app keeps using build.sh/Xcode; this Makefile targets `swift build`
# on Linux and gates macOS-only targets out via Package.swift (Phase 0).
BINARY  := FluidVoiceLinuxCLI
PREFIX  ?= /usr/local
SWIFT_BUILD_FLAGS := -c release

# Toolchain decision (Phase 1): Ubuntu ships a real, current Swift toolchain as the
# `swiftlang` apt package (6.1.3 at the time of writing) — plenty recent for this
# package's `swift-tools-version: 5.9`. No vendored toolchain is needed; `apt-deps`
# installs `swiftlang`/`swiftlang-dev` directly. See docs/LINUX_SETUP.md.
SWIFT := swift

# Suite-level wall-clock cap for `swift test` (issues/020): a clean `swift package clean`
# rebuild + full test run measures ~8s and a warm run ~3s (61 tests, slowest single test
# ~1.1s), so 300s/5m leaves generous headroom while still catching a silent hang (the
# issue 017 incident ran 20+ minutes with nothing to catch it) in minutes, not tens of
# minutes. `--kill-after` guarantees a SIGKILL if the process tree ignores SIGTERM.
TEST_TIMEOUT      := 300
TEST_KILL_AFTER   := 10

help: 🤖  # show this help
	@grep -E '^[a-zA-Z_-]+:.*[⚙🤖].*#+' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*#+ "}; {printf "    $(_prim)%-15s$(_rst) %s\n", $$1, $$2}'

preflight: ⚙️  # check the Swift toolchain is on PATH
	@command -v $(SWIFT) >/dev/null || (echo "❌ swift is not installed — run 'make apt-deps' (Debian/Ubuntu) or 'make dnf-deps' (Fedora), see docs/LINUX_SETUP.md" && exit 1)
	@$(SWIFT) --version

build: ⚙️ preflight  # build the Linux CLI binary
	$(SWIFT) build $(SWIFT_BUILD_FLAGS) --product $(BINARY)

run: ⚙️ build  # run the freshly built binary (pass args via ARGS="record --seconds 3 --out /tmp/test.wav")
	.build/release/$(BINARY) $(ARGS)

install: ⚙️ build  # install to ~/.local/bin (user) and best-effort PREFIX/bin (system)
	@mkdir -p $(HOME)/.local/bin
	@install -m 0755 .build/release/$(BINARY) $(HOME)/.local/bin/$(BINARY) && \
	  ln -sf $(HOME)/.local/bin/$(BINARY) $(HOME)/.local/bin/fluidvoice-linux && \
	  ln -sf $(HOME)/.local/bin/$(BINARY) $(HOME)/.local/bin/fluidvoice && \
	  echo "✅ Installed to $(HOME)/.local/bin/$(BINARY) (with fluidvoice-linux & fluidvoice aliases)"
	@sudo install -m 0755 .build/release/$(BINARY) $(PREFIX)/bin/$(BINARY) 2>/dev/null && \
	  sudo ln -sf $(PREFIX)/bin/$(BINARY) $(PREFIX)/bin/fluidvoice-linux 2>/dev/null && \
	  sudo ln -sf $(PREFIX)/bin/$(BINARY) $(PREFIX)/bin/fluidvoice 2>/dev/null && \
	  echo "✅ Installed for all users" || echo "⚠️ System install skipped (no sudo)"

uninstall: ⚙️  # remove installed binary from user and system paths
	rm -f $(HOME)/.local/bin/$(BINARY) $(HOME)/.local/bin/fluidvoice-linux $(HOME)/.local/bin/fluidvoice $(PREFIX)/bin/$(BINARY) $(PREFIX)/bin/fluidvoice-linux $(PREFIX)/bin/fluidvoice

check: ⚙️ preflight  # run tests for Linux-eligible targets (excludes macOS-only Tests/FluidDictationIntegrationTests)
	@SWIFT=$(SWIFT) TEST_TIMEOUT=$(TEST_TIMEOUT) TEST_KILL_AFTER=$(TEST_KILL_AFTER) ./scripts/run-tests-with-timeout.sh

test: ⚙️ check  # alias for check

clean: ⚙️  # remove build artifacts
	$(SWIFT) package clean
	rm -rf .build

apt-deps: ⚙️  # install Swift toolchain + build deps on Debian/Ubuntu (sudo)
	sudo apt-get update
	sudo apt-get install -y \
		swiftlang \
		swiftlang-dev \
		clang \
		libcurl4-openssl-dev \
		libicu-dev \
		libxml2-dev \
		zlib1g-dev \
		libsqlite3-dev \
		libncurses-dev \
		libedit-dev \
		libasound2-dev \
		libwhisper-dev \
		libwhisper1 \
		libggml-dev \
		libggml0-backend-vulkan \
		mesa-vulkan-drivers \
		libvulkan1 \
		curl \
		git

dnf-deps: ⚙️  # install Swift toolchain + build deps on Fedora (sudo, untested on this box)
	sudo dnf install -y \
		swift-lang \
		clang \
		libcurl-devel \
		libicu-devel \
		libxml2-devel \
		zlib-devel \
		sqlite-devel \
		ncurses-devel \
		libedit-devel \
		alsa-lib-devel \
		whisper-cpp-devel \
		mesa-vulkan-drivers \
		vulkan-loader \
		curl \
		git
