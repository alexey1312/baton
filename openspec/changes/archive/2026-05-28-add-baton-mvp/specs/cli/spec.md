# CLI

The `baton` command-line interface: an `AsyncParsableCommand` executable exposing the `init`, `review`, `config`, `render`, `publish`, and `doctor` subcommands with global verbosity options, driving the BatonKit core and BatonForge publisher.

## ADDED Requirements

### Requirement: Command tree and global options

The system SHALL provide an executable named `baton`, implemented with `swift-argument-parser` as an `AsyncParsableCommand`, that exposes the subcommands `init`, `review`, `config`, `render`, `publish`, and `doctor`, and accepts the mutually informative global options `--verbose` and `--quiet` that adjust logging and terminal output verbosity for every subcommand.

#### Scenario: Listing available subcommands

- **WHEN** the user runs `baton --help`
- **THEN** the help output SHALL list the subcommands `init`, `review`, `config`, `render`, `publish`, and `doctor`
- **AND** SHALL document the global `--verbose` and `--quiet` options

#### Scenario: Global verbose flag applies to a subcommand

- **WHEN** the user runs `baton --verbose review`
- **THEN** the system SHALL raise the logging and terminal-output verbosity for that invocation
- **AND** SHALL execute the `review` subcommand with that verbosity in effect

#### Scenario: Global quiet flag suppresses non-essential output

- **WHEN** the user runs `baton --quiet review`
- **THEN** the system SHALL suppress non-essential progress and informational output for that invocation

#### Scenario: Unknown subcommand is rejected

- **WHEN** the user runs `baton frobnicate`
- **THEN** the system SHALL exit with a non-zero status
- **AND** SHALL report that the subcommand is unrecognized

### Requirement: init writes a starter configuration

The system SHALL provide a `baton init` subcommand that writes a starter `baton.toml`, honoring `--agent` to set the `[agent]` kind, `--model` to set the agent model, `--path` to choose the target directory or file location, and `--force` to permit overwriting; absent `--force`, the subcommand SHALL refuse to overwrite an existing `baton.toml` and exit with a non-zero status and a recovery suggestion.

#### Scenario: Create a starter config in a clean directory

- **WHEN** the user runs `baton init --agent claude --model claude-opus-4-7` in a directory with no existing `baton.toml`
- **THEN** the system SHALL write a `baton.toml` whose `[agent]` block has `kind = "claude"` and `model = "claude-opus-4-7"`
- **AND** SHALL exit with a zero status

#### Scenario: Refuse to overwrite without force

- **WHEN** the user runs `baton init` and a `baton.toml` already exists at the target location
- **AND** `--force` is not supplied
- **THEN** the system SHALL NOT modify the existing file
- **AND** SHALL exit with a non-zero status and a `recoverySuggestion` advising the use of `--force`

#### Scenario: Overwrite when force is supplied

- **WHEN** the user runs `baton init --force` and a `baton.toml` already exists at the target location
- **THEN** the system SHALL overwrite the existing file with the starter configuration
- **AND** SHALL exit with a zero status

#### Scenario: Honor an explicit path

- **WHEN** the user runs `baton init --path ./services/api`
- **THEN** the system SHALL write the starter `baton.toml` at the location resolved from `--path`

### Requirement: review runs configured reviews over the resolved diff

The system SHALL provide a `baton review [name]` subcommand that discovers scopes, cascades configuration, resolves the diff, and runs the review orchestration. When an optional positional `name` is provided it SHALL run only the named review; otherwise it SHALL run all configured reviews. It SHALL honor `--base` (diff base, taking precedence over scope defaults), `--agent` and `--model` (overriding the resolved agent kind and model), `--json` (emit machine-readable findings), `--max-concurrency` (sliding-window task limit, forced `>= 1`), `--repo` (the repository root to operate on), and `--allow-unpinned` (permit remote skills without a SHA `ref`). The exit status SHALL reflect the configured `fail_on` severity semantics.

#### Scenario: Run all reviews over the default diff

- **WHEN** the user runs `baton review` in a repository with one or more `baton.toml` scopes
- **THEN** the system SHALL run every configured `(scope, review)` task over the resolved diff
- **AND** SHALL emit the aggregated findings

#### Scenario: Run a single named review

- **WHEN** the user runs `baton review security`
- **THEN** the system SHALL run only the review named `security` for each scope that has it
- **AND** SHALL NOT run other reviews

#### Scenario: Base override takes precedence

- **WHEN** the user runs `baton review --base origin/main`
- **THEN** the system SHALL resolve the diff against `origin/main`
- **AND** SHALL take that base in precedence over any scope `defaults.base`

#### Scenario: Agent and model overrides apply uniformly

- **WHEN** the user runs `baton review --agent codex --model o4`
- **THEN** the system SHALL invoke the `codex` agent with model `o4` for the review tasks, overriding the resolved configuration

#### Scenario: JSON output

- **WHEN** the user runs `baton review --json`
- **THEN** the system SHALL print the findings as machine-readable JSON to standard output

#### Scenario: Concurrency limit is enforced and floored

- **WHEN** the user runs `baton review --max-concurrency 2`
- **THEN** the orchestrator SHALL run at most two `(scope, review)` tasks concurrently
- **AND** any value below 1 SHALL be forced to at least 1

#### Scenario: Unpinned remote skills are rejected by default

- **WHEN** the user runs `baton review` and a remote skill source lacks a SHA `ref`
- **AND** `--allow-unpinned` is not supplied
- **THEN** the system SHALL refuse to resolve the unpinned remote skill
- **AND** SHALL exit with a non-zero status and a recovery suggestion

#### Scenario: Allow unpinned remote skills when explicitly permitted

- **WHEN** the user runs `baton review --allow-unpinned` and a remote skill source lacks a SHA `ref`
- **THEN** the system SHALL permit resolving the unpinned remote skill

#### Scenario: Exit status reflects fail_on severity

- **WHEN** the user runs `baton review` and at least one finding meets or exceeds the configured `fail_on` severity
- **THEN** the system SHALL exit with a non-zero status

#### Scenario: Operate on an explicit repository root

- **WHEN** the user runs `baton review --repo /path/to/monorepo`
- **THEN** the system SHALL discover scopes and resolve the diff relative to that repository root

### Requirement: config explain prints effective configuration with provenance

The system SHALL provide a `baton config` subcommand that, with the `--explain` flag, prints the effective per-scope configuration after the cascade, annotating each effective value with its provenance (the source `baton.toml` file the value came from).

#### Scenario: Explain the effective config with provenance

- **WHEN** the user runs `baton config --explain` in a repository with nested `baton.toml` scopes
- **THEN** the system SHALL print, per scope, the effective `[agent]`, `[defaults]`, `[[skills]]`, and `[[reviews]]` values after cascade
- **AND** SHALL annotate each effective value with the source file it originated from

#### Scenario: Inherited and overridden values show their true source

- **WHEN** a child scope overrides an ancestor's `defaults.fail_on`
- **AND** the user runs `baton config --explain`
- **THEN** the effective `fail_on` for the child scope SHALL be reported with provenance pointing at the child's `baton.toml`

### Requirement: render and publish operate over a saved run without re-invoking the agent

The system SHALL provide `baton render --format <fmt>` and `baton publish` subcommands that operate over a previously saved run record, selected with `--run <id|latest|path>` and defaulting to the `latest` run pointer, and SHALL NOT re-invoke the external agent. `render` SHALL support the `--format` values `terminal`, `markdown`, and `json` for local output and `github-review`, `check-run`, and `github-summary` for GitHub payloads; the `github-review` and `check-run` formats SHALL require a head commit SHA supplied via `--head-sha`. `publish` SHALL post the saved findings to the GitHub PR via the `gh` CLI and SHALL accept the optional overrides `--head-sha`, `--gh-repo owner/repo`, and `--pr` (otherwise resolved from the GitHub Actions environment).

#### Scenario: GitHub render format requires a head SHA

- **WHEN** the user runs `baton render --format check-run` (or `--format github-review`) without `--head-sha` and outside any GitHub Actions environment that supplies one
- **THEN** the system SHALL exit with a non-zero status
- **AND** SHALL emit a typed error whose `recoverySuggestion` instructs the user to pass `--head-sha`

#### Scenario: publish accepts explicit context overrides

- **WHEN** the user runs `baton publish --gh-repo owner/repo --head-sha <sha> --pr 7`
- **THEN** the system SHALL publish the saved run against that repository, head SHA, and PR number instead of any GitHub Actions environment values

#### Scenario: Render a saved run as markdown

- **WHEN** the user runs `baton render --format markdown` and a saved run exists
- **THEN** the system SHALL read the latest saved run record
- **AND** SHALL produce a markdown rendering of its findings
- **AND** SHALL NOT invoke any external agent

#### Scenario: Render a saved run as JSON

- **WHEN** the user runs `baton render --format json`
- **THEN** the system SHALL produce a machine-readable JSON rendering from the saved run record without re-invoking the agent

#### Scenario: Publish a saved run to a PR

- **WHEN** the user runs `baton publish` in a GitHub PR context and a saved run exists
- **THEN** the system SHALL post the saved findings to the PR through the `gh` CLI
- **AND** SHALL NOT re-invoke the external agent

#### Scenario: Render and publish never re-run the agent

- **WHEN** the user runs `baton render` or `baton publish` over a saved run
- **THEN** the system SHALL operate solely on the persisted run artifacts
- **AND** SHALL NOT spawn an agent subprocess

### Requirement: doctor And Tool Preflight

The system SHALL provide a `baton doctor` subcommand that checks all required external tools and reports their status, and the `review` and `publish` subcommands SHALL run an automatic preflight that fails fast before doing work when a required tool is missing. The required tools are `git` (always), each configured agent CLI by name (`claude`, `codex`, `gemini`, `opencode`), and `gh` (for `publish`).

#### Scenario: baton doctor reports per-tool status

- **WHEN** the user runs `baton doctor`
- **THEN** the system SHALL check `git`, `gh`, and each configured agent CLI (such as `claude`, `codex`, `gemini`, or `opencode`)
- **AND** SHALL print whether each tool is present or missing and, where checkable, whether it is authenticated or unauthenticated
- **AND** SHALL include an install or login `recoverySuggestion` for anything missing or unauthenticated

#### Scenario: A required tool is missing

- **WHEN** the user runs `baton doctor` and at least one required tool is missing
- **THEN** the system SHALL exit with a non-zero status

#### Scenario: review preflight finds the configured agent CLI absent

- **WHEN** the user runs `baton review` and the configured agent CLI is not present on the system
- **THEN** the system SHALL fail fast before discovering scopes or running any task
- **AND** SHALL exit with a non-zero status and a `recoverySuggestion` naming the agent CLI and how to install it

#### Scenario: publish preflight finds gh absent or unauthenticated

- **WHEN** the user runs `baton publish` and the `gh` CLI is absent or not authenticated
- **THEN** the system SHALL fail fast before posting any findings
- **AND** SHALL exit with a non-zero status and the appropriate `recoverySuggestion` to install or authenticate `gh`

### Requirement: Invalid Invocation Handling

The system SHALL reject invalid invocations with a typed error carrying a `recoverySuggestion`.

#### Scenario: Named review does not exist in any scope

- **WHEN** the user runs `baton review <name>` and no scope defines a review with that name
- **THEN** the system SHALL exit with a non-zero status
- **AND** SHALL emit a typed error whose `recoverySuggestion` lists the available review names

#### Scenario: Repository path is invalid

- **WHEN** the user runs a subcommand with `--repo` pointing to a non-existent directory or a directory that is not a git repository
- **THEN** the system SHALL exit with a non-zero status
- **AND** SHALL emit a typed error with a `recoverySuggestion`

#### Scenario: Run outside a repository without an explicit repo

- **WHEN** the user runs `baton review` outside any git repository and no `--repo` is given
- **THEN** the system SHALL exit with a non-zero status
- **AND** SHALL emit a typed error whose `recoverySuggestion` advises running inside a repository or passing `--repo`
