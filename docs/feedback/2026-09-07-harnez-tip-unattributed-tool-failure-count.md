# harnez tip cites failed tool calls with no attributable command

## What happened

During Phase 3/4/007 fresh-sprint dev sessions on the Linux migration work
stream, `harnez` repeatedly printed a tip of the shape:

```
harnez tip: N tool call(s) failed without a `harnez rate` report — use
`harnez rate <tool> <score> "<summary>"` to record what went wrong (see
Tool Feedback Protocol).
```

At least twice this was investigated and the underlying "failed" call
could not be identified — no command in the session had returned a
nonzero/error exit status other than expected, harmless probes (e.g.
`git diff`/`ls` against a path that legitimately doesn't exist yet, or
`git show ... | head` triggering `SIGPIPE`). One occurrence *was*
successfully attributed (the `git show --stat ... | head` SIGPIPE case,
rated via `harnez rate Bash 3 ...`), but at least one other subagent
session hit the same tip and reported being unable to find any candidate
failing call at all before finishing its task.

## Why this matters

The protocol asks agents to rate the specific failing tool call with a
1-line outcome summary. When the failure can't be attributed to any
observed command, an agent either:
- guesses/fabricates a plausible-sounding but unverified rating target
  (bad — pollutes the feedback signal `harnez rate` is meant to collect), or
- silently ignores the tip (also bad — the underlying signal, whatever
  it is, goes unrecorded), or
- spends extra turns re-scanning session history for a failure that may
  not be re-discoverable from the agent's own transcript (the tip's
  failure-counting mechanism may see process-level or hook-level
  failures the agent's own tool-call history doesn't surface, e.g. a
  failed hook invocation rather than a failed user-visible tool call).

## What would help

Some way for the tip itself to name (or let the agent query) *which*
call(s) it considers failed — e.g. a `harnez rate --last-failed` or
`harnez feedback pending` listing that surfaces the actual command/tool
name and timestamp the counter is tracking, rather than only a count.
Without that, the tip is currently unactionable when the obvious
recent-history candidates don't pan out.

## Live reproduction while writing this note

The tip fired again (`4 tool call(s) failed`) immediately after `git add
-f`-ing this very file, in a run of commands (`make build`, `make test`,
a `transcribe` run from `/tmp`, `ls`, `git status --porcelain`) where
none had a nonzero exit as far as the agent's own tool-call history
shows. Confirms this isn't a one-off; the tip's failure count does not
correspond to anything visible in-session.

## Status

Not filed as a `harnez feedback issue` — this is proposed-tool-behavior
friction rather than a clear, reproducible bug with a known trigger.
Recorded here per `docs/AgenticLoop.md`'s "Calibrated Friction
Reporting" guidance for a genuine (if minor) recurring hurdle. Revisit
if it recurs with more detail, or if `harnez` gains a way to surface the
attributed call.
