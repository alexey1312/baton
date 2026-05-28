# Baton

Monorepo AI code-review orchestrator. Like a conductor's baton directing an ensemble, it
routes each part of a pull request to the right reviewer: every scope of a monorepo gets its
own agent, model, skills, and standards through cascading `baton.toml` configuration.

Baton discovers scopes, routes the diff to the deepest owning scope, runs the configured
reviews concurrently through external coding CLIs, and renders the findings locally or
publishes them to a GitHub PR — Baton has no model of its own.

## Features

- **Per-scope config cascade** — each subtree's `baton.toml` inherits and overrides
  (agent/model/skills/reviews), closest-wins, with provenance.
- **Pluggable agents** — claude, codex, gemini, opencode, or a `custom` CLI; `binary`/`args`
  honored uniformly.
- **Structural diff chunking** — splits oversized diffs by file/hunk (never mid-line), not raw bytes.
- **Skill security** — remote skills are SHA-pinned and source-allowlisted; their markdown
  is embedded in an isolated, untrusted prompt block.
- **GitHub publish** — resolvable inline comments + per-`(scope, review)` Check Runs via `gh`.

## Quick start

```sh
baton init --agent claude --model claude-opus-4-7   # write a starter baton.toml
baton doctor                                         # check git / gh / agent CLIs
baton review                                         # review the diff; exit code honors fail_on
baton render --format markdown                       # render the saved run (no agent re-run)
baton publish                                         # post findings to the GitHub PR
```

`baton review security` runs one review; `--base origin/main` sets the diff base; `--json`
emits machine-readable findings. `baton config --explain` prints the effective per-scope
config with the source of each value.

## Install

```sh
mise use -g github:alexey1312/swift-baton   # mise (recommended)
brew install alexey1312/tap/baton           # Homebrew
```

From source (Swift 6.3, macOS 13+): `swift build -c release && .build/release/baton --help`.

## Notes

- Builds and is tested on macOS and Linux; Windows is best-effort.
- macOS binaries are **not** code-signed/notarized in the MVP — clear quarantine with
  `xattr -d com.apple.quarantine <path>` if Gatekeeper blocks them.
- Prebuilt archives are on [Releases](https://github.com/alexey1312/swift-baton/releases);
  docs at <https://alexey1312.github.io/baton>.
