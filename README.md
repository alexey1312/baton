# Baton

[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Falexey1312%2Fswift-baton%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/alexey1312/swift-baton)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Falexey1312%2Fswift-baton%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/alexey1312/swift-baton)
[![CI](https://github.com/alexey1312/swift-baton/actions/workflows/ci.yml/badge.svg)](https://github.com/alexey1312/swift-baton/actions/workflows/ci.yml)
[![Release](https://github.com/alexey1312/swift-baton/actions/workflows/release.yml/badge.svg)](https://github.com/alexey1312/swift-baton/actions/workflows/release.yml)
[![Docs](https://github.com/alexey1312/swift-baton/actions/workflows/deploy-docc.yml/badge.svg)](https://alexey1312.github.io/baton/documentation/batoncli)
[![License](https://img.shields.io/github/license/alexey1312/swift-baton.svg)](LICENSE)

Baton runs AI code review across a monorepo, one scope at a time. Each subtree keeps its own
`baton.toml`, and the settings cascade down the tree with the closest one winning, so the iOS
code and the backend code can use different agents, models, skills, and standards. The name
comes from a conductor's baton: it directs the reviewers, it doesn't play.

## Overview

Baton has no model of its own. It finds the scopes, routes the diff to the deepest one that
owns each file, runs the configured reviews through external coding CLIs, and either prints
the findings or posts them to a GitHub pull request. The full documentation is at
<https://alexey1312.github.io/baton>.

## Features

- Per-scope configuration that cascades down the tree, with `baton config --explain` showing
  where each effective value came from.
- Works with claude, codex, gemini, opencode, or any other CLI through `kind = "custom"`. The
  `binary` and `args` overrides apply to every agent the same way.
- Oversized diffs are split at file and hunk boundaries, never mid-line, instead of being cut
  off at a byte count.
- Remote skills must be pinned to a commit SHA and matched against an allowlist, and their
  markdown enters the prompt as untrusted reference data rather than instructions.
- Posts resolvable inline comments and one Check Run per `(scope, review)` through the `gh`
  CLI, with the saved run kept on disk for re-rendering without re-running the agent.

## Installation

### mise (recommended)

```sh
mise use -g github:alexey1312/swift-baton
```

### Homebrew

```sh
brew install alexey1312/tap/baton
```

### Build from source

```sh
git clone https://github.com/alexey1312/swift-baton.git
cd swift-baton
swift build -c release
.build/release/baton --help
```

Requires Swift 6.3 and macOS 13+.

## Quick start

```sh
baton init --agent claude --model claude-opus-4-7   # write a starter baton.toml
baton doctor                                         # check git / gh / agent CLIs
baton review                                         # review the diff; exit code honors fail_on
baton render --format markdown                       # render the saved run (no agent re-run)
baton publish                                         # post findings to the GitHub PR
```

`baton review security` runs a single review. `--base origin/main` sets the diff base, and
`--json` prints machine-readable findings.

## Platform support

Builds and runs on macOS, Linux, and Windows. Prebuilt archives for each platform are attached
to every tagged release.

## Development

Tooling is pinned through [mise](https://mise.jdx.dev). Run `mise install` once to fetch the
toolchain (Swift 6.3, SwiftLint, SwiftFormat, dprint, hk, actionlint, git-cliff), then
`mise run setup` to wire up the git hooks under `.githooks/`. Then:

```sh
mise run build        # debug build
mise run test         # full test suite
mise run lint         # SwiftLint --strict + actionlint
mise run format       # SwiftFormat + dprint fmt
mise run docs         # generate the DocC site at ./docs
```

Capabilities live under `openspec/specs/`; new work goes through a fresh OpenSpec change
(`openspec change add <name>`, then `openspec validate <name> --strict`). Completed changes
are archived under `openspec/changes/archive/`.

## License

[MIT](LICENSE).
