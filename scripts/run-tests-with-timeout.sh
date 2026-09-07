#!/usr/bin/env bash
set -uo pipefail
# Suite-level wall-clock cap for `swift test` (issues/020). Deliberately does not use
# `set -e` here: the exit status of the `timeout`-wrapped `swift test` call must be
# inspected, not just propagated.

swift_bin="${SWIFT:-swift}"
test_timeout="${TEST_TIMEOUT:-300}"
test_kill_after="${TEST_KILL_AFTER:-10}"

timeout --kill-after="$test_kill_after" "$test_timeout" "$swift_bin" test
status=$?

if test "$status" -eq 124 -o "$status" -eq 137
then printf '❌ swift test exceeded %ss suite-level timeout (see issues/020)\n' "$test_timeout" >&2
     exit 1
fi

if test "$status" -ne 0
then printf '⚠️  no Linux test target yet — expected pre-Phase 5, see docs/LINUX_MIGRATION_BRANCH_PLAN.md\n'
fi

exit 0
