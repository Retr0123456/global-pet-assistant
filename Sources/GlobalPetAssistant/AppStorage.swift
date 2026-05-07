import Foundation

enum AppStorage {
    static let rootDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".global-pet-assistant", isDirectory: true)

    static let petsDirectory = rootDirectory
        .appendingPathComponent("pets", isDirectory: true)

    static let logsDirectory = rootDirectory
        .appendingPathComponent("logs", isDirectory: true)

    static let eventsLogURL = logsDirectory
        .appendingPathComponent("events.jsonl")

    static let runtimeLogURL = logsDirectory
        .appendingPathComponent("runtime.jsonl")

    static let tokenURL = rootDirectory
        .appendingPathComponent("token")

    private static let windowOriginURL = rootDirectory
        .appendingPathComponent("window-origin.json")

    private static let eventPreferencesURL = rootDirectory
        .appendingPathComponent("event-preferences.json")

    private static let focusTimerURL = rootDirectory
        .appendingPathComponent("focus-timer.json")

    private static let selectedPetURL = rootDirectory
        .appendingPathComponent("selected-pet")

    private static let configurationURL = rootDirectory
        .appendingPathComponent("config.json")

    static func ensureLayout() throws {
        try FileManager.default.createDirectory(
            at: petsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: logsDirectory,
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

    static func loadFocusTimerRecord() -> FocusTimerRecord? {
        guard let data = try? Data(contentsOf: focusTimerURL) else {
            return nil
        }

        return try? JSONDecoder().decode(FocusTimerRecord.self, from: data)
    }

    static func saveFocusTimerRecord(_ record: FocusTimerRecord) throws {
        try ensureLayout()
        let data = try JSONEncoder().encode(record)
        try data.write(to: focusTimerURL, options: [.atomic])
    }

    static func clearFocusTimerRecord() {
        try? FileManager.default.removeItem(at: focusTimerURL)
    }

    static func loadSelectedPetID() -> String? {
        guard let data = try? Data(contentsOf: selectedPetURL) else {
            return nil
        }

        let selectedPetID = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedPetID?.isEmpty == false ? selectedPetID : nil
    }

    static func saveSelectedPetID(_ selectedPetID: String) throws {
        try ensureLayout()
        try Data((selectedPetID + "\n").utf8).write(to: selectedPetURL, options: [.atomic])
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
            let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
            let migratedConfiguration = configuration.migratedForCurrentDefaults()
            if migratedConfiguration != configuration {
                try? saveConfiguration(migratedConfiguration)
            }
            return migratedConfiguration
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

    static func loadOrCreateToken(
        fileManager: FileManager = .default,
        tokenGenerator: () -> String = LocalAuthToken.generate
    ) throws -> String {
        try ensureLayout()

        if let existingToken = try readToken(from: tokenURL), !existingToken.isEmpty {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokenURL.path
            )
            return existingToken
        }

        let token = tokenGenerator()
        try Data((token + "\n").utf8).write(to: tokenURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )
        return token
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

    private static func readToken(from url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
