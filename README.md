<p align="center">
  <img src="assets/AppIcon.png" width="128" alt="Codex Status Bar icon">
</p>

# Codex Status Bar

A tiny native macOS menu-bar app that shows live Codex Desktop task state.

It watches Codex Desktop's local lifecycle event stream. There is no setup, account, helper process, or hook configuration.

## What it shows

- A rotating Claude-style thinking word while Codex works (`Pondering…`, `Brewing…`, `Tinkering…`).
- The full elapsed time of the current turn, including thinking and tool use.
- A yellow indicator when Codex needs permission.
- Independent **Thinking words** and **Show timer** toggles.
- A completion sound after every turn by default, optionally limited to turns longer than 1, 5, or 15 minutes.
- Automatic launch at login, with an in-app toggle.
- Exact Codex task titles for every active or recently completed session.

The app is local-only. It does not read message content, collect telemetry, use an API key, or require Node, npm, Bun, or another runtime. For Codex Desktop it watches file changes rather than repeatedly scanning the session tree, then inspects only lifecycle event names and session metadata.

## Build and install

Requires macOS 13 or later.

### Install the app

1. Download the latest `CodexStatusBar.dmg` from [Releases](https://github.com/nickxma/codex-status-bar/releases/latest).
2. Drag **CodexStatusBar** into Applications.
3. Right-click the app and choose **Open** the first time. The current community build is not Apple-notarized, so a normal double-click may be blocked by Gatekeeper.

The app launches at login by default. Disable **Launch at login** from its menu at any time.

### Build from source

Building requires Xcode Command Line Tools.

```bash
./build.sh
open build/CodexStatusBar.app
```

For a DMG:

```bash
./build.sh --dmg
```

Builds are native to the current Mac by default. A release runner with full Xcode can produce a universal binary with `BUILD_ARCH=universal ./build.sh --dmg`.

Move the app to `/Applications` or `~/Applications`, then open it once. It enables **Launch at login** by default and remains as a lightweight menu-bar utility so it can notice Codex opening later.

## Session behavior

- A session appears when Codex records its first real `task_started` lifecycle event. Merely opening a conversation does not add a row.
- Every active task is shown, ordered by recent activity.
- After completion or cancellation, up to five of the most recently completed tasks remain visible for 15 minutes.
- Completed state files are removed after 15 minutes. Active states have a 12-hour safety timeout in case Codex exits without writing a terminal event.
- Row names come from Codex's local task-title index. The workspace folder name is used only when the task has no indexed title.

## Testing

```bash
scripts/test.sh
swiftc -typecheck Sources/*.swift -framework Cocoa
./build.sh
```

See [PRIVACY.md](PRIVACY.md), [TROUBLESHOOTING.md](TROUBLESHOOTING.md), and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT

## Trademark / not affiliated

This is an unofficial open-source project. It is not affiliated with, endorsed by, or sponsored by OpenAI or Anthropic. Codex and OpenAI are trademarks of OpenAI. Claude and the Claude spark logo are trademarks of Anthropic. The spark is used in the same nominative, noncommercial spirit as the upstream Claude Status Bar project; the MIT license does not grant trademark rights.
