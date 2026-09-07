import XCTest
import Foundation

// Per-test wall-clock timeout enforcement (issues/020).
//
// Canary results (recorded in issues/020, negative results included):
//   - `XCTestCase.executionTimeAllowance` does not exist on swift-corelibs-xctest for this
//     project's toolchain (Swift 6.1.3, Linux) — setting it fails to compile. Apple's
//     per-test allowance API is not available here.
//   - Swift Testing's `@Test(.timeLimit(...))` trait does work on Linux with this
//     toolchain (bundled `Testing` module, no extra SPM dependency needed) and genuinely
//     fails a hung `async` test once the limit elapses. However its `Duration` only
//     accepts minute granularity (`.seconds(_:)` is `unavailable`), and adopting it means
//     rewriting every `XCTestCase`/`func testX()` in this suite into standalone
//     `@Test`/`async` functions — a full-suite migration off XCTest, not a low-friction
//     addition. Given the suite's tests normally run in well under a second, a
//     minute-granularity native timeout is also too coarse to be a useful per-test guard.
//   - A manual watchdog (below) works today, needs no new dependency, and needs no test
//     rewrite: each `XCTestCase` overrides `invokeTest()` once to run the real test body on
//     a background thread and fail fast if it does not finish within `perTestTimeoutSeconds`.
//
// LIMITATION (recorded honestly, not worked around): this cannot forcibly kill a thread
// that is truly stuck (Swift/Foundation on Linux has no safe thread-cancellation API), so a
// genuinely wedged synchronous call keeps running in the background after `XCTFail` fires.
// This is still a real improvement — the suite fails that test promptly and moves on
// instead of hanging on it — but the actual backstop against a wedged process tree (e.g.
// stuck on an inherited subprocess pipe) is the suite-level `timeout`-wrapped `make check`
// recipe in the Makefile, which reaps the whole process tree unconditionally.
let perTestTimeoutSeconds: TimeInterval = 15

extension XCTestCase {
    /// Runs `body` — the real per-test invocation — under a wall-clock watchdog. If `body`
    /// has not completed within `seconds`, records a clear `XCTFail` and returns promptly
    /// instead of blocking the suite. See the file-level comment for the mechanism's
    /// rationale and known limitation.
    func runWithTimeout(
        _ seconds: TimeInterval = perTestTimeoutSeconds,
        file: StaticString = #filePath,
        line: UInt = #line,
        body: @escaping () -> Void
    ) {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            body()
            done.signal()
        }
        thread.stackSize = 4 << 20
        thread.start()
        if done.wait(timeout: .now() + seconds) == .timedOut {
            XCTFail(
                "Test exceeded \(Int(seconds))s per-test timeout — likely a hang or deadlock (see issues/020)",
                file: file,
                line: line
            )
        }
    }
}
