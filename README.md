# Codex Status Bar

A tiny native macOS menu-bar app that shows live Codex task state across Codex CLI and Codex Desktop.

It watches Codex Desktop's local lifecycle event stream and uses Codex's documented hooks for CLI sessions. Multiple sessions are aggregated so a permission request is never hidden behind ordinary work.

## What it shows

- A rotating Claude-style thinking word while Codex works (`Pondering…`, `Brewing…`, `Tinkering…`).
- The full elapsed time of the current turn, including thinking and tool use.
- A yellow indicator when Codex needs permission.
- Independent **Thinking words** and **Show timer** toggles.
- A configurable completion sound: every turn, or only turns longer than 1, 5, or 15 minutes.
- Session rows with project, surface, and state.

The app is local-only. It does not read message content, collect telemetry, use an API key, or require Node, npm, Bun, or another runtime. For Codex Desktop it watches file changes rather than repeatedly scanning the session tree, then inspects only lifecycle event names and session metadata.

## Build and install

Requirements: macOS 12+ and Xcode Command Line Tools.

```bash
./build.sh
open build/CodexStatusBar.app
```

For a DMG:

```bash
./build.sh --dmg
```

Builds are native to the current Mac by default. A release runner with full Xcode can produce a universal binary with `BUILD_ARCH=universal ./build.sh --dmg`.

Codex Desktop works automatically. On first launch, Codex Status Bar asks whether it may add CLI hooks to `~/.codex/hooks.json`. Existing hooks are preserved and the original file is backed up once.

CLI users should then open `/hooks` in Codex, review the eight Codex Status Bar commands, and trust them. Codex intentionally skips new hooks until their exact definitions are approved.

## Supported events

- `SessionStart`
- `UserPromptSubmit`
- `SubagentStart`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `SubagentStop`
- `Stop`

CLI sessions are removed when their Codex process exits. Desktop sessions are discovered from `~/.codex/sessions`, updated through filesystem events, and collapsed to the latest resting row per workspace.

## Uninstall hooks

Use **Reinstall Hooks…** to repair moved helper paths. Choose **Uninstall Hooks…** to remove only Codex Status Bar's marked commands while preserving every unrelated hook.

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
