# Troubleshooting

## Nothing changes while Codex works

Confirm that Codex Status Bar is running and that Codex Desktop has created local sessions under `~/.codex/sessions`. The app does not support Codex CLI and does not install hooks.

## The app does not start after login

Turn **Launch at login** off and on in the menu. macOS may also show the app under **System Settings → General → Login Items**.

## Desktop rows remain longer than expected

Every active task remains visible. Up to five completed tasks remain for 15 minutes, after which their local status files are removed.

## Debug state

Per-session status lives in `~/.codex/statusbar/state.d`. These files contain metadata only and can be removed safely while Codex is idle.
