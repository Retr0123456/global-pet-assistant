import Foundation

struct AppConfiguration: Codable, Equatable {
    var trustedSources: [String: SourceActionPolicy]

    static let defaultConfiguration = AppConfiguration(
        trustedSources: [
            "codex-cli": SourceActionPolicy(
                actions: ["open_url", "open_folder", "open_file", "open_app"],
                urlHosts: ["github.com", "127.0.0.1"],
                folderRoots: [
                    "/Users/ryanchen/codespace",
                    "/Users/ryanchen/.global-pet-assistant"
                ],
                appBundleIds: [
                    "com.openai.codex",
                    "com.microsoft.VSCode",
                    "com.openai.chat",
                    "com.apple.Terminal"
                ]
            ),
            "claude-code": SourceActionPolicy(
                actions: ["open_folder", "open_file"],
                folderRoots: [
                    "/Users/ryanchen/codespace",
                    "/Users/ryanchen/.global-pet-assistant"
                ]
            ),
            "local-build": SourceActionPolicy(
                actions: ["open_folder", "open_file"],
                folderRoots: [
                    "/Users/ryanchen/codespace",
                    "/Users/ryanchen/.global-pet-assistant/logs"
                ]
            ),
            "ci": SourceActionPolicy(
                actions: ["open_url"],
                urlHosts: ["github.com"]
            )
        ]
    )

    func policy(for rawSource: String) -> SourceActionPolicy? {
        trustedSources[Self.normalizedSource(rawSource)]
    }

    static func normalizedSource(_ rawSource: String) -> String {
        let trimmed = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
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
