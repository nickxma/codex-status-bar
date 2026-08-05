# Changelog

## 0.4.1

- Split the vague Sessions list into clear **Active tasks** and **Recently completed** sections.
- Show **Open Codex** under a simple Codex heading when there is no task history to display.

## 0.4.0

- Added native launch-at-login support, enabled by default with an in-app toggle.
- Made completion sound after every turn the explicit first-run default.
- Defined deterministic session behavior: all active tasks plus the five most recent completed tasks for 15 minutes.
- Removed the self-quit behavior so the login utility can detect Codex opening later.
- Added a 12-hour active-state safety timeout for missed terminal events.
- Fixed fractional lifecycle timestamps so relaunching cannot make old completed tasks look new.
- Filtered internal, CLI, automation, and untitled helper sessions from the user-task list.
- Updated installation, troubleshooting, privacy, and contribution documentation for the Desktop-only app.

## 0.3.1

- Display the exact Codex task title from the local session index.
- Propagate task-title renames through filesystem events.
- Keep the workspace folder name only as a fallback when no title is available.

## 0.3.0

- Simplified the app to zero-setup Codex Desktop support only.
- Removed CLI hooks, the bundled hook helper, hook setup UI, and hook configuration entirely.
- Removed redundant APP badges and their rendering code.

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
