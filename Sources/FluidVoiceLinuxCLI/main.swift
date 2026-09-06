// Phase 2 canary for the Linux migration (see docs/LINUX_MIGRATION_BRANCH_PLAN.md and
// issues/002-linux-migration-phase-2-hello-swift-canary-cli.md). Replaces the Phase 0
// compile-gating stub (`print("stub")`, issue 001) with the real "hello swift" banner —
// the go/no-go gate before investing in Phase 3 (audio capture). Banner-building logic
// lives in FluidVoiceLinuxCLICore so it is unit-testable; this file is kept to a single
// simple entrypoint (no subcommand/argument-parsing framework yet — that's Phase 3).
import FluidVoiceLinuxCLICore

print(FluidVoiceLinuxCLIBanner.banner())
