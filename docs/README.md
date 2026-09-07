# Project Docs Index

`docs/` holds two kinds of files — see `docs/Markdown.md` for the
naming convention (PascalCase evergreen, kebab-case ephemeral).

## Harnez-managed practice docs

Referenced directly from the project's `CLAUDE.md` — general agentic/
dev conventions, not specific to this project. Read `CLAUDE.md` for the
canonical list; not duplicated here since harnez keeps these in sync.

`AgenticLoop.md`, `Bash.md`, `Canary.md`, `Git.md`, `IssueTracking.md`,
`Make.md`, `Markdown.md`, `Spec.md`.

## Project evergreens

Specific to FluidVoice / this repo, not managed by harnez:

- [SwiftLinux.md](SwiftLinux.md) — how Swift-on-Linux actually behaves:
  toolchain gotchas, the `Package.swift` platform-gating trick, the
  executable/library testability split, C-interop target patterns
  (hand-written shim vs. `.systemLibrary`), where an installed CLI
  should look for its own data files. **Read this first** before any
  Linux CLI work.
- [LINUX_MIGRATION_BRANCH_PLAN.md](LINUX_MIGRATION_BRANCH_PLAN.md) —
  the phased roadmap for the Linux CLI work stream (canary → record →
  transcribe → ...). Phases 0-4 done; see its Status section.
- [LINUX_SETUP.md](LINUX_SETUP.md) — toolchain/dependency install
  details and decisions (apt package names, ALSA vs. PipeWire, whisper
  backend choice) for the Linux CLI work stream.
- [MACOS_UI_AUTOMATION_BRANCH_PLAN.md](MACOS_UI_AUTOMATION_BRANCH_PLAN.md)
  — unrelated: a separate-branch plan for macOS `XCUITest` automation
  coverage. Not touched by the Linux migration work.

## Feedback notes (`docs/feedback/`)

Ephemeral, kebab-case with date prefixes — genuine agentic/tooling
friction worth remembering but not yet a filed `harnez feedback issue`.
Check here before re-reporting the same friction.

- [2026-09-07-harnez-tip-unattributed-tool-failure-count.md](feedback/2026-09-07-harnez-tip-unattributed-tool-failure-count.md)

## Note on `docs/` and git

`docs/` is gitignored repo-wide (`.gitignore`) except for files
explicitly `git add -f`'d — every file listed above is force-tracked.
When adding a new project evergreen or feedback note, remember
`git add -f`, or it silently won't be committed.

## Case studies (`docs/studies/`)

Retrospectives written via the `story` skill — candid session
post-mortems used as research material for refining evergreen docs and
harness rules.

| Date | Study | Summary |
|---|---|---|
| 2026-09-07 | [swift-token-burn.md](studies/2026-09-07-swift-token-burn.md) | A fresh-sprint subagent burned 202k tokens diagnosing a `wl-copy` stdio-inheritance hang in `swift test` with no timeout anywhere to bound the search; the subagent correctly refused to revert its verified fix when a coordinator escalation was based on stale state. |
