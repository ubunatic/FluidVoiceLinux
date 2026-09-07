# 020 — Per-test and test-suite timeouts to prevent silent hangs (swift test / make check)

**Status**: In Progress — fresh-sprint: per-test and suite-level timeouts
**Priority**: P1 (High)
**Severity**: Major
**Category**: Infrastructure
**Related**: `issues/017-continuous-streaming-dictation-loop-in-dictate-subcommand-without-premature-cutoff.md` (implementation session that triggered this), `Sources/FluidVoiceLinuxCLICore/TextOutputDriver.swift`, `Tests/FluidVoiceLinuxCLITests`, `Package.swift`, `Makefile`, `docs/Make.md`, `docs/Bash.md`

---

## 1. Problem & Motivation

During the fresh-sprint implementation of issue 017, a subagent's `swift test` run hung for 20+ minutes with zero indication anything was wrong.

### Root cause (diagnosed manually mid-session)

A newly-added clipboard-output unit test (matched by the string "FluidVoice transcription output test", exercising `TextOutputDriver`'s clipboard path) spawned a real `wl-copy --trim-newline` subprocess via `Process()` without detaching its stdio. `wl-copy` intentionally stays resident after being invoked — that's how it keeps serving the Wayland clipboard selection — so the orphaned `wl-copy` process kept the test's inherited stdout/stderr pipe open. The actual XCTest runner process had already gone zombie, but `swift-test` itself blocked forever in `sigsuspend` (frozen CPU time) waiting for EOF on that pipe, which would never arrive.

There was no timeout anywhere in the toolchain — not at the individual-test level, not at the suite/invocation level — to catch this automatically. The hang silently consumed 20+ minutes of a session before a human noticed and asked "is this stuck?" and had to manually kill PIDs and redirect the subagent.

This is a **general process/testing-infrastructure gap**, not specific to that one test: any future test that shells out to a subprocess with similarly non-terminating or pipe-inheriting behavior can reproduce the same silent hang, and nothing in the current setup would catch it.

## 2. Current State (investigated this session)

- `Package.swift` (`swift-tools-version: 5.9`, actual toolchain `Swift 6.1.3`) declares one Linux test target, `FluidVoiceLinuxCLITests` (29 `func test...` cases across `Tests/FluidVoiceLinuxCLITests` and the macOS-only `Tests/FluidDictationIntegrationTests`). No `swift-testing` package dependency is declared, and no test file currently does `import Testing` — the suite is plain XCTest.
- `Makefile`'s `check`/`test` targets (`check: ⚙️ preflight` → `$(SWIFT) test`, `test: ⚙️ check` as an alias) invoke `swift test` with no wrapping timeout of any kind.
- **Open question, not yet verified**: whether XCTest on Linux (as shipped with this project's Swift 6.1.3 toolchain) supports a per-test execution-time allowance (`XCTestCase.executionTimeAllowance` is documented for Apple's XCTest but its Linux/swift-corelibs-xctest support is unconfirmed), and whether adopting Swift Testing's `.timeLimit()` trait is viable without otherwise changing the suite off XCTest. This needs a canary check against the actual toolchain before committing to an implementation approach — do not assume either mechanism "just works" here.

## 3. Proposal & Scope

Two layers of timeout enforcement, per the user's ask ("each test must have a proper timeout and big test suites must have their own timeout too"):

1. **Per-test timeout**: a maximum duration enforced per individual test method, so one hanging test fails fast with a clear timeout error instead of hanging (or zombie-blocking) the whole suite indefinitely. Candidate mechanisms to canary-check against the real toolchain before choosing one:
   - `XCTestCase.executionTimeAllowance` if actually supported by swift-corelibs-xctest on this Linux toolchain.
   - Migrating affected/new tests to Swift Testing's `@Test(.timeLimit(...))` trait, if pulling in `swift-testing` (bundled with the Swift 6 toolchain, or as an explicit SPM dependency) is otherwise low-friction for this package.
   - A manual test-level wrapper (e.g. a `withTimeout` helper using `DispatchQueue`/a watchdog thread that fails the test and force-terminates any child process) if neither native mechanism is available on this toolchain.
2. **Suite-level timeout**: an overall wall-clock cap on the entire `swift test` invocation, wrapping the `Makefile`'s `check`/`test` recipe (e.g. with the `timeout` shell utility) so a hang anywhere — including in tooling itself (`swift-test`'s process-reaping, not just user test code) — can't silently eat a session indefinitely. Any shell snippet must follow this repo's `docs/Bash.md`/`docs/Make.md` conventions (no `;`, no `if [[ ]]`/`if [ ]`, use `if test`, `⚙️` phony sentinel, smart indent).
3. **Subprocess hygiene for tests that shell out**: separately from timeouts, any test that spawns a subprocess (like the `wl-copy` case) should detach/redirect its stdio (e.g. pipe to `/dev/null` or explicitly close inherited fds) so an intentionally-resident child process can't hold the test runner's pipes open. This is a complementary fix, not a substitute for the timeout layers above — future subprocess-spawning tests could still hang for other reasons (e.g. a real deadlock) that a timeout would catch but stdio hygiene wouldn't.

### Timeout durations — explicitly not prescribed here

Do not invent specific timeout numbers in this ticket. Pick sane defaults **based on the current suite's typical/observed runtime, with headroom**, as part of the investigation work — see Acceptance Criteria below.

## 4. Acceptance Criteria

- [ ] Canary-verified which per-test timeout mechanism (native XCTest `executionTimeAllowance` on Linux, Swift Testing `.timeLimit()` trait, or a manual watchdog wrapper) actually works on this project's toolchain (Swift 6.1.3, swift-tools-version 5.9) — recorded in this ticket before implementation.
- [ ] Every test in `Tests/FluidVoiceLinuxCLITests` (and `Tests/FluidDictationIntegrationTests` where applicable) has an enforced per-test timeout using the chosen mechanism.
- [ ] The `Makefile`'s `check`/`test` recipe wraps `swift test` with an overall suite-level wall-clock timeout, following `docs/Make.md`/`docs/Bash.md` conventions.
- [ ] Both the per-test and suite-level timeout values are chosen based on measuring the current suite's actual runtime (and slowest individual tests) with reasonable headroom — the measured baseline and chosen values are recorded in this ticket, not invented from assumption.
- [x] The specific `wl-copy`-spawning clipboard test (or equivalent `TextOutputDriver` subprocess test) is fixed to not inherit/hold open stdio from a resident child process, independent of the timeout work. (Fixed in issue 017's implementation: `TextOutputDriver.copyToClipboard`'s wl-copy branch now sets `standardOutput`/`standardError` to `FileHandle.nullDevice` instead of inheriting the caller's, and terminates the previous wl-copy instance before starting a new one. The rest of this ticket's scope -- per-test/suite timeout enforcement -- is still open.)
- [ ] A deliberately-hung dummy test (e.g. an infinite sleep or a subprocess spawned the same broken way) is used to verify the per-test timeout actually fires and fails fast, and that the suite-level timeout independently caps a full-suite hang — not just that `swift test` exits 0 on the existing, already-passing suite.
- [ ] Open questions/limitations discovered during investigation (e.g. if Linux XCTest truly lacks `executionTimeAllowance` support) are recorded in this ticket rather than silently worked around.

## 5. Verification Plan

- Canary probe: attempt `executionTimeAllowance` and/or a minimal Swift Testing `@Test(.timeLimit(...))` case against this toolchain and record whether each compiles/enforces on Linux.
- Baseline measurement: run `swift test` (or `make check`) a few times and record total wall-clock time and the slowest individual test(s), to derive proposed timeout values with headroom.
- Regression test: introduce a temporary/dummy hanging test (removed or permanently disabled after verification) to confirm the per-test timeout fires and fails the test rather than hanging, and that the suite-level `timeout`-wrapped `make check` recipe exits non-zero within its cap rather than hanging indefinitely.
- Re-run the full existing suite after changes to confirm no regressions (no previously-passing test now spuriously times out).
