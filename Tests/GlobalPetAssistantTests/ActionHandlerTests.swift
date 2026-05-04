import Foundation
import Testing
@testable import GlobalPetAssistant

struct ActionHandlerTests {
    private var configuration: AppConfiguration {
        AppConfiguration(
            trustedSources: [
                "codex-cli": SourceActionPolicy(
                    actions: ["open_url", "open_folder", "open_file", "open_app"],
                    urlHosts: ["github.com", "127.0.0.1"],
                    folderRoots: [
                        "/Users/ryanchen/codespace",
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
        try ActionHandler.validate(
            LocalPetAction(
                type: "open_folder",
                path: "/Users/ryanchen/codespace/global-pet-assistant"
            ),
            source: "codex-cli",
            configuration: configuration
        )
    }

    @Test
    func testRejectsFilePathForOpenFolder() {
        #expect(throws: ActionValidationError.self) {
            try ActionHandler.validate(
                LocalPetAction(
                    type: "open_folder",
                    path: "/Users/ryanchen/codespace/global-pet-assistant/Package.swift"
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
}
