import Foundation

struct AppConfiguration: Codable, Equatable {
    var trustedSources: [String: SourceActionPolicy]
    var petImportSourceDirectories: [String]

    init(
        trustedSources: [String: SourceActionPolicy],
        petImportSourceDirectories: [String] = Self.defaultPetImportSourceDirectories()
    ) {
        self.trustedSources = trustedSources
        self.petImportSourceDirectories = petImportSourceDirectories
    }

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
            ],
            petImportSourceDirectories: defaultPetImportSourceDirectories()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case trustedSources
        case petImportSourceDirectories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trustedSources = try container.decode([String: SourceActionPolicy].self, forKey: .trustedSources)
        petImportSourceDirectories = try container.decodeIfPresent(
            [String].self,
            forKey: .petImportSourceDirectories
        ) ?? []
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
        if configuration.petImportSourceDirectories.isEmpty {
            configuration.petImportSourceDirectories = Self.defaultPetImportSourceDirectories()
        }

        return configuration
    }

    func petImportSourceDirectoryURLs() -> [URL] {
        var seen: Set<String> = []
        return petImportSourceDirectories
            .map(Self.expandUserPath)
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .filter { url in
                guard !seen.contains(url.path) else {
                    return false
                }
                seen.insert(url.path)
                return true
            }
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

    private static func defaultPetImportSourceDirectories() -> [String] {
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("pets", isDirectory: true)
                .standardizedFileURL
                .path
        ]
    }

    private static func expandUserPath(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }

        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        }

        return path
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
