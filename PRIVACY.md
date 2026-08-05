# Privacy

Codex Status Bar runs locally and collects no telemetry.

For Codex Desktop, the app watches recently active JSONL files under `~/.codex/sessions`. It parses only session metadata and structured lifecycle envelopes such as `task_started`, tool-call type, `task_complete`, `task_cancelled`, and `turn_aborted`. It does not access user or assistant message bodies. Filesystem events wake the monitor when a session changes; it does not continuously rescan or upload the session tree.

The app makes no network requests and does not modify Codex configuration.
