import Foundation
import Testing
@testable import GlobalPetAssistant

struct ActionHandlerTests {
    private var configuration: AppConfiguration {
        AppConfiguration(
            trustedSources: [
                "codex-cli": SourceActionPolicy(
                    actions: ["open_url", "open_folder", "open_file", "open_app", "focus_kitty_window"],
                    urlHosts: ["github.com", "127.0.0.1"],
                    folderRoots: [
                        FileManager.default.temporaryDirectory.path
                    ],
                    appBundleIds: ["com.openai.codex"]
                )
            ]
        )
    }

    @Test
    func testAllowsGitHubURL() throws {
        try ActionHandler.validate(
            LocalPetAction(
                type: "open_url",
                url: "https://github.com/Retr0123456/global-pet-assistant"
            ),
            source: "codex-cli",
            configuration: configuration
        )
    }

    @Test
    func testAllowsLocalhostHTTPURL() throws {
        try ActionHandler.validate(
            LocalPetAction(
                type: "open_url",
                url: "http://127.0.0.1:17321/healthz"
            ),
            source: "codex-cli",
            configuration: configuration
        )
    }

    @Test
    func testRejectsFTPURL() {
        #expect(throws: ActionValidationError.self) {
            try ActionHandler.validate(
                LocalPetAction(type: "open_url", url: "ftp://example.com/file"),
                source: "codex-cli",
                configuration: configuration
            )
        }
    }

    @Test
    func testAllowsProjectFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("global-pet-assistant", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }

        try ActionHandler.validate(
            LocalPetAction(
                type: "open_folder",
                path: directory.path
            ),
            source: "codex-cli",
            configuration: configuration
        )
    }

    @Test
    func testRejectsFilePathForOpenFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Package.swift")
        try Data("swift package".utf8).write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        #expect(throws: ActionValidationError.self) {
            try ActionHandler.validate(
                LocalPetAction(
                    type: "open_folder",
                    path: fileURL.path
                ),
                source: "codex-cli",
                configuration: configuration
            )
        }
    }

    @Test
    func testUnknownSourceCannotUseAction() {
        let error = #expect(throws: ActionValidationError.self) {
            try ActionHandler.validate(
                LocalPetAction(
                    type: "open_url",
                    url: "https://github.com/Retr0123456/global-pet-assistant"
                ),
                source: "unknown-tool",
                configuration: configuration
            )
        }
        #expect(error?.isActionAuthorizationFailure == true)
    }

    @Test
    func testAllowsFileUnderAllowedRoot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("local-build-latest.log")
        try Data("build failed".utf8).write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try ActionHandler.validate(
            LocalPetAction(type: "open_file", path: fileURL.path),
            source: "codex-cli",
            configuration: configuration
        )
    }

    @Test
    func testAllowsConfiguredApplicationBundleID() throws {
        try ActionHandler.validate(
            LocalPetAction(type: "open_app", bundleId: "com.openai.codex"),
            source: "codex-cli",
            configuration: configuration,
            applicationURLForBundleIdentifier: { bundleID in
                bundleID == "com.openai.codex"
                    ? URL(fileURLWithPath: "/Applications/Codex.app")
                    : nil
            }
        )
    }

    @Test
    func testSessionSourceInheritsCodexActionPolicy() throws {
        try ActionHandler.validate(
            LocalPetAction(
                type: "focus_kitty_window",
                kittyWindowId: "42",
                kittyListenOn: "unix:/tmp/mykitty"
            ),
            source: "codex-cli:019df293-29f68f4b",
            configuration: configuration
        )
    }

    @Test
    func testMigratesCodexKittyActionIntoExistingConfiguration() {
        let legacyConfiguration = AppConfiguration(
            trustedSources: [
                "codex-cli": SourceActionPolicy(actions: ["open_url"])
            ]
        )

        let migratedPolicy = legacyConfiguration
            .migratedForCurrentDefaults()
            .policy(for: "codex-cli:019df293-29f68f4b")

        #expect(migratedPolicy?.actions.contains("open_url") == true)
        #expect(migratedPolicy?.actions.contains("focus_kitty_window") == true)
    }

    @Test
    func testRejectsInvalidKittyWindowID() {
        #expect(throws: ActionValidationError.self) {
            try ActionHandler.validate(
                LocalPetAction(
                    type: "focus_kitty_window",
                    kittyWindowId: "abc",
                    kittyListenOn: "unix:/tmp/mykitty"
                ),
                source: "codex-cli",
                configuration: configuration
            )
        }
    }

    @Test
    func testRejectsNonLocalKittyListenOn() {
        #expect(throws: ActionValidationError.self) {
            try ActionHandler.validate(
                LocalPetAction(
                    type: "focus_kitty_window",
                    kittyWindowId: "42",
                    kittyListenOn: "tcp:192.168.1.2:5000"
                ),
                source: "codex-cli",
                configuration: configuration
            )
        }
    }

    @Test
    func testFocusesKittyWindowWithExpectedRemoteControlArguments() {
        var capturedArguments: [String] = []
        let handler = ActionHandler(runKittyRemoteControl: { arguments in
            capturedArguments = arguments
            return true
        })

        let result = handler.perform(
            LocalPetAction(
                type: "focus_kitty_window",
                kittyWindowId: "42",
                kittyListenOn: "unix:/tmp/mykitty"
            ),
            source: "codex-cli:019df293-29f68f4b",
            configuration: configuration
        )

        #expect(result == true)
        #expect(capturedArguments == [
            "@",
            "--to",
            "unix:/tmp/mykitty",
            "focus-window",
            "--match",
            "id:42"
        ])
    }
}
