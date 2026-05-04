import Foundation

enum PetEventLevel: String, Codable {
    case info
    case running
    case success
    case warning
    case danger
}

struct LocalPetAction: Codable, Equatable {
    var type: String
    var url: String?
    var path: String?
    var bundleId: String?
}

struct LocalPetEvent: Codable, Equatable {
    var source: String
    var type: String?
    var level: PetEventLevel?
    var title: String?
    var message: String?
    var state: PetAnimationState?
    var ttlMs: Int?
    var dedupeKey: String?
    var action: LocalPetAction?

    enum CodingKeys: String, CodingKey {
        case source
        case type
        case level
        case title
        case message
        case state
        case ttlMs
        case dedupeKey
        case action
    }

    init(
        source: String = "unknown",
        type: String? = nil,
        level: PetEventLevel? = nil,
        title: String? = nil,
        message: String? = nil,
        state: PetAnimationState? = nil,
        ttlMs: Int? = nil,
        dedupeKey: String? = nil,
        action: LocalPetAction? = nil
    ) {
        self.source = source.isEmpty ? "unknown" : source
        self.type = type
        self.level = level
        self.title = title
        self.message = message
        self.state = state
        self.ttlMs = ttlMs
        self.dedupeKey = dedupeKey
        self.action = action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        type = try container.decodeIfPresent(String.self, forKey: .type)
        level = try container.decodeIfPresent(PetEventLevel.self, forKey: .level)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        state = try container.decodeIfPresent(PetAnimationState.self, forKey: .state)
        ttlMs = try container.decodeIfPresent(Int.self, forKey: .ttlMs)
        dedupeKey = try container.decodeIfPresent(String.self, forKey: .dedupeKey)
        action = try container.decodeIfPresent(LocalPetAction.self, forKey: .action)
    }

    var resolvedPetState: PetAnimationState {
        if let state {
            return state
        }

        switch level {
        case .danger:
            return .failed
        case .warning:
            return .waiting
        case .success:
            return .review
        case .running:
            return .running
        case .info, .none:
            return .idle
        }
    }

    var isClearEvent: Bool {
        type?.lowercased() == "clear"
    }

    var clearsRouter: Bool {
        isClearEvent || state == .idle
    }

    var normalizedDedupeKey: String? {
        guard let dedupeKey else {
            return nil
        }

        let trimmed = dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
