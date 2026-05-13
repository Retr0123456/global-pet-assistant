import Foundation
import ImageIO
import Darwin

struct PetctlAction: Encodable {
    var type: String
    var url: String? = nil
    var path: String? = nil
    var bundleId: String? = nil
}

struct PetctlEvent: Encodable {
    var source = "petctl"
    var type: String
    var level: String? = nil
    var title: String? = nil
    var message: String? = nil
    var state: String? = nil
    var ttlMs: Int? = nil
    var dedupeKey: String? = nil
    var action: PetctlAction? = nil
    var transient: Bool? = nil
}

struct PetctlRequest {
    var event: PetctlEvent
    var timeoutSeconds: TimeInterval
}

struct PetctlRunRequest {
    var command: [String]
    var source: String
    var timeoutSeconds: TimeInterval
}

enum PetctlCommand {
    case send(PetctlRequest)
    case run(PetctlRunRequest)
    case openFolder
    case openLogs
    case importPet(String)
    case install(InstallerRequest)
    case doctor
    case uninstall(InstallerRequest)
}

struct InstallerRequest {
    var moduleIDs: [String]
    var dryRun: Bool
    var assumeYes: Bool
}

private struct IntegrationModule {
    struct ManagedBlock {
        var path: String
        var begin: String
        var end: String
    }

    struct UninstallSpec {
        var removePaths: [String]
        var managedBlocks: [ManagedBlock]
        var codexManagedHooks: Bool = false
        var codexFeatureFlagPath: String? = nil
    }

    var id: String
    var title: String
    var category: String
    var recommended: Bool
    var requiredCommands: [String]
    var modifiedPaths: [String]
    var installScript: String?
    var verifyScript: String?
    var installEnvironment: [String: String] = [:]
    var uninstall: UninstallSpec
}

private struct PetImportManifest: Decodable {
    var id: String
    var displayName: String
    var description: String
    var spritesheetPath: String
}

private struct PetImportPackage {
    var sourceDirectory: URL
    var manifestURL: URL
    var spritesheetURL: URL
    var spritesheetPath: String
}

enum PetctlError: Error, CustomStringConvertible {
    case usage(String)
    case requestFailed(String)

    var description: String {
        switch self {
        case .usage(let message):
            message
        case .requestFailed(let message):
            message
        }
    }
}

private let allowedLevels: Set<String> = [
    "info",
    "running",
    "success",
    "warning",
    "danger"
]

private let allowedFlashLevels: Set<String> = [
    "info",
    "success",
    "warning",
    "danger"
]

private let allowedStates: Set<String> = [
    "idle",
    "running",
    "waiting",
    "failed",
    "review",
    "jumping",
    "waving",
    "running-left",
    "running-right"
]

private let usage = """
Usage:
  petctl notify --level success --title "Task complete" [--source codex-cli] [--message "..."] [--action-url https://github.com/Retr0123456/global-pet-assistant] [--action-file ~/.global-pet-assistant/logs/local-build-latest.log] [--action-app com.openai.codex] [--timeout 5]
  petctl flash --level success --message "swift test passed" [--source terminal] [--ttl-ms 4500] [--timeout 5]
  petctl state running --message "Working..." [--source codex-cli] [--ttl-ms 15000] [--timeout 5]
  petctl run [--source terminal] [--timeout 5] -- swift test
  petctl clear [--source codex-cli] [--timeout 5]
  petctl open-folder
  petctl open-logs
  petctl import-pet <name>
  petctl import-codex-pet <name>
  petctl install [--with kitty,codex] [--dry-run] [--yes]
  petctl doctor
  petctl uninstall <module[,module...]> [--dry-run] [--yes]

Commands:
  notify            Send a notification event. Levels: info, running, success, warning, danger.
  flash             Send a short-lived flash event. Levels: info, success, warning, danger.
  state             Switch directly to a pet state: idle, running, waiting, failed, review, jumping, waving, running-left, running-right.
  run               Run a command and flash success or failure based on its exit code.
  clear             Clear active events and return the pet to idle.
  open-folder       Open ~/.global-pet-assistant/pets in Finder.
  open-logs         Open ~/.global-pet-assistant/logs in Finder.
  import-pet        Validate and copy a pet from configured import source directories.
  import-codex-pet  Compatibility alias for import-pet.
  install           Interactively install external integrations from the bundled App tools.
  doctor            Check app reachability, bundled tools, integration scripts, and dependencies.
  uninstall         Remove Global Pet Assistant managed integration configuration.
"""

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let command = try parse(arguments)
    try run(command)
} catch {
    fputs("\(String(describing: error))\n\n\(usage)\n", stderr)
    exit(1)
}

private func parse(_ arguments: [String]) throws -> PetctlCommand {
    guard let command = arguments.first else {
        throw PetctlError.usage("Missing command.")
    }

    switch command {
    case "notify":
        var options = try parseOptions(Array(arguments.dropFirst()), booleanFlags: ["transient"])
        let timeoutSeconds = try takeTimeout(from: &options)
        let source = options.removeValue(forKey: "source") ?? "petctl"
        let level = options.removeValue(forKey: "level") ?? "info"
        guard allowedLevels.contains(level) else {
            throw PetctlError.usage("Invalid level: \(level).")
        }
        let action = try takeAction(from: &options)

        let title = options.removeValue(forKey: "title")
        let event = PetctlEvent(
            source: source,
            type: options.removeValue(forKey: "type") ?? "notify",
            level: level,
            title: title,
            message: options.removeValue(forKey: "message"),
            ttlMs: try takeTTL(from: &options),
            dedupeKey: options.removeValue(forKey: "dedupe-key"),
            action: action,
            transient: try takeBool("transient", from: &options)
        )
        try rejectUnknownOptions(options)
        return .send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
    case "flash":
        var options = try parseOptions(Array(arguments.dropFirst()))
        let timeoutSeconds = try takeTimeout(from: &options)
        let source = options.removeValue(forKey: "source") ?? "petctl"
        let level = options.removeValue(forKey: "level") ?? "info"
        guard allowedFlashLevels.contains(level) else {
            throw PetctlError.usage("Invalid flash level: \(level).")
        }
        let state = options.removeValue(forKey: "state")
        if let state, !allowedStates.contains(state) {
            throw PetctlError.usage("Invalid state: \(state).")
        }
        guard let message = options.removeValue(forKey: "message"),
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw PetctlError.usage("Missing --message for flash.")
        }
        let event = PetctlEvent(
            source: source,
            type: "flash",
            level: level,
            message: message,
            state: state,
            ttlMs: try takeTTL(from: &options)
        )
        try rejectUnknownOptions(options)
        return .send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
    case "state":
        guard arguments.count >= 2 else {
            throw PetctlError.usage("Missing state name.")
        }

        let state = arguments[1]
        guard allowedStates.contains(state) else {
            throw PetctlError.usage("Invalid state: \(state).")
        }

        var options = try parseOptions(Array(arguments.dropFirst(2)))
        let timeoutSeconds = try takeTimeout(from: &options)
        let source = options.removeValue(forKey: "source") ?? "petctl"
        let event = PetctlEvent(
            source: source,
            type: options.removeValue(forKey: "type") ?? "state",
            message: options.removeValue(forKey: "message"),
            state: state,
            ttlMs: try takeTTL(from: &options),
            dedupeKey: options.removeValue(forKey: "dedupe-key")
        )
        try rejectUnknownOptions(options)
        return .send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
    case "clear":
        var options = try parseOptions(Array(arguments.dropFirst()))
        let timeoutSeconds = try takeTimeout(from: &options)
        let source = options.removeValue(forKey: "source") ?? "petctl"
        let event = PetctlEvent(
            source: source,
            type: "clear",
            state: "idle"
        )
        try rejectUnknownOptions(options)
        return .send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
    case "run":
        return try parseRunCommand(Array(arguments.dropFirst()))
    case "open-folder":
        guard arguments.count == 1 else {
            throw PetctlError.usage("open-folder does not accept arguments.")
        }

        return .openFolder
    case "open-logs":
        guard arguments.count == 1 else {
            throw PetctlError.usage("open-logs does not accept arguments.")
        }

        return .openLogs
    case "import-pet", "import-codex-pet":
        guard arguments.count == 2 else {
            throw PetctlError.usage("Usage: petctl import-pet <name>.")
        }

        return .importPet(arguments[1])
    case "install":
        return .install(try parseInstallerRequest(Array(arguments.dropFirst()), requiresModuleArgument: false))
    case "doctor":
        guard arguments.count == 1 else {
            throw PetctlError.usage("doctor does not accept arguments.")
        }

        return .doctor
    case "uninstall":
        return .uninstall(try parseInstallerRequest(Array(arguments.dropFirst()), requiresModuleArgument: true))
    case "help", "--help", "-h":
        print(usage)
        exit(0)
    default:
        throw PetctlError.usage("Unknown command: \(command).")
    }
}

private func run(_ command: PetctlCommand) throws {
    switch command {
    case .send(let request):
        try send(request)
    case .run(let request):
        try executeRun(request)
    case .openFolder:
        try openPetFolder()
    case .openLogs:
        try openLogsFolder()
    case .importPet(let name):
        try importPet(named: name)
    case .install(let request):
        try installIntegrations(request)
    case .doctor:
        try runDoctor()
    case .uninstall(let request):
        try uninstallIntegrations(request)
    }
}

private func parseInstallerRequest(
    _ arguments: [String],
    requiresModuleArgument: Bool
) throws -> InstallerRequest {
    if requiresModuleArgument {
        guard let first = arguments.first, !first.hasPrefix("--") else {
            throw PetctlError.usage("Usage: petctl uninstall <module[,module...]> [--dry-run] [--yes].")
        }
        var options = try parseOptions(Array(arguments.dropFirst()), booleanFlags: ["dry-run", "yes"])
        let request = InstallerRequest(
            moduleIDs: moduleIDs(from: first),
            dryRun: try takeBool("dry-run", from: &options) ?? false,
            assumeYes: try takeBool("yes", from: &options) ?? false
        )
        try rejectUnknownOptions(options)
        return request
    }

    var options = try parseOptions(arguments, booleanFlags: ["dry-run", "yes"])
    let moduleIDs = options.removeValue(forKey: "with").map(moduleIDs(from:)) ?? []
    let request = InstallerRequest(
        moduleIDs: moduleIDs,
        dryRun: try takeBool("dry-run", from: &options) ?? false,
        assumeYes: try takeBool("yes", from: &options) ?? false
    )
    try rejectUnknownOptions(options)
    return request
}

private func moduleIDs(from rawValue: String) -> [String] {
    rawValue
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func parseRunCommand(_ arguments: [String]) throws -> PetctlCommand {
    guard let separatorIndex = arguments.firstIndex(of: "--") else {
        throw PetctlError.usage("Usage: petctl run [--source terminal] [--timeout 5] -- <command> [args...]")
    }

    var options = try parseOptions(Array(arguments[..<separatorIndex]))
    let command = Array(arguments[arguments.index(after: separatorIndex)...])
    guard !command.isEmpty else {
        throw PetctlError.usage("Missing command after --.")
    }

    let timeoutSeconds = try takeTimeout(from: &options)
    let source = options.removeValue(forKey: "source") ?? "petctl-run"
    try rejectUnknownOptions(options)

    return .run(PetctlRunRequest(
        command: command,
        source: source,
        timeoutSeconds: timeoutSeconds
    ))
}

private func parseOptions(_ arguments: [String], booleanFlags: Set<String> = []) throws -> [String: String] {
    var options: [String: String] = [:]
    var index = 0

    while index < arguments.count {
        let rawKey = arguments[index]
        guard rawKey.hasPrefix("--") else {
            throw PetctlError.usage("Unexpected argument: \(rawKey).")
        }

        let key = String(rawKey.dropFirst(2))
        if booleanFlags.contains(key),
           (index + 1 == arguments.count || arguments[index + 1].hasPrefix("--")) {
            options[key] = "true"
            index += 1
            continue
        }

        guard index + 1 < arguments.count else {
            throw PetctlError.usage("Missing value for \(rawKey).")
        }

        options[key] = arguments[index + 1]
        index += 2
    }

    return options
}

private func takeBool(_ key: String, from options: inout [String: String]) throws -> Bool? {
    guard let rawValue = options.removeValue(forKey: key) else {
        return nil
    }

    switch rawValue.lowercased() {
    case "true", "yes", "1":
        return true
    case "false", "no", "0":
        return false
    default:
        throw PetctlError.usage("Invalid --\(key) value: \(rawValue).")
    }
}

private func takeTTL(from options: inout [String: String]) throws -> Int? {
    guard let rawTTL = options.removeValue(forKey: "ttl-ms") else {
        return nil
    }

    guard let ttlMs = Int(rawTTL), ttlMs >= 0 else {
        throw PetctlError.usage("Invalid --ttl-ms value: \(rawTTL).")
    }

    return ttlMs
}

private func takeTimeout(from options: inout [String: String]) throws -> TimeInterval {
    guard let rawTimeout = options.removeValue(forKey: "timeout") else {
        return 5
    }

    guard let timeout = TimeInterval(rawTimeout), timeout > 0 else {
        throw PetctlError.usage("Invalid --timeout value: \(rawTimeout).")
    }

    return timeout
}

private func takeAction(from options: inout [String: String]) throws -> PetctlAction? {
    let actionURL = options.removeValue(forKey: "action-url")
    let actionFolder = options.removeValue(forKey: "action-folder")
    let actionFile = options.removeValue(forKey: "action-file")
    let actionApp = options.removeValue(forKey: "action-app")
    let actionCount = [actionURL, actionFolder, actionFile, actionApp].compactMap { $0 }.count
    guard actionCount <= 1 else {
        throw PetctlError.usage("Use only one action option: --action-url, --action-folder, --action-file, or --action-app.")
    }

    if let actionURL {
        return PetctlAction(type: "open_url", url: actionURL)
    }

    if let actionFolder {
        return PetctlAction(type: "open_folder", path: actionFolder)
    }

    if let actionFile {
        return PetctlAction(type: "open_file", path: actionFile)
    }

    if let actionApp {
        return PetctlAction(type: "open_app", bundleId: actionApp)
    }

    return nil
}

private func rejectUnknownOptions(_ options: [String: String]) throws {
    guard let unknownOption = options.keys.sorted().first else {
        return
    }

    throw PetctlError.usage("Unknown option: --\(unknownOption).")
}

private func openPetFolder() throws {
    let appPetsDirectory = appPetsDirectoryURL()
    try FileManager.default.createDirectory(
        at: appPetsDirectory,
        withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [appPetsDirectory.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw PetctlError.requestFailed("Could not open \(appPetsDirectory.path).")
    }
}

private func openLogsFolder() throws {
    let logsDirectory = logsDirectoryURL()
    try FileManager.default.createDirectory(
        at: logsDirectory,
        withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [logsDirectory.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw PetctlError.requestFailed("Could not open \(logsDirectory.path).")
    }
}

private func importPet(named name: String) throws {
    let safeName = try validatedPetName(name)
    let package = try findImportPackage(named: safeName)
    let destinationDirectory = appPetsDirectoryURL().appendingPathComponent(safeName, isDirectory: true)

    try FileManager.default.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
    )
    try replaceCopy(
        from: package.manifestURL,
        to: destinationDirectory.appendingPathComponent("pet.json")
    )
    try replaceCopy(
        from: package.spritesheetURL,
        to: destinationDirectory.appendingPathComponent(package.spritesheetPath)
    )

    print("Imported \(safeName) from \(package.sourceDirectory.path) to \(destinationDirectory.path)")
}

private func validatedPetName(_ name: String) throws -> String {
    guard
        !name.isEmpty,
        !name.contains("/"),
        !name.contains(".."),
        name == URL(fileURLWithPath: name).lastPathComponent
    else {
        throw PetctlError.usage("Invalid pet name: \(name).")
    }

    return name
}

private func findImportPackage(named name: String) throws -> PetImportPackage {
    let sourceDirectories = petImportSourceDirectoryURLs()
    guard !sourceDirectories.isEmpty else {
        throw PetctlError.requestFailed(
            "No pet import source directories configured in \(appConfigurationURL().path)."
        )
    }

    for sourceRoot in sourceDirectories {
        let sourceDirectory = sourceRoot.appendingPathComponent(name, isDirectory: true)
        let manifestURL = sourceDirectory.appendingPathComponent("pet.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            continue
        }

        return try validateImportPackage(in: sourceDirectory)
    }

    let searchedPaths = sourceDirectories.map(\.path).joined(separator: ", ")
    throw PetctlError.requestFailed("Could not find pet '\(name)' in: \(searchedPaths).")
}

private func validateImportPackage(in sourceDirectory: URL) throws -> PetImportPackage {
    let manifestURL = sourceDirectory.appendingPathComponent("pet.json")
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(PetImportManifest.self, from: manifestData)
    let spritesheetPath = try validatedSpritesheetPath(manifest.spritesheetPath)
    let spritesheetURL = sourceDirectory.appendingPathComponent(spritesheetPath)

    guard FileManager.default.fileExists(atPath: spritesheetURL.path) else {
        throw PetctlError.requestFailed("Missing source spritesheet: \(spritesheetURL.path).")
    }

    try validateAtlasImage(at: spritesheetURL)

    return PetImportPackage(
        sourceDirectory: sourceDirectory,
        manifestURL: manifestURL,
        spritesheetURL: spritesheetURL,
        spritesheetPath: spritesheetPath
    )
}

private func validatedSpritesheetPath(_ path: String) throws -> String {
    guard
        !path.isEmpty,
        !path.hasPrefix("/"),
        !path.contains(".."),
        path == URL(fileURLWithPath: path).lastPathComponent
    else {
        throw PetctlError.requestFailed("pet.json must contain a safe spritesheetPath filename.")
    }

    return path
}

private func validateAtlasImage(at url: URL) throws {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else {
        throw PetctlError.requestFailed("Could not read pet atlas image dimensions: \(url.path).")
    }

    guard width.intValue == 1536, height.intValue == 1872 else {
        throw PetctlError.requestFailed(
            "Invalid pet atlas dimensions for \(url.path): expected 1536x1872, got \(width.intValue)x\(height.intValue)."
        )
    }
}

private func replaceCopy(from sourceURL: URL, to destinationURL: URL) throws {
    if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
    }

    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
}

private func installIntegrations(_ request: InstallerRequest) throws {
    let modules = try selectedInstallModules(for: request)
    guard !modules.isEmpty else {
        print("No integration modules selected.")
        return
    }

    printInstallPlan(title: "Global Pet Assistant integration install plan", modules: modules)
    fflush(stdout)
    if request.dryRun {
        print("Dry run only. No files were changed.")
        return
    }

    try confirmIfNeeded(request.assumeYes, prompt: "Continue with installation? [y/N] ")
    let resourceRoot = try bundledResourceRoot()
    for module in modules {
        print("\nInstalling \(module.title)")
        try backupExternalFiles(for: module)
        fflush(stdout)
        if module.id == "petctl-shim" {
            try installPetctlShim()
        } else if let installScript = module.installScript {
            try runBundledScript(
                installScript,
                resourceRoot: resourceRoot,
                environment: module.installEnvironment
            )
        } else {
            throw PetctlError.requestFailed("No installer is defined for module '\(module.id)'.")
        }

        if let verifyScript = module.verifyScript {
            try runBundledScript(verifyScript, resourceRoot: resourceRoot)
        }
    }

    print("\nIntegration install finished.")
    print("Some tools may need a restart before they load new configuration.")
}

private func uninstallIntegrations(_ request: InstallerRequest) throws {
    let modules = try modulesMatching(request.moduleIDs)
    printInstallPlan(title: "Global Pet Assistant integration uninstall plan", modules: modules)
    fflush(stdout)
    if request.dryRun {
        print("Dry run only. No files were changed.")
        return
    }

    try confirmIfNeeded(request.assumeYes, prompt: "Continue with uninstall? [y/N] ")
    for module in modules {
        print("\nUninstalling \(module.title)")
        try backupExternalFiles(for: module)
        fflush(stdout)
        if module.id == "petctl-shim" {
            try uninstallPetctlShim()
        }
        for managedBlock in module.uninstall.managedBlocks {
            try removeManagedBlock(managedBlock)
        }
        for path in module.uninstall.removePaths {
            let url = expandedURL(path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("Removed \(pathForDisplay(url))")
            }
        }
        if module.uninstall.codexManagedHooks {
            try removeCodexManagedHooks()
        }
        if let featureFlagPath = module.uninstall.codexFeatureFlagPath {
            try disableCodexHooksFeatureFlag(at: expandedURL(featureFlagPath))
        }
    }

    print("\nIntegration uninstall finished.")
}

private func runDoctor() throws {
    let resourceRoot = try? bundledResourceRoot()
    print("Global Pet Assistant doctor")
    print("App home: \(appRootDirectoryURL().path)")
    print("petctl: \(petctlExecutableURL().path)")
    if let resourceRoot {
        print("resources: \(resourceRoot.path)")
    } else {
        print("resources: not found")
    }

    print("healthz: \(localAppHealthStatus(timeoutSeconds: 0.7))")
    print("\nDependencies:")
    for command in ["kitty", "codex"] {
        if let path = commandPath(command) {
            print("  \(command): \(path)")
        } else {
            print("  \(command): not found")
        }
    }

    print("\nIntegration modules:")
    for module in integrationModules() {
        let scriptStatus: String
        if let installScript = module.installScript, let resourceRoot {
            let scriptURL = resourceRoot.appendingPathComponent(installScript)
            scriptStatus = FileManager.default.isExecutableFile(atPath: scriptURL.path) ? "ready" : "missing"
        } else if module.id == "petctl-shim" {
            scriptStatus = "built in"
        } else {
            scriptStatus = "not configured"
        }
        print("  \(module.id): \(scriptStatus)")
    }
}

private func selectedInstallModules(for request: InstallerRequest) throws -> [IntegrationModule] {
    if !request.moduleIDs.isEmpty {
        return try modulesMatching(request.moduleIDs)
    }

    if isatty(STDIN_FILENO) == 0 && !request.assumeYes && !request.dryRun {
        throw PetctlError.usage("Use --with, --yes, or run petctl install from an interactive terminal.")
    }

    let recommendedModules = integrationModules().filter(\.recommended)
    if request.assumeYes || request.dryRun {
        return recommendedModules
    }

    print("Global Pet Assistant Setup")
    print("\nDetected:")
    for command in ["kitty", "codex"] {
        let status = commandPath(command) == nil ? "not found" : "found"
        print("  \(command): \(status)")
    }

    print("\nAvailable modules:")
    for module in integrationModules() {
        let marker = module.recommended ? "recommended" : "advanced"
        print("  \(module.id) - \(module.title) (\(marker))")
        for path in module.modifiedPaths {
            print("      modifies \(path)")
        }
    }

    let defaultIDs = recommendedModules.map(\.id).joined(separator: ",")
    print("\nChoose modules to install [\(defaultIDs)]: ", terminator: "")
    guard let line = readLine() else {
        throw PetctlError.usage("No modules selected.")
    }

    let selectedIDs = line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? recommendedModules.map(\.id)
        : moduleIDs(from: line)
    return try modulesMatching(selectedIDs)
}

private func modulesMatching(_ ids: [String]) throws -> [IntegrationModule] {
    let modulesByID = Dictionary(uniqueKeysWithValues: integrationModules().map { ($0.id, $0) })
    var modules: [IntegrationModule] = []
    for id in ids {
        guard let module = modulesByID[id] else {
            throw PetctlError.usage("Unknown integration module: \(id).")
        }
        modules.append(module)
    }
    return modules
}

private func integrationModules() -> [IntegrationModule] {
    [
        IntegrationModule(
            id: "kitty",
            title: "Kitty Command Flashes",
            category: "terminal",
            recommended: true,
            requiredCommands: ["kitty"],
            modifiedPaths: [
                "~/.config/kitty/kitty.conf",
                "~/.config/kitty/global-pet-assistant/"
            ],
            installScript: "plugins/kitty/install.sh",
            verifyScript: "Tools/verify-kitty-plugin.sh",
            uninstall: .init(
                removePaths: ["~/.config/kitty/global-pet-assistant/"],
                managedBlocks: [
                    .init(
                        path: "~/.config/kitty/kitty.conf",
                        begin: "# >>> global-pet-assistant kitty remote control >>>",
                        end: "# <<< global-pet-assistant kitty remote control <<<"
                    ),
                    .init(
                        path: "~/.zshrc",
                        begin: "# >>> global-pet-assistant kitty plugin >>>",
                        end: "# <<< global-pet-assistant kitty plugin <<<"
                    )
                ]
            )
        ),
        IntegrationModule(
            id: "codex",
            title: "Codex Session Reminders",
            category: "agent",
            recommended: true,
            requiredCommands: ["codex"],
            modifiedPaths: [
                "~/.codex/hooks.json",
                "~/.codex/config.toml"
            ],
            installScript: "plugins/codex/install.sh",
            verifyScript: nil,
            uninstall: .init(
                removePaths: [],
                managedBlocks: [],
                codexManagedHooks: true,
                codexFeatureFlagPath: "~/.codex/config.toml"
            )
        ),
        IntegrationModule(
            id: "petctl-shim",
            title: "Optional petctl command shim",
            category: "cli",
            recommended: false,
            requiredCommands: [],
            modifiedPaths: [
                "~/.local/bin/petctl"
            ],
            installScript: nil,
            verifyScript: nil,
            uninstall: .init(
                removePaths: ["~/.local/bin/petctl"],
                managedBlocks: []
            )
        ),
        IntegrationModule(
            id: "kitty-legacy-zsh",
            title: "Legacy Kitty zsh Compatibility",
            category: "terminal",
            recommended: false,
            requiredCommands: ["kitty"],
            modifiedPaths: [
                "~/.zshrc",
                "~/.config/kitty/global-pet-assistant/"
            ],
            installScript: "plugins/kitty/install.sh",
            verifyScript: nil,
            installEnvironment: ["GPA_KITTY_PLUGIN_INSTALL_ZSHRC": "1"],
            uninstall: .init(
                removePaths: [],
                managedBlocks: [
                    .init(
                        path: "~/.zshrc",
                        begin: "# >>> global-pet-assistant kitty plugin >>>",
                        end: "# <<< global-pet-assistant kitty plugin <<<"
                    )
                ]
            )
        )
    ]
}

private func printInstallPlan(title: String, modules: [IntegrationModule]) {
    print(title)
    print("healthz: \(localAppHealthStatus(timeoutSeconds: 0.7))")
    print("\nModules:")
    for module in modules {
        print("  - \(module.id): \(module.title)")
        let missingCommands = module.requiredCommands.filter { commandPath($0) == nil }
        if !missingCommands.isEmpty {
            print("    warning: missing command(s): \(missingCommands.joined(separator: ", "))")
        }
    }

    let modifiedPaths = modules.flatMap(\.modifiedPaths)
    if !modifiedPaths.isEmpty {
        print("\nExternal files or directories that may change:")
        for path in Array(Set(modifiedPaths)).sorted() {
            print("  \(path)")
        }
    }

    print("\nExisting files will be backed up before modification.")
}

private func confirmIfNeeded(_ assumeYes: Bool, prompt: String) throws {
    if assumeYes {
        return
    }

    guard isatty(STDIN_FILENO) != 0 else {
        throw PetctlError.usage("Refusing to modify external configuration without --yes in a non-interactive shell.")
    }

    print(prompt, terminator: "")
    let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard answer == "y" || answer == "yes" else {
        throw PetctlError.usage("Cancelled.")
    }
}

private func backupExternalFiles(for module: IntegrationModule) throws {
    var rawPaths = module.modifiedPaths
    rawPaths.append(contentsOf: module.uninstall.managedBlocks.map(\.path))
    if module.uninstall.codexManagedHooks {
        rawPaths.append("~/.codex/hooks.json")
    }
    if let codexFeatureFlagPath = module.uninstall.codexFeatureFlagPath {
        rawPaths.append(codexFeatureFlagPath)
    }

    for rawPath in Array(Set(rawPaths)).sorted() {
        let url = expandedURL(rawPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            continue
        }
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).global-pet-assistant-backup-\(backupTimestamp())")
        try FileManager.default.copyItem(at: url, to: backupURL)
        print("Backed up \(pathForDisplay(url)) to \(pathForDisplay(backupURL))")
    }
}

private func runBundledScript(
    _ relativePath: String,
    resourceRoot: URL,
    environment: [String: String] = [:]
) throws {
    let scriptURL = resourceRoot.appendingPathComponent(relativePath)
    guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
        throw PetctlError.requestFailed("Bundled script is missing or not executable: \(scriptURL.path)")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["bash", scriptURL.path]
    var processEnvironment = ProcessInfo.processInfo.environment
    processEnvironment["GPA_RESOURCE_ROOT"] = resourceRoot.path
    for (key, value) in environment {
        processEnvironment[key] = value
    }
    process.environment = processEnvironment
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw PetctlError.requestFailed("\(relativePath) failed with exit \(process.terminationStatus).")
    }
}

private func installPetctlShim() throws {
    let shimURL = expandedURL("~/.local/bin/petctl")
    try FileManager.default.createDirectory(
        at: shimURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: shimURL.path) {
        try FileManager.default.removeItem(at: shimURL)
    }
    try FileManager.default.createSymbolicLink(
        at: shimURL,
        withDestinationURL: petctlExecutableURL()
    )
    print("Installed \(pathForDisplay(shimURL)) -> \(petctlExecutableURL().path)")
    if !PATHContains(shimURL.deletingLastPathComponent()) {
        print("Note: ~/.local/bin is not currently on PATH. Add it manually if you want to run petctl by name.")
    }
}

private func uninstallPetctlShim() throws {
    let shimURL = expandedURL("~/.local/bin/petctl")
    guard FileManager.default.fileExists(atPath: shimURL.path) else {
        return
    }
    try FileManager.default.removeItem(at: shimURL)
    print("Removed \(pathForDisplay(shimURL))")
}

private func removeManagedBlock(_ block: IntegrationModule.ManagedBlock) throws {
    let url = expandedURL(block.path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }
    let content = try String(contentsOf: url, encoding: .utf8)
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var output: [String] = []
    var skipping = false
    var removed = false
    for line in lines {
        if line == block.begin {
            skipping = true
            removed = true
            continue
        }
        if line == block.end {
            skipping = false
            continue
        }
        if !skipping {
            output.append(line)
        }
    }
    guard removed else {
        return
    }
    try output.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    print("Removed managed block from \(pathForDisplay(url))")
}

private func removeCodexManagedHooks() throws {
    let hooksURL = expandedURL("~/.codex/hooks.json")
    guard FileManager.default.fileExists(atPath: hooksURL.path) else {
        return
    }
    let data = try Data(contentsOf: hooksURL)
    var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    guard var hooks = root["hooks"] as? [String: Any] else {
        return
    }
    var changed = false
    for (eventName, rawGroups) in hooks {
        guard let groups = rawGroups as? [[String: Any]] else {
            continue
        }
        var nextGroups: [[String: Any]] = []
        for var group in groups {
            guard let entries = group["hooks"] as? [[String: Any]] else {
                nextGroups.append(group)
                continue
            }
            let filteredEntries = entries.filter { entry in
                guard let command = entry["command"] as? String else {
                    return true
                }
                return !command.contains("global-pet-agent-bridge")
            }
            if filteredEntries.count != entries.count {
                changed = true
            }
            if !filteredEntries.isEmpty {
                group["hooks"] = filteredEntries
                nextGroups.append(group)
            }
        }
        hooks[eventName] = nextGroups
    }
    guard changed else {
        return
    }
    root["hooks"] = hooks
    var output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    output.append(0x0a)
    try output.write(to: hooksURL, options: [.atomic])
    print("Removed managed Codex hook entries from \(pathForDisplay(hooksURL))")
}

private func disableCodexHooksFeatureFlag(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }
    let content = try String(contentsOf: url, encoding: .utf8)
    guard content.contains("codex_hooks") else {
        return
    }
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("codex_hooks") {
            return "codex_hooks = false"
        }
        return String(line)
    }
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    print("Disabled codex_hooks in \(pathForDisplay(url))")
}

private func localAppHealthStatus(timeoutSeconds: TimeInterval) -> String {
    guard let url = URL(string: "http://127.0.0.1:17321/healthz") else {
        return "invalid URL"
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResponseBox()
    URLSession(configuration: configuration).dataTask(with: url) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            box.result = .failure(error)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            box.result = .failure(PetctlError.requestFailed("no HTTP response"))
            return
        }
        box.result = .success((data ?? Data(), httpResponse))
    }.resume()
    guard semaphore.wait(timeout: .now() + timeoutSeconds) == .success,
          let result = box.result
    else {
        return "not reachable"
    }
    switch result {
    case .success((_, let response)):
        return (200..<300).contains(response.statusCode) ? "reachable" : "HTTP \(response.statusCode)"
    case .failure:
        return "not reachable"
    }
}

private func commandPath(_ command: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["sh", "-lc", "command -v \(shellQuoted(command))"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else {
        return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return path?.isEmpty == false ? path : nil
}

private func bundledResourceRoot() throws -> URL {
    if let rawRoot = ProcessInfo.processInfo.environment["GPA_RESOURCE_ROOT"],
       !rawRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return expandedURL(rawRoot)
    }

    let executableURL = petctlExecutableURL()
    let binDirectory = executableURL.deletingLastPathComponent()
    if binDirectory.lastPathComponent == "bin",
       binDirectory.deletingLastPathComponent().lastPathComponent == "Resources" {
        return binDirectory.deletingLastPathComponent()
    }

    var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .standardizedFileURL
    while candidate.path != "/" {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }

    throw PetctlError.requestFailed("Could not locate bundled resources. Set GPA_RESOURCE_ROOT.")
}

private func petctlExecutableURL() -> URL {
    let rawPath = CommandLine.arguments[0]
    let url: URL
    if rawPath.hasPrefix("/") {
        url = URL(fileURLWithPath: rawPath)
    } else {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(rawPath)
    }
    return url.standardizedFileURL
}

private func expandedURL(_ path: String) -> URL {
    URL(fileURLWithPath: expandUserPath(path)).standardizedFileURL
}

private func pathForDisplay(_ url: URL) -> String {
    let home = userHomeDirectoryURL().standardizedFileURL.path
    if url.path == home {
        return "~"
    }
    if url.path.hasPrefix(home + "/") {
        return "~/" + String(url.path.dropFirst(home.count + 1))
    }
    return url.path
}

private func backupTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func PATHContains(_ directory: URL) -> Bool {
    let target = directory.standardizedFileURL.path
    return (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .map(String.init)
        .contains { URL(fileURLWithPath: $0).standardizedFileURL.path == target }
}

private func executeRun(_ request: PetctlRunRequest) throws -> Never {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = request.command

    do {
        try process.run()
    } catch {
        try? sendFlash(
            source: request.source,
            level: "danger",
            message: "\(commandDescription(request.command)) could not start",
            timeoutSeconds: request.timeoutSeconds
        )
        throw error
    }

    process.waitUntilExit()

    let exitCode: Int32
    switch process.terminationReason {
    case .exit:
        exitCode = process.terminationStatus
    case .uncaughtSignal:
        exitCode = 128 + process.terminationStatus
    @unknown default:
        exitCode = process.terminationStatus
    }

    let description = commandDescription(request.command)
    let level = exitCode == 0 ? "success" : "danger"
    let message = exitCode == 0
        ? "\(description) passed"
        : "\(description) failed (exit \(exitCode))"
    do {
        try sendFlash(
            source: request.source,
            level: level,
            message: message,
            timeoutSeconds: request.timeoutSeconds
        )
    } catch {
        fputs("petctl run: command finished, but flash failed: \(String(describing: error))\n", stderr)
    }

    exit(exitCode)
}

private func sendFlash(
    source: String,
    level: String,
    message: String,
    timeoutSeconds: TimeInterval
) throws {
    let event = PetctlEvent(
        source: source,
        type: "flash",
        level: level,
        message: message
    )
    try send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
}

private func commandDescription(_ command: [String]) -> String {
    command.joined(separator: " ")
}

private func send(_ requestEnvelope: PetctlRequest) throws {
    let url = URL(string: "http://127.0.0.1:17321/events")!
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestEnvelope.timeoutSeconds
    configuration.timeoutIntervalForResource = requestEnvelope.timeoutSeconds

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(try loadToken())", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(requestEnvelope.event)

    let semaphore = DispatchSemaphore(value: 0)
    let responseBox = ResponseBox()

    let task = URLSession(configuration: configuration).dataTask(with: request) { data, response, error in
        defer {
            semaphore.signal()
        }

        if let error {
            responseBox.result = .failure(error)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            responseBox.result = .failure(PetctlError.requestFailed("No HTTP response from local app."))
            return
        }

        responseBox.result = .success((data ?? Data(), httpResponse))
    }
    task.resume()

    let waitResult = semaphore.wait(timeout: .now() + requestEnvelope.timeoutSeconds)
    guard waitResult == .success else {
        task.cancel()
        throw PetctlError.requestFailed("Timed out after \(requestEnvelope.timeoutSeconds) seconds waiting for local app.")
    }

    let (data, response) = try responseBox.result!.get()
    guard (200..<300).contains(response.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw PetctlError.requestFailed("Local app returned HTTP \(response.statusCode): \(body)")
    }

    if let body = String(data: data, encoding: .utf8), !body.isEmpty {
        print(body)
    }
}

private final class ResponseBox: @unchecked Sendable {
    var result: Result<(Data, HTTPURLResponse), Error>?
}

private func appPetsDirectoryURL() -> URL {
    appRootDirectoryURL()
        .appendingPathComponent("pets", isDirectory: true)
}

private func logsDirectoryURL() -> URL {
    appRootDirectoryURL()
        .appendingPathComponent("logs", isDirectory: true)
}

private func appTokenURL() -> URL {
    appRootDirectoryURL()
        .appendingPathComponent("token")
}

private func loadToken() throws -> String {
    let tokenURL = appTokenURL()
    guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !token.isEmpty
    else {
        throw PetctlError.requestFailed("Missing local auth token at \(tokenURL.path). Start Global Pet Assistant once to create it.")
    }

    return token
}

private func appConfigurationURL() -> URL {
    appRootDirectoryURL()
        .appendingPathComponent("config.json")
}

private func appRootDirectoryURL() -> URL {
    if let root = ProcessInfo.processInfo.environment["GLOBAL_PET_ASSISTANT_HOME"],
       !root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: expandUserPath(root), isDirectory: true).standardizedFileURL
    }

    return userHomeDirectoryURL()
        .appendingPathComponent(".global-pet-assistant", isDirectory: true)
}

private func petImportSourceDirectoryURLs() -> [URL] {
    let configuredPaths = configuredPetImportSourceDirectories()
        ?? [defaultCodexPetsDirectoryURL().path]
    var seen: Set<String> = []
    return configuredPaths
        .map(expandUserPath)
        .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        .filter { url in
            guard !seen.contains(url.path) else {
                return false
            }
            seen.insert(url.path)
            return true
        }
}

private func configuredPetImportSourceDirectories() -> [String]? {
    guard let data = try? Data(contentsOf: appConfigurationURL()),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let paths = object["petImportSourceDirectories"] as? [String]
    else {
        return nil
    }

    return paths
}

private func expandUserPath(_ path: String) -> String {
    if path == "~" {
        return userHomeDirectoryURL().path
    }

    if path.hasPrefix("~/") {
        return userHomeDirectoryURL()
            .appendingPathComponent(String(path.dropFirst(2)))
            .path
    }

    return path
}

private func defaultCodexPetsDirectoryURL() -> URL {
    userHomeDirectoryURL()
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("pets", isDirectory: true)
}

private func userHomeDirectoryURL() -> URL {
    if let home = ProcessInfo.processInfo.environment["HOME"],
       !home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
    }

    return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
}
