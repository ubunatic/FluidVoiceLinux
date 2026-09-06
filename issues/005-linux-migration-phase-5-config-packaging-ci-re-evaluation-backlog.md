# 005 — Linux migration Phase 5+: config, packaging, CI re-evaluation backlog

**Status**: Open
**Priority**: P3 (Low)
**Severity**: Minor
**Category**: Architecture

---

## 1. Problem & Motivation

Catch-all backlog ticket for `docs/LINUX_MIGRATION_BRANCH_PLAN.md`'s
"Phase 5+ (and so on)" section, kept as a single low-priority ticket
until any one item is scoped enough to split into its own P2 ticket.
Do not start any of this before issues 003 and 004 (record + transcribe
MVPs) are done — this is deliberately last.

## 2. Technical Specification / Findings

Candidate items from the plan doc, unscoped:
- Config/settings persistence — a headless equivalent of
  `Sources/Fluid/Persistence/**` (macOS-only, uses its own storage
  mechanism — check what it is before assuming a straight port works).
- Hotkey-free CLI UX polish: flags, `--daemon` mode, JSON output.
- Packaging: `.deb`/AppImage, once Phase 4 (MVP2) is stable.
- Re-evaluate CI: the user has fully disabled GitHub Actions; if a
  self-hosted/local Linux CI story is wanted later, scope it then —
  don't build speculative CI now.

## 3. Implementation & Verification Plan

When any item here is ready to start, split it into its own ticket
with a concrete acceptance criterion and real verification plan (per
`docs/AgenticLoop.md`'s canary/test-driven-verification invariant),
rather than expanding this ticket in place.
