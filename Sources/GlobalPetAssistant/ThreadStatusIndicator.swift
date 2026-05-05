import Foundation

struct ThreadStatusIndicator: Equatable {
    let symbolName: String
    let accessibilityDescription: String
}

extension PetThreadStatus {
    var indicator: ThreadStatusIndicator {
        switch self {
        case .running:
            ThreadStatusIndicator(
                symbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: "Thread is running"
            )
        case .waiting:
            ThreadStatusIndicator(
                symbolName: "hourglass",
                accessibilityDescription: "Thread is waiting"
            )
        case .success:
            ThreadStatusIndicator(
                symbolName: "checkmark.circle.fill",
                accessibilityDescription: "Thread completed successfully"
            )
        case .failed:
            ThreadStatusIndicator(
                symbolName: "xmark.circle.fill",
                accessibilityDescription: "Thread failed"
            )
        case .approvalRequired:
            ThreadStatusIndicator(
                symbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "Thread needs approval"
            )
        case .info:
            ThreadStatusIndicator(
                symbolName: "info.circle.fill",
                accessibilityDescription: "Thread status"
            )
        }
    }
}
