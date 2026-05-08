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
        self.canSendMessage = thread.capabilities.contains(.sendMessage)
    }

    private static func state(for status: PetThreadStatus) -> PetAnimationState {
        switch status {
        case .running:
            return .running
        case .waiting, .approvalRequired:
            return .waiting
        case .success:
            return .review
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
}
