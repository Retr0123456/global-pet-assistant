import Foundation

struct ThreadDisplayRow: Equatable, Identifiable {
    enum RowKind: Equatable {
        case generic
        case agent
    }

    let id: String
    let kind: RowKind
    let source: String
    let title: String
    let context: String
    let directoryName: String
    let messagePreview: String
    let action: LocalPetAction?
    let state: PetAnimationState
    let status: PetThreadStatus
    let canSendMessage: Bool

    init(generic thread: PetThreadSnapshot) {
        self.id = thread.source
        self.kind = .generic
        self.source = thread.source
        self.title = thread.title
        self.context = thread.context
        self.directoryName = thread.directoryName
        self.messagePreview = thread.messagePreview
        self.action = thread.action
        self.state = thread.state
        self.status = thread.status
        self.canSendMessage = false
    }

    init(agent thread: AgentThreadSnapshot) {
        self.id = thread.id
        self.kind = .agent
        self.source = thread.id
        self.title = thread.title
        self.context = thread.context
        self.directoryName = thread.directoryName
        self.messagePreview = thread.messagePreview
        self.action = nil
        self.state = Self.state(for: thread.status)
        self.status = thread.status
        self.canSendMessage = thread.capabilityRoutes.contains { route, capabilities in
            route != .terminalPlugin && capabilities.contains(.sendMessage)
        }
    }

    private static func state(for status: PetThreadStatus) -> PetAnimationState {
        switch status {
        case .running:
            return .running
        case .waiting, .approvalRequired:
            return .waiting
        case .success:
            return .waving
        case .failed:
            return .failed
        case .info:
            return .idle
        }
    }
}

struct ThreadPanelSnapshot: Equatable {
    let genericThreads: [PetThreadSnapshot]
    let agentThreads: [AgentThreadSnapshot]
    let flashMessages: [PetFlashSnapshot]

    init(
        genericThreads: [PetThreadSnapshot] = [],
        agentThreads: [AgentThreadSnapshot] = [],
        flashMessages: [PetFlashSnapshot] = []
    ) {
        self.genericThreads = genericThreads.filter { !$0.source.hasPrefix("agent:") }
        self.agentThreads = agentThreads
        self.flashMessages = flashMessages
    }

    var activeCount: Int {
        genericThreads.count + agentThreads.count
    }

    var displayRows: [ThreadDisplayRow] {
        agentThreads.map(ThreadDisplayRow.init(agent:))
            + genericThreads.map(ThreadDisplayRow.init(generic:))
    }

    var statusSummary: ThreadStatusSummary {
        ThreadStatusSummary(rows: displayRows)
    }

    var preferredPetState: PetAnimationState {
        statusSummary.preferredPetState
    }
}

struct ThreadStatusSummary: Equatable {
    let failedCount: Int
    let runningCount: Int
    let successCount: Int
    let hasWaiting: Bool

    static let empty = ThreadStatusSummary(
        failedCount: 0,
        runningCount: 0,
        successCount: 0,
        hasWaiting: false
    )

    init(
        failedCount: Int,
        runningCount: Int,
        successCount: Int,
        hasWaiting: Bool
    ) {
        self.failedCount = failedCount
        self.runningCount = runningCount
        self.successCount = successCount
        self.hasWaiting = hasWaiting
    }

    init(rows: [ThreadDisplayRow]) {
        var failedCount = 0
        var runningCount = 0
        var successCount = 0
        var hasWaiting = false

        for row in rows {
            switch row.status {
            case .failed:
                failedCount += 1
            case .running:
                runningCount += 1
            case .waiting, .approvalRequired:
                runningCount += 1
                hasWaiting = true
            case .success:
                successCount += 1
            case .info:
                break
            }
        }

        self.failedCount = failedCount
        self.runningCount = runningCount
        self.successCount = successCount
        self.hasWaiting = hasWaiting
    }

    var totalCount: Int {
        failedCount + runningCount + successCount
    }

    var preferredPetState: PetAnimationState {
        if failedCount > 0 {
            return .failed
        }

        if successCount > 0 {
            return .waving
        }

        if runningCount > 0 {
            return hasWaiting ? .waiting : .running
        }

        return .idle
    }

    var tooltip: String {
        "\(failedCount) failed, \(runningCount) running or waiting, \(successCount) successful"
    }
}
