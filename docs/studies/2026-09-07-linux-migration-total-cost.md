# The Cost of the Linux Migration

## 1. Header & Context

- **Date**: 2026-09-07
- **Scope**: total Claude Code cost of standing up the Linux CLI port of
  FluidVoice from scratch — Phases 0-6 (canary → record → GPU-accelerated
  transcribe → VAD → AI enhancement → streaming dictate), 21 issues
  filed/closed (001-021), 50 commits touching Linux-specific paths, across
  **2026-09-06 to 2026-09-07** (about 2 calendar days).
- **Trigger**: the user asked for an estimate of the whole effort's token
  cost, then ran `/usage` on the current session and asked for a doc.

## 2. Hard Numbers (this session only, from `/usage`)

Authoritative, reported directly by Claude Code for session
`46ab69dc-28c5-42a9-a776-ebdc6d10ce2b` (issue 020 verification, issue 021
filing/closing, README voxi handoff note, this cost analysis):

| Metric | Value |
|---|---|
| Total cost | **$13.10** |
| API duration | 51m 49s |
| Wall duration | 6h 36m 58s |
| Code changes | +1217 / -134 lines |
| `claude-sonnet-5` | 69.0k input, 223.6k output, 42.4M cache read, 726.9k cache write ($13.06) |
| `claude-haiku-4-5` | 32.6k input, 2.3k output, 0 cache ($0.04) |
| Prompt cache | 98% of input tokens served from cache; 124 requests, 1 miss |

The Haiku usage (0.3% of session cost) was not something invoked
deliberately — it matches Claude Code's own internal lightweight machinery
(e.g. the auto-mode permission classifier that gated a `git commit --amend`
attempt this session), not the main reasoning stream, which ran on Sonnet 5
throughout.

## 3. Estimated Numbers (prior session, no `/usage` available)

Only **one other** local session transcript exists for this project:
`69bc1e67-19cc-46a5-8bd6-de0da999eedd` (started 2026-09-07 01:32, 341
assistant turns) — this is almost certainly the session that did the bulk of
the implementation work (Phases 0-6, issues 001-020), since it's the only
other Claude Code history found for this working directory.

`/usage` was never run in that session, so there is no authoritative cost
figure for it. Summing the raw `usage` blocks embedded in its transcript
gives:

| Field | Raw sum |
|---|---|
| input_tokens | 677 |
| cache_creation_input_tokens | 483,579 |
| cache_read_input_tokens | 58,874,714 |
| output_tokens | 189,947 |

**Caveat on accuracy**: running the identical summation method against
*this* session's own transcript file yielded 20.4M cache-read tokens versus
the 42.4M `/usage` actually reported — i.e. the transcript-sum method
undercounts by roughly 2x here, likely because it misses tool-result/
sub-agent token accounting that `/usage` includes. Treat the prior
session's raw sums, and any cost derived from them, as a **lower-bound
estimate**, not a measurement.

Applying published Sonnet-5-class list pricing ($3/M input, $15/M output,
$6/M cache write at 1h TTL, $0.30/M cache read) to those raw sums gives a
back-of-envelope **~$23** for that session — plausibly **$25-45** once the
same ~2x undercount correction seen in §2 is applied.

## 4. Total Estimate

| Session | Cost |
|---|---|
| `46ab69dc...` (this session, measured) | $13.10 |
| `69bc1e67...` (prior session, estimated) | ~$25-45 |
| **Total (2 known sessions)** | **~$40-60** |

This is bounded to the **2 Claude Code sessions with local transcripts** for
this project directory — no earlier history was found (no other project
directories matched, no other session files exist). If any part of Phases
0-6 was done through a different tool, a different session cache that has
since been pruned, or before the transcript retention window, it isn't
reflected here.

## 5. Key Takeaway

For ~2 days of work — a from-scratch Swift/Linux CLI port covering audio
capture, three swappable GPU-accelerated STT backends, VAD segmentation,
local LLM post-enhancement, and streaming dictation with X11/Wayland output
drivers, all with real test coverage — total agentic cost across the known
sessions lands in the **$40-60** range. The single most expensive
identified sub-task remains issue 017 (continuous streaming dictation),
documented separately in
[2026-09-07-swift-token-burn.md](2026-09-07-swift-token-burn.md) at ~202k
tokens for one ticket, chasing a silent subprocess-hang bug with no
timeout infrastructure to bound the search — see issue 020 for the fix
that followed.
