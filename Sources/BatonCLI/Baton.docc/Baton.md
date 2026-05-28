# Baton

@Metadata {
    @TitleHeading("Command-Line Tool")
    @DisplayName("Baton")
}

Orchestrate AI code review across a monorepo with decentralized, cascading review configuration.

## Overview

Baton is a Swift command-line tool that routes a pull-request diff to the subtrees that own
it and runs an external coding CLI (claude, codex, gemini, or opencode) against each subtree's
slice of the diff. Findings are rendered locally or published to GitHub as resolvable review
comments and Check Runs.

Every subtree may declare a `baton.toml`. Baton walks the directory tree, computes the effective
configuration for each scope via a closest-wins cascade (with provenance), and partitions the
diff so each `(scope, review)` task is reviewed by that scope's configured agent and skills.

Baton contains no language model of its own — it drives external coding CLIs as subprocesses and
shells out to `git` and the `gh` CLI for GitHub operations. It runs on macOS 13+ and Linux, with
Windows support on a best-effort basis.

> Note: macOS release binaries are not code-signed or notarized in the current release. Code
> signing and notarization are planned for a future release.

## Topics

### Essentials

- <doc:GettingStarted>

### Commands

Baton exposes six commands:

- **`baton init`** — scaffold a starter `baton.toml` for a scope.
- **`baton review`** — route the diff to scopes and run the configured agents, producing findings.
- **`baton config`** — show the effective configuration for a scope (use `--explain` for provenance).
- **`baton render`** — render a saved run to the terminal, markdown, or JSON without re-running the agent.
- **`baton publish`** — publish a saved run to GitHub as a PR review and Check Runs.
- **`baton doctor`** — check that the required external tools (`git`, the agent CLI, `gh`) are present and authenticated.
