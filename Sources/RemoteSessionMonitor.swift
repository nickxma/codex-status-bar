import Foundation

/// Mirrors lifecycle-only state from Codex Desktop's configured SSH projects.
///
/// Codex runs remote SSH threads on the remote host, so their rollout files never appear in this
/// Mac's ~/.codex/sessions directory. This monitor reads the host aliases Codex already stores in
/// .codex-global-state.json, then uses non-interactive SSH to inspect only session metadata and
/// task lifecycle event names. It never reads prompt or response bodies and never starts another
/// Codex app-server.
final class RemoteSessionMonitor {
    struct Host: Equatable {
        let id: String
        let alias: String
        let label: String
    }

    typealias SnapshotProvider = (_ host: Host) -> Data?

    private let remoteHostsURL: URL
    private var remoteHostsModifiedAt: Date?
    private let globalStateURL: URL
    private let stateRoot: URL
    private let customSnapshotProvider: SnapshotProvider?
    private let queue = DispatchQueue(label: "com.nickxma.codexstatusbar.remote-monitor", qos: .utility)
    private let lock = NSLock()
    private var nextPoll: TimeInterval = 0
    private var pollInFlight = false
    private var retryAfter: [String: TimeInterval] = [:]
    private var activeProcesses: [pid_t: Process] = [:]
    private var cachedConfiguration = Configuration(hosts: [], assignments: [:])
    private var configurationModifiedAt: Date?
    private var configurationSize: UInt64?
    private let pollInterval: TimeInterval
    private let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoBasic = ISO8601DateFormatter()

    init(
        globalStateURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json"),
        remoteHostsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/statusbar/remote-hosts.json"),
        stateRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/statusbar/state.d", isDirectory: true),
        pollInterval: TimeInterval = 5,
        snapshotProvider: SnapshotProvider? = nil
    ) {
        self.remoteHostsURL = remoteHostsURL
        self.globalStateURL = globalStateURL
        self.stateRoot = stateRoot
        self.pollInterval = pollInterval
        self.customSnapshotProvider = snapshotProvider
    }

    func poll(enabled: Bool, now: TimeInterval = Date().timeIntervalSince1970) {
        guard enabled else { return }
        lock.lock()
        guard !pollInFlight, now >= nextPoll else {
            lock.unlock()
            return
        }
        pollInFlight = true
        nextPoll = now + pollInterval
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.pollInFlight = false
                self.lock.unlock()
            }
            let configuration = self.loadConfiguration()
            for host in configuration.hosts {
                let assignedThreadIDs = configuration.assignments[host.id] ?? []
                guard now >= self.retryAfter[host.id, default: 0] else { continue }
                let snapshot: Data?
                if let provider = self.customSnapshotProvider {
                    snapshot = provider(host)
                } else {
                    snapshot = self.fetchSnapshot(host: host)
                }
                guard let data = snapshot else {
                    // A 1Password-backed SSH agent may require physical approval. Do not create
                    // recurring approval prompts: after one bounded failure, leave this host alone
                    // until the status app is relaunched.
                    self.retryAfter[host.id] = .greatestFiniteMagnitude
                    continue
                }
                self.retryAfter[host.id] = nil
                self.applySnapshot(data, host: host, assignedThreadIDs: assignedThreadIDs)
            }
        }
    }

    func stop() {
        lock.lock()
        let processes = Array(activeProcesses.values)
        activeProcesses.removeAll()
        lock.unlock()
        for process in processes where process.isRunning { process.terminate() }
    }

    private struct Configuration {
        var hosts: [Host]
        var assignments: [String: Set<String>]
    }

    private func loadConfiguration() -> Configuration {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: globalStateURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            cachedConfiguration = Configuration(hosts: [], assignments: [:])
            configurationModifiedAt = nil
            configurationSize = nil
            return cachedConfiguration
        }
        let mappingDate = (try? FileManager.default.attributesOfItem(atPath: remoteHostsURL.path))?[.modificationDate] as? Date
        if configurationModifiedAt == modifiedAt, configurationSize == size, remoteHostsModifiedAt == mappingDate {
            return cachedConfiguration
        }
        guard let data = try? Data(contentsOf: globalStateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return cachedConfiguration
        }

        var hosts: [Host] = []
        if let rows = root["codex-managed-remote-connections"] as? [[String: Any]] {
            for row in rows {
                guard let id = row["hostId"] as? String,
                      id.hasPrefix("remote-ssh-"),
                      let alias = row["alias"] as? String, !alias.isEmpty else { continue }
                let label = (row["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? alias
                hosts.append(Host(id: id, alias: alias, label: label))
            }
        }

        // Remote Control carries Codex status, but Claude hook files need an SSH route.
        // Accept explicit mappings only for hosts already configured in Codex.
        let configuredIDs = Set((root["remote-projects"] as? [[String: Any]] ?? []).compactMap { $0["hostId"] as? String })
            .union(hosts.map(\.id))
        if let data = try? Data(contentsOf: remoteHostsURL),
           let mappings = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            for mapping in mappings {
                guard let id = mapping["hostId"], configuredIDs.contains(id),
                      let alias = mapping["alias"], !alias.isEmpty, !alias.hasPrefix("-"),
                      alias.allSatisfy({ $0.isLetter || $0.isNumber || "._-@".contains($0) }),
                      !hosts.contains(where: { $0.id == id || $0.alias == alias }) else { continue }
                hosts.append(Host(id: id, alias: alias, label: mapping["label"] ?? alias))
            }
        }
        remoteHostsModifiedAt = mappingDate

        var assignments: [String: Set<String>] = [:]
        if let rows = root["thread-project-assignments"] as? [String: Any] {
            for (threadID, value) in rows {
                guard let row = value as? [String: Any],
                      row["projectKind"] as? String == "remote",
                      let hostID = row["hostId"] as? String else { continue }
                assignments[hostID, default: []].insert(threadID)
            }
        }
        cachedConfiguration = Configuration(hosts: hosts, assignments: assignments)
        configurationModifiedAt = modifiedAt
        configurationSize = size
        return cachedConfiguration
    }

    private func fetchSnapshot(host: Host) -> Data? {
        let fm = FileManager.default
        let controlRoot = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/statusbar/ssh", isDirectory: true)
        try? fm.createDirectory(at: controlRoot, withIntermediateDirectories: true)
        let controlPath = controlRoot.appendingPathComponent("%C").path
        let command = #"root="${CODEX_HOME:-$HOME/.codex}"; printf '__CODEX_STATUS_INDEX__\n'; tail -n 2000 "$root/session_index.jsonl" 2>/dev/null || true; printf '__CODEX_STATUS_SESSIONS__\n'; find "$root/sessions" -type f -name 'rollout-*.jsonl' -mmin -35 -print 2>/dev/null | while IFS= read -r f; do printf '__CODEX_STATUS_FILE__%s\n' "$f"; grep -E '"type":"session_meta"|"type":"(task_started|task_complete|task_cancelled|turn_aborted)"' "$f" 2>/dev/null | tail -n 24; done; printf '__CLAUDE_STATUS_STATES__\n'; find "$HOME/.claude/statusbar/state.d" -type f -name '*.json' -mmin -35 -exec cat {} \; -exec printf '\n' \; 2>/dev/null || true"#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        let quotedCommand = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
        process.arguments = [
            "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=4",
            "-o", "ConnectionAttempts=1", "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=1", "-o", "ControlMaster=auto",
            "-o", "ControlPersist=60", "-o", "ControlPath=\(controlPath)",
            host.alias, "sh -c \(quotedCommand)",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            lock.lock()
            activeProcesses[process.processIdentifier] = process
            lock.unlock()
            defer {
                lock.lock()
                activeProcesses[process.processIdentifier] = nil
                lock.unlock()
            }
            let completed = DispatchSemaphore(value: 0)
            let reader = DispatchGroup()
            let resultLock = NSLock()
            var result = Data()
            reader.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                resultLock.lock()
                result = data
                resultLock.unlock()
                reader.leave()
            }
            process.terminationHandler = { _ in completed.signal() }
            guard completed.wait(timeout: .now() + 10) == .success else {
                process.terminate()
                if completed.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                _ = completed.wait(timeout: .now() + 1)
                reader.wait()
                return nil
            }
            reader.wait()
            resultLock.lock()
            let data = result
            resultLock.unlock()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }

    private struct Cursor {
        var id = ""
        var cwd = ""
        var threadSource = ""
        var state: [String: Any] = [:]
    }

    private func applySnapshot(_ data: Data, host: Host, assignedThreadIDs: Set<String>) {
        let text = String(decoding: data, as: UTF8.self)
        var titles: [String: String] = [:]
        var cursor: Cursor?
        var readingClaude = false
        var seenClaudeIDs = Set<String>()

        func finish(_ candidate: Cursor?) {
            guard let candidate, !candidate.id.isEmpty, !candidate.state.isEmpty,
                  assignedThreadIDs.contains(candidate.id) else { return }
            write(candidate.state, sessionID: candidate.id)
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line == "__CLAUDE_STATUS_STATES__" {
                finish(cursor); cursor = nil; readingClaude = true
                continue
            }
            if readingClaude {
                if let object = parse(line), let id = mirrorClaudeState(object, host: host) {
                    seenClaudeIDs.insert(id)
                }
                continue
            }
            if line == "__CODEX_STATUS_INDEX__" || line == "__CODEX_STATUS_SESSIONS__" { continue }
            if line.hasPrefix("__CODEX_STATUS_FILE__") {
                finish(cursor)
                let path = String(line.dropFirst("__CODEX_STATUS_FILE__".count))
                cursor = Cursor(id: sessionID(from: path))
                continue
            }
            guard let object = parse(line) else { continue }
            if cursor == nil {
                if let id = object["id"] as? String,
                   let title = object["thread_name"] as? String,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    titles[id] = title
                }
                continue
            }
            guard var current = cursor, let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else { continue }
            if type == "session_meta" {
                current.id = payload["id"] as? String ?? current.id
                current.cwd = payload["cwd"] as? String ?? current.cwd
                current.threadSource = payload["thread_source"] as? String ?? current.threadSource
                cursor = current
                continue
            }
            guard type == "event_msg", let event = payload["type"] as? String else { continue }
            let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp)
                ?? Date().timeIntervalSince1970
            let fallback = remoteDisplayName(host: host, cwd: current.cwd)
            let project = titles[current.id] ?? fallback
            switch event {
            case "task_started":
                current.state = makeState(current, host: host, state: "thinking", label: "Thinking…",
                                          project: project, timestamp: timestamp, startedAt: timestamp,
                                          turnID: payload["turn_id"] as? String ?? "")
            case "task_complete":
                current.state = makeState(current, host: host, state: "done", label: "Done",
                                          project: project, timestamp: timestamp, startedAt: 0,
                                          turnID: payload["turn_id"] as? String ?? "")
            case "task_cancelled", "turn_aborted":
                current.state = makeState(current, host: host, state: "idle", label: "",
                                          project: project, timestamp: timestamp, startedAt: 0,
                                          turnID: payload["turn_id"] as? String ?? "")
            default: break
            }
            cursor = current
        }
        finish(cursor)
        // Only a successful complete snapshot can remove vanished remote hook files.
        if readingClaude {
            let prefix = claudeStatePrefix(host)
            for file in (try? FileManager.default.contentsOfDirectory(atPath: stateRoot.path)) ?? []
                where file.hasPrefix(prefix) && file.hasSuffix(".json") {
                let id = String(file.dropLast(5))
                if !seenClaudeIDs.contains(id) {
                    try? FileManager.default.removeItem(at: stateRoot.appendingPathComponent(file))
                }
            }
        }
    }

    private func claudeStatePrefix(_ host: Host) -> String {
        // Encode instead of replacing punctuation to avoid collisions between hosts.
        "remote-claude-" + host.id.utf8.map { String(format: "%02x", $0) }.joined() + "-"
    }

    private func mirrorClaudeState(_ object: [String: Any], host: Host) -> String? {
        guard let session = object["sessionId"] as? String, !session.isEmpty,
              let state = object["state"] as? String,
              ["thinking", "tool", "subagent", "permission", "done", "idle"].contains(state),
              let timestamp = object["ts"] as? Double,
              timestamp <= Date().timeIntervalSince1970 + 60,
              Date().timeIntervalSince1970 - timestamp <= StatusPolicy.activeInactivityTimeout else { return nil }
        let id = claudeStatePrefix(host) + session.utf8.map { String(format: "%02x", $0) }.joined()
        let project = object["project"] as? String ?? "Claude Code"
        let payload: [String: Any] = [
            "sessionId": id, "state": state, "label": object["label"] as? String ?? "",
            "project": "\(host.label) · \(project)", "remoteHost": host.label,
            "cwd": object["cwd"] as? String ?? "", "entrypoint": "cli",
            "term_program": "", "pid": 0, "started": true,
            "startedAt": object["startedAt"] as? Double ?? 0, "ts": timestamp,
        ]
        write(payload, sessionID: id)
        return id
    }

    private func makeState(_ cursor: Cursor, host: Host, state: String, label: String,
                           project: String, timestamp: Double, startedAt: Double,
                           turnID: String) -> [String: Any] {
        [
            "state": state, "label": label, "project": project,
            "indexedTitle": project != remoteDisplayName(host: host, cwd: cursor.cwd),
            "threadSource": cursor.threadSource, "cwd": cursor.cwd,
            "sessionId": cursor.id, "turnId": turnID, "remoteHost": host.label,
            "transcript": "", "surface": "codex-desktop", "term_program": "",
            "pid": 0, "started": true, "startedAt": startedAt, "ts": timestamp,
            "activeAgents": [String](), "tool": "",
        ]
    }

    private func remoteDisplayName(host: Host, cwd: String) -> String {
        let folder = cwd.isEmpty ? "Codex" : URL(fileURLWithPath: cwd).lastPathComponent
        return folder.isEmpty || folder == host.label ? host.label : "\(host.label) · \(folder)"
    }

    private func sessionID(from path: String) -> String {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "-")
        guard parts.count >= 6 else { return stem }
        return parts.suffix(5).joined(separator: "-")
    }

    private func write(_ state: [String: Any], sessionID: String) {
        try? FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)
        let safeID = sessionID.map { $0.isLetter || $0.isNumber || "._-".contains($0) ? $0 : "_" }
        let url = stateRoot.appendingPathComponent(String(safeID) + ".json")
        CodexStateStore.write(state, to: url)
    }

    private func parse(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseTimestamp(_ value: String) -> TimeInterval? {
        (isoFractional.date(from: value) ?? isoBasic.date(from: value))?.timeIntervalSince1970
    }
}
