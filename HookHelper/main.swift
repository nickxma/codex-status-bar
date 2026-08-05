import Foundation
import Darwin

let environment = ProcessInfo.processInfo.environment
let home = environment["CODEX_STATUSBAR_HOME"] ?? NSHomeDirectory()
let stateDirectory = URL(fileURLWithPath: home)
    .appendingPathComponent(".codex/statusbar/state.d", isDirectory: true)
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }
let event = CommandLine.arguments.dropFirst().first ?? payload["hook_event_name"] as? String ?? ""
let sessionID = payload["session_id"] as? String ?? "unknown"
let stateURL = stateDirectory.appendingPathComponent(HookEventMapper.safeID(sessionID) + ".json")
try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
let lockURL = stateDirectory.appendingPathComponent(".\(HookEventMapper.safeID(sessionID)).lock")
let lockDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
if lockDescriptor >= 0 { _ = flock(lockDescriptor, LOCK_EX) }

let previous: [String: Any]? = FileManager.default.contents(atPath: stateURL.path)
    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

var enriched = payload
enriched["term_program"] = environment["TERM_PROGRAM"] ?? previous?["term_program"] ?? ""
if enriched["surface"] == nil {
    var pathBuffer = [CChar](repeating: 0, count: 4096)
    let pathLength = proc_pidpath(getppid(), &pathBuffer, UInt32(pathBuffer.count))
    let parentPath = pathLength > 0 ? String(cString: pathBuffer) : ""
    let inferred = parentPath.contains("/Applications/ChatGPT.app/") ? "codex-desktop" : "cli"
    enriched["surface"] = environment["CODEX_STATUSBAR_SURFACE"] ?? inferred
}

guard let state = HookEventMapper.update(
    payload: enriched,
    event: event,
    previous: previous,
    pid: environment["CODEX_STATUSBAR_HOST_PID"].flatMap(Int32.init) ?? getppid(),
    now: Date().timeIntervalSince1970
) else { exit(0) }

do {
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    let temporary = stateDirectory.appendingPathComponent(".\(HookEventMapper.safeID(sessionID)).\(getpid()).tmp")
    try data.write(to: temporary, options: .atomic)
    _ = try FileManager.default.replaceItemAt(stateURL, withItemAt: temporary)
} catch {
    do {
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        let temporary = stateDirectory.appendingPathComponent(".\(HookEventMapper.safeID(sessionID)).\(getpid()).tmp")
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.moveItem(at: temporary, to: stateURL)
    } catch { }
}

if lockDescriptor >= 0 {
    _ = flock(lockDescriptor, LOCK_UN)
    _ = Darwin.close(lockDescriptor)
}

if event == "SessionStart", environment["CODEX_STATUSBAR_NO_LAUNCH"] != "1" {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-g", "-b", "com.nickxma.codexstatusbar"]
    try? task.run()
}

if event == "SubagentStop" || event == "Stop" { print("{}") }
