# learn Specification

## Purpose
TBD - created by archiving change add-learn-mode. Update Purpose after archive.
## Requirements
### Requirement: Learn Command And Safe Dry-Run Default

The system SHALL provide a `learn` command that analyzes recent review signal and proposes
edits to the review setup, and SHALL default to a read-only preview that performs no GitHub
writes unless delivery is configured (root `[learn]` delivery fields) or explicitly requested.

#### Scenario: Preview is the default

- **WHEN** the user runs `learn` with no delivery configuration and no explicit apply flag
- **THEN** the system SHALL print the proposed review-setup edits as a local preview
- **AND** the system SHALL NOT open or update any pull request and SHALL NOT write to GitHub

#### Scenario: Delivery when configured

- **WHEN** the user runs `learn` with root `[learn]` delivery configured or an explicit apply request
- **THEN** the system SHALL consolidate the proposed edits into the rolling draft pull request

### Requirement: Signal Collection From Merged Pull Requests

The system SHALL collect usefulness signal by scanning pull requests merged within the
effective `lookback_days` window, identifying Baton-authored review threads by the
`<!-- baton:finding -->` marker, and reading both the 👍/👎 reactions on those comments (via
the GitHub Reactions API) and each thread's resolution state (via GitHub GraphQL). The system
SHALL determine whether a thread's resolution was produced by Baton's own automation in a
token-independent way: a thread any of whose comments carries the `<!-- baton:auto-resolved -->`
marker SHALL be treated as resolved by Baton automation regardless of the resolving actor's
login, and SHALL NOT be counted as a human usefulness signal.

#### Scenario: Baton threads identified by marker

- **WHEN** the system scans a merged pull request containing both Baton-authored and human-authored review threads
- **THEN** the system SHALL select the threads whose comment body contains the `<!-- baton:finding -->` marker as Baton-authored signal

#### Scenario: Reactions and resolution state are read

- **WHEN** the system processes a Baton-authored review thread
- **THEN** the system SHALL read the 👍/👎 reactions on its comment via the Reactions API
- **AND** the system SHALL read the thread's resolution state (resolved, unresolved, or outdated) via GraphQL

#### Scenario: Resolution by Baton's own automation is not human signal

- **WHEN** a thread's resolution or outdated state was produced by Baton's own automation rather than a human actor
- **THEN** the system SHALL NOT treat that resolution as a usefulness signal

#### Scenario: Resolution carrying Baton's auto-resolve marker is not human signal

- **WHEN** a review thread contains a comment carrying the `<!-- baton:auto-resolved -->` marker
- **THEN** the system SHALL treat the thread's resolution as Baton automation
- **AND** the system SHALL NOT count it as a usefulness signal, regardless of the resolving actor's login

#### Scenario: Human-authored threads count as missing-coverage signal

- **WHEN** a merged pull request contains a human-authored review thread that Baton did not author
- **THEN** the system SHALL record it as a signal of a review category Baton does not yet cover

#### Scenario: Pull requests outside the window are ignored

- **WHEN** a pull request merged earlier than the effective `lookback_days` window is encountered
- **THEN** the system SHALL NOT include its threads in the collected signal

### Requirement: Signal Source Of Truth And Optional Local Cache

The system SHALL treat GitHub as the authoritative source of signal and SHALL re-derive the
signal from GitHub on every run so that a run requires no persisted local state. The system
MAY cache observed signal in a local store under `.baton/` for trend reporting, but SHALL NOT
require, commit, or depend on that cache for correctness. The cache SHALL NOT extend the
effective signal window beyond `lookback_days`: any cross-window history it retains feeds only
`baton stats` trends and SHALL NOT enter the input a scope's agent analyzes.

#### Scenario: A run with no local cache still produces signal

- **WHEN** the system runs in an environment with no pre-existing local cache (e.g. an ephemeral CI runner)
- **THEN** the system SHALL collect the full signal by reading GitHub and SHALL proceed without error

#### Scenario: Cache presence does not change the agent's inputs

- **WHEN** the same window and GitHub state are processed once with and once without the local cache present
- **THEN** the system SHALL feed each scope's agent the same collected signal and the same candidate ranking in both cases
- **AND** the local cache SHALL NOT add, remove, or reweight any signal relative to reading GitHub alone

### Requirement: Per-Scope Signal Attribution

The system SHALL attribute each review thread to the scope that owns its file using the same
deepest-ancestor owner resolution that diff routing uses.

#### Scenario: Thread attributed to the deepest owning scope

- **WHEN** a review thread anchors to a file owned by a nested scope
- **THEN** the system SHALL attribute that thread's signal to the deepest scope that is an ancestor of the file

#### Scenario: Thread on a file outside any scope is dropped

- **WHEN** a review thread anchors to a file that no scope owns
- **THEN** the system SHALL NOT attribute its signal to any scope

### Requirement: Bucketing And Usefulness Weighting

The system SHALL bucket collected threads into accepted, ignored, outdated, and human-authored
categories, and SHALL combine the reaction weight (+1 per 👍, −1 per 👎) with the thread's
resolution state to rank findings — treating 👎-heavy rules as candidates to relax or remove
and 👍-heavy rules as candidates to reinforce. Reaction weight SHALL augment, not replace, the
resolution signal. Reactions authored by the pull request's own author SHALL NOT be counted,
so a self-reaction cannot manufacture signal.

#### Scenario: Upvoted, resolved finding is a reinforce candidate

- **WHEN** a finding's thread is resolved and carries net-positive 👍 reactions
- **THEN** the system SHALL rank the underlying rule as a candidate to reinforce

#### Scenario: Downvoted, ignored finding is a relax candidate

- **WHEN** a finding's thread is unresolved and carries net-negative 👎 reactions
- **THEN** the system SHALL rank the underlying rule as a candidate to relax or remove

#### Scenario: Outdated threads are weighted low

- **WHEN** a thread is flagged outdated by GitHub
- **THEN** the system SHALL weight its signal lower than an equivalent resolved or unresolved thread

#### Scenario: Reaction augments rather than replaces resolution

- **WHEN** a thread is resolved but carries net-negative 👎 reactions
- **THEN** the system SHALL NOT treat it as a reinforce candidate solely because it was resolved

#### Scenario: Author's own reaction is not counted

- **WHEN** the 👍/👎 reaction on a Baton thread was authored by the pull request's own author
- **THEN** the system SHALL exclude that reaction from the reaction weight

### Requirement: Edit Allowlist Excludes Source Code

The system SHALL restrict every proposed edit to the review setup — `baton.toml` review
prompts and skill lists, local skill directories, and agent-facing documentation — and SHALL
refuse to modify source code, tests, CI workflows, or dependency manifests. The system SHALL
enforce the allowlist by inspecting the file changes the agent actually produced and dropping
any path outside the allowlist, rather than relying on the agent to self-report a compliant
proposal.

#### Scenario: Setup edits are allowed

- **WHEN** the analysis proposes changing a `baton.toml` review prompt or a local skill file
- **THEN** the system SHALL include that edit in the proposal

#### Scenario: Source, test, CI, and dependency edits are refused

- **WHEN** the analysis proposes an edit to a source file, a test, a CI workflow, or a dependency manifest
- **THEN** the system SHALL refuse that edit and SHALL exclude it from the proposal

#### Scenario: Out-of-allowlist changes are dropped even when the agent emits them

- **WHEN** the agent writes changes that touch a path outside the allowlist alongside permitted setup edits
- **THEN** the system SHALL keep only the permitted setup edits
- **AND** the system SHALL drop the out-of-allowlist changes from the proposal

### Requirement: Per-Scope Agent Pass Over Setup

The system SHALL run the learning analysis for each scope using that scope's effective
`[agent]` and skills, and the agent SHALL propose edits only to that scope's own setup.

#### Scenario: Scope analyzed with its own effective agent and skills

- **WHEN** the system analyzes signal for a scope
- **THEN** it SHALL drive the analysis with that scope's effective `[agent]` and effective skills

#### Scenario: Proposal limited to the scope's setup

- **WHEN** the agent proposes edits for a scope
- **THEN** the system SHALL accept only edits to that scope's own `baton.toml`, local skills, and agent docs

### Requirement: Missing-Coverage Proposals From Human Threads

The system SHALL feed each scope's human-authored missing-coverage signal into that scope's
agent pass and SHALL accept a resulting proposal that adds or broadens a review or skill to
cover the uncovered category, subject to the same edit allowlist and per-scope limits as any
other proposed edit.

#### Scenario: Missing-coverage signal is offered to the agent

- **WHEN** a scope has human-authored review threads recorded as missing-coverage signal
- **THEN** the system SHALL include that signal in the scope's agent pass
- **AND** the system SHALL accept a resulting proposal that adds or broadens a `[[reviews]]` entry or skill within the allowlist

#### Scenario: No proposal without a recognizable gap

- **WHEN** a scope's human-authored threads do not cluster into a category Baton fails to cover
- **THEN** the system SHALL propose no new coverage for that scope

### Requirement: Rolling Pull Request Delivery

When delivery is enabled, the system SHALL consolidate all proposed edits across all scopes
into a single rolling pull request per repository on the configured `learn` branch — opened as
a draft by default and configurable via the root `[learn].draft` field — and SHALL update the
existing branch and pull request on subsequent runs rather than opening new ones.

#### Scenario: First run opens one draft pull request

- **WHEN** delivery is enabled and no `learn` pull request exists yet
- **THEN** the system SHALL open exactly one draft pull request on the `learn` branch containing all scopes' proposed edits

#### Scenario: Subsequent run updates the same pull request

- **WHEN** delivery is enabled and a `learn` pull request already exists
- **THEN** the system SHALL update the existing branch and pull request rather than opening a new one

### Requirement: Gating By Minimum Signal And Opt-In

The system SHALL gate each scope on signal volume — the count of Baton-authored threads
attributed to the scope within the `lookback_days` window — and SHALL NOT measure `min_signal`
against the signed reaction weight, so that a scope rich in negative (👎) signal is never
skipped for being "below threshold." The system SHALL emit no proposal for a scope whose
signal volume is below the effective `min_signal`, and SHALL skip any scope whose effective
`[learn].enabled` is false.

#### Scenario: Below-threshold scope yields no proposal

- **WHEN** the count of Baton-authored threads attributed to a scope in the window is below its effective `min_signal`
- **THEN** the system SHALL emit no proposed edits for that scope

#### Scenario: Negative signal does not push a scope below threshold

- **WHEN** a scope meets its `min_signal` thread count but those threads are net-negative (👎-heavy)
- **THEN** the system SHALL NOT skip the scope for being below threshold
- **AND** the system SHALL treat the underlying rules as relax-or-remove candidates per the weighting rule

#### Scenario: Disabled scope is skipped

- **WHEN** a scope's effective `[learn].enabled` is false
- **THEN** the system SHALL skip that scope and collect no signal for it

### Requirement: Scheduled CI Execution

The system SHALL support unattended execution on a schedule (e.g. GitHub Actions `schedule`),
reading reactions and threads and delivering the rolling draft pull request using a token with
`contents` and `pull-requests` write permissions, and SHALL degrade to preview output with a
warning when the token lacks permission to open or update the pull request.

#### Scenario: Scheduled run delivers with a sufficient token

- **WHEN** the system runs unattended with a token granting `contents` and `pull-requests` write
- **THEN** the system SHALL deliver the rolling draft pull request without manual interaction

#### Scenario: Insufficient token degrades to preview

- **WHEN** the system runs with a token that cannot open or update the pull request
- **THEN** the system SHALL emit the preview output and a warning rather than failing the run

### Requirement: Stats Surfacing Of Feedback

The system SHALL surface the most 👎-weighted and 👍-weighted rules in `baton stats` so that
learn proposals are explainable.

#### Scenario: Stats lists most-downvoted and most-upvoted rules

- **WHEN** the user runs `baton stats` after signal has been observed
- **THEN** the output SHALL include the rules with the most net-negative 👎 weight and the rules with the most net-positive 👍 weight

