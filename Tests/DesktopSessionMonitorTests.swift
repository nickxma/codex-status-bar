import Foundation

@main
struct DesktopSessionMonitorTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("codex-status-monitor-\(UUID().uuidString)")
        let sessions = root.appendingPathComponent("sessions")
        let states = root.appendingPathComponent("states")
        let titleIndex = root.appendingPathComponent("session_index.jsonl")
        defer { try? fm.removeItem(at: root) }

        let now = Date()
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: now)
        let day = sessions
            .appendingPathComponent(String(format: "%04d", parts.year!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.month!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.day!), isDirectory: true)
        try fm.createDirectory(at: day, withIntermediateDirectories: true)

        let sessionID = "desktop-monitor-test"
        try Data("{\"id\":\"\(sessionID)\",\"thread_name\":\"Trace Will the Real X\"}\n".utf8).write(to: titleIndex)
        let log = day.appendingPathComponent("rollout-test-\(sessionID).jsonl")
        let initial = """
        {"timestamp":"2026-08-05T12:00:00.123Z","type":"session_meta","payload":{"id":"\(sessionID)","cwd":"/tmp/example","thread_source":"user"}}
        {"timestamp":"2026-08-05T12:00:01Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"old-turn"}}

        """
        try Data(initial.utf8).write(to: log)

        let monitor = DesktopSessionMonitor(
            sessionsRoot: sessions, stateRoot: states, titleIndexURL: titleIndex, pidProvider: { 4242 }
        )
        monitor.poll(now: now.timeIntervalSince1970)
        let state = states.appendingPathComponent(sessionID + ".json")
        let discoveryDeadline = Date().addingTimeInterval(0.75)
        while Date() < discoveryDeadline, readState(state)?["state"] as? String != "done" {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard readState(state)?["state"] as? String == "done" else {
            fatalError("initial Desktop state was not discovered")
        }
        guard readState(state)?["project"] as? String == "Trace Will the Real X" else {
            fatalError("Codex thread title was not used")
        }
        guard readState(state)?["indexedTitle"] as? Bool == true,
              readState(state)?["threadSource"] as? String == "user" else {
            fatalError("user-thread metadata was not preserved")
        }

        let started = Date()
        let event = "{\"timestamp\":\"2026-08-05T12:00:02.456Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"new-turn\"}}\n"
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(event.utf8))
        try handle.close()

        let deadline = Date().addingTimeInterval(0.75)
        while Date() < deadline, readState(state)?["state"] as? String != "thinking" {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let result = readState(state), result["state"] as? String == "thinking" else {
            fatalError("filesystem event did not surface task_started within 750 ms")
        }
        let expectedFormatter = ISO8601DateFormatter()
        expectedFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedTimestamp = expectedFormatter.date(from: "2026-08-05T12:00:02.456Z")!.timeIntervalSince1970
        guard abs((result["ts"] as? Double ?? 0) - expectedTimestamp) < 0.01 else {
            fatalError("fractional lifecycle timestamps were not parsed")
        }
        guard result["pid"] as? Int == 4242 else { fatalError("Desktop host PID was not preserved") }
        guard StatusPolicy.recentSessionRetention == 900 else { fatalError("recent-session retention changed") }
        guard StatusPolicy.maximumRecentSessions == 5 else { fatalError("recent-session cap changed") }
        let renamed = "{\"id\":\"\(sessionID)\",\"thread_name\":\"Renamed Thread\"}\n"
        try Data(renamed.utf8).write(to: titleIndex)
        let renameDeadline = Date().addingTimeInterval(0.75)
        while Date() < renameDeadline, readState(state)?["project"] as? String != "Renamed Thread" {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard readState(state)?["project"] as? String == "Renamed Thread" else {
            fatalError("thread rename was not propagated within 750 ms")
        }
        let latency = Date().timeIntervalSince(started)
        print(String(format: "DesktopSessionMonitorTests: event latency %.0f ms", latency * 1_000))
    }

    private static func readState(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
