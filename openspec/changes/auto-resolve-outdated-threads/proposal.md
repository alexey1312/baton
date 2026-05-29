## Why

Baton ships a fully-implemented `resolveReviewThread` GraphQL mutation that has **no caller** — the write side of thread resolution was never wired up. Meanwhile the `learn` spec guarantees that "Resolution by Baton's own automation is not human signal", but the read side detects automation purely by the resolving actor's login (`[bot]` suffix or a configured `automation_actors` set). Under a personal access token the resolving actor is a human login, so any Baton-driven resolution would be miscounted as human usefulness signal — silently violating that guarantee. We need to connect the write side **and** make resolution provenance token-independent.

## What Changes

- Add an opt-in publish step that auto-resolves Baton-authored review threads GitHub has flagged **outdated** (anchor line changed). Gated behind a new `[publish].resolve_outdated_threads` config flag, **default `false`** (safe-by-default).
- Before resolving each thread, post a reply comment carrying a new `<!-- baton:auto-resolved -->` marker, then invoke the existing `resolveReviewThread` mutation. The marker makes Baton's resolution self-identifying regardless of which token/actor performed it.
- Make `learn` honor the marker: a thread carrying `<!-- baton:auto-resolved -->` is treated as Baton automation (not human signal) independent of the resolving actor's login.
- Degrade gracefully: a token lacking write permission skips auto-resolution with a single warning rather than failing the publish (mirrors the existing Check Run degradation).
- Idempotent re-runs: threads already resolved or already carrying the marker are skipped (no duplicate replies).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `github-publish`: adds a requirement for opt-in auto-resolution of Baton's own outdated review threads via reply-marker + `resolveReviewThread`, with default-off gating and permission degradation.
- `learn`: the "Resolution by Baton's own automation is not human signal" requirement gains a token-independent path — a thread carrying the `<!-- baton:auto-resolved -->` marker is automation regardless of the resolving actor's login.

## Impact

- **Config**: new `[publish]` block (`resolve_outdated_threads`), root-only (publish is a repo-level write), defaulting to `false`.
- **BatonKit**: `BatonMarker.autoResolved` + reply-body helper; `PublishConfig`/`EffectivePublish`; `ConfigDefaults`.
- **BatonForge**: new shared `ReviewThreadReader` (GraphQL thread read, reused by publish and learn); `GitHubForge` publish step + `Options.resolveOutdatedThreads`; `GitHubAPIBodies.ReplyComment`; `PublishReport` counters; `ForgeError.threadResolveForbidden`; `GitHubLearnForge` marker-aware signal; `LearnAPIBodies` comment paging.
- **BatonCLI**: `--resolve-outdated-threads` flag on `PublishCommand`; counter surfacing in `Publisher`.
- **No breaking changes**: feature is off by default; existing publish behavior is unchanged unless the flag is set.
