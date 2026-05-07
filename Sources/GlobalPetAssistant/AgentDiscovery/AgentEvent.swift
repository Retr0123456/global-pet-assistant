import Foundation

struct AgentEvent: Equatable, Sendable {
    var sessionID: String
    var kind: AgentKind
    var status: AgentStatus
    var observedAt: Date
    var metadata: [String: JSONValue]
}
