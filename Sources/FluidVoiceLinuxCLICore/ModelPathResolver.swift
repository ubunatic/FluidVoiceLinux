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

    public static let repoRelativeCohereModelPath = "models/cohere-transcribe-q4_k.gguf"
    static let xdgCohereModelSubpath = "fluidvoice/models/cohere-transcribe-q4_k.gguf"
    static let crispasrCacheSubpath = ".cache/crispasr/cohere-transcribe-q4_k.gguf"

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

    public static func resolveCohere(
        explicit: String?,
        fileExists: (String) -> Bool,
        xdgDataHome: String?,
        home: String?
    ) -> String {
        if let explicit {
            return explicit
        }

        if fileExists(repoRelativeCohereModelPath) {
            return repoRelativeCohereModelPath
        }

        if let home, !home.isEmpty {
            let crispCache = "\(home)/\(crispasrCacheSubpath)"
            if fileExists(crispCache) {
                return crispCache
            }
        }

        if let xdgDataHome, !xdgDataHome.isEmpty {
            return "\(xdgDataHome)/\(xdgCohereModelSubpath)"
        }

        if let home, !home.isEmpty {
            return "\(home)/\(homeDataHomeSuffix)/\(xdgCohereModelSubpath)"
        }

        return "\(homeDataHomeSuffix)/\(xdgCohereModelSubpath)"
    }

    public static let repoRelativeParakeetModelPath = "models/parakeet-tdt-0.6b-v3-q4_k.gguf"
    static let xdgParakeetModelSubpath = "fluidvoice/models/parakeet-tdt-0.6b-v3-q4_k.gguf"
    static let crispasrParakeetCacheSubpath = ".cache/crispasr/parakeet-tdt-0.6b-v3-q4_k.gguf"

    public static let repoRelativeNemotronModelPath = "models/nemotron-3.5-asr-streaming-0.6b-q4_k.gguf"
    static let xdgNemotronModelSubpath = "fluidvoice/models/nemotron-3.5-asr-streaming-0.6b-q4_k.gguf"
    static let crispasrNemotronCacheSubpath = ".cache/crispasr/nemotron-3.5-asr-streaming-0.6b-q4_k.gguf"

    public static func resolveParakeet(
        explicit: String?,
        fileExists: (String) -> Bool,
        xdgDataHome: String?,
        home: String?
    ) -> String {
        if let explicit { return explicit }
        if fileExists(repoRelativeParakeetModelPath) { return repoRelativeParakeetModelPath }
        if let home, !home.isEmpty {
            let cachePath = "\(home)/\(crispasrParakeetCacheSubpath)"
            if fileExists(cachePath) { return cachePath }
        }
        if let xdgDataHome, !xdgDataHome.isEmpty { return "\(xdgDataHome)/\(xdgParakeetModelSubpath)" }
        if let home, !home.isEmpty { return "\(home)/\(homeDataHomeSuffix)/\(xdgParakeetModelSubpath)" }
        return "\(homeDataHomeSuffix)/\(xdgParakeetModelSubpath)"
    }

    public static func resolveNemotron(
        explicit: String?,
        fileExists: (String) -> Bool,
        xdgDataHome: String?,
        home: String?
    ) -> String {
        if let explicit { return explicit }
        if fileExists(repoRelativeNemotronModelPath) { return repoRelativeNemotronModelPath }
        if let home, !home.isEmpty {
            let cachePath = "\(home)/\(crispasrNemotronCacheSubpath)"
            if fileExists(cachePath) { return cachePath }
        }
        if let xdgDataHome, !xdgDataHome.isEmpty { return "\(xdgDataHome)/\(xdgNemotronModelSubpath)" }
        if let home, !home.isEmpty { return "\(home)/\(homeDataHomeSuffix)/\(xdgNemotronModelSubpath)" }
        return "\(homeDataHomeSuffix)/\(xdgNemotronModelSubpath)"
    }

    public static let repoRelativeSileroVadPath = "models/silero_vad.onnx"
    static let xdgSileroVadSubpath = "fluidvoice/models/silero_vad.onnx"
    static let crispasrSileroVadCacheSubpath = ".cache/crispasr/silero_vad.onnx"

    public static func resolveSileroVAD(
        explicit: String?,
        fileExists: (String) -> Bool,
        xdgDataHome: String?,
        home: String?
    ) -> String {
        if let explicit { return explicit }
        if fileExists(repoRelativeSileroVadPath) { return repoRelativeSileroVadPath }
        if let home, !home.isEmpty {
            let cachePath = "\(home)/\(crispasrSileroVadCacheSubpath)"
            if fileExists(cachePath) { return cachePath }
        }
        if let xdgDataHome, !xdgDataHome.isEmpty { return "\(xdgDataHome)/\(xdgSileroVadSubpath)" }
        if let home, !home.isEmpty { return "\(home)/\(homeDataHomeSuffix)/\(xdgSileroVadSubpath)" }
        return "\(homeDataHomeSuffix)/\(xdgSileroVadSubpath)"
    }
}

