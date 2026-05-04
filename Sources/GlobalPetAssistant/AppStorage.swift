import Foundation

enum AppStorage {
    static let rootDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".global-pet-assistant", isDirectory: true)

    static let petsDirectory = rootDirectory
        .appendingPathComponent("pets", isDirectory: true)

    private static let windowOriginURL = rootDirectory
        .appendingPathComponent("window-origin.json")

    private static let eventPreferencesURL = rootDirectory
        .appendingPathComponent("event-preferences.json")

    static func ensureLayout() throws {
        try FileManager.default.createDirectory(
            at: petsDirectory,
            withIntermediateDirectories: true
        )
    }

    static func loadWindowOrigin() -> StoredWindowOrigin? {
        guard let data = try? Data(contentsOf: windowOriginURL) else {
            return nil
        }

        return try? JSONDecoder().decode(StoredWindowOrigin.self, from: data)
    }

    static func saveWindowOrigin(_ origin: StoredWindowOrigin) throws {
        try ensureLayout()
        let data = try JSONEncoder().encode(origin)
        try data.write(to: windowOriginURL, options: [.atomic])
    }

    static func loadEventPreferences() -> EventPreferences {
        guard let data = try? Data(contentsOf: eventPreferencesURL),
              let preferences = try? JSONDecoder().decode(EventPreferences.self, from: data)
        else {
            return EventPreferences()
        }

        return preferences
    }

    static func saveEventPreferences(_ preferences: EventPreferences) throws {
        try ensureLayout()
        let data = try JSONEncoder().encode(preferences)
        try data.write(to: eventPreferencesURL, options: [.atomic])
    }
}

struct StoredWindowOrigin: Codable {
    let x: Double
    let y: Double
}

struct EventPreferences: Codable {
    var isPaused = false
    var mutedSources: [String] = []

    var mutedSourceSet: Set<String> {
        Set(mutedSources)
    }
}
