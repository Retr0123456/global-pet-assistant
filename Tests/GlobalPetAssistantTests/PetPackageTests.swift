import Foundation
import Testing
@testable import GlobalPetAssistant

struct PetPackageTests {
    @Test
    func testLoadsBundledDefaultPet() throws {
        let package = try PetPackage.loadBundledDefaultPet()

        #expect(package.id == "blobbit")
        #expect(package.displayName == "Blobbit")
        #expect(package.spritesheetURL.lastPathComponent == "spritesheet.webp")
        #expect(FileManager.default.fileExists(atPath: package.spritesheetURL.path))
    }

    @Test
    func testAcceptsCodexCompatiblePackageLayout() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest = """
        {
          "id": "sample-pet",
          "displayName": "Sample Pet",
          "description": "A Codex-compatible test package.",
          "spritesheetPath": "spritesheet.webp"
        }
        """
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("pet.json"))

        let package = try PetPackage.load(from: directory)

        #expect(package.id == "sample-pet")
        #expect(package.spritesheetURL.lastPathComponent == "spritesheet.webp")
        #expect(package.spritesheetURL.deletingLastPathComponent() == directory)
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
