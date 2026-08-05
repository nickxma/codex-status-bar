# Codex Status Bar

A tiny native macOS menu-bar app that shows live Codex Desktop task state.

It watches Codex Desktop's local lifecycle event stream. There is no setup, account, helper process, or hook configuration.

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

Open the app while Codex Desktop is running. Sessions are discovered from `~/.codex/sessions`, updated through filesystem events, and collapsed to the latest resting row per workspace.

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
