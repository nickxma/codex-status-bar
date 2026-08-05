# Contributing

Keep Codex Status Bar small, local, native, and dependency-free.

Welcome changes include correctness fixes, Codex Desktop lifecycle compatibility, performance improvements, accessibility, and restrained visual polish.

Out of scope: Codex CLI hooks, message-content parsing, usage or cost dashboards, telemetry, API calls, and unrelated agent providers.

Before submitting a change, run:

```bash
scripts/test.sh
swiftc -typecheck Sources/*.swift -framework Cocoa
bash -n build.sh
./build.sh
```

Test behavioral changes in Codex Desktop. Use Conventional Commit prefixes such as `feat`, `fix`, `test`, `docs`, and `chore`.
