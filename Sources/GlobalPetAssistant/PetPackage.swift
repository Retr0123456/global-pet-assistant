import Foundation

struct PetPackage: Decodable {
    let id: String
    let displayName: String
    let description: String
    let spritesheetPath: String
    let directoryURL: URL

    var spritesheetURL: URL {
        directoryURL.appendingPathComponent(spritesheetPath)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case description
        case spritesheetPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        spritesheetPath = try Self.validatedSpritesheetPath(
            try container.decode(String.self, forKey: .spritesheetPath)
        )
        directoryURL = decoder.userInfo[.packageDirectoryURL] as? URL ?? URL(fileURLWithPath: "/")
    }

    static func loadBundledSample() throws -> PetPackage {
        guard let manifestURL = Bundle.module.url(
            forResource: "pet",
            withExtension: "json",
            subdirectory: "SamplePets/placeholder"
        ) else {
            throw PetPackageError.missingBundledSample
        }

        let directoryURL = manifestURL.deletingLastPathComponent()
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.userInfo[.packageDirectoryURL] = directoryURL
        return try decoder.decode(PetPackage.self, from: data)
    }

    static func loadFirstInstalledPet() throws -> PetPackage {
        if let installedPet = loadInstalledPets().first {
            return installedPet
        }

        return try loadBundledSample()
    }

    static func loadInstalledPets() -> [PetPackage] {
        loadCompatiblePets(in: AppStorage.petsDirectory) + loadCompatiblePets(in: codexPetsDirectory)
    }

    static func loadFirstInstalledAppPet() -> PetPackage? {
        loadCompatiblePets(in: AppStorage.petsDirectory).first
    }

    static func loadFirstInstalledCodexPet() -> PetPackage? {
        loadCompatiblePets(in: codexPetsDirectory).first
    }

    static func load(from directoryURL: URL) throws -> PetPackage {
        let manifestURL = directoryURL.appendingPathComponent("pet.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.userInfo[.packageDirectoryURL] = directoryURL
        return try decoder.decode(PetPackage.self, from: data)
    }

    private static func validatedSpritesheetPath(_ path: String) throws -> String {
        guard
            !path.isEmpty,
            !path.hasPrefix("/"),
            !path.contains(".."),
            path == URL(fileURLWithPath: path).lastPathComponent
        else {
            throw PetPackageError.invalidSpritesheetPath(path)
        }

        return path
    }

    private static var codexPetsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
    }

    private static func loadCompatiblePets(in petsDirectory: URL) -> [PetPackage] {
        guard let petDirectories = try? FileManager.default.contentsOfDirectory(
            at: petsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return petDirectories
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? load(from: $0) }
    }
}

enum PetPackageError: Error, CustomStringConvertible {
    case missingBundledSample
    case invalidSpritesheetPath(String)

    var description: String {
        switch self {
        case .missingBundledSample:
            "Bundled placeholder pet manifest is missing."
        case .invalidSpritesheetPath(let path):
            "Invalid spritesheetPath in pet manifest: \(path)."
        }
    }
}

extension CodingUserInfoKey {
    static let packageDirectoryURL = CodingUserInfoKey(rawValue: "packageDirectoryURL")!
}
