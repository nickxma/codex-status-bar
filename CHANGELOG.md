# Changelog

## 0.2.0

- Added live Codex Desktop support through local lifecycle event watching.
- Replaced recursive session polling with filesystem events for faster startup and lower idle work.
- Added Claude-style rotating thinking words and independent timer controls.
- Added configurable completion sounds.
- Added the Claude spark menu-bar icon and app icon.
- Collapsed duplicate resting Desktop sessions by workspace.
- Removed the Codex pet picker, sprite renderer, configuration writes, animation timer, tests, and bundled pet atlas.
- Removed the temporary Desktop completion-notification bridge and all machine-specific paths.
- Changed the release bundle identifier to `com.nickxma.codexstatusbar`.

## 0.1.0

- Forked the original Claude Status Bar architecture for Codex.
- Added documented Codex lifecycle hook support for CLI and Desktop.
- Added explicit first-launch confirmation before hook installation.
- Added safe, idempotent `~/.codex/hooks.json` merging and backup.
- Replaced Node hook scripts with a universal native Swift helper.
- Replaced Claude artwork with the selected custom Codex pet atlas from `~/.codex/pets`, including idle, working, and waiting states.
- Added bounded `turn_aborted` event detection so Esc clears working state.
- Removed message parsing, upstream release checks, and external runtime dependencies.
