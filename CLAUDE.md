# Baton

Swift 6.3 CLI (`baton`) — orchestrates AI code review across a monorepo. Each subtree
declares a `baton.toml`; the diff is routed to the deepest owning scope; per `(scope, review)`
an external coding CLI (claude/codex/gemini/opencode, plus a `custom` escape hatch) reviews
that slice; findings render locally or publish to a GitHub PR via `gh`.

## Modules (keep the boundaries)

- `BatonKit` — core domain logic. **No UI deps** (no ArgumentParser/Noora). Config/Scope/Git/
  Skill/Agent/Review/RunRecord. Shared GitHub payload formatting lives here (`GitHubPresentation`)
  so both BatonForge and BatonCLI reuse it.
- `BatonForge` — GitHub via the `gh` CLI (`GHRunning` is injected for testing). Depends on BatonKit.
- `BatonCLI` — `@main` executable, ArgumentParser commands, TerminalUI (Noora), rendering.
  Retroactive conformances like `AgentKind: ExpressibleByArgument` live here (no `@retroactive` —
  same package).

## Commands (via mise; build/test pipe through xcsift)

- `mise run build` / `mise run test` — debug build / full test suite.
- `mise run test:filter <Suite>` — e.g. `mise run test:filter BatonKitTests`.
- `mise run lint` — swiftlint --strict + actionlint. `mise run format` — swiftformat + dprint fmt.
- `mise run format-check` — CI formatting gate. swiftformat is via mise: `mise x swiftformat@0.60.1 -- swiftformat Sources Tests`.
- New mise config needs `mise trust` once.
- Manual e2e: `swift build -c release`, then `.build/release/baton doctor|config|review [name]`. `baton config` prints the effective per-scope config incl. resolved skills; `baton review` diffs the working tree vs HEAD, so an untracked file must be `git add`-ed to show up in the reviewed diff.

## Conventions

- Every domain error conforms to `BatonError` (LocalizedError + `recoverySuggestion`), rendered `✗ <desc>` / `→ <recovery>`.
- Tests use **swift-testing** (`import Testing`, `@Test`, `#expect`, `#require`). `#require` requires the test be `throws` + `try`.
- Use `FileManager.default` inline (not a `static let` — concurrency). Thread-safe helpers are `@unchecked Sendable` over `NSLock`; mocks accessed from async are `actor`s (`NSLock.lock()` is unavailable in async).
- JSON: use `JSONCodec` (BatonKit, YYJSON wrapper). DOM access for parsing varied agent output.
- Skills are vendored locally under `.claude/skills/<name>/` and wired via a local `[[skills]]` source. The resolver inlines every `*.md` under the skill dir (excluding the SKILL.md/README.md body) into the headless prompt under a per-skill byte budget: `[security].references_budget_kb`, default 1 MiB.

## Gotchas

- **swift-toml**: its `.convertFromSnakeCase` is broken for camelCase props — declare explicit snake_case `CodingKeys` instead.
- **TOML semantics**: top-level keys (e.g. `disabled_reviews`) must precede any `[table]`/`[[array]]` header or they bind to the last table.
- **mise tasks that pipe** need `#!/usr/bin/env bash` + `set -euo pipefail` (Linux runner uses dash; a bare `swift build | xcsift` returns xcsift's exit 0 and masks failures). xcsift has no Linux build, so build/test tasks fall back to plain `swift` when it is absent.
- **swiftlint --strict** rules hit here: `optional_data_string_conversion` (use `String(bytes:encoding:) ?? ""`, not `String(decoding:as:)`); `for_where`; `function_parameter_count` ≤5 (bundle into a request struct); `function_body_length` ≤60; `type_body_length` warning 300 (move methods to an extension file — extensions count separately); line length 120; `file_length` is 600 (test files run long).
- **swiftformat** removes `@Suite("name")` and rewrites closures to key-path shorthand — the latter can break the `#expect` macro; extract to a `let` first. `--ifdef no-indent` keeps `#if` bodies at column 0.

## Cross-platform (Windows is best-effort, but CI is green on all three)

- **Never hardcode `/usr/bin/env`** to launch a subprocess — it does not exist on Windows. Use `ProcessLauncher.configure(_:executable:arguments:)` (BatonKit), which keeps the POSIX `/usr/bin/env` path and resolves via `PATH`+`PATHEXT` on Windows. All process launchers (`ProcessExecutor`, `GitRunner`, `LiveGHRunner`, doctor's gh check) go through it.
- The package **compiles on Windows** — swift-toml (toml++/C++ interop) builds fine, so no `LebJe/TOMLKit` fallback is needed.
- Tests that spawn real subprocesses (git, `echo`/`cat`/`sleep`, a `/bin/sh` fixture), create symlinks, or assume POSIX `PATH`/`/bin/sh` are gated behind `#if !os(Windows)`. macOS/Linux run all 138 tests; Windows runs the platform-agnostic subset. The CI Windows job is `continue-on-error` but currently passes.

## Workflow

- Commit directly to `main`, granular Conventional Commits. Automated commits use `HK=0 git commit` (hooks validated separately).
- After a chunk: `swiftformat` → `swiftlint --strict` → `swift test` (through xcsift), commit, push, then `gh run watch <id>` to verify CI.
- Tooling/CI scaffolding is ported from the ExFig project at `/Users/aleksei/Developer/ExFig` — compare against it when CI/tooling misbehaves.
- Capabilities live in `openspec/specs/` (the MVP change is archived under `openspec/changes/archive/`). New work goes through a fresh OpenSpec change.
