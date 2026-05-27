# Change: Bootstrap Baton — monorepo AI code-review orchestrator (MVP + GitHub publish)

## Why

Existing AI code reviewers are monolithic: one prompt, one model, one rule set for an entire
repository. In a monorepo with multiple stacks (iOS + web + backend), each team needs different
standards, models, and skills. [tuist/blick](https://github.com/tuist/blick) (Rust) solved this with
decentralized, cascading review configuration, but has limitations: it is GitHub-only via an opaque
agent abstraction, the agent sees only the diff, large diffs are truncated by raw bytes, reviews do
not inherit, remote skills are a prompt-injection vector, and there is no Windows build.

Baton brings this model to Swift 6.3 (cross-platform, building on the proven scaffolding of the ExFig
project) and fixes those limitations. The name reflects the architecture: a conductor's baton that
directs an ensemble of external agents across the sections (scopes) of a monorepo.

This change bootstraps the project and delivers the MVP plus GitHub publishing: discover scopes,
cascade config, route the diff, run agents concurrently, aggregate findings, and post them to a PR.

## What Changes

- **NEW** `swift-baton` SPM package (Swift 6.3), executable `baton`.
- **NEW** `BatonKit` core (no UI deps): `config-cascade`, `diff-routing`, `agent-execution`,
  `skill-resolution`, `review-orchestration` capabilities.
- **NEW** `BatonForge`: GitHub integration via the `gh` CLI (`github-publish` capability).
- **NEW** `BatonCLI` executable: `cli` capability — commands `init`, `review`, `config`,
  `render`, `publish`, `doctor`; plus the `rendering` capability (terminal / markdown / json / github formats).
- **NEW** Robust error handling and edge-case coverage: tool preflight + `baton doctor`, invalid/unfetched
  base refs, oversized/binary/renamed files, focus-mode fallback, remote-skill failures, and publish
  failures (missing permissions, rate limits, stale head SHA). Every failure carries a `recoverySuggestion`.
- **NEW** Reuse of ExFig scaffolding patterns: terminal UI, sliding-window orchestrator,
  subprocess executor, `LocalizedError` + `recoverySuggestion`.
- **NEW** Project tooling, CI, docs, and distribution ported from ExFig: pinned toolchain + tasks via
  `mise`, git hooks via `hk`, SwiftLint/SwiftFormat/dprint/actionlint; CI build+test+lint on
  macOS/Linux (Windows best-effort) piped through `xcsift`; DocC site deployed to GitHub Pages;
  tag-triggered GitHub Releases with `git-cliff` changelog and multi-platform binaries (macOS
  universal); distribution via `mise` (github backend) and Homebrew (`alexey1312/homebrew-tap`).
- **NEW** Improvements over blick (in scope for this change):
  1. Optional cross-file repo context for the agent (`context = "repo"`).
  2. Per-review glob/language filters and inherited `[[reviews]]` with override/disable.
  3. Skill security: mandatory SHA pinning for remote skills + source allowlist + prompt isolation.
  4. Structural diff chunking (by file/hunk) instead of raw-byte truncation.

## Impact

- Affected specs: none yet (this change introduces all initial capabilities).
- New capabilities: `config-cascade`, `diff-routing`, `agent-execution`, `skill-resolution`,
  `review-orchestration`, `github-publish`, `rendering`, `cli`, `developer-tooling`, `ci`,
  `documentation`, `release-distribution`.
- Out of scope for this change (future): `learn` self-improvement mode, non-GitHub forges
  (GitLab/Bitbucket), native (non-`gh`) GitHub API client, user-customizable prompt templates.
- New code: `Package.swift`, `Sources/BatonKit/**`, `Sources/BatonForge/**`, `Sources/BatonCLI/**`,
  `Tests/**`, `mise.toml`, CI workflows.
