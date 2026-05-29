# rendering Specification

## Purpose
TBD - created by archiving change add-baton-mvp. Update Purpose after archive.
## Requirements
### Requirement: Local render formats

The system SHALL render a saved run record into `terminal`, `markdown`, and `json` output formats, reading only the run's on-disk artifacts under `.baton/runs/<run-id>/` (the machine record, manifest, and assembled prompt) without recomputing scopes, diffs, or findings.

#### Scenario: Render a saved run to terminal

- **WHEN** the user runs `render` for a saved run and selects the `terminal` format
- **AND** the run record contains findings with severity, file, line, title, and body
- **THEN** the system SHALL emit human-readable terminal output listing each finding with its severity badge, file and line, title, and body
- **AND** the system SHALL read the findings from the saved run record rather than recomputing them

#### Scenario: Render a saved run to markdown

- **WHEN** the user runs `render` for a saved run and selects the `markdown` format
- **THEN** the system SHALL emit a markdown report of the findings sourced from the saved run record

#### Scenario: Render a saved run to json

- **WHEN** the user runs `render` for a saved run and selects the `json` format
- **THEN** the system SHALL emit a machine-readable JSON document of the findings sourced from the saved run record

#### Scenario: Default to the latest run

- **WHEN** the user runs `render` without specifying a run id
- **THEN** the system SHALL resolve the run via the `latest` pointer under `.baton/runs/`
- **AND** the system SHALL render that run record in the selected format

### Requirement: GitHub render formats

The system SHALL render the same saved run record into `github-review`, `check-run`, and `github-summary` output formats, producing GitHub-shaped payloads from the saved findings without contacting GitHub or re-invoking any agent. The `github-review` and `check-run` formats SHALL require a head commit SHA (supplied via `--head-sha` or the CI environment) to anchor comments and annotations, and SHALL fail with a typed error carrying a `recoverySuggestion` when it is absent; `github-summary` SHALL NOT require a head SHA.

#### Scenario: Render github-review payload

- **WHEN** the user runs `render` for a saved run and selects the `github-review` format
- **THEN** the system SHALL produce a GitHub PR review payload whose review comments are derived from the saved findings, each anchored to its file and line

#### Scenario: Render check-run payload

- **WHEN** the user runs `render` for a saved run and selects the `check-run` format
- **AND** a head commit SHA is supplied via `--head-sha` or the CI environment
- **THEN** the system SHALL produce a GitHub Check Run payload (including annotations derived from the saved findings) from the run record anchored to that head SHA

#### Scenario: GitHub anchored format without a head SHA fails

- **WHEN** the user selects `github-review` or `check-run` and no head commit SHA is available from `--head-sha` or the CI environment
- **THEN** the system SHALL fail with a typed error
- **AND** the error SHALL carry a `recoverySuggestion` instructing the user to pass `--head-sha`

#### Scenario: Render github-summary payload

- **WHEN** the user runs `render` for a saved run and selects the `github-summary` format
- **THEN** the system SHALL produce a GitHub summary (markdown) document aggregating the saved findings

#### Scenario: Same run renders to multiple formats consistently

- **WHEN** the user renders one saved run record to `github-review`, then to `check-run`, then to `github-summary`
- **THEN** every format SHALL be derived from the same saved findings in that run record
- **AND** no format SHALL add, remove, or alter findings relative to the saved run record

### Requirement: Finding presentation

The system SHALL present each rendered finding with its severity badge (low, medium, or high), its file and line, and its title and body; and for the GitHub formats (`github-review`, `check-run`, `github-summary`) each finding SHALL additionally include a collapsible "Instructions for AI agents" block.

#### Scenario: Finding fields are shown in every format

- **WHEN** a finding from the saved run record is rendered in any format
- **THEN** the rendered finding SHALL include a severity badge reflecting the finding's severity (low, medium, or high)
- **AND** it SHALL include the finding's file and line
- **AND** it SHALL include the finding's title and body

#### Scenario: GitHub formats include collapsible AI-agent instructions

- **WHEN** a finding is rendered in `github-review`, `check-run`, or `github-summary` format
- **THEN** the rendered finding SHALL include a collapsible "Instructions for AI agents" block
- **AND** that block SHALL be sourced from the saved finding's content rather than newly generated

### Requirement: Comment Marker And Usefulness Feedback

The system SHALL embed a stable, machine-recognizable footer marker (`<!-- baton:finding -->`) in every rendered GitHub comment body so that re-runs can deduplicate posted comments and a future `learn` capability can identify Baton-authored threads. The `github-review` inline-comment body SHALL additionally include a short affordance inviting the reviewer to react 👍/👎 to signal whether the finding was useful.

#### Scenario: Rendered GitHub comment carries the footer marker

- **WHEN** a finding is rendered into a `github-review` inline comment or a `github-summary`/`check-run` entry
- **THEN** the rendered body SHALL contain the `<!-- baton:finding -->` footer marker

#### Scenario: Inline comment invites a usefulness reaction

- **WHEN** a finding is rendered into a `github-review` inline comment
- **THEN** the body SHALL include a short prompt inviting a 👍/👎 reaction to indicate whether the finding was useful
- **AND** the prompt SHALL be produced by the template (presentation), requiring nothing to be posted by Baton (reviewers add the reaction themselves)

### Requirement: No re-invocation

The system SHALL render any format operating purely over the saved run record and SHALL NOT re-invoke any agent, coding CLI, or LLM during rendering.

#### Scenario: Rendering does not spawn an agent

- **WHEN** the user renders a saved run record in any of the `terminal`, `markdown`, `json`, `github-review`, `check-run`, or `github-summary` formats
- **THEN** the system SHALL produce the output solely from the saved run artifacts
- **AND** the system SHALL NOT spawn any `AgentRunner` subprocess or call any LLM

#### Scenario: Rendering is read-only over the run record

- **WHEN** rendering reads a saved run record to produce output
- **THEN** the system SHALL treat the run record as read-only input
- **AND** the system SHALL NOT recompute the diff, re-resolve skills, or otherwise regenerate findings

### Requirement: Render Edge Cases

The system SHALL handle missing, dangling, and empty run records deterministically.

#### Scenario: Requested run record is missing or corrupt

- **WHEN** the user runs `render` for a specific run id whose on-disk record is missing or corrupt
- **THEN** the system SHALL fail with a typed error
- **AND** the error SHALL carry a `recoverySuggestion` advising the user to verify the run id or re-run `baton review`

#### Scenario: The latest pointer is absent or dangling

- **WHEN** the user runs `render` without a run id
- **AND** the `latest` pointer under `.baton/runs/` is absent or points to a non-existent run
- **THEN** the system SHALL fail with a typed error
- **AND** the error SHALL carry a `recoverySuggestion` advising the user to run `baton review` first

#### Scenario: The saved run has zero findings

- **WHEN** the user renders a saved run record that contains zero findings in any selected format
- **THEN** the system SHALL still produce valid, well-formed output for the selected format
- **AND** the system SHALL emit an empty report rather than an error

### Requirement: User-Customizable Local Report Templates

The system SHALL render the human-facing local report formats — the `render` `markdown` report and the `learn` rolling-pull-request-body markdown — from Jinja templates, SHALL ship bundled default templates that reproduce the previous built-in rendering's content and structure (with their output locked by a snapshot test), and SHALL allow a user to override a template via the `[render]` configuration block or a `--template` flag on `render`. The system SHALL keep the `github-review`, `check-run`, `github-summary`, `json`, and `terminal` formats built in code so that the required `<!-- baton:finding -->` marker, the 👍/👎 usefulness affordance, and the collapsible "Instructions for AI agents" block cannot be removed by a user template.

#### Scenario: Default template preserves the rendered findings

- **WHEN** a saved run is rendered to `markdown` with no custom template configured
- **THEN** the output SHALL render every finding with its severity badge, its file and line, and its title and body, matching the prior built-in rendering's content and structure
- **AND** the bundled default output SHALL be locked by a snapshot test

#### Scenario: User template overrides a local format

- **WHEN** the user configures `[render].markdown_template` or passes `--template <path>` for the `markdown` format
- **THEN** the system SHALL render that format from the user's template rather than the bundled default

#### Scenario: Invalid template fails with a typed error

- **WHEN** a configured or passed template contains a syntax error
- **THEN** the system SHALL fail with a typed error
- **AND** the error SHALL carry a `recoverySuggestion` instructing the user to fix the template

#### Scenario: GitHub formats are not user-templatable

- **WHEN** the user passes `--template` together with `github-review`, `check-run`, or `github-summary`
- **THEN** the system SHALL reject the request with a typed error
- **AND** the GitHub formats SHALL continue to emit the `<!-- baton:finding -->` marker, the 👍/👎 affordance, and the AI-agent instructions block

#### Scenario: Required marker preserved regardless of render configuration

- **WHEN** any GitHub comment body is produced under any `[render]` configuration
- **THEN** it SHALL contain the `<!-- baton:finding -->` footer marker

