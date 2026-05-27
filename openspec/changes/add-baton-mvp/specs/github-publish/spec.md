# GitHub Publish

Publishing a saved Baton run to a GitHub PR via the `gh` CLI as resolvable inline review comments and per-`(scope, review)` Check Runs, without re-invoking the LLM.

## ADDED Requirements

### Requirement: gh CLI Preflight

The system SHALL verify, before publishing, that the `gh` CLI is present in `PATH` and authenticated, and SHALL fail with a `recoverySuggestion` to install/authenticate `gh` when this precondition is not met.

#### Scenario: gh missing from PATH

- **WHEN** `publish` is invoked and no `gh` executable is found in `PATH`
- **THEN** publishing fails without contacting GitHub
- **AND** the error carries a `recoverySuggestion` instructing the user to install the `gh` CLI

#### Scenario: gh present but not authenticated

- **WHEN** `gh` is found in `PATH` but `gh auth status` reports it is not authenticated
- **THEN** publishing fails without posting any review comment or Check Run
- **AND** the error carries a `recoverySuggestion` instructing the user to authenticate `gh` (e.g. `gh auth login` or a token env var)

#### Scenario: gh present and authenticated

- **WHEN** `gh` is found in `PATH`
- **AND** `gh auth status` reports an authenticated session
- **THEN** the preflight succeeds and publishing proceeds

### Requirement: PR Context Detection

The system SHALL resolve the target repository slug, head SHA, and PR number from explicit CLI overrides (`--gh-repo owner/repo`, `--head-sha`, `--pr`) when given, otherwise from the GitHub Actions environment (`GITHUB_REPOSITORY`, the `GITHUB_EVENT_PATH` pull-request payload, and `GITHUB_SHA`), so that `GitHubForge` publishes against the correct pull request and commit. When a repository and head SHA are resolvable but no PR number can be determined, the system SHALL post only Check Runs (which need no PR) and SHALL NOT fail.

#### Scenario: PR context resolved from GitHub Actions environment

- **WHEN** `publish` runs inside GitHub Actions on a pull request event with no explicit overrides
- **THEN** `GitHubForge` reads the repository slug, PR number, and head SHA from the GitHub Actions environment (the event payload and `GITHUB_REPOSITORY`/`GITHUB_SHA`)
- **AND** all subsequent review comments and Check Runs target that PR number and head SHA

#### Scenario: Explicit overrides take precedence over the environment

- **WHEN** `publish` is invoked with `--gh-repo owner/repo`, `--head-sha <sha>`, and `--pr <n>`
- **THEN** `GitHubForge` SHALL use the override values instead of the GitHub Actions environment values

#### Scenario: Head SHA or repository cannot be determined

- **WHEN** `publish` runs and neither the GitHub Actions environment nor an explicit override provides a repository slug and head SHA
- **THEN** publishing fails with an error whose `recoverySuggestion` explains how to supply `--gh-repo` and `--head-sha`

#### Scenario: Repository and head SHA known but no PR number

- **WHEN** a repository slug and head SHA are resolvable but no PR number can be determined from overrides or the environment
- **THEN** the system SHALL post only the per-`(scope, review)` Check Runs against the head SHA
- **AND** the system SHALL NOT fail for the absence of a PR number

### Requirement: PR Review Posting

The system SHALL post findings that fall inside the PR diff hunks as inline comments within a single PR review submitted with event `COMMENT` and an empty review body, so that each inline comment is resolvable by the PR author.

#### Scenario: findings inside diff hunks become resolvable inline comments

- **WHEN** publishing a saved run for a `(scope, review)`
- **AND** one or more findings reference a file and line located inside a diff hunk of the PR
- **THEN** those findings are submitted as inline comments anchored to their file and line within a single PR review
- **AND** the PR review event is `COMMENT` with an empty review body
- **AND** each inline comment is created so it is resolvable by the PR author

#### Scenario: no findings inside diff hunks

- **WHEN** publishing a saved run and no finding falls inside a diff hunk
- **THEN** no PR review with inline comments is created for those findings

### Requirement: Check Run Creation

The system SHALL create exactly one Check Run per `(scope, review)`, set its conclusion to `failure` when any high-severity finding exists, to `success` when there are no findings, and to `neutral` otherwise, and SHALL fold findings that fall outside the diff into the Check Run summary. This conclusion SHALL be gated on high severity by design, independent of the review's `fail_on` threshold (which governs only the local CLI exit status).

#### Scenario: one Check Run per scope-review with failure conclusion

- **WHEN** publishing a saved run for a `(scope, review)` whose findings include at least one high-severity finding
- **THEN** exactly one Check Run is created for that `(scope, review)`
- **AND** its conclusion is `failure`

#### Scenario: success conclusion when no findings

- **WHEN** publishing a `(scope, review)` that produced no findings
- **THEN** exactly one Check Run is created for that `(scope, review)`
- **AND** its conclusion is `success`

#### Scenario: neutral conclusion with non-high findings

- **WHEN** publishing a `(scope, review)` that produced findings but none are high-severity
- **THEN** exactly one Check Run is created for that `(scope, review)`
- **AND** its conclusion is `neutral`

#### Scenario: findings outside the diff folded into the summary

- **WHEN** publishing a `(scope, review)` whose findings reference files or lines that fall outside any PR diff hunk
- **THEN** those findings are not posted as inline review comments
- **AND** they are folded into the Check Run summary for that `(scope, review)`

### Requirement: Thread Resolution and Dedupe

The system SHALL be able to resolve PR review threads via the GraphQL `resolveReviewThread` mutation and SHALL deduplicate findings against already-posted comments so that re-runs do not spam the PR.

#### Scenario: dedupe against already-posted comments

- **WHEN** `publish` runs again on a PR where a previous run already posted an inline comment for a finding
- **THEN** `GitHubForge` detects the matching already-posted comment
- **AND** it does not post a duplicate inline comment for that finding

#### Scenario: resolve a review thread

- **WHEN** the tool determines a previously posted review thread should be marked resolved
- **THEN** `GitHubForge` invokes the GraphQL `resolveReviewThread` mutation for that thread via `gh`
- **AND** the corresponding inline comment thread is marked resolved on the PR

#### Scenario: re-run does not spam the PR

- **WHEN** `publish` is re-run and the saved run's findings are unchanged from a prior publish
- **THEN** no duplicate inline comments are created
- **AND** the existing Check Runs and review comments reflect the current findings without redundant posts

### Requirement: Reviewed-SHA Persistence For Focus Mode

The system SHALL persist the reviewed head SHA on the pull request when publishing, so that a later `review` run can recover it for focus mode. The SHA SHALL be discoverable from the Baton-authored Check Runs and SHALL also be embedded as a `<!-- baton:last-reviewed=<sha> -->` marker in the Baton PR-review body.

#### Scenario: reviewed SHA recoverable from a published run

- **WHEN** `publish` posts Check Runs and a PR review for a saved run against head SHA `S`
- **THEN** the published Check Runs SHALL be attributable to head SHA `S`
- **AND** the PR-review body SHALL contain a `<!-- baton:last-reviewed=S -->` marker

#### Scenario: a later run recovers the SHA for focus mode

- **WHEN** a subsequent `review` runs in CI on the same pull request after a prior `publish`
- **THEN** it SHALL be able to recover the previously reviewed head SHA from the PR's Baton Check Runs or the review-body marker
- **AND** it SHALL use that SHA as the focus-mode base (per the `diff-routing` capability)

### Requirement: Publish Failure Handling

The system SHALL handle GitHub publishing failures gracefully and keep re-runs idempotent.

#### Scenario: token lacks write permission

- **WHEN** `publish` runs against a PR where the available token lacks write permission (e.g. a pull request opened from a fork)
- **AND** GitHub rejects the attempt to post review comments or Check Runs
- **THEN** publishing fails with a typed error
- **AND** the error carries a `recoverySuggestion` explaining the missing write permission and the fork-PR limitation

#### Scenario: Check Run creation needs a GitHub App token

- **WHEN** `publish` runs with a token that cannot create Check Runs (the Checks API requires a GitHub App token such as the Actions `GITHUB_TOKEN`, not a plain PAT used locally)
- **THEN** the system SHALL NOT abort the whole publish
- **AND** it SHALL degrade to posting the PR review (inline comments plus a summary comment) and emit a warning that Check Runs were skipped because the token cannot create them

#### Scenario: rate-limit or 5xx response from GitHub

- **WHEN** GitHub returns a rate-limit response or a 5xx error while publishing
- **THEN** the system SHALL retry the request with backoff
- **AND** if the request still fails after the retries it SHALL raise a typed error whose `recoverySuggestion` explains the rate-limit or server-error condition and how to retry

#### Scenario: PR head SHA has advanced since the saved run

- **WHEN** `publish` runs and the PR head SHA has advanced beyond the head SHA recorded in the saved run
- **THEN** the system SHALL NOT anchor inline comments to lines that may have moved
- **AND** the affected findings SHALL be folded into the Check Run summary
- **AND** a warning SHALL be emitted indicating the saved run is stale relative to the current head SHA

#### Scenario: comment count exceeds GitHub limits

- **WHEN** the number of inline comments to post exceeds GitHub's per-review or API limits
- **THEN** the overflow findings SHALL NOT be dropped
- **AND** the overflow findings SHALL be folded into the Check Run summary

#### Scenario: re-running after an interrupted publish

- **WHEN** a previous `publish` was interrupted partway and `publish` is re-run for the same saved run
- **THEN** re-running SHALL be idempotent via dedupe against already-posted comments and Check Runs
- **AND** no duplicate inline comments SHALL be created
