import Foundation

public enum TextOutputTarget: String, CaseIterable, Equatable {
    case stdout
    case clipboard
    case typing
}

public enum TextOutputDriverError: Error, CustomStringConvertible {
    case toolNotFound(String)
    case executionFailed(String)

    public var description: String {
        switch self {
        case .toolNotFound(let tool):
            return "required output tool '\(tool)' not found on system PATH"
        case .executionFailed(let msg):
            return "failed to output text: \(msg)"
        }
    }
}

public enum TextOutputDriver {
    private static func findExecutable(_ names: [String]) -> String? {
        for name in names {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [name]
            let pipe = Pipe()
            process.standardOutput = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty { return path }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Copies text to the system clipboard using wl-copy, xclip, or xsel.
    public static func copyToClipboard(_ text: String) throws {
        let isWayland = ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil
        let candidates = isWayland ? ["wl-copy", "xclip", "xsel"] : ["xclip", "xsel", "wl-copy"]

        guard let tool = findExecutable(candidates) else {
            throw TextOutputDriverError.toolNotFound("wl-copy or xclip")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)

        if tool.hasSuffix("xclip") {
            process.arguments = ["-selection", "clipboard"]
        } else if tool.hasSuffix("xsel") {
            process.arguments = ["--clipboard", "--input"]
        } else {
            process.arguments = []
        }

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        do {
            try process.run()
            if let data = text.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try stdinPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()
        } catch {
            throw TextOutputDriverError.executionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            throw TextOutputDriverError.executionFailed("clipboard tool exited with code \(process.terminationStatus)")
        }
    }

    /// Types text into the currently active window using wtype, xdotool, or ydotool.
    public static func simulateTyping(_ text: String) throws {
        guard !text.isEmpty else { return }

        let isWayland = ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil
        let candidates = isWayland ? ["wtype", "ydotool", "xdotool"] : ["xdotool", "ydotool", "wtype"]

        guard let tool = findExecutable(candidates) else {
            throw TextOutputDriverError.toolNotFound("wtype, xdotool, or ydotool")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)

        if tool.hasSuffix("wtype") {
            process.arguments = [text]
        } else if tool.hasSuffix("xdotool") {
            process.arguments = ["type", "--clearmodifiers", text]
        } else if tool.hasSuffix("ydotool") {
            process.arguments = ["type", text]
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TextOutputDriverError.executionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            throw TextOutputDriverError.executionFailed("typing simulator exited with code \(process.terminationStatus)")
        }
    }

    /// Dispatches text to the desired output target.
    public static func emit(_ text: String, target: TextOutputTarget) throws {
        switch target {
        case .stdout:
            print(text)
        case .clipboard:
            try copyToClipboard(text)
            print("[Copied to clipboard]")
        case .typing:
            try simulateTyping(text)
        }
    }
}
