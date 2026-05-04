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

    private static let configurationURL = rootDirectory
        .appendingPathComponent("config.json")

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

    static func loadConfiguration(
        fileManager: FileManager = .default,
        now: () -> Date = Date.init
    ) -> AppConfiguration {
        do {
            try ensureLayout()
        } catch {
            NSLog("GlobalPetAssistant could not create app storage: \(String(describing: error))")
            return .defaultConfiguration
        }

        guard fileManager.fileExists(atPath: configurationURL.path) else {
            saveDefaultConfiguration()
            return .defaultConfiguration
        }

        do {
            let data = try Data(contentsOf: configurationURL)
            return try JSONDecoder().decode(AppConfiguration.self, from: data)
        } catch {
            do {
                let backupURL = backupURLForInvalidConfiguration(now: now())
                try fileManager.moveItem(at: configurationURL, to: backupURL)
                NSLog("GlobalPetAssistant backed up invalid config to \(backupURL.path)")
            } catch {
                NSLog("GlobalPetAssistant could not back up invalid config: \(String(describing: error))")
            }

            saveDefaultConfiguration()
            return .defaultConfiguration
        }
    }

    static func saveConfiguration(_ configuration: AppConfiguration) throws {
        try ensureLayout()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: [.atomic])
    }

    private static func saveDefaultConfiguration() {
        do {
            try saveConfiguration(.defaultConfiguration)
        } catch {
            NSLog("GlobalPetAssistant could not write default config: \(String(describing: error))")
        }
    }

    private static func backupURLForInvalidConfiguration(now: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        return rootDirectory.appendingPathComponent("config.invalid-\(timestamp).json")
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
