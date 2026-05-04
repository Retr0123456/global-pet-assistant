import Foundation

struct AppConfiguration: Codable, Equatable {
    var trustedSources: [String: SourceActionPolicy]

    static var defaultConfiguration: AppConfiguration {
        let workspaceRoots = defaultWorkspaceRoots()
        let appStateRoot = AppStorage.rootDirectory.standardizedFileURL.path
        let logsRoot = AppStorage.logsDirectory.standardizedFileURL.path

        return AppConfiguration(
            trustedSources: [
                "codex-cli": SourceActionPolicy(
                    actions: ["open_url", "open_folder", "open_file", "open_app", "focus_kitty_window"],
                    urlHosts: ["github.com", "127.0.0.1"],
                    folderRoots: workspaceRoots + [appStateRoot],
                    appBundleIds: [
                        "com.openai.codex",
                        "com.microsoft.VSCode",
                        "com.openai.chat",
                        "com.apple.Terminal"
                    ]
                ),
                "claude-code": SourceActionPolicy(
                    actions: ["open_folder", "open_file"],
                    folderRoots: workspaceRoots + [appStateRoot]
                ),
                "local-build": SourceActionPolicy(
                    actions: ["open_folder", "open_file"],
                    folderRoots: workspaceRoots + [logsRoot]
                ),
                "ci": SourceActionPolicy(
                    actions: ["open_url"],
                    urlHosts: ["github.com"]
                )
            ]
        )
    }

    func policy(for rawSource: String) -> SourceActionPolicy? {
        let source = Self.normalizedSource(rawSource)
        if let policy = trustedSources[source] {
            return policy
        }

        if let family = source.split(separator: ":", maxSplits: 1).first {
            return trustedSources[String(family)]
        }

        return nil
    }

    func migratedForCurrentDefaults() -> AppConfiguration {
        var configuration = self
        let codexSource = "codex-cli"
        let kittyAction = "focus_kitty_window"
        if var codexPolicy = configuration.trustedSources[codexSource],
           !codexPolicy.actions.contains(kittyAction) {
            codexPolicy.actions.append(kittyAction)
            configuration.trustedSources[codexSource] = codexPolicy
        }

        return configuration
    }

    static func normalizedSource(_ rawSource: String) -> String {
        let trimmed = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func defaultWorkspaceRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("codespace", isDirectory: true),
            home.appendingPathComponent("Developer", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true)
        ]
        .map { $0.standardizedFileURL.path }
    }
}

struct SourceActionPolicy: Codable, Equatable {
    var actions: [String]
    var urlHosts: [String]
    var folderRoots: [String]
    var appBundleIds: [String]

    init(
        actions: [String] = [],
        urlHosts: [String] = [],
        folderRoots: [String] = [],
        appBundleIds: [String] = []
    ) {
        self.actions = actions
        self.urlHosts = urlHosts
        self.folderRoots = folderRoots
        self.appBundleIds = appBundleIds
    }

    var actionSet: Set<String> {
        Set(actions)
    }

    var urlHostSet: Set<String> {
        Set(urlHosts.map { $0.lowercased() })
    }

    var appBundleIdSet: Set<String> {
        Set(appBundleIds)
    }
}
