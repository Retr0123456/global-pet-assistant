import Foundation
import Testing
@testable import GlobalPetAssistant

struct PetPackageTests {
    @Test
    func testAcceptsEmmaPackageLayout() throws {
        let emmaDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
            .appendingPathComponent("emma", isDirectory: true)

        #expect(FileManager.default.fileExists(atPath: emmaDirectory.appendingPathComponent("pet.json").path))

        let package = try PetPackage.load(from: emmaDirectory)

        #expect(package.id == "emma")
        #expect(package.spritesheetURL.deletingLastPathComponent() == emmaDirectory)
    }

    @Test
    func testRejectsSpritesheetPathTraversal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest = """
        {
          "id": "bad",
          "displayName": "Bad",
          "description": "Bad package",
          "spritesheetPath": "../spritesheet.webp"
        }
        """
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("pet.json"))

        #expect(throws: (any Error).self) {
            try PetPackage.load(from: directory)
        }
    }
}
