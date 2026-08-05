import Foundation

enum StatusPolicy {
    static func isWorking(_ state: String) -> Bool {
        state == "thinking" || state == "tool" || state == "subagent"
    }

    static func priority(of state: String) -> Int {
        switch state {
        case "permission": return 2
        case "thinking", "tool", "subagent": return 1
        default: return 0
        }
    }

    static func effectiveState(rawState: String, age: Double) -> String {
        guard rawState == "done" else { return rawState }
        return age < 0.84 ? "done" : "idle"
    }

    static func displayLabel(state: String, storedLabel: String) -> String {
        if !storedLabel.isEmpty { return storedLabel }
        return state == "tool" ? "Working…" : "Thinking…"
    }

    static func versionIsNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func turnWasAborted(in data: Data, turnID: String) -> Bool {
        guard !turnID.isEmpty, let text = String(data: data, encoding: .utf8) else { return false }
        for line in text.split(separator: "\n").reversed() {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["turn_id"] as? String == turnID else { continue }
            return payload["type"] as? String == "turn_aborted"
        }
        return false
    }
}

enum HookEventMapper {
    static func safeID(_ value: String?) -> String {
        let raw = value ?? ""
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        let cleaned = String(raw.unicodeScalars.filter { allowed.contains($0) }.prefix(96))
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    static func toolLabel(_ name: String) -> String {
        let lower = name.lowercased()
        if lower == "bash" || lower.contains("exec") || lower.contains("command") { return "Running command" }
        if lower == "apply_patch" || lower.contains("edit") || lower.contains("write") { return "Editing" }
        if lower.contains("read") || lower.contains("fetch") || lower.contains("open") { return "Reading" }
        if lower.contains("search") || lower.contains("find") || lower.contains("grep") || lower.contains("glob") { return "Searching" }
        if lower.contains("browser") || lower.contains("web") { return "Browsing web" }
        return "Using tool"
    }

    static func subagentLabel(count: Int) -> String {
        count == 1 ? "Herding an agent…" : "Herding \(count) agents…"
    }

    static func update(payload: [String: Any], event: String, previous: [String: Any]?, pid: Int32, now: Double) -> [String: Any]? {
        let previous = previous ?? [:]
        let sessionID = payload["session_id"] as? String ?? previous["sessionId"] as? String ?? "unknown"
        let cwd = payload["cwd"] as? String ?? previous["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? (previous["project"] as? String ?? "") : URL(fileURLWithPath: cwd).lastPathComponent
        let tool = payload["tool_name"] as? String ?? ""
        let agentID = payload["agent_id"] as? String ?? ""
        var state: String
        var label: String
        var activeAgents = previous["activeAgents"] as? [String] ?? []
        var startedAt = previous["startedAt"] as? Double ?? 0
        var started = previous["started"] as? Bool ?? false

        switch event {
        case "SessionStart":
            activeAgents = []
            state = "idle"; label = ""; startedAt = 0
        case "UserPromptSubmit":
            activeAgents = []
            state = "thinking"; label = "Thinking…"; startedAt = now; started = true
        case "SubagentStart":
            if !agentID.isEmpty, !activeAgents.contains(agentID) { activeAgents.append(agentID) }
            activeAgents.sort()
            state = "subagent"; label = subagentLabel(count: max(1, activeAgents.count))
            startedAt = startedAt == 0 ? now : startedAt; started = true
        case "SubagentStop":
            if !agentID.isEmpty { activeAgents.removeAll { $0 == agentID } }
            if activeAgents.isEmpty {
                state = "thinking"; label = "Thinking…"
            } else {
                state = "subagent"; label = subagentLabel(count: activeAgents.count)
            }
            startedAt = startedAt == 0 ? now : startedAt; started = true
        case "PreToolUse":
            state = "tool"; label = toolLabel(tool)
            startedAt = startedAt == 0 ? now : startedAt; started = true
        case "PostToolUse":
            if activeAgents.isEmpty {
                state = "thinking"; label = "Thinking…"
            } else {
                state = "subagent"; label = subagentLabel(count: activeAgents.count)
            }
            startedAt = startedAt == 0 ? now : startedAt; started = true
        case "PermissionRequest":
            state = "permission"; label = "Awaiting permission"; startedAt = 0; started = true
        case "Stop":
            activeAgents = []
            state = "done"; label = "Done"; startedAt = 0; started = true
        default:
            return nil
        }

        return [
            "state": state,
            "label": label,
            "activeAgents": activeAgents,
            "tool": tool,
            "project": project,
            "cwd": cwd,
            "sessionId": sessionID,
            "turnId": payload["turn_id"] as? String ?? previous["turnId"] as? String ?? "",
            "transcript": payload["transcript_path"] as? String ?? previous["transcript"] as? String ?? "",
            "model": payload["model"] as? String ?? previous["model"] as? String ?? "",
            "surface": payload["surface"] as? String ?? previous["surface"] as? String ?? "",
            "term_program": payload["term_program"] as? String ?? previous["term_program"] as? String ?? "",
            "pid": Int(pid),
            "started": started,
            "startedAt": startedAt,
            "ts": now,
        ]
    }
}

enum HookConfiguration {
    static let marker = "codex-status-bar-hook"
    static let events = ["SessionStart", "UserPromptSubmit", "SubagentStart", "PreToolUse", "PostToolUse", "PermissionRequest", "SubagentStop", "Stop"]

    static func command(helperPath: String, event: String) -> String {
        let quoted = "'" + helperPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "\(quoted) \(event) # \(marker)"
    }

    static func decode(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CodexStatusBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "hooks.json must contain a JSON object"])
        }
        return root
    }

    static func encoded(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        return data
    }

    static func uninstallObject(_ root: [String: Any]) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let keptGroups: [[String: Any]] = groups.compactMap { group in
                var group = group
                let handlers = (group["hooks"] as? [[String: Any]] ?? []).filter {
                    !(($0["command"] as? String) ?? "").contains(marker)
                }
                guard !handlers.isEmpty else { return nil }
                group["hooks"] = handlers
                return group
            }
            if keptGroups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = keptGroups }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return root
    }

    static func install(existing: Data?, helperPath: String) throws -> Data {
        var root = uninstallObject(try decode(existing))
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command(helperPath: helperPath, event: event), "timeout": 5]],
            ]
            if event == "SessionStart" { group["matcher"] = "startup|resume|clear|compact" }
            if ["PreToolUse", "PostToolUse", "PermissionRequest"].contains(event) { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try encoded(root)
    }

    static func uninstall(existing: Data?) throws -> Data {
        try encoded(uninstallObject(try decode(existing)))
    }
}
