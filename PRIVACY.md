# Privacy

Codex Status Bar runs locally and collects no telemetry.

The CLI hook helper receives Codex's documented hook metadata and stores status, timestamps, project directory, model identifier, tool name, surface, process identifiers, active subagent identifiers, current turn ID, and session-file path under `~/.codex/statusbar/state.d`.

For Codex Desktop, the app watches recently active JSONL files under `~/.codex/sessions`. It parses only session metadata and structured lifecycle envelopes such as `task_started`, tool-call type, `task_complete`, `task_cancelled`, and `turn_aborted`. It does not access user or assistant message bodies. Filesystem events wake the monitor when a session changes; it does not continuously rescan or upload the session tree.

The app makes no network requests. It modifies `~/.codex/hooks.json` only after explicit confirmation and creates at most one backup named `hooks.json.bak-codex-statusbar`.
