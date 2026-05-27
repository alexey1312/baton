# Project Context

## Purpose

Baton is a Swift CLI that orchestrates AI code review across a monorepo. It discovers a per-scope
`baton.toml` in each subtree, routes the diff of a pull request to the deepest owning scope, runs
already-installed coding CLIs (claude / codex / gemini / opencode) concurrently per `(scope, review)`,
parses structured findings, and publishes them to GitHub pull requests as resolvable review comments
and Check Runs.

It is a Swift reimagining of [tuist/blick](https://github.com/tuist/blick) (Rust), keeping blick's
core idea — decentralized, cascading review configuration for monorepos — while improving on its
limitations.

The tool is a **conductor's baton**: it does not contain an LLM. It directs an *ensemble* of external
agents across the *sections* (scopes) of a monorepo and aggregates their findings onto one PR.

## Tech Stack

- Swift 6.3 with Swift Package Manager (strict concurrency)
- swift-argument-parser — CLI command tree
- swift-log — logging (routed through terminal UI)
- Noora (Tuist) — interactive terminal UI, prompts, progress
- mattt/swift-toml — `baton.toml` parsing (Codable, toml++)
- swift-yyjson — JSON parsing of agent output and run records
- swift-jinja — prompt and report templates
- `gh` CLI — GitHub integration (reviews, Check Runs, thread resolution)
- `git` — diff collection and base resolution
- swift-docc-plugin — DocC documentation (deployed to GitHub Pages)

### Tooling & Distribution (ported from ExFig)

- `mise` — pinned toolchain + tasks; `hk` — git hooks (pre-commit lint/format, conventional commits)
- SwiftLint / SwiftFormat / dprint / actionlint — linting & formatting; `git-cliff` — changelog
- CI: build/test/lint on macOS + Linux (Windows best-effort) via GitHub Actions, output through `xcsift`
- Distribution: GitHub Releases (macOS universal + Linux binaries) → `mise` (github backend) and
  Homebrew tap `alexey1312/homebrew-tap` (`brew install alexey1312/tap/baton`)

## Project Conventions

### Code Style

- Enforced by SwiftLint; format via `mise run format`
- Module layout: pure core (`BatonKit`) with no UI dependencies; UI/orchestration in `BatonCLI`;
  GitHub integration isolated in `BatonForge`

### Architecture Patterns

- Core modules under `BatonKit`: `Config`, `Scope`, `Git`, `Skill`, `Agent`, `Review`, `RunRecord`
- `BatonForge` — GitHub integration via `gh` CLI, isolated behind a `Forge` protocol
- `BatonCLI` — executable `baton`; commands `init`, `review`, `config`, `render`, `publish`, `doctor`
- Concurrency: actor-based orchestrator with sliding-window parallelism (ported from ExFig's
  `BatchExecutor` + `parallelMapEntries`)
- Subprocess execution centralized in one `ProcessExecutor`; per-agent `AgentRunner` adapters only
  declare how to invoke their CLI (binary, base args, prompt delivery, output parsing)
- Errors are `LocalizedError` carrying a `recoverySuggestion` (ported from ExFig)

### Testing Strategy

- swift-testing; test targets mirror source modules
- Build/test output piped through `xcsift`

### Git Workflow

- Conventional commits: `<type>(<scope>): <description>` with scopes like `config`, `scope`,
  `agent`, `forge`, `cli`
- Run format and lint before committing

## Domain Context

- A **scope** is a subtree owning a `baton.toml`. The deepest scope that is an ancestor of a changed
  file owns that file.
- Configuration **cascades** from the repository root down to a scope: `[agent]` (closest-wins whole
  block), `[[skills]]` (union + closest-wins by name), `[defaults]` (field-by-field closest-wins),
  `[[reviews]]` (inherited with override/disable — an improvement over blick).
- A **review** runs one agent invocation against the scope's portion of the diff, producing
  **findings** (file, line, severity, title, body).
- **Skills** are markdown instruction bundles (local or remote `owner/repo`) injected into the agent
  prompt; remote skills must be SHA-pinned and come from an allowlisted source.

## Important Constraints

- Configs may be read from untrusted repositories/forks → config format must be pure data (TOML),
  remote skills must be pinned and allowlisted, and skill markdown must be isolated in the prompt.
- The agent only receives the scope's diff by default; cross-file repo context is opt-in per review.
- GitHub integration depends on the `gh` CLI being present and authenticated.
- macOS + Linux are primary targets; Windows is best-effort.
