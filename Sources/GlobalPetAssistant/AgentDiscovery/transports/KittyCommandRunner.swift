import Foundation

protocol KittyCommandRunning: Sendable {
    func run(arguments: [String]) async throws -> KittyCommandResult
}

struct KittyCommandResult: Equatable, Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

struct KittyCommandRunner: KittyCommandRunning {
    private let executableURL: URL

    init(executableURL: URL? = nil) throws {
        if let executableURL {
            self.executableURL = executableURL
            return
        }

        guard let resolved = Self.resolveExecutable() else {
            throw TerminalTransportError.unavailable("kitty executable not found")
        }
        self.executableURL = resolved
    }

    func run(arguments: [String]) async throws -> KittyCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return KittyCommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func resolveExecutable() -> URL? {
        let candidates = [
            "/Applications/kitty.app/Contents/MacOS/kitty",
            "/opt/homebrew/bin/kitty",
            "/usr/local/bin/kitty"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
