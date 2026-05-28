# Design: `learn` self-improvement mode

## Context

`learn` is the feedback loop that closes the review cycle: it observes how Baton's findings
landed with humans and proposes edits to Baton's own review setup. The MVP preserved the
extension points (finding marker, owner resolution, per-scope agent/skills) but left the
behavior unspecified. This document records the decisions that turn those hooks into a
buildable capability, with the primary execution context being **unattended CI** (scheduled
GitHub Actions), where runners are ephemeral and `.baton/` is gitignored.

## Decision 1 — Signal model: GitHub is the source of truth; CI is stateless

The authoritative usefulness signal lives in GitHub: 👍/👎 reactions on Baton comments and
the resolution/outdated state of review threads. `learn` re-derives the signal from GitHub on
every run, so a CI run needs **no persisted state** — it scans merged PRs in the
`lookback_days` window and reads reactions + thread state directly.

A durable SQLite `feedback` table MAY exist as an **optional local cache** in gitignored
`.baton/` (a new table in the existing run-history DB) purely to power `baton stats` trends
and avoid re-fetching old PRs on a developer machine. It is never authoritative, never
committed, and never required by CI.

- **Rejected — committed ledger on the `learn` branch:** `.baton/` is gitignored, so the file
  would have to be force-added, and a binary/NDJSON ledger on a bot branch is noisy.
- **Rejected — `actions/cache` / artifacts:** eviction and retention limits mean silent loss
  of a signal we advertise as "durable."
- **Tradeoff (accepted):** on CI the signal is bounded by `lookback_days`. Quiet scopes widen
  the window. Cross-window accumulation is a local-cache nicety, not a CI mechanism.

## Decision 2 — Reading GitHub via the existing `GHRunning`

Reaction reads use the Reactions API (`GET /repos/{repo}/pulls/{pr}/comments` already drives
dedupe in `GitHubForge.fetchExistingComments`; reactions are read from the comment's
`/reactions` endpoint). Thread resolution/outdated state uses GraphQL (the same surface as the
existing `resolveReviewThread` mutation). Both go through the injected `GHRunning` so the whole
pass stays unit-testable with a recording mock, exactly like publishing.

Baton-authored threads are identified by the `<!-- baton:finding -->` marker
(`BatonMarker.finding`). Each thread is attributed to a scope with the same deepest-ancestor
owner resolution that `diff-routing` uses, kept side-effect-free for reuse.

## Decision 3 — `[learn]` cascade is split, not blanket

Delivery fields (`branch`, `base`, `reviewers`, `team_reviewers`, `labels`, `draft`) are
read only from the repository root and are not inherited — there is one rolling PR per repo,
so per-scope branches would mean N competing PRs. Analysis fields (`lookback_days`,
`min_signal`, `enabled`) cascade field-by-field, closest-wins, like `[defaults]`: a
high-traffic scope can demand more signal, a quiet one can widen its window or opt out. This
mirrors how Baton already made `[[reviews]]` inherit where blick does not, and is the spec
realization of the "repository-global sections live at the root" rule locked in by the MVP.

## Decision 4 — Edit allowlist: review setup only, never source

Proposed edits are constrained to: `baton.toml` review prompts and skill lists, local skill
directories (auto-discovered `.baton/skills/**` and any local `[[skills]]` source dir such as
`.claude/skills/**`), and agent-facing docs. Edits to source code, tests, CI workflows, or
dependency manifests are refused. The agent runs per scope with that scope's effective
`[agent]` + skills and may only touch that scope's own setup. The self-reinforcing property
holds: a bad setup edit shows up next window as more ignored/👎 threads, which the next pass
tries to fix.

## Decision 5 — Delivery: one rolling draft PR, safe-by-default

`baton learn` defaults to a read-only **preview** (terminal/markdown of proposed edits,
mirroring `render`'s read-only philosophy) and performs no GitHub writes unless delivery is
configured (root `[learn]` delivery fields) or explicitly requested. When delivery is enabled,
all proposals across all scopes funnel into a single rolling draft PR per repository on the
`learn` branch; subsequent runs force-update that branch/PR rather than opening new ones,
making re-runs idempotent (stateless scan + single rolling PR ⇒ nothing to double-count).

## Decision 6 — CI execution model

The primary trigger is a scheduled GitHub Actions workflow (`.github/workflows/learn.yml`,
`schedule:` + `workflow_dispatch`). It needs `permissions: contents: write` (push the `learn`
branch) and `pull-requests: write` (open/update the draft PR); reading reactions/threads is
covered by the default `GITHUB_TOKEN`. As with Check Runs in the MVP, a token lacking PR-write
permission (e.g. a local PAT) degrades to preview output plus a warning rather than failing.

## Risks / Open Questions

- Reaction sparsity: reactions are opt-in and rare; the design combines them with thread state
  rather than relying on them alone.
- `resolved` ambiguity: a resolved thread may be a fix or a dismissal — reaction weight
  augments but does not override resolution state (a resolved + 👎 thread is not auto-reinforced).
- GitHub App token requirement for some operations (mirrors the MVP Check Run caveat).
