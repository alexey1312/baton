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

Baton has no model of its own. It finds the scopes, routes the diff to the deepest one that
owns each file, runs the configured reviews through external coding CLIs, and either prints
the findings or posts them to a GitHub pull request.

## Features

- Per-scope configuration that cascades down the tree, with `baton config --explain` showing
  where each effective value came from.
- Works with claude, codex, gemini, opencode, or any other CLI through `kind = "custom"`. The
  `binary` and `args` overrides apply to every agent the same way.
- Oversized diffs are split at file and hunk boundaries, never mid-line, instead of being cut
  off at a byte count.
- Remote skills must be pinned to a commit SHA and matched against an allowlist, and their
  markdown enters the prompt as untrusted reference data rather than instructions.
- Posts resolvable inline comments and one Check Run per `(scope, review)` through the `gh` CLI.

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

## Install

```sh
mise use -g github:alexey1312/swift-baton   # mise (recommended)
brew install alexey1312/tap/baton           # Homebrew
```

From source (Swift 6.3, macOS 13+): `swift build -c release && .build/release/baton --help`.

## Notes

- Builds and runs on macOS and Linux. Windows is best-effort.
- macOS binaries are not signed or notarized yet. If Gatekeeper blocks the binary, clear the
  quarantine flag: `xattr -d com.apple.quarantine <path>`.
- Release archives are on the [Releases](https://github.com/alexey1312/swift-baton/releases)
  page; full docs at <https://alexey1312.github.io/baton>.
