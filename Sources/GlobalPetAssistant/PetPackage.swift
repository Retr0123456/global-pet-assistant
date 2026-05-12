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

    static func loadBundledDefaultPet() throws -> PetPackage {
        guard let manifestURL = bundledDefaultPetManifestURL() else {
            throw PetPackageError.missingBundledDefaultPet
        }

        let directoryURL = manifestURL.deletingLastPathComponent()
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.userInfo[.packageDirectoryURL] = directoryURL
        return try decoder.decode(PetPackage.self, from: data)
    }

    @discardableResult
    static func ensureBundledDefaultPetInstalled() throws -> PetPackage {
        let bundledPackage = try loadBundledDefaultPet()
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

        return try loadBundledDefaultPet()
    }

    static func loadInstalledPets() -> [PetPackage] {
        loadCompatiblePets(in: AppStorage.petsDirectory)
    }

    @discardableResult
    static func syncFromImportSources(
        _ sourceDirectories: [URL],
        destinationRoot: URL = AppStorage.petsDirectory
    ) -> PetSyncSummary {
        var summary = PetSyncSummary()
        for sourceDirectory in sourceDirectories {
            let packages = loadCompatiblePets(in: sourceDirectory)
            for package in packages {
                do {
                    let destinationDirectory = destinationRoot
                        .appendingPathComponent(package.directoryURL.lastPathComponent, isDirectory: true)
                    guard destinationDirectory.standardizedFileURL != package.directoryURL.standardizedFileURL else {
                        continue
                    }

                    if try syncPackage(package, to: destinationDirectory) {
                        summary.syncedPackageIDs.append(package.id)
                    }
                } catch {
                    summary.failedPackages.append(PetSyncFailure(
                        packageID: package.id,
                        sourcePath: package.directoryURL.path,
                        errorDescription: String(describing: error)
                    ))
                }
            }
        }

        return summary
    }

    static func sortedForDisplay(_ packages: [PetPackage]) -> [PetPackage] {
        packages.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func preferredPackage(from packages: [PetPackage], selectedPetID: String?) -> PetPackage? {
        guard let selectedPetID else {
            return packages.first
        }

        return packages.first {
            $0.id == selectedPetID || $0.directoryURL.lastPathComponent == selectedPetID
        } ?? packages.first
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

    private static func bundledDefaultPetManifestURL() -> URL? {
        bundledResourceBundleDirectories()
            .lazy
            .flatMap { bundleDirectory in
                [
                    bundleDirectory
                        .appendingPathComponent("BundledPets", isDirectory: true)
                        .appendingPathComponent("blobbit", isDirectory: true)
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

    private static func syncPackage(_ package: PetPackage, to destinationDirectory: URL) throws -> Bool {
        let sourceManifestURL = package.directoryURL.appendingPathComponent("pet.json")
        let sourceSpritesheetURL = package.spritesheetURL
        let destinationManifestURL = destinationDirectory.appendingPathComponent("pet.json")
        let destinationSpritesheetURL = destinationDirectory.appendingPathComponent(package.spritesheetPath)

        guard FileManager.default.fileExists(atPath: sourceSpritesheetURL.path) else {
            throw PetPackageError.missingSpritesheet(sourceSpritesheetURL.path)
        }

        let manifestChanged = filesDiffer(sourceManifestURL, destinationManifestURL)
        let spritesheetChanged = filesDiffer(sourceSpritesheetURL, destinationSpritesheetURL)
        guard manifestChanged || spritesheetChanged else {
            return false
        }

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        try replaceCopy(from: sourceManifestURL, to: destinationManifestURL)
        try replaceCopy(from: sourceSpritesheetURL, to: destinationSpritesheetURL)
        return true
    }

    private static func filesDiffer(_ lhs: URL, _ rhs: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: rhs.path),
              let lhsData = try? Data(contentsOf: lhs),
              let rhsData = try? Data(contentsOf: rhs)
        else {
            return true
        }

        return lhsData != rhsData
    }
}

struct PetSyncSummary: Equatable {
    var syncedPackageIDs: [String] = []
    var failedPackages: [PetSyncFailure] = []
}

struct PetSyncFailure: Equatable {
    let packageID: String
    let sourcePath: String
    let errorDescription: String
}

enum PetPackageError: Error, CustomStringConvertible {
    case missingBundledDefaultPet
    case invalidSpritesheetPath(String)
    case missingSpritesheet(String)

    var description: String {
        switch self {
        case .missingBundledDefaultPet:
            "Bundled default pet manifest is missing."
        case .invalidSpritesheetPath(let path):
            "Invalid spritesheetPath in pet manifest: \(path)."
        case .missingSpritesheet(let path):
            "Missing source spritesheet: \(path)."
        }
    }
}

extension CodingUserInfoKey {
    static let packageDirectoryURL = CodingUserInfoKey(rawValue: "packageDirectoryURL")!
}
