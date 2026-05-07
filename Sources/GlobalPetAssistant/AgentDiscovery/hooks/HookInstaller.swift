import Foundation

enum HookInstaller {
    static func updatedHooksPayload(existing: JSONValue?, profile: CodexHookProfile) -> JSONValue {
        var root = existing?.objectValue ?? [:]
        var hooks = root["hooks"]?.objectValue ?? [:]

        for event in profile.events {
            let existingGroups = hooks[event.name]?.arrayValue ?? []
            var groups = existingGroups.compactMap { groupValue -> JSONValue? in
                guard var group = groupValue.objectValue else {
                    return groupValue
                }
                let hookEntries = group["hooks"]?.arrayValue ?? []
                let filteredEntries = hookEntries.filter { hookValue in
                    guard let command = hookValue.objectValue?["command"]?.stringValue else {
                        return true
                    }
                    return !command.contains(profile.managedCommandNeedle)
                }
                guard !filteredEntries.isEmpty else {
                    return nil
                }
                group["hooks"] = .array(filteredEntries)
                return .object(group)
            }
            groups.append(managedGroup(for: event, profile: profile))
            hooks[event.name] = .array(groups)
        }

        root["hooks"] = .object(hooks)
        return .object(root)
    }

    static func managedGroup(for event: CodexHookProfile.Event, profile: CodexHookProfile) -> JSONValue {
        var group: [String: JSONValue] = [
            "hooks": .array([
                .object([
                    "type": .string("command"),
                    "command": .string(profile.command),
                    "timeout": .number(Double(profile.timeoutSeconds)),
                    "statusMessage": .string(event.statusMessage)
                ])
            ])
        ]
        if let matcher = event.matcher {
            group["matcher"] = .string(matcher)
        }
        return .object(group)
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }
}
