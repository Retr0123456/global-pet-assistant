import Foundation

struct TerminalCommandFlashProjection {
    private static let ignoredCommands: Set<String> = [
        "cd",
        "ls",
        "pwd",
        "git status",
        "clear",
        "history",
        "jobs"
    ]

    private static let ignoredGitSubcommands: Set<String> = [
        "status",
        "diff",
        "log",
        "branch"
    ]

    var minimumSuccessDurationMs = 2_000
    var ttlMs = 4_500

    func localEvent(for event: TerminalPluginEvent) -> LocalPetEvent? {
        guard event.kind == .commandCompleted else {
            return nil
        }

        let command = event.command ?? event.terminal.command
        guard let command, !isIgnored(command) else {
            return nil
        }

        let exitCode = event.exitCode ?? 0
        if exitCode == 0, (event.durationMs ?? 0) < minimumSuccessDurationMs {
            return nil
        }

        let level: PetEventLevel = exitCode == 0 ? .success : .danger
        let label = commandLabel(command)
        let message = exitCode == 0 ? "\(label) passed" : "\(label) failed (\(exitCode))"

        return LocalPetEvent(
            source: "terminal:kitty:\(event.terminal.sessionId)",
            type: "flash",
            level: level,
            title: "Terminal command",
            message: message,
            state: exitCode == 0 ? .waving : .failed,
            ttlMs: ttlMs,
            dedupeKey: "terminal-command:\(event.terminal.sessionId):\(label)",
            cwd: event.terminal.cwd,
            transient: true
        )
    }

    private func isIgnored(_ command: String) -> Bool {
        let words = firstCommandSegment(command)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard let firstWord = words.first else {
            return true
        }
        if Self.ignoredCommands.contains(firstWord) {
            return true
        }
        if firstWord == "git",
           words.count >= 2,
           Self.ignoredGitSubcommands.contains(words[1]) {
            return true
        }
        return false
    }

    private func firstCommandSegment(_ command: String) -> String {
        var segment = command.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [";", "|", "&"] {
            segment = String(segment.split(
                separator: Character(separator),
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first ?? "")
        }
        return segment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commandLabel(_ command: String) -> String {
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > 44 else {
            return normalized
        }
        let end = normalized.index(normalized.startIndex, offsetBy: 43)
        return "\(normalized[..<end])…"
    }
}
