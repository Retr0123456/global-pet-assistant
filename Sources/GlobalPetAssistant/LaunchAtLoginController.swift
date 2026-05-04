import Foundation
import ServiceManagement

enum LaunchAtLoginError: Error, CustomStringConvertible {
    case unavailableStatus(SMAppService.Status)

    var description: String {
        switch self {
        case .unavailableStatus(let status):
            "Launch at login is unavailable for this app bundle status: \(status)."
        }
    }
}

final class LaunchAtLoginController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private func enable() throws {
        switch SMAppService.mainApp.status {
        case .enabled:
            return
        case .notRegistered:
            try SMAppService.mainApp.register()
        case .requiresApproval, .notFound:
            throw LaunchAtLoginError.unavailableStatus(SMAppService.mainApp.status)
        @unknown default:
            throw LaunchAtLoginError.unavailableStatus(SMAppService.mainApp.status)
        }
    }

    private func disable() throws {
        guard SMAppService.mainApp.status == .enabled else {
            return
        }

        try SMAppService.mainApp.unregister()
    }
}
