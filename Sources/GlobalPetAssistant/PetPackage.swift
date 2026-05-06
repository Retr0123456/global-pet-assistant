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
        guard let manifestURL = bundledSampleManifestURL() else {
            throw PetPackageError.missingBundledSample
        }

        let directoryURL = manifestURL.deletingLastPathComponent()
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.userInfo[.packageDirectoryURL] = directoryURL
        return try decoder.decode(PetPackage.self, from: data)
    }

    @discardableResult
    static func ensureBundledSampleInstalled() throws -> PetPackage {
        let bundledPackage = try loadBundledSample()
        let destinationDirectory = AppStorage.petsDirectory
            .appendingPathComponent(bundledPackage.id, isDirectory: true)
        let destinationManifestURL = destinationDirectory.appendingPathComponent("pet.json")
        let destinationSpritesheetURL = destinationDirectory
            .appendingPathComponent(bundledPackage.spritesheetPath)

        if FileManager.default.fileExists(atPath: destinationManifestURL.path),
           FileManager.default.fileExists(atPath: destinationSpritesheetURL.path),
           let installedPackage = try? load(from: destinationDirectory) {
            return installedPackage
        }

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        try replaceCopy(
            from: bundledPackage.directoryURL.appendingPathComponent("pet.json"),
            to: destinationManifestURL
        )
        try replaceCopy(
            from: bundledPackage.spritesheetURL,
            to: destinationSpritesheetURL
        )

        return try load(from: destinationDirectory)
    }

    static func loadFirstInstalledPet() throws -> PetPackage {
        if let installedPet = loadInstalledPets().first {
            return installedPet
        }

        return try loadBundledSample()
    }

    static func loadInstalledPets() -> [PetPackage] {
        loadCompatiblePets(in: AppStorage.petsDirectory)
    }

    static func loadFirstInstalledAppPet() -> PetPackage? {
        loadCompatiblePets(in: AppStorage.petsDirectory).first
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

    private static func bundledSampleManifestURL() -> URL? {
        bundledResourceBundleDirectories()
            .lazy
            .flatMap { bundleDirectory in
                [
                    bundleDirectory
                        .appendingPathComponent("SamplePets", isDirectory: true)
                        .appendingPathComponent("placeholder", isDirectory: true)
                        .appendingPathComponent("pet.json"),
                    bundleDirectory.appendingPathComponent("pet.json")
                ]
            }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func bundledResourceBundleDirectories() -> [URL] {
        let resourceBundleName = "GlobalPetAssistant_GlobalPetAssistant.bundle"
        var candidates: [URL] = []

        if let bundleURL = Bundle.main.url(
            forResource: "GlobalPetAssistant_GlobalPetAssistant",
            withExtension: "bundle"
        ) {
            candidates.append(bundleURL)
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true))
        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(resourceBundleName, isDirectory: true)
        )

        if let executableURL = Bundle.main.executableURL {
            let executableDirectory = executableURL.deletingLastPathComponent()
            candidates.append(executableDirectory.appendingPathComponent(resourceBundleName, isDirectory: true))
            candidates.append(
                executableDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(resourceBundleName, isDirectory: true)
            )
        }

        #if DEBUG
        candidates.append(Bundle.module.bundleURL)
        #endif

        var seen: Set<String> = []
        return candidates
            .map { $0.standardizedFileURL }
            .filter { url in
                guard !seen.contains(url.path) else {
                    return false
                }
                seen.insert(url.path)
                return true
            }
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

    private static func replaceCopy(from sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
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
