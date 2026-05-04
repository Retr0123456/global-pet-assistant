import AppKit
import Foundation

final class ActionHandler {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    @discardableResult
    func perform(_ action: LocalPetAction?) -> Bool {
        guard let action else {
            return false
        }

        do {
            guard let target = try Self.validatedTarget(for: action, fileManager: fileManager) else {
                return false
            }

            switch target {
            case .url(let url):
                return workspace.open(url)
            case .folder(let url):
                return workspace.open(url)
            }
        } catch {
            NSLog("GlobalPetAssistant rejected action: \(String(describing: error))")
            return false
        }
    }

    static func validate(_ action: LocalPetAction?, fileManager: FileManager = .default) throws {
        _ = try validatedTarget(for: action, fileManager: fileManager)
    }

    private static func validatedTarget(
        for action: LocalPetAction?,
        fileManager: FileManager
    ) throws -> ActionTarget? {
        guard let action else {
            return nil
        }

        switch action.type {
        case "open_url":
            guard let rawURL = action.url, let components = URLComponents(string: rawURL), let url = components.url else {
                throw ActionValidationError.invalidURL(action.url ?? "")
            }

            guard isAllowedURL(components) else {
                throw ActionValidationError.disallowedURL(rawURL)
            }

            return .url(url)
        case "open_folder":
            guard let rawPath = action.path, !rawPath.isEmpty else {
                throw ActionValidationError.invalidFolderPath(action.path ?? "")
            }

            let url = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard isAllowedFolderPath(url.path) else {
                throw ActionValidationError.disallowedFolderPath(url.path)
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ActionValidationError.folderDoesNotExist(url.path)
            }

            return .folder(url)
        default:
            throw ActionValidationError.unsupportedActionType(action.type)
        }
    }

    private static func isAllowedURL(_ components: URLComponents) -> Bool {
        if components.scheme == "https", components.host == "github.com" {
            return true
        }

        if components.scheme == "http", components.host == "127.0.0.1" {
            return true
        }

        return false
    }

    private static func isAllowedFolderPath(_ path: String) -> Bool {
        let allowedRoots = [
            "/Users/ryanchen/codespace",
            "/Users/ryanchen/.global-pet-assistant"
        ]

        return allowedRoots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }
}

private enum ActionTarget {
    case url(URL)
    case folder(URL)
}

enum ActionValidationError: Error, CustomStringConvertible {
    case unsupportedActionType(String)
    case invalidURL(String)
    case disallowedURL(String)
    case invalidFolderPath(String)
    case disallowedFolderPath(String)
    case folderDoesNotExist(String)

    var description: String {
        switch self {
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
        }
    }
}
