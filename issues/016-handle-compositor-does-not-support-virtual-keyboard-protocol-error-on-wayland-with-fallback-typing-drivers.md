# 016 — Handle 'Compositor does not support virtual keyboard protocol' error on Wayland with fallback typing drivers

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Moderate
**Category**: Bug
**Related**: `issues/014-end-to-end-live-dictation-pipeline-dictate-subcommand-with-typing-output.md`, `issues/015-integration-tests-for-60s-concatenated-audio-dictation-clipboard-typing-output-drivers.md`

---

## 1. Problem & Motivation

When `--type` is selected as an output target for `dictate` or `transcribe`, `TextOutputDriver.swift` currently checks for `WAYLAND_DISPLAY != nil` and prioritizes candidate typing tools in order: `["wtype", "ydotool", "xdotool"]`.

On Wayland compositors that do not implement or expose the `zwp_virtual_keyboard_v1` protocol (notably GNOME/Mutter and certain restricted or locked-down Wayland sessions), `wtype` fails with:
```
Compositor does not support the virtual keyboard protocol
```
Because `TextOutputDriver.swift` currently stops after the first executable found on `$PATH` (`findExecutable` returns `wtype`), any failure of `wtype` immediately throws `TextOutputDriverError.executionFailed`, halting text output and terminating the dictation/transcription workflow without attempting other available drivers.

## 2. Technical Findings & Proposed Solution

### Technical Findings
1. **Candidate Tool Resolution**:
   - `wtype` requires `zwp_virtual_keyboard_v1` (supported by wlroots-based compositors like Sway, Hyprland, Wayfire, River, but not GNOME/Mutter).
   - `ydotool` operates via the Linux `/dev/uinput` kernel device (communicating with `ydotoold`), which works independently of Wayland compositor protocols.
   - `dotool` is an alternative `/dev/uinput` or Wayland input injector.
   - `xdotool` works under X11 or XWayland (when an X11 window has focus).
2. **Current Failure Mode**:
   - `findExecutable(candidates)` finds the first binary present on `$PATH`. If `wtype` is installed on a GNOME Wayland system, `TextOutputDriver` executes `wtype`, captures its non-zero exit status or error output, and fails unconditionally rather than trying the next candidate.

### Proposed Solution
1. **Sequential Driver Fallback**:
   - Refactor `TextOutputDriver.simulateTyping(_:)` to iterate through available candidate typing tools (`wtype`, `ydotool`, `dotool`, `xdotool`) rather than selecting only the first binary found.
   - If a tool fails (e.g. `wtype` exiting due to protocol unavailability, or `ydotool` unable to reach `ydotoold` / `/dev/uinput`), capture the failure diagnostic and attempt the next candidate tool in sequence.
2. **Graceful Clipboard / Paste Fallback**:
   - If all typing tools fail or none are available, provide a fallback strategy: copy the transcribed text to the system clipboard (`copyToClipboard`) and notify the user (or optionally trigger a paste shortcut if configured/supported).
3. **Actionable Diagnostics & Error Messaging**:
   - Surface clear diagnostic hints when typing fails across all tools (e.g. indicating why `wtype` failed and how to set up `ydotool` / `ydotoold` permissions or `/dev/uinput`).

## 3. Implementation & Verification Plan

### Acceptance Criteria
- [ ] `TextOutputDriver.swift` attempts secondary typing drivers (`ydotool`, `dotool`, `xdotool`) if `wtype` exits with a protocol error or non-zero status.
- [ ] If all keystroke simulation tools fail, the driver falls back gracefully to clipboard copy with clear diagnostic logging to stderr.
- [ ] Helpful, actionable error diagnostics are provided explaining compositor limitations and `ydotool`/uinput setup instructions.
- [ ] Unit tests and mock execution tests cover the sequential fallback and clipboard fallback scenarios.

### Verification Plan
1. Unit tests in `Tests/FluidVoiceLinuxCLICoreTests/` verifying driver fallback sequences when simulated commands fail with protocol errors.
2. Test on Wayland environments (GNOME/Mutter vs wlroots) verifying smooth fallback behavior without crash or unhandled error propagation.

