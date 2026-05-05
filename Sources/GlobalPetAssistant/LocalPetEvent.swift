import Foundation

enum PetEventLevel: String, Codable, Equatable {
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
    var kittyWindowId: String?
    var kittyListenOn: String?
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
    var cwd: String?
    var transient: Bool?

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
        case cwd
        case transient
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
        action: LocalPetAction? = nil,
        cwd: String? = nil,
        transient: Bool? = nil
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
        self.cwd = cwd
        self.transient = transient
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
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        transient = try container.decodeIfPresent(Bool.self, forKey: .transient)
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

    var isFlashEvent: Bool {
        type?.lowercased() == "flash" || transient == true
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

    var threadTitle: String {
        let candidates = [
            title,
            type,
            source
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Untitled thread"
    }

    var threadContext: String {
        let candidates = [
            message,
            level?.rawValue,
            state?.rawValue
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? source
    }

    var threadDirectoryName: String {
        if let directoryName = directoryName(from: cwd) {
            return directoryName
        }

        if let actionPath = action?.path {
            let displayPath = action?.type == "open_file"
                ? URL(fileURLWithPath: actionPath).deletingLastPathComponent().path
                : actionPath
            if let directoryName = directoryName(from: displayPath) {
                return directoryName
            }
        }

        return threadTitle
    }

    var threadMessagePreview: String {
        let normalized = threadContext
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return Self.truncate(normalized, limit: 120)
    }

    var flashMessagePreview: String {
        let candidates = [
            message,
            title,
            level?.rawValue,
            source
        ]

        let normalized = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Event received"

        return Self.truncate(
            normalized.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            limit: 96
        )
    }

    var flashAnimationState: PetAnimationState {
        if let state {
            return state
        }

        switch level {
        case .danger:
            return .failed
        case .warning:
            return .waiting
        case .success:
            return .waving
        case .running:
            return .jumping
        case .info, .none:
            return .waving
        }
    }

    private func directoryName(from rawPath: String?) -> String? {
        guard let rawPath else {
            return nil
        }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: trimmed)
        let lastComponent = url.lastPathComponent
        return lastComponent.isEmpty ? trimmed : lastComponent
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: max(0, limit - 1))
        return text[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
