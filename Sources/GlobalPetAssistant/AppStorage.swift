import Foundation

enum AppStorage {
    static let rootDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".global-pet-assistant", isDirectory: true)

    static let petsDirectory = rootDirectory
        .appendingPathComponent("pets", isDirectory: true)

    static func ensureLayout() throws {
        try FileManager.default.createDirectory(
            at: petsDirectory,
            withIntermediateDirectories: true
        )
    }
}
