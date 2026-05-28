# Diff Routing

Resolves the review base, collects the PR diff, and routes each changed file to the deepest owning scope, partitioning the diff per scope, computing the focus diff in CI, structurally chunking oversized slices, and filtering files per review by glob.

## ADDED Requirements

### Requirement: Base Resolution

The system SHALL resolve the diff base using the priority order `--base` flag, then the scope default `base`, then `HEAD`.

#### Scenario: Explicit `--base` flag wins

- **WHEN** the user passes `--base origin/main` on the command line
- **AND** the scope default `base` is also set in `[defaults]`
- **THEN** the system SHALL use `origin/main` as the base and ignore the scope default and `HEAD`

#### Scenario: Scope default used when no flag

- **WHEN** no `--base` flag is provided
- **AND** the effective `[defaults]` config sets `base = "origin/develop"`
- **THEN** the system SHALL use `origin/develop` as the base

#### Scenario: Fall back to HEAD

- **WHEN** no `--base` flag is provided
- **AND** no scope default `base` is configured
- **THEN** the system SHALL use `HEAD` as the base

### Requirement: Diff Collection

The system SHALL collect the diff by running `git diff --find-renames` against the resolved base together with untracked files, parsing `diff --git a/… b/…` headers carefully including rename headers.

#### Scenario: Tracked changes via git diff with rename detection

- **WHEN** the system collects the diff against the resolved base
- **THEN** the system SHALL run `git diff --find-renames`
- **AND** the system SHALL parse each `diff --git a/… b/…` header to determine the changed file boundaries

#### Scenario: Rename headers parsed without misattribution

- **WHEN** a file has been renamed and `git diff --find-renames` emits a rename header with distinct `a/…` and `b/…` paths
- **THEN** the system SHALL parse the rename header boundary correctly
- **AND** the system SHALL attribute the change to the renamed (new) path without splitting the file mid-diff

#### Scenario: Untracked files included

- **WHEN** the working tree contains untracked files
- **THEN** the system SHALL include those untracked files in the collected diff in addition to the `git diff --find-renames` output

### Requirement: Owner Resolution

The system SHALL assign each changed file to the scope whose root is the deepest ancestor of that file, and SHALL drop files that fall outside any scope.

#### Scenario: Deepest-ancestor owner wins

- **GIVEN** scopes rooted at `/` and `/ios`
- **WHEN** a changed file is located at `/ios/App/View.swift`
- **THEN** the system SHALL assign the file to the `/ios` scope because its root is the deepest ancestor
- **AND** the system SHALL NOT assign the file to the `/` scope

#### Scenario: Files outside any scope are dropped

- **WHEN** a changed file has no scope root as an ancestor
- **THEN** the system SHALL drop the file from routing
- **AND** the system SHALL NOT route it to any scope

### Requirement: Diff Grouping

The system SHALL partition the collected diff per scope so each scope receives only the slice of the diff corresponding to the files it owns.

#### Scenario: Per-scope slice partitioning

- **GIVEN** changed files owned by the `/ios` scope and other changed files owned by the `/backend` scope
- **WHEN** the system groups the diff
- **THEN** the system SHALL produce a separate diff slice per scope
- **AND** the `/ios` scope slice SHALL contain only the `/ios`-owned files and the `/backend` scope slice SHALL contain only the `/backend`-owned files

### Requirement: Focus-Mode Diff

The system SHALL detect pull-request context from the GitHub Actions environment (`GITHUB_EVENT_PATH`, `GITHUB_REPOSITORY`) and, when in that context, recover the previous Baton review's head SHA from state stored on the pull request itself — Baton-authored Check Runs on prior commits, with a fallback to a `<!-- baton:last-reviewed=<sha> -->` marker in the Baton PR-review body — and additionally compute the focus diff containing only the changes since that SHA. The system SHALL NOT rely on local `.baton/runs/` artifacts for this SHA, because they do not survive between CI jobs.

#### Scenario: Focus diff computed from the previous review SHA recovered from the PR

- **GIVEN** the run is in CI on a pull request (PR context detected from the GitHub Actions environment)
- **AND** a previous Baton review's head SHA is recoverable from the PR's Baton Check Runs or the review-body marker
- **WHEN** the system collects the diff
- **THEN** the system SHALL recover that head SHA from the pull-request state rather than from local run artifacts
- **AND** the system SHALL additionally compute the focus diff as the changes since that SHA so the re-run focuses on new changes

#### Scenario: No previous review on the PR

- **WHEN** the run is in CI on a pull request
- **AND** no previous Baton review SHA can be recovered from the pull request
- **THEN** the system SHALL proceed with the full base diff and SHALL NOT compute a focus diff

#### Scenario: Not in a pull-request context

- **WHEN** no pull-request context can be detected from the GitHub Actions environment
- **THEN** the system SHALL proceed with the full base diff and SHALL NOT compute a focus diff

### Requirement: Structural Diff Chunking

The system SHALL, when a scope's diff slice exceeds `diff_budget` bytes, split the slice by file (or by hunk according to `chunk_strategy`) without ever splitting mid-file, run multiple agent passes over the chunks, and merge the findings, instead of truncating raw bytes.

#### Scenario: Split by file when budget exceeded

- **GIVEN** `chunk_strategy = "by-file"`
- **WHEN** a scope's diff slice exceeds `diff_budget` bytes
- **THEN** the system SHALL split the slice into chunks at file boundaries without splitting any file mid-file
- **AND** the system SHALL run a separate agent pass per chunk and merge the findings from all passes

#### Scenario: Split by hunk per chunk strategy

- **GIVEN** `chunk_strategy = "by-hunk"`
- **WHEN** a scope's diff slice exceeds `diff_budget` bytes
- **THEN** the system SHALL split the slice by hunk
- **AND** the system SHALL NOT split a single file's content in a way that breaks a hunk boundary

#### Scenario: No raw-byte truncation

- **WHEN** a scope's diff slice exceeds `diff_budget` bytes
- **THEN** the system SHALL chunk and run multiple passes
- **AND** the system SHALL NOT truncate the diff at a raw byte offset

#### Scenario: Within budget runs as a single pass

- **WHEN** a scope's diff slice is at or below `diff_budget` bytes
- **THEN** the system SHALL run a single agent pass over the whole slice without chunking

### Requirement: Per-Review Glob Filtering

The system SHALL route to each review only the files that match that review's `glob` patterns within the review's scope.

#### Scenario: Only matching files routed to a review

- **GIVEN** a review with `glob = ["**/*.swift"]` in a scope
- **WHEN** the scope's owned files include `App/View.swift` and `docs/README.md`
- **THEN** the system SHALL route `App/View.swift` to that review
- **AND** the system SHALL NOT route `docs/README.md` to that review

#### Scenario: No matching files yields no routed slice

- **GIVEN** a review with `glob = ["**/*.kt"]` in a scope
- **WHEN** none of the scope's owned files match the `glob` patterns
- **THEN** the system SHALL route no files to that review

### Requirement: Base And Empty-Diff Handling

The system SHALL validate the resolved base ref before collecting the diff and SHALL exit successfully without creating tasks when the resolved diff contains no changes.

#### Scenario: Invalid or unfetched base ref

- **WHEN** the resolved base ref (e.g. `origin/main`) is not present in the local repository
- **THEN** the system SHALL fail with a typed error
- **AND** the error SHALL carry a `recoverySuggestion` instructing the user to fetch the base ref (e.g. `git fetch origin main`)

#### Scenario: Empty resolved diff creates no tasks

- **WHEN** the resolved diff against the base contains no changes
- **THEN** the system SHALL create no tasks
- **AND** the system SHALL emit an informational message that there are no changes to review
- **AND** the system SHALL exit successfully

### Requirement: Oversized File Chunking Fallback

The system SHALL, when a single file's diff alone exceeds `diff_budget`, fall back from `by-file` to `by-hunk` for that file; if a single hunk still exceeds `diff_budget` the system SHALL send that hunk whole, mark the file `truncated` in the run record, and emit a warning, and SHALL NOT cut the diff at a raw byte offset mid-line.

#### Scenario: Single file larger than budget splits by hunk

- **GIVEN** `chunk_strategy = "by-file"`
- **WHEN** a single file's diff alone exceeds `diff_budget` bytes so it cannot fit in a `by-file` chunk
- **THEN** the system SHALL fall back to `by-hunk` for that file and split it at hunk boundaries
- **AND** the system SHALL NOT cut the diff at a raw byte offset mid-line

#### Scenario: Single hunk still larger than budget is sent whole and marked truncated

- **WHEN** a single hunk of that file still exceeds `diff_budget` bytes
- **THEN** the system SHALL send that hunk whole without cutting it at a raw byte offset mid-line
- **AND** the system SHALL mark the file `truncated` in the run record
- **AND** the system SHALL emit a warning that the file was sent oversized and marked truncated

### Requirement: Special Path And File Kinds

The system SHALL correctly parse diff headers with unusual paths and route binary and deleted files to their owning scope by path.

#### Scenario: Quoted, spaced, or unicode paths parsed without misattribution

- **WHEN** a `diff --git` header contains a quoted path, a path with spaces, or a path with unicode characters
- **THEN** the system SHALL parse the file boundary correctly
- **AND** the system SHALL NOT misattribute the change to the wrong file

#### Scenario: Binary file change routed by path with no line-anchored findings

- **WHEN** a changed file is binary and has no textual hunk
- **THEN** the system SHALL route the file to its owning scope by path
- **AND** the system SHALL NOT produce line-anchored findings for that file

#### Scenario: Deleted file owned by the scope of its path

- **WHEN** a changed file has been deleted
- **THEN** the system SHALL assign the file to the scope whose root is the deepest ancestor of its path
- **AND** the system SHALL allow file-level findings for that file

### Requirement: Rename Across Scope Boundary

The system SHALL own a renamed file by the scope of its new (`b/`) path.

#### Scenario: Rename crossing scope boundary owned by the new path's scope

- **GIVEN** scopes rooted at `libs/a` and `apps/ios`
- **WHEN** a file is renamed from `libs/a/x.swift` to `apps/ios/x.swift`
- **THEN** the system SHALL assign the renamed file to the `apps/ios` scope because that is the scope of its new (`b/`) path
- **AND** the system SHALL NOT assign the renamed file to the `libs/a` scope

### Requirement: Focus-Mode Fallback

The system SHALL fall back to the full base diff and emit a warning when the previous Baton review SHA cannot be located.

#### Scenario: Previous review SHA unreachable after force-push

- **GIVEN** the run is in CI on a pull request and a previous Baton review SHA was recorded
- **WHEN** the previous Baton review SHA cannot be located in the repository (e.g. after a force-push)
- **THEN** the system SHALL fall back to the full base diff instead of the focus diff
- **AND** the system SHALL emit a warning that the previous review SHA was unreachable
- **AND** the system SHALL continue the run
