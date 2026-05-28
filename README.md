# Baton

Baton is a monorepo AI code-review orchestrator. Like a conductor's baton directing an
ensemble, it routes the parts of a pull request to the right reviewers: each scope of a
monorepo (iOS, web, backend, ...) gets its own agent, model, skills, and standards through
cascading `baton.toml` configuration. Baton discovers scopes, resolves the diff, runs the
configured reviews concurrently through external agent CLIs, aggregates the findings, and
publishes them back to the GitHub pull request.

## Quick start

1. Create a starter configuration in your repository:

   ```sh
   baton init --agent claude --model claude-opus-4-7
   ```

   This writes a `baton.toml` whose `[agent]` block uses the `claude` agent with the given
   model. Add `--path ./services/api` to place the config in a nested scope, or `--force`
   to overwrite an existing file.

2. Check that the required external tools are present and authenticated:

   ```sh
   baton doctor
   ```

   `doctor` reports the status of `git`, `gh`, and each configured agent CLI (`claude`,
   `codex`, `gemini`, `opencode`), with a recovery suggestion for anything missing.

3. Run the configured reviews over the current diff:

   ```sh
   baton review
   ```

   Pass an optional name to run a single review (`baton review security`), `--base
   origin/main` to choose the diff base, or `--json` for machine-readable findings. The exit
   status reflects the configured `fail_on` severity.

4. Render or publish a saved run without re-invoking the agent:

   ```sh
   baton render --format markdown
   baton publish
   ```

   `render` supports `terminal`, `markdown`, and `json` for local output and
   `github-review`, `check-run`, and `github-summary` for GitHub payloads. `publish` posts
   the saved findings to the pull request through the `gh` CLI.

Use `baton config --explain` at any time to print the effective per-scope configuration
after the cascade, annotated with the source `baton.toml` each value came from.

## Installation

### mise (recommended)

Install the latest release through the [mise](https://mise.jdx.dev) GitHub backend:

```sh
mise use -g github:alexey1312/swift-baton
```

### Homebrew

```sh
brew install alexey1312/tap/baton
```

### From source

Baton is a Swift 6.3 package (minimum macOS 13). Build and run it directly with SPM:

```sh
git clone https://github.com/alexey1312/swift-baton.git
cd swift-baton
swift build -c release
.build/release/baton --help
```

## Platform support

Baton builds and is tested on macOS and Linux. Windows is supported on a best-effort basis.

> **Note:** macOS release binaries are **not** code-signed or notarized in the MVP. On first
> launch Gatekeeper may block the binary; you can remove the quarantine attribute with
> `xattr -d com.apple.quarantine <path-to-baton>` or allow it in System Settings. Code
> signing and notarization are planned as future work.

## Releases

Prebuilt archives for macOS (universal), Linux (x86_64), and Windows (best-effort) are
attached to each tagged release on the
[GitHub Releases](https://github.com/alexey1312/swift-baton/releases) page. The mise and
Homebrew install channels are fed by these same archives.

Full documentation is published at <https://alexey1312.github.io/baton>.
