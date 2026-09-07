# 020 — Per-test and test-suite timeouts to prevent silent hangs (swift test / make check)

**Status**: Closed — per-test watchdog + suite-level `timeout` wrapper implemented and verified
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

- [x] Canary-verified which per-test timeout mechanism (native XCTest `executionTimeAllowance` on Linux, Swift Testing `.timeLimit()` trait, or a manual watchdog wrapper) actually works on this project's toolchain (Swift 6.1.3, swift-tools-version 5.9) — recorded in this ticket before implementation. See §6 below.
- [x] Every test in `Tests/FluidVoiceLinuxCLITests` (and `Tests/FluidDictationIntegrationTests` where applicable) has an enforced per-test timeout using the chosen mechanism. All 10 `XCTestCase` subclasses in `Tests/FluidVoiceLinuxCLITests` now override `invokeTest()` to run the real test body under `runWithTimeout` (see `Tests/FluidVoiceLinuxCLITests/TestTimeout.swift`). `Tests/FluidDictationIntegrationTests` is macOS-only and excluded from `make check`; left untouched (out of scope/low priority per this ticket's own text).
- [x] The `Makefile`'s `check`/`test` recipe wraps `swift test` with an overall suite-level wall-clock timeout, following `docs/Make.md`/`docs/Bash.md` conventions. `make check` now calls `scripts/run-tests-with-timeout.sh` (new script, follows `docs/Bash.md`: `#!/usr/bin/env bash`, `if test`, no `[[`/`[`), which runs `timeout --kill-after=$TEST_KILL_AFTER $TEST_TIMEOUT swift test` and turns a timeout (exit 124/137) into a hard failure distinct from the pre-existing "no test target yet" warning path.
- [x] Both the per-test and suite-level timeout values are chosen based on measuring the current suite's actual runtime (and slowest individual tests) with reasonable headroom — the measured baseline and chosen values are recorded in this ticket, not invented from assumption. See §7 below.
- [x] The specific `wl-copy`-spawning clipboard test (or equivalent `TextOutputDriver` subprocess test) is fixed to not inherit/hold open stdio from a resident child process, independent of the timeout work. (Fixed in issue 017's implementation: `TextOutputDriver.copyToClipboard`'s wl-copy branch now sets `standardOutput`/`standardError` to `FileHandle.nullDevice` instead of inheriting the caller's, and terminates the previous wl-copy instance before starting a new one. Untouched by this ticket.)
- [x] A deliberately-hung dummy test (e.g. an infinite sleep or a subprocess spawned the same broken way) is used to verify the per-test timeout actually fires and fails fast, and that the suite-level timeout independently caps a full-suite hang — not just that `swift test` exits 0 on the existing, already-passing suite. See §8 below (both proofs run, dummy tests removed afterward).
- [x] Open questions/limitations discovered during investigation (e.g. if Linux XCTest truly lacks `executionTimeAllowance` support) are recorded in this ticket rather than silently worked around. See §6 and §9 below.

## 5. Verification Plan

- Canary probe: attempt `executionTimeAllowance` and/or a minimal Swift Testing `@Test(.timeLimit(...))` case against this toolchain and record whether each compiles/enforces on Linux.
- Baseline measurement: run `swift test` (or `make check`) a few times and record total wall-clock time and the slowest individual test(s), to derive proposed timeout values with headroom.
- Regression test: introduce a temporary/dummy hanging test (removed or permanently disabled after verification) to confirm the per-test timeout fires and fails the test rather than hanging, and that the suite-level `timeout`-wrapped `make check` recipe exits non-zero within its cap rather than hanging indefinitely.
- Re-run the full existing suite after changes to confirm no regressions (no previously-passing test now spuriously times out).

## 6. Canary Results (recorded before implementation)

Ran against the real toolchain (`swift --version`: Swift 6.1.3, `x86_64-pc-linux-gnu`) in a scratch SwiftPM package, not the project package, to avoid polluting the real suite while probing:

1. **`XCTestCase.executionTimeAllowance` — NOT supported on Linux.** A minimal `XCTestCase` subclass that set `self.executionTimeAllowance = 2` in `invokeTest()` **failed to compile**:
   `error: value of type 'XCTestAllowanceTests' has no member 'executionTimeAllowance'`
   swift-corelibs-xctest on this toolchain does not expose the property at all (it's an Apple-XCTest-only API). This path is dead — confirmed negative, not just "untested."

2. **Swift Testing `@Test(.timeLimit(...))` — works, with two real caveats.**
   - The `Testing` module is bundled with the toolchain (`/usr/libexec/swift/lib/swift/linux/Testing.swiftmodule`) — no new SPM dependency needed, contrary to the ticket's "if adopting `swift-testing`..." framing.
   - A canary test with `@Test(.timeLimit(.minutes(1)))` wrapping `try await Task.sleep(nanoseconds: 200_000_000_000)` genuinely failed after ~60.0s with `Time limit was exceeded: 60.000 seconds` — the mechanism actively enforces and fails, it isn't just a documentation-only trait.
   - **Caveat A (disqualifying for "low-friction"):** `@Test` only works on free `async` functions, not on `XCTestCase` methods — adopting it means rewriting every one of the 61 existing `func testX()` XCTestCase methods across 10 classes into standalone `@Test` functions. That is a full-suite migration off XCTest, not an incremental addition, which the ticket explicitly says to avoid ("if adopting `swift-testing` turns out to require significant disruption to the existing XCTest suite, prefer the manual watchdog wrapper instead").
   - **Caveat B (disqualifying on its own):** `TimeLimitTrait.Duration.seconds(_:)` is explicitly `@available(*, unavailable, message: "Time limit must be specified in minutes")` — confirmed by compiler error when trying `.timeLimit(.seconds(3))`. Only minute granularity is available. This project's suite runs 61 tests in ~2-3s total with the slowest single test at ~1.1s; a minimum 1-minute-granularity timeout is far too coarse to be a meaningful per-test guard here.
   - **Decision: not adopted**, for both reasons independently.

3. **Manual watchdog wrapper — adopted.** A `Thread` + `DispatchSemaphore(timeout:)`-based watchdog, invoked once per `XCTestCase` subclass via an `invokeTest()` override (rather than wrapping every individual test method body), was canary-tested with three cases in one scratch suite: a passing test, a normal `XCTAssertEqual` failure, and a 30s `Thread.sleep` hang under a 3s watchdog. Result: the hang was caught and failed at exactly ~3.0s (`"Test exceeded 3s per-test timeout"`), the normal failure still surfaced correctly, and the passing test still passed — total suite wall time was ~4.8s, not 30s+. This is the mechanism implemented in `Tests/FluidVoiceLinuxCLITests/TestTimeout.swift`.

**Known limitation of the manual watchdog (recorded honestly, not worked around):** Swift/Foundation on Linux has no safe API to forcibly cancel a running `Thread`. If a test body is genuinely wedged (e.g. blocked in a syscall), the watchdog's `XCTFail` fires and the *test* is reported as failed and the suite *moves on*, but the underlying stuck thread keeps running in the background for the rest of the process's life. This is a real improvement over the original bug (no test blocks the suite indefinitely) but is not a true kill — the suite-level `timeout` wrapper (§7-8) is the actual backstop that reaps a genuinely wedged process tree (e.g. the original inherited-pipe class of bug), and is required precisely because the per-test watchdog cannot guarantee termination on its own.

## 7. Baseline Measurement & Chosen Timeout Values

Measured on this dev machine, repeated runs of the real project suite (`Tests/FluidVoiceLinuxCLITests`, 61 tests across 10 `XCTestCase` classes):

- Warm `swift test` (no rebuild): **~2.7-4.5s** wall clock (varied 2.7s / 3.1s / 4.3s / 4.5s across repeated runs).
- Cold `swift test` after `swift package clean`: **~8.2s** wall clock (includes full rebuild of `FluidVoiceLinuxCLICore`, `LinuxAudioCaptureSupport`, `CWhisper` system library wrapper, and the test target).
- Slowest individual test observed: **~1.1s** (subprocess/backend-detection-style test); the next slowest cluster is ~0.1-0.2s; the overwhelming majority of the 61 tests run in single-digit milliseconds or less.
- `ConcatenatedAudioDictationTests` is a special case: `testParakeetTranscriptionOn60sAudio` / `testCohereTranscriptionOn60sAudio` / `testWhisperTranscriptionOn60sAudio` synthesize ~88s of audio and run it through real ASR backends when dev sample fixtures + backend deps are present (`test60sConcatenatedAudioSynthesis` builds the fixture). In this environment they short-circuit fast (~0.3s) because the optional Python backends aren't installed, but when the backends *are* present, real model load + inference over ~88s of audio could plausibly take tens of seconds.

Chosen values (with headroom):

- **Per-test default: 15s** (`perTestTimeoutSeconds` in `TestTimeout.swift`) — roughly 13x the slowest observed real test (~1.1s), generous for slower/loaded CI machines while still failing a hang in seconds rather than minutes.
- **Per-class override: 180s for `ConcatenatedAudioDictationTests`** — accounts for the real-backend-transcription scenario above; a blanket 15s would risk spurious failures if/when those optional backends are installed and exercised for real.
- **Suite-level: `TEST_TIMEOUT=300` (5 minutes), `TEST_KILL_AFTER=10`** (`Makefile` variables, used by `scripts/run-tests-with-timeout.sh`) — roughly 35-100x the measured cold/warm full-suite runtime, comfortably below the 20+ minute silent hang from the issue 017 incident, so a hang anywhere (including inside `swift-test` itself, past all individual tests) is caught in minutes rather than eating a whole session. `--kill-after=10` sends `SIGKILL` if the process tree ignores the initial `SIGTERM`, matching the original bug's process-group-holding-a-pipe-open failure mode.

## 8. Regression Proof (dummy hangs — run then removed)

A temporary file `Tests/FluidVoiceLinuxCLITests/ZZZDummyHangTests.swift` (not committed, deleted immediately after verification) contained two throwaway `XCTestCase`s:

1. **Per-test watchdog proof**: `ZZZDummyPerTestWatchdogTests`, `invokeTest()` overridden with a 3s watchdog, one test doing `Thread.sleep(forTimeInterval: 300)`. Ran with `swift test --filter ZZZDummyPerTestWatchdogTests`:
   `error: ... failed - Test exceeded 3s per-test timeout — likely a hang or deadlock (see issues/020)`, test reported failed at exactly 3.0s, `swift test` process exited cleanly at ~5.2s total (not 300s). **Confirms the per-test mechanism fires and fails fast.**

2. **Suite-level backstop proof**: `ZZZDummySuiteHangTests.testLeavesResidentSubprocessHoldingStdioOpen` spawned `/bin/sleep 300` via `Process()` **without** redirecting stdout/stderr to `FileHandle.nullDevice` (deliberately reproducing the exact bug class fixed for `wl-copy` in issue 017) and returned immediately without waiting on it — so the test method itself passes its own per-test watchdog, but the orphaned child keeps the process's stdio pipe open after all tests finish. Ran with `TEST_TIMEOUT=8 TEST_KILL_AFTER=3 ./scripts/run-tests-with-timeout.sh`: all 61 real tests plus the dummy ran and completed, then the whole `swift test` invocation hung (as expected — this is exactly the issue 017 failure mode) and was killed by the wrapper at the 8s cap:
   `❌ swift test exceeded 8s suite-level timeout (see issues/020)`, script exited 1 at ~8.2s wall clock (not indefinitely). **Confirms the suite-level backstop independently catches a hang the per-test watchdog cannot see.**

The orphaned `/bin/sleep 300` process was manually killed after the proof (`kill -9`), and `ZZZDummyHangTests.swift` was deleted. Re-ran the real suite via `make check` afterward: 61 tests executed, same 3 pre-existing failures as the pre-change baseline (see §9), no new failures, no spurious timeouts, total wall time ~4.5s.

## 9. Open Questions / Limitations

- **Pre-existing, unrelated test failures** (not introduced or touched by this ticket, present before and after this change): `ConcatenatedAudioDictationTests.testCohereTranscriptionOn60sAudio`, `ConcatenatedAudioDictationTests.testParakeetTranscriptionOn60sAudio`, and `VoiceActivityDetectorTests.testSileroVADOnRealAudioSample` fail in this dev environment because optional Python packages (`crispasr`, `silero_vad`/`torch`) are not installed. Out of scope here; flagged for a separate ticket if not already tracked.
- **Manual watchdog cannot force-kill a genuinely wedged thread** (see §6) — it reports a fast, clear failure but the underlying stuck work keeps running in the background. The suite-level `timeout` wrapper is the real backstop for a truly wedged process tree; this is by design given Linux/Foundation's lack of a safe thread-cancellation API, not an oversight.
- **`make check`'s pre-existing "swallow real failures as a warning" behavior was preserved, not fixed.** The original recipe (`swift test || echo "no Linux test target yet..."`) already had the effect of returning exit 0 even when real tests fail (as currently happens with the 3 pre-existing failures above) — it was written for an earlier pre-test-suite phase of the Linux migration and never tightened after real tests landed. This ticket's script (`scripts/run-tests-with-timeout.sh`) intentionally preserves that exact fallback-warning behavior for any non-timeout failure (to stay in scope and not silently change `make check`'s pass/fail semantics as a side effect), while adding a genuinely new hard-failure path for timeouts (exit 124/137 -> script exits 1). Whether `make check` should also start hard-failing on ordinary test failures is a separate, pre-existing gap worth its own ticket.
- Swift Testing's bundled availability (no new SPM dependency required) means a *future*, deliberate, whole-suite migration to Swift Testing remains a live option if the team ever wants native per-test timeouts with less custom code — just not adopted now, per the caveats in §6.
