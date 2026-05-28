# Usage

The `baton` commands and their options.

## Overview

`baton` exposes six subcommands. The global `--verbose` and `--quiet` flags adjust output for
any of them and may appear before or after the subcommand.

## init

Write a starter `baton.toml`.

```sh
baton init --agent claude --model claude-opus-4-7
```

- `--agent <kind>` — `[agent].kind` (claude/codex/gemini/opencode/custom).
- `--model <id>` — the agent model.
- `--path <dir|file>` — where to write the config (default: `./baton.toml`).
- `--force` — overwrite an existing file.

## review

Discover scopes, cascade config, resolve the diff, and run the configured reviews. An optional
positional name runs only that review.

```sh
baton review                 # all reviews
baton review security        # only the "security" review
```

- `--base <ref>` — diff base (takes precedence over scope defaults).
- `--agent <kind>` / `--model <id>` — override the resolved agent/model.
- `--json` — emit machine-readable findings.
- `--max-concurrency <n>` — sliding-window task limit (forced `>= 1`).
- `--repo <path>` — repository root to operate on.
- `--allow-unpinned` — permit remote skills without a SHA `ref`.

The exit status is non-zero when any finding meets the review's `fail_on` severity.

## config

Print the effective per-scope configuration. With `--explain`, each value is annotated with
the `baton.toml` it came from.

```sh
baton config --explain
```

## render

Render a saved run without re-invoking the agent. See <doc:OutputFormats>.

```sh
baton render --format markdown
```

- `--format <fmt>` — output format.
- `--run <id|latest>` — which run to render (default: `latest`).
- `--head-sha <sha>` — required for `github-review` and `check-run`.

## publish

Post a saved run to a GitHub pull request through the `gh` CLI (one PR review with resolvable
inline comments, plus one Check Run per `(scope, review)`).

```sh
baton publish
```

- `--head-sha <sha>`, `--gh-repo <owner/repo>`, `--pr <n>` — override the GitHub Actions
  context.
- `--run <id|latest>` — which saved run to publish.

## doctor

Check that `git`, `gh`, and the configured agent CLIs are present (and, where checkable,
authenticated).

```sh
baton doctor
```

