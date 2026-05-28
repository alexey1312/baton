# review-orchestration Specification

## Purpose
TBD - created by archiving change add-baton-mvp. Update Purpose after archive.
## Requirements
### Requirement: Prompt Assembly

The system SHALL assemble each review prompt in code via a typed `PromptBuilder` that concatenates, in a fixed order, the role instructions, the review instructions (from the review's `prompt` or `prompt_file`), an isolated skills block, the output-format instructions, and the scope's diff slice.

#### Scenario: Inline prompt with skills

- **WHEN** `PromptBuilder` builds the prompt for a `(scope, review)` task whose review defines `prompt` and references one or more skills
- **THEN** the assembled prompt contains the role instructions first
- **AND** the review's `prompt` text is included as the review instructions
- **AND** the resolved skill markdown is embedded inside a clearly delimited untrusted skills block, never in an instruction position
- **AND** the output-format instructions and the scope diff are appended after the skills block

#### Scenario: Instructions loaded from prompt_file

- **WHEN** a review defines `prompt_file` instead of an inline `prompt`
- **THEN** `PromptBuilder` reads the referenced file and uses its contents as the review instructions in the same fixed position

#### Scenario: Scaffold built in code

- **WHEN** any review prompt is assembled
- **THEN** the role block, output-format block, and block delimiters are produced by code (not by user-supplied data)
- **AND** user-supplied review instructions and skills appear only as data within their designated positions

### Requirement: Concurrent Task Execution

The system SHALL create one task per `(scope, review)` pair and execute the tasks concurrently, bounded by the effective `max_concurrency` via a sliding-window orchestrator that keeps up to `max_concurrency` tasks in flight.

#### Scenario: Sliding window bounds concurrency

- **WHEN** the number of `(scope, review)` tasks exceeds the effective `max_concurrency`
- **THEN** at most `max_concurrency` tasks run at any one time
- **AND** a new task starts as soon as an in-flight task completes, until all tasks have run

#### Scenario: One task per scope-review pair

- **WHEN** the routed diff covers multiple scopes, each with multiple effective reviews
- **THEN** exactly one task is created for each distinct `(scope, review)` combination

#### Scenario: A failing task does not abort the window

- **WHEN** one task fails during concurrent execution
- **THEN** the remaining in-flight and pending tasks continue to run
- **AND** the failed task's outcome is recorded for the run

### Requirement: Agent Response Parsing

The system SHALL parse the agent's textual output into findings robustly, attempting plain JSON first, then fenced JSON, then brace-balanced extraction that is aware of string literals; when no findings can be parsed the task SHALL fail gracefully with a `recoverySuggestion`.

#### Scenario: Plain JSON output

- **WHEN** the agent output is a valid JSON document of findings
- **THEN** the parser decodes it directly into findings without further extraction

#### Scenario: Fenced JSON output

- **WHEN** plain JSON parsing fails and the output contains a fenced code block containing JSON
- **THEN** the parser extracts the fenced JSON and decodes it into findings

#### Scenario: Brace-balanced extraction

- **WHEN** both plain and fenced JSON parsing fail but a JSON object is embedded in surrounding prose
- **THEN** the parser performs brace-balanced extraction that ignores braces appearing inside string literals
- **AND** decodes the extracted JSON into findings

#### Scenario: Malformed output fails gracefully

- **WHEN** none of the parsing strategies yield decodable findings
- **THEN** the task fails without crashing the run
- **AND** the resulting error carries a `recoverySuggestion`

### Requirement: Run Record Artifacts

The system SHALL persist each run under `.baton/runs/<run-id>/`, writing for every task a machine record `<scope>--<review>.json`, an agent `.log`, and the exact assembled `.prompt.md`, and writing a run-level `manifest.json` and updating a `latest` pointer to the run. The `manifest.json` SHALL record the resolved diff `base` and the review-time head commit SHA so that `publish` can later detect when the pull-request head has advanced beyond the reviewed commit.

#### Scenario: Per-task artifacts written

- **WHEN** a `(scope, review)` task completes
- **THEN** a `<scope>--<review>.json` machine record of its findings and outcome is written under `.baton/runs/<run-id>/`
- **AND** the agent's output is written to a corresponding `.log`
- **AND** the exact prompt assembled by `PromptBuilder` is written to a corresponding `.prompt.md`

#### Scenario: Manifest and latest pointer

- **WHEN** all tasks in a run have completed
- **THEN** a `manifest.json` describing the run is written under `.baton/runs/<run-id>/`
- **AND** the `manifest.json` records the resolved diff `base` and the review-time head commit SHA
- **AND** the `latest` pointer is updated to reference this run

#### Scenario: Artifacts enable replay without re-invoking the agent

- **WHEN** a downstream command reads a saved run from `.baton/runs/<run-id>/`
- **THEN** the persisted machine records are sufficient to render or publish findings without re-invoking the agent

### Requirement: Severity And Exit Semantics

The system SHALL attach a severity of low, medium, or high to each finding (ordered low < medium < high), fail a review when any of its findings has a severity at or above the review's effective `fail_on` threshold, and reflect whether any review failed in the command's exit status. This `fail_on`-based local exit status SHALL be independent of the GitHub Check Run conclusion (defined by the `github-publish` capability), which is gated on high severity regardless of `fail_on`.

#### Scenario: Finding at or above fail_on fails the review

- **WHEN** a review's effective `fail_on` is `medium` and one of its findings has severity `high`
- **THEN** the review is marked as failed

#### Scenario: Findings below fail_on pass the review

- **WHEN** a review's effective `fail_on` is `high` and all of its findings have severity `low` or `medium`
- **THEN** the review is marked as passed

#### Scenario: Exit status reflects any failed review

- **WHEN** at least one review across all scopes is marked as failed
- **THEN** the command exits with a non-zero status
- **AND** **WHEN** no review failed, the command exits with a zero status

### Requirement: Orchestration Edge Cases And Robustness

The system SHALL behave deterministically when there is no work, when all tasks fail, when findings are duplicated by chunking, when findings are malformed, and when artifact filenames or disk writes are problematic.

#### Scenario: No tasks to run

- **WHEN** routing produces zero `(scope, review)` tasks
- **THEN** the run SHALL exit successfully with an informational "nothing to review" message
- **AND** a `manifest.json` SHALL still be written for the run

#### Scenario: Every task fails

- **WHEN** every `(scope, review)` task fails during the run
- **THEN** the run SHALL complete rather than abort early
- **AND** the `manifest.json` SHALL record each task's failure
- **AND** the command SHALL exit with a non-zero status

#### Scenario: Duplicate findings from diff chunking

- **WHEN** the same finding is produced by two different diff chunks
- **THEN** the merged result SHALL deduplicate findings by `(file, line, severity, title)`

#### Scenario: Malformed finding is dropped or clamped

- **WHEN** a finding has an invalid or missing field, such as a line number outside the file or no `severity`
- **THEN** the system SHALL drop or clamp the finding and emit a warning
- **AND** the system SHALL NOT crash the run

#### Scenario: Scope or review name with path separators

- **WHEN** a scope or review name contains path separators such as `/` or `\`
- **THEN** the artifact filename SHALL be sanitized by flattening those separators so it is filesystem-safe

#### Scenario: Artifact write failure

- **WHEN** writing a run artifact fails, for example because the disk is full
- **THEN** the system SHALL raise a typed error
- **AND** the error SHALL carry a `recoverySuggestion`

