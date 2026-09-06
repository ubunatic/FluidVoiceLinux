// Phase 3 (see docs/LINUX_MIGRATION_BRANCH_PLAN.md and
// issues/003-linux-migration-phase-3-mvp-record-audio-alsa-pipewire.md) adds the
// `record` subcommand on top of the Phase 2 canary banner (issue 002). Per the
// executable/library split (docs/SwiftLinux.md §3), all real logic lives in
// FluidVoiceLinuxCLICore — this file stays a thin dispatcher with no
// subcommand-parsing framework (hand-rolled `CommandLine.arguments`, as planned).
import FluidVoiceLinuxCLICore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

if let subcommand = arguments.first {
    switch subcommand {
    case "record":
        exit(RecordCommand.run(arguments: Array(arguments.dropFirst())))
    case "transcribe":
        exit(TranscribeCommand.run(arguments: Array(arguments.dropFirst())))
    case "dictate":
        exit(DictateCommand.run(arguments: Array(arguments.dropFirst())))
    default:
        FileHandle.standardError.write(Data("unknown subcommand '\(subcommand)'\n".utf8))
        exit(1)
    }
} else {
    print(FluidVoiceLinuxCLIBanner.banner())
}
