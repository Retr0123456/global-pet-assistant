import AppKit
import Foundation

final class ActionHandler {
    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let applicationURLForBundleIdentifier: (String) -> URL?

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default,
        applicationURLForBundleIdentifier: ((String) -> URL?)? = nil
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.applicationURLForBundleIdentifier = applicationURLForBundleIdentifier
            ?? { workspace.urlForApplication(withBundleIdentifier: $0) }
    }

    @discardableResult
    func perform(
        _ action: LocalPetAction?,
        source: String?,
        configuration: AppConfiguration
    ) -> Bool {
        guard let action else {
            return false
        }

        do {
            guard
                let source,
                let target = try Self.validatedTarget(
                    for: action,
                    source: source,
                    configuration: configuration,
                    fileManager: fileManager,
                    applicationURLForBundleIdentifier: applicationURLForBundleIdentifier
                )
            else {
                return false
            }

            switch target {
            case .url(let url):
                return workspace.open(url)
            case .folder(let url):
                return workspace.open(url)
            case .file(let url):
                return workspace.open(url)
            case .app(let url):
                let configuration = NSWorkspace.OpenConfiguration()
                workspace.openApplication(at: url, configuration: configuration)
                return true
            }
        } catch {
            NSLog("GlobalPetAssistant rejected action: \(String(describing: error))")
            return false
        }
    }

    static func validate(
        _ action: LocalPetAction?,
        source: String,
        configuration: AppConfiguration,
        fileManager: FileManager = .default,
        applicationURLForBundleIdentifier: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    ) throws {
        _ = try validatedTarget(
            for: action,
            source: source,
            configuration: configuration,
            fileManager: fileManager,
            applicationURLForBundleIdentifier: applicationURLForBundleIdentifier
        )
    }

    private static func validatedTarget(
        for action: LocalPetAction?,
        source: String,
        configuration: AppConfiguration,
        fileManager: FileManager,
        applicationURLForBundleIdentifier: (String) -> URL?
    ) throws -> ActionTarget? {
        guard let action else {
            return nil
        }

        guard let policy = configuration.policy(for: source),
              policy.actionSet.contains(action.type)
        else {
            throw ActionValidationError.actionNotAllowed(
                source: AppConfiguration.normalizedSource(source),
                type: action.type
            )
        }

        switch action.type {
        case "open_url":
            guard let rawURL = action.url, let components = URLComponents(string: rawURL), let url = components.url else {
                throw ActionValidationError.invalidURL(action.url ?? "")
            }

            guard isSupportedURL(components) else {
                throw ActionValidationError.invalidURL(rawURL)
            }

            guard isAllowedURL(components, policy: policy) else {
                throw ActionValidationError.disallowedURL(rawURL)
            }

            return .url(url)
        case "open_folder":
            guard let rawPath = action.path, !rawPath.isEmpty else {
                throw ActionValidationError.invalidFolderPath(action.path ?? "")
            }

            let url = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard isAllowedPath(url.path, roots: policy.folderRoots) else {
                throw ActionValidationError.disallowedFolderPath(url.path)
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ActionValidationError.folderDoesNotExist(url.path)
            }

            return .folder(url)
        case "open_file":
            guard let rawPath = action.path, !rawPath.isEmpty else {
                throw ActionValidationError.invalidFilePath(action.path ?? "")
            }

            let url = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard isAllowedPath(url.path, roots: policy.folderRoots) else {
                throw ActionValidationError.disallowedFilePath(url.path)
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw ActionValidationError.fileDoesNotExist(url.path)
            }

            return .file(url)
        case "open_app":
            guard let bundleId = action.bundleId, !bundleId.isEmpty else {
                throw ActionValidationError.invalidBundleID(action.bundleId ?? "")
            }

            guard policy.appBundleIdSet.contains(bundleId) else {
                throw ActionValidationError.disallowedBundleID(bundleId)
            }

            guard let url = applicationURLForBundleIdentifier(bundleId) else {
                throw ActionValidationError.applicationDoesNotExist(bundleId)
            }

            return .app(url)
        default:
            throw ActionValidationError.unsupportedActionType(action.type)
        }
    }

    private static func isSupportedURL(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased(), components.host != nil else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    private static func isAllowedURL(_ components: URLComponents, policy: SourceActionPolicy) -> Bool {
        guard let host = components.host?.lowercased() else {
            return false
        }

        return policy.urlHostSet.contains(host)
    }

    private static func isAllowedPath(_ path: String, roots: [String]) -> Bool {
        roots
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .contains { root in
                path == root || path.hasPrefix(root + "/")
            }
    }
}

private enum ActionTarget {
    case url(URL)
    case folder(URL)
    case file(URL)
    case app(URL)
}

enum ActionValidationError: Error, CustomStringConvertible {
    case actionNotAllowed(source: String, type: String)
    case unsupportedActionType(String)
    case invalidURL(String)
    case disallowedURL(String)
    case invalidFolderPath(String)
    case disallowedFolderPath(String)
    case folderDoesNotExist(String)
    case invalidFilePath(String)
    case disallowedFilePath(String)
    case fileDoesNotExist(String)
    case invalidBundleID(String)
    case disallowedBundleID(String)
    case applicationDoesNotExist(String)

    var isActionAuthorizationFailure: Bool {
        switch self {
        case .actionNotAllowed, .disallowedURL, .disallowedFolderPath, .disallowedFilePath, .disallowedBundleID:
            return true
        case .unsupportedActionType,
             .invalidURL,
             .invalidFolderPath,
             .folderDoesNotExist,
             .invalidFilePath,
             .fileDoesNotExist,
             .invalidBundleID,
             .applicationDoesNotExist:
            return false
        }
    }

    var description: String {
        switch self {
        case let .actionNotAllowed(source, type):
            "Action type \(type) is not allowed for source \(source)."
        case .unsupportedActionType(let type):
            "Unsupported action type: \(type)."
        case .invalidURL(let url):
            "Invalid action URL: \(url)."
        case .disallowedURL(let url):
            "Action URL is not allowed: \(url)."
        case .invalidFolderPath(let path):
            "Invalid action folder path: \(path)."
        case .disallowedFolderPath(let path):
            "Action folder path is not allowed: \(path)."
        case .folderDoesNotExist(let path):
            "Action folder path is not an existing directory: \(path)."
        case .invalidFilePath(let path):
            "Invalid action file path: \(path)."
        case .disallowedFilePath(let path):
            "Action file path is not allowed: \(path)."
        case .fileDoesNotExist(let path):
            "Action file path is not an existing file: \(path)."
        case .invalidBundleID(let bundleID):
            "Invalid action app bundle identifier: \(bundleID)."
        case .disallowedBundleID(let bundleID):
            "Action app bundle identifier is not allowed: \(bundleID)."
        case .applicationDoesNotExist(let bundleID):
            "Action app bundle identifier could not be resolved: \(bundleID)."
        }
    }
}
