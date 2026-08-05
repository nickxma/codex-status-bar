# Privacy

Codex Status Bar runs locally and collects no telemetry.

For Codex Desktop, the app watches recently active JSONL files under `~/.codex/sessions` and task names in `~/.codex/session_index.jsonl`. It parses only task titles, session metadata, and structured lifecycle envelopes such as `task_started`, tool-call type, `task_complete`, `task_cancelled`, and `turn_aborted`. It does not access user or assistant message bodies. Filesystem events wake the monitor when a session changes; it does not continuously rescan or upload the session tree.

The app makes no network requests and does not modify Codex configuration. When **Launch at login** is enabled, it registers itself using macOS's native login-item service.
