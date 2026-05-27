# Developer Tooling

Pins the toolchain and developer tasks via `mise`, enforces formatting/linting and conventional commits via `hk` git hooks, and standardizes the linters/formatters — ported from the ExFig setup.

## ADDED Requirements

### Requirement: Pinned Toolchain And Tasks via mise

The system SHALL provide a `mise.toml` that pins the developer toolchain (Swift 6.3, `swiftlint`, `swiftformat`, `dprint`, `hk`, `actionlint`, `git-cliff`, `xcsift`) to explicit versions and defines tasks for the common workflows so contributors run identical tooling locally and in CI.

#### Scenario: Tasks exist for the core workflows

- **WHEN** a contributor lists the available `mise` tasks
- **THEN** there SHALL be tasks for building, testing, linting, and formatting (e.g. `build`, `test`, `lint`, `format`, `format-check`)
- **AND** the build and test tasks SHALL pipe `swift` output through `xcsift`

#### Scenario: Toolchain versions are pinned

- **WHEN** `mise` resolves the project tools
- **THEN** each tool SHALL resolve to the explicit version pinned in `mise.toml` (not "latest")
- **AND** a `mise.lock` SHALL record the resolved versions

### Requirement: Git Hooks via hk

The system SHALL configure `hk` (via `hk.pkl`) to run a `pre-commit` hook that formats and lints staged files (SwiftFormat, SwiftLint strict, dprint for markdown, actionlint for workflows) and a `commit-msg` hook that enforces Conventional Commits, wired so the native git hook delegates to `hk` through `mise`.

#### Scenario: pre-commit formats and lints staged files

- **WHEN** a contributor commits staged Swift, markdown, or workflow files
- **THEN** the `pre-commit` hook SHALL run SwiftFormat and SwiftLint (strict) on staged Swift files, dprint on staged markdown, and actionlint on workflow files
- **AND** auto-fixable issues SHALL be fixed and re-staged before the commit proceeds

#### Scenario: commit message must be a conventional commit

- **WHEN** a commit message does not follow the Conventional Commits format
- **THEN** the `commit-msg` hook SHALL reject the commit

#### Scenario: hooks can be bypassed for automation

- **WHEN** the environment variable `HK=0` is set
- **THEN** the git hooks SHALL skip running `hk`

### Requirement: Standardized Linters And Formatters

The system SHALL include `.swiftlint.yml`, `.swiftformat`, and a `dprint.json` configuration, and the `lint` and `format-check` tasks SHALL fail on any violation so CI can gate on them.

#### Scenario: lint fails on a violation

- **WHEN** the `lint` task runs against source that violates a SwiftLint rule
- **THEN** the task SHALL exit non-zero

#### Scenario: format-check fails on unformatted code

- **WHEN** the `format-check` task runs against unformatted Swift or markdown
- **THEN** the task SHALL exit non-zero without modifying files
