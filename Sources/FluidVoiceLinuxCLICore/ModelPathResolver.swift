import Foundation

/// Issue 007 (see issues/007-default-whisper-model-path-is-cwd-relative-breaks-
/// when-installed.md): resolves the default whisper model path used by
/// `transcribe` when `--model` isn't given explicitly. Order:
///
/// 1. Explicit `--model` flag, if the caller passed one (unchanged behavior).
/// 2. Repo-relative `models/ggml-base.en.bin`, if it exists — keeps `make run`
///    from the repo root working exactly as before (issues 001-004's
///    verification), since that's still the convenient dev-workflow location.
/// 3. `$XDG_DATA_HOME/fluidvoice/models/ggml-base.en.bin`, falling back to
///    `~/.local/share/fluidvoice/models/ggml-base.en.bin` when `$XDG_DATA_HOME`
///    is unset — the real default for an installed binary invoked from an
///    arbitrary directory (`make install` puts the binary on `PATH`).
///
/// Pure function: takes injectable "does this path exist" / "what is
/// $XDG_DATA_HOME / $HOME" inputs (docs/SwiftLinux.md §3) so all three
/// branches are unit-testable without touching the real filesystem or
/// environment. `TranscribeCommand.run` supplies the real implementations.
public enum ModelPathResolver {
    public static let repoRelativeModelPath = "models/ggml-base.en.bin"
    static let xdgModelSubpath = "fluidvoice/models/ggml-base.en.bin"
    static let homeDataHomeSuffix = ".local/share"

    public static func resolve(
        explicit: String?,
        fileExists: (String) -> Bool,
        xdgDataHome: String?,
        home: String?
    ) -> String {
        if let explicit {
            return explicit
        }

        if fileExists(repoRelativeModelPath) {
            return repoRelativeModelPath
        }

        if let xdgDataHome, !xdgDataHome.isEmpty {
            return "\(xdgDataHome)/\(xdgModelSubpath)"
        }

        if let home, !home.isEmpty {
            return "\(home)/\(homeDataHomeSuffix)/\(xdgModelSubpath)"
        }

        // No $XDG_DATA_HOME and no $HOME — fall back to a relative path under
        // the XDG default suffix. Should not happen in practice (every real
        // login shell sets $HOME), but keeps this function total.
        return "\(homeDataHomeSuffix)/\(xdgModelSubpath)"
    }
}
