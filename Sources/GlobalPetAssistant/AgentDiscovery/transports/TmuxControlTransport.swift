import Foundation

struct TmuxControlTransport: AgentControlTransport {
    let kind: AgentControlTransportKind = .tmux

    func capabilities(for session: AgentSession) -> Set<AgentCapability> {
        []
    }
}
