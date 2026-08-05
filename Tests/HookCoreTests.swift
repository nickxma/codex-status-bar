import Foundation

@main
struct HookCoreTests {
    static var failures = 0
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { failures += 1; fputs("FAIL: \(message)\n", stderr) }
    }

    static func main() throws {
        let base: [String: Any] = [
            "session_id": "thread/../../unsafe",
            "cwd": "/tmp/project",
            "model": "gpt-5",
            "turn_id": "turn-1",
            "transcript_path": "/tmp/session.jsonl",
        ]
        let now = 1_750_000_000.0
        let prompt = HookEventMapper.update(payload: base, event: "UserPromptSubmit", previous: nil, pid: 42, now: now)
        expect(prompt?["state"] as? String == "thinking", "prompt starts thinking")
        expect(prompt?["startedAt"] as? Double == now, "prompt starts timer")
        expect(prompt?["sessionId"] as? String == "thread/../../unsafe", "raw session id remains metadata")
        expect(prompt?["transcript"] as? String == "/tmp/session.jsonl", "session event path is retained")
        expect(HookEventMapper.safeID("thread/../../unsafe") == "thread....unsafe", "unsafe filename characters are removed")

        var toolPayload = base
        toolPayload["tool_name"] = "apply_patch"
        let tool = HookEventMapper.update(payload: toolPayload, event: "PreToolUse", previous: prompt, pid: 42, now: now + 1)
        expect(tool?["state"] as? String == "tool", "pre-tool starts tool state")
        expect(tool?["label"] as? String == "Editing", "apply_patch gets editing label")
        expect(tool?["startedAt"] as? Double == now, "tool preserves turn timer")

        let post = HookEventMapper.update(payload: base, event: "PostToolUse", previous: tool, pid: 42, now: now + 2)
        expect(post?["state"] as? String == "thinking", "post-tool resumes thinking")
        let permission = HookEventMapper.update(payload: toolPayload, event: "PermissionRequest", previous: post, pid: 42, now: now + 3)
        expect(permission?["state"] as? String == "permission", "permission request waits")
        expect(permission?["startedAt"] as? Double == 0, "permission clears timer")
        let stop = HookEventMapper.update(payload: base, event: "Stop", previous: permission, pid: 42, now: now + 4)
        expect(stop?["state"] as? String == "done", "stop completes turn")
        expect(HookEventMapper.update(payload: base, event: "Unknown", previous: nil, pid: 1, now: now) == nil, "unknown event is ignored")

        expect(StatusPolicy.effectiveState(rawState: "done", age: 0.50) == "done", "completion remains visible during jump")
        expect(StatusPolicy.effectiveState(rawState: "done", age: 0.84) == "idle", "completion expires after jump")
        expect(StatusPolicy.effectiveState(rawState: "thinking", age: 30) == "thinking", "non-completion state remains unchanged")
        expect(StatusPolicy.displayLabel(state: "thinking", storedLabel: "Thinking…") == "Thinking…", "thinking label stays plain")
        expect(StatusPolicy.displayLabel(state: "tool", storedLabel: "Running command") == "Running command", "tool action label is preserved")
        expect(StatusPolicy.displayLabel(state: "tool", storedLabel: "") == "Working…", "missing tool label gets normal fallback")

        var commandPayload = base
        commandPayload["tool_name"] = "exec_command"
        let firstCommand = HookEventMapper.update(payload: commandPayload, event: "PreToolUse", previous: post, pid: 42, now: now + 5)
        expect(firstCommand?["label"] as? String == "Running command", "command keeps its action label")

        var firstAgentPayload = base
        firstAgentPayload["agent_id"] = "agent-one"
        firstAgentPayload["agent_type"] = "explorer"
        let firstAgent = HookEventMapper.update(payload: firstAgentPayload, event: "SubagentStart", previous: prompt, pid: 42, now: now + 8)
        expect(firstAgent?["state"] as? String == "subagent", "subagent start enters agent state")
        expect(firstAgent?["label"] as? String == "Herding an agent…", "one agent gets funny singular copy")
        expect(firstAgent?["activeAgents"] as? [String] == ["agent-one"], "first active agent is persisted")

        var secondAgentPayload = base
        secondAgentPayload["agent_id"] = "agent-two"
        secondAgentPayload["agent_type"] = "reviewer"
        let secondAgent = HookEventMapper.update(payload: secondAgentPayload, event: "SubagentStart", previous: firstAgent, pid: 42, now: now + 9)
        expect(secondAgent?["label"] as? String == "Herding 2 agents…", "multiple agents show their count")

        let oneAgentStopped = HookEventMapper.update(payload: firstAgentPayload, event: "SubagentStop", previous: secondAgent, pid: 42, now: now + 10)
        expect(oneAgentStopped?["state"] as? String == "subagent", "remaining agent keeps agent state")
        expect(oneAgentStopped?["label"] as? String == "Herding an agent…", "remaining agent restores singular copy")
        expect(oneAgentStopped?["activeAgents"] as? [String] == ["agent-two"], "stopped agent is removed")
        let allAgentsStopped = HookEventMapper.update(payload: secondAgentPayload, event: "SubagentStop", previous: oneAgentStopped, pid: 42, now: now + 11)
        expect(allAgentsStopped?["state"] as? String == "thinking", "last agent stop resumes parent thinking")
        expect(allAgentsStopped?["label"] as? String == "Thinking…", "last agent stop restores normal copy")
        expect(allAgentsStopped?["activeAgents"] as? [String] == [], "last active agent is removed")
        expect(StatusPolicy.priority(of: "subagent") > StatusPolicy.priority(of: "idle"), "agent work outranks idle")
        expect(StatusPolicy.isWorking("subagent"), "subagent state renders as active work")
        expect(!StatusPolicy.isWorking("idle"), "idle state does not render as active work")
        expect(HookConfiguration.events.contains("SubagentStart"), "subagent start hook is installed")
        expect(HookConfiguration.events.contains("SubagentStop"), "subagent stop hook is installed")

        let existing = Data("""
        {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"keep-me"}]}]}}
        """.utf8)
        let installed = try HookConfiguration.install(existing: existing, helperPath: "/Applications/CodexStatusBar.app/Contents/Resources/CodexStatusHook")
        let installedAgain = try HookConfiguration.install(existing: installed, helperPath: "/Applications/CodexStatusBar.app/Contents/Resources/CodexStatusHook")
        let root = try JSONSerialization.jsonObject(with: installedAgain) as! [String: Any]
        let hooks = root["hooks"] as! [String: Any]
        let pre = hooks["PreToolUse"] as! [[String: Any]]
        let commands = pre.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        expect(commands.contains("keep-me"), "install preserves unrelated hooks")
        expect(commands.filter { $0.contains(HookConfiguration.marker) }.count == 1, "reinstall is idempotent")
        expect((hooks["SubagentStart"] as? [[String: Any]])?.count == 1, "subagent start hook installs once")
        expect((hooks["SubagentStop"] as? [[String: Any]])?.count == 1, "subagent stop hook installs once")
        let removed = try HookConfiguration.uninstall(existing: installedAgain)
        let removedText = String(decoding: removed, as: UTF8.self)
        expect(removedText.contains("keep-me"), "uninstall preserves unrelated hook")
        expect(!removedText.contains(HookConfiguration.marker), "uninstall removes marked hooks")

        do {
            _ = try HookConfiguration.install(existing: Data("not json".utf8), helperPath: "/tmp/helper")
            expect(false, "invalid JSON must fail")
        } catch { expect(true, "invalid JSON fails") }

        expect(StatusPolicy.priority(of: "permission") > StatusPolicy.priority(of: "tool"), "permission outranks work")
        expect(StatusPolicy.priority(of: "thinking") > StatusPolicy.priority(of: "idle"), "work outranks idle")
        expect(StatusPolicy.versionIsNewer("0.1.10", than: "0.1.9"), "version comparison is numeric")
        let transcript = Data("""
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-1","reason":"interrupted"}}
        """.utf8)
        expect(StatusPolicy.turnWasAborted(in: transcript, turnID: "turn-1"), "current turn abort is detected")
        expect(!StatusPolicy.turnWasAborted(in: transcript, turnID: "turn-2"), "old turn abort is ignored")

        if failures > 0 { exit(1) }
        print("HookCoreTests: \(assertions) passed")
    }
}
