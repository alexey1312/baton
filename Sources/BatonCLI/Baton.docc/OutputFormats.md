# Output Formats

The formats `baton render` produces from a saved run.

## Overview

`baton review` saves each run under `.baton/runs/<run-id>/` (per-task JSON, the agent log, the
assembled prompt, and a `manifest.json`). `baton render --format <fmt>` turns a saved run into
output without re-invoking any agent. `baton publish` posts the GitHub-shaped results.

## Local formats

- **terminal** — human-readable findings with severity badges, file and line, title, and body.
- **markdown** — a markdown report grouped by `(scope, review)`.
- **json** — a machine-readable document of the run's results (base, head SHA, findings).

## GitHub formats

- **github-review** — a PR review payload: inline comments anchored to each finding's file and
  line, each carrying a collapsible "Instructions for AI agents" block, a 👍/👎 affordance, and
  the `<!-- baton:finding -->` marker.
- **check-run** — one Check Run payload per `(scope, review)`. The conclusion is high-gated:
  `failure` when any finding is high, `success` when there are none, otherwise `neutral`
  (independent of `fail_on`, which only governs the local exit status).
- **github-summary** — a markdown summary aggregating the findings.

`github-review` and `check-run` anchor to a commit, so they require a head SHA via `--head-sha`
(or the GitHub Actions environment). `github-summary` does not.

## Severity and exit status

Findings are `low`, `medium`, or `high`. A review fails (non-zero CLI exit) when any finding
meets or exceeds its effective `fail_on`. The Check Run conclusion is a separate, high-gated
signal — see above.

