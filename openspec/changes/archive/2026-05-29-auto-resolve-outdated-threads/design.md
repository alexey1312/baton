## Context

`GitHubForge.resolveReviewThread(threadId:)` (Sources/BatonForge/GitHubForge.swift) is implemented but has no caller. The `learn` capability already models resolution provenance (`ReviewThreadSignal.resolutionActor` / `.resolvedByAutomation`) and specs that Baton's own resolution is not human signal — but `GitHubLearnForge.isAutomation` detects automation only from the resolving actor's login (`[bot]` suffix or a configured `automation_actors` set). Connecting the write side under a personal access token (human actor login) would therefore corrupt the learn signal. This change wires the write side **and** closes the provenance gap.

Current publish flow (`GitHubForge.publish`): stale-head check → `fetchExistingComments` (REST, path+line only) → build plan → `postReview` → `postCheckRuns`. The REST dedupe read returns neither thread node IDs nor `isOutdated`, so auto-resolution needs a separate GraphQL read — the same `reviewThreads` shape `GitHubLearnForge` already queries.

## Goals / Non-Goals

**Goals:**
- Wire `resolveReviewThread` to a concrete, conservative trigger: Baton's own threads GitHub flagged outdated.
- Make resolution provenance token-independent so the learn "not human signal" guarantee holds under any token.
- Keep it opt-in (default off) and degrade gracefully when the token lacks write permission.
- Idempotent re-runs (no duplicate replies / re-resolves).
- Reuse one GraphQL thread reader across publish and learn.

**Non-Goals:**
- Resolving "fixed" findings inferred by absence from the current run (agent non-determinism risk — explicitly rejected for now; possible later opt-in).
- A standalone `resolve` command.
- Changing reaction-weight or bucketing logic in `learn`.

## Decisions

### Decision 1: Conservative trigger — only GitHub-flagged outdated threads
Resolve only threads where `isOutdated == true`. GitHub sets `isOutdated` itself when the anchored line changes, so the staleness signal is actor-independent and cannot close a still-valid finding. *Alternative:* resolve findings absent from the current run — rejected because agent non-determinism between runs could silently resolve a still-valid thread.

### Decision 2: Token-independent provenance via a reply marker
Before resolving, post a reply comment carrying a new `BatonMarker.autoResolved` (`<!-- baton:auto-resolved -->`), then call `resolveReviewThread`. The marker lives in the GitHub thread itself, so `learn` can recognize Baton's automation regardless of `resolvedBy.login`. *Alternatives:* (a) config `automation_actors` only — fails under PATs and needs every consumer to pre-list the bot; kept only as a secondary OR-clause. (b) Infer from `isOutdated` alone — works for the outdated-only trigger today but does not generalize to future non-outdated resolutions; the marker is the robust general mechanism and is cheap.

The reply body deliberately omits `<!-- baton:finding -->` so it is invisible to dedupe (`fetchExistingComments` keys on `baton:finding`) and to finding-identity parsing (`BatonMarker.parseFinding`).

### Decision 3: Order — reply (marker) before resolve mutation
Post the marker first, resolve second. If the resolve mutation fails after the reply succeeds, the thread is still correctly attributed to automation (marker present) and the next publish retries the resolve because the thread is still `!isResolved`. The idempotency guard (skip threads already carrying the marker) prevents duplicate replies on retry.

### Decision 4: Trigger lives inside `publish`, gated root-only and default-off
`publish` already resolves the PR context, head SHA, and current findings — the natural seam; a separate command would duplicate that. The flag `[publish].resolve_outdated_threads` is read **root-only** (publish is a repo-level write, like `[learn]` delivery fields), defaults to `false`, and is overridable via a `--resolve-outdated-threads` CLI flag. *Alternative:* a cascading per-scope flag — rejected; there is one publish per PR.

### Decision 5: Shared `ReviewThreadReader` for the GraphQL thread read
A new `ReviewThreadReader` struct in BatonForge owns the `reviewThreads` GraphQL query + decoder (node id, `isResolved`, `isOutdated`, `resolvedBy.login`, comments with `databaseId`/`body`/`path`/`line`). Both `GitHubForge` (resolve) and `GitHubLearnForge` (signal) consume it, removing the duplicated query and keeping the comment-paging change (`first: 1` → a sufficient page) in one place.

### Decision 6: Permission failure degrades, like Check Runs
A 403 / "must have write access" on the reply or the mutation is caught as a degradable `ForgeError.threadResolveForbidden`, counted in `PublishReport.threadsResolveSkipped` with one aggregated warning; the publish does not fail (review and Check Runs already posted). Rate-limit/5xx use the existing retry path, then skip+warn rather than aborting.

## Risks / Trade-offs

- **[Reply comment adds noise]** → We only reply on threads GitHub already flagged outdated (already collapsed/greyed); the reply is one short line plus the HTML-comment marker, and idempotency prevents repeats.
- **[GraphQL comment paging may miss the marker on huge threads]** → Page `comments(first: 100)`; Baton threads are small (a finding + a few replies), so 100 is ample. Document the bound.
- **[Marker present but resolve never succeeds (permanent permission loss)]** → Thread stays unresolved but is correctly excluded from human signal via the marker; no correctness regression, only cosmetic.
- **[`automation_actors` still needed for pre-marker historical threads]** → Kept as a secondary OR-clause so existing bot-resolved threads keep working; new resolutions use the marker.
