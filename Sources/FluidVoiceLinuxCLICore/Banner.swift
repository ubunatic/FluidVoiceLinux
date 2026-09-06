import Foundation

/// Phase 2 canary content (see docs/LINUX_MIGRATION_BRANCH_PLAN.md and
/// issues/002-linux-migration-phase-2-hello-swift-canary-cli.md). Split into a small
/// library target so the banner-building logic is testable from
/// Tests/FluidVoiceLinuxCLITests without depending on the executable target directly.
public enum FluidVoiceLinuxCLIBanner {
    public static let programName = "FluidVoiceLinuxCLI"

    // Placeholder — no real versioning wired up yet, see Phase 2 scope.
    public static let version = "0.1.0-linux-canary"

    /// Builds the "hello swift" banner, including live OS/platform info so this
    /// proves it is actually running as a Linux CLI rather than printing a
    /// hardcoded platform string.
    public static func banner() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        \(programName) v\(version) — hello swift
        Running on: \(osVersion)
        """
    }
}
