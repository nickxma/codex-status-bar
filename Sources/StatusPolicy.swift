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
}
