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
	  echo "✅ Installed to $(HOME)/.local/bin/$(BINARY)"
	@sudo install -m 0755 .build/release/$(BINARY) $(PREFIX)/bin/$(BINARY) && \
	  echo "✅ Installed for all users" || echo "⚠️ System install skipped (no sudo)"

uninstall: ⚙️  # remove installed binary from user and system paths
	rm -f $(HOME)/.local/bin/$(BINARY) $(PREFIX)/bin/$(BINARY)

check: ⚙️ preflight  # run tests for Linux-eligible targets (excludes macOS-only Tests/FluidDictationIntegrationTests)
	@$(SWIFT) test || echo "⚠️  no Linux test target yet — expected pre-Phase 5, see docs/LINUX_MIGRATION_BRANCH_PLAN.md"

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
