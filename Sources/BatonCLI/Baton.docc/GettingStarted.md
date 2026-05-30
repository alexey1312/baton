# Getting Started

Install Baton and run your first review.

@Metadata {
    @TitleHeading("Getting Started")
    @PageColor(blue)
}

## Overview

Baton orchestrates AI code review across a monorepo. It discovers per-scope `baton.toml` files,
computes each scope's effective configuration via a cascade, routes a pull-request diff to the
owning scopes, and runs an external coding CLI against each scope's slice of the diff.

## Requirements

- macOS 13.0 or later, or Linux (Windows is best-effort)
- `git` on `PATH`
- An external coding CLI on `PATH` for `baton review` — one of `claude`, `codex`, `gemini`, or `opencode`
- The GitHub CLI (`gh`), authenticated, for `baton publish`

Run `baton doctor` at any time to verify these prerequisites.

## Installation

### Using mise

```bash
mise use -g github:alexey1312/baton
```

### Using Homebrew

```bash
brew install alexey1312/tap/baton
```

### From Source

```bash
git clone https://github.com/alexey1312/baton.git
cd baton
swift build -c release
cp .build/release/baton /usr/local/bin/
```

### Download a Binary

Download the latest archive from [GitHub Releases](https://github.com/alexey1312/baton/releases).
macOS binaries are universal (`arm64` + `x86_64`).

> Note: macOS binaries are not code-signed or notarized in the current release; you may need to
> clear the quarantine attribute (`xattr -dr com.apple.quarantine ./baton`). Signing and
> notarization are planned for a future release.

## Quick Start

### 1. Scaffold a configuration

```bash
baton init
```

This writes a starter `baton.toml` describing the agent, defaults, and reviews for the scope.

### 2. Inspect the effective configuration

```bash
baton config --explain
```

`--explain` reports the provenance of each effective value (which `baton.toml` it came from).

### 3. Run a review

```bash
baton review
```

Baton resolves the base, collects the diff, routes it to the owning scopes, and runs each scope's
configured agent against its slice of the diff. The findings are saved as a run under `.baton/runs/`.

### 4. Render or publish

```bash
# Render the latest saved run to the terminal, markdown, or JSON
baton render --format markdown

# Publish the latest run to the pull request as a review and Check Runs
baton publish
```

Both `render` and `publish` operate over a saved run without re-invoking the agent.

## What's Next

- <doc:Baton> — overview of Baton and its commands
