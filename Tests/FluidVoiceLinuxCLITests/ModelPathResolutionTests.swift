import Foundation
import XCTest
@testable import FluidVoiceLinuxCLICore

// Issue 007 (issues/007-default-whisper-model-path-is-cwd-relative-breaks-when-
// installed.md): ModelPathResolver.resolve is pure — it takes injectable
// "does this path exist" / "what is $XDG_DATA_HOME / $HOME" closures instead of
// touching the real filesystem or environment, so all three resolution branches
// are deterministically testable here (docs/SwiftLinux.md §3).
final class ModelPathResolutionTests: XCTestCase {
    func testExplicitFlagWinsEvenWhenRepoRelativeExists() {
        let resolved = ModelPathResolver.resolve(
            explicit: "/opt/models/ggml-tiny.en.bin",
            fileExists: { _ in true },
            xdgDataHome: "/home/user/.data",
            home: "/home/user"
        )

        XCTAssertEqual(resolved, "/opt/models/ggml-tiny.en.bin")
    }

    func testRepoRelativeWinsOverXDGDefaultWhenItExists() {
        var checkedPaths: [String] = []
        let resolved = ModelPathResolver.resolve(
            explicit: nil,
            fileExists: { path in
                checkedPaths.append(path)
                return path == ModelPathResolver.repoRelativeModelPath
            },
            xdgDataHome: "/home/user/.data",
            home: "/home/user"
        )

        XCTAssertEqual(resolved, ModelPathResolver.repoRelativeModelPath)
        XCTAssertEqual(checkedPaths, [ModelPathResolver.repoRelativeModelPath])
    }

    func testXDGDataHomeUsedWhenRepoRelativeMissing() {
        let resolved = ModelPathResolver.resolve(
            explicit: nil,
            fileExists: { _ in false },
            xdgDataHome: "/home/user/.data",
            home: "/home/user"
        )

        XCTAssertEqual(resolved, "/home/user/.data/fluidvoice/models/ggml-base.en.bin")
    }

    func testHomeFallbackUsedWhenXDGDataHomeUnset() {
        let resolved = ModelPathResolver.resolve(
            explicit: nil,
            fileExists: { _ in false },
            xdgDataHome: nil,
            home: "/home/user"
        )

        XCTAssertEqual(resolved, "/home/user/.local/share/fluidvoice/models/ggml-base.en.bin")
    }

    func testHomeFallbackUsedWhenXDGDataHomeEmpty() {
        let resolved = ModelPathResolver.resolve(
            explicit: nil,
            fileExists: { _ in false },
            xdgDataHome: "",
            home: "/home/user"
        )

        XCTAssertEqual(resolved, "/home/user/.local/share/fluidvoice/models/ggml-base.en.bin")
    }

    func testRelativeFallbackWhenNeitherXDGDataHomeNorHomeSet() {
        let resolved = ModelPathResolver.resolve(
            explicit: nil,
            fileExists: { _ in false },
            xdgDataHome: nil,
            home: nil
        )

        XCTAssertEqual(resolved, ".local/share/fluidvoice/models/ggml-base.en.bin")
    }

    func testCohereResolutionPriority() {
        // Explicit wins
        XCTAssertEqual(
            ModelPathResolver.resolveCohere(
                explicit: "/custom/cohere.gguf",
                fileExists: { _ in true },
                xdgDataHome: "/data",
                home: "/home/user"
            ),
            "/custom/cohere.gguf"
        )

        // Repo relative wins if exists
        XCTAssertEqual(
            ModelPathResolver.resolveCohere(
                explicit: nil,
                fileExists: { $0 == ModelPathResolver.repoRelativeCohereModelPath },
                xdgDataHome: "/data",
                home: "/home/user"
            ),
            ModelPathResolver.repoRelativeCohereModelPath
        )

        // Crisp cache wins if exists
        XCTAssertEqual(
            ModelPathResolver.resolveCohere(
                explicit: nil,
                fileExists: { $0 == "/home/user/.cache/crispasr/cohere-transcribe-q4_k.gguf" },
                xdgDataHome: "/data",
                home: "/home/user"
            ),
            "/home/user/.cache/crispasr/cohere-transcribe-q4_k.gguf"
        )

        // XDG data home fallback
        XCTAssertEqual(
            ModelPathResolver.resolveCohere(
                explicit: nil,
                fileExists: { _ in false },
                xdgDataHome: "/data",
                home: "/home/user"
            ),
            "/data/fluidvoice/models/cohere-transcribe-q4_k.gguf"
        )
    }
}
