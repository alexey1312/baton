# Change: Add `learn` self-improvement mode

## Why

`learn` was designed into Baton from the start as a deferred capability: the archived MVP
design (`openspec/changes/archive/2026-05-28-add-baton-mvp/design.md`, "Future: `learn`")
records it as a non-goal whose extension points the MVP deliberately preserves, but it has
never been specified as its own capability. The hooks are already in place and unused — every
rendered finding already carries the `<!-- baton:finding -->` marker and a "React 👍 / 👎 if
useful" affordance (capability `rendering`), owner resolution is reusable (capability
`diff-routing`), and per-scope agent/skills come for free from the cascade.

This change formalizes `learn` as a real capability and locks in Baton's improvements over
blick's `learn`: a usefulness signal read from 👍/👎 reactions (blick reads none), a
per-scope-cascading `[learn]` block (blick is root-only), and explainability through
`baton stats`. It also resolves how `learn` runs unattended on CI — its primary trigger —
where runners are ephemeral and `.baton/` is gitignored.

## What Changes

- A new `learn` command performs a periodic reflection pass: it scans recently merged PRs,
  reads reaction + thread signal, buckets findings, and asks each scope's agent to propose
  edits to the **review setup only** (`baton.toml`, local skills, agent docs) — never source
  code — consolidated into one rolling **draft PR** per repository.
- The usefulness signal is read authoritatively from GitHub on every run (👍/👎 via the
  Reactions API, thread resolution via GraphQL). CI execution is therefore **stateless**; an
  optional local SQLite cache under gitignored `.baton/` exists only to power `baton stats`
  trends and avoid re-fetching, and is never required, committed, or depended on.
- The `[learn]` config block is **split** in the cascade: delivery fields are root-only;
  analysis fields cascade closest-wins per scope.
- A scheduled GitHub Actions workflow (`.github/workflows/learn.yml`) becomes the primary,
  unattended trigger; it degrades to preview output when the token cannot open/update the PR.
- `baton stats` surfaces the most 👎/👍-weighted rules.

## Capabilities

### New Capabilities

- `learn`: a periodic, opt-in reflection pass that reads usefulness signal (👍/👎 reactions
  + thread resolution) from merged PRs, attributes it per scope, and proposes review-setup
  edits as a single rolling draft PR — gated by `min_signal` over a `lookback_days` window,
  constrained to an edit allowlist, safe-by-default (preview), and runnable unattended on CI.

### Modified Capabilities

- `config-cascade`: adds the rule for resolving the effective `[learn]` block (delivery
  fields root-only and non-inherited; analysis fields cascade closest-wins).

## Impact

- Affected specs: `learn` (new), `config-cascade` (one new requirement).
- Affected code (future implementation, out of scope for this change): `Sources/BatonKit/Learn/*`
  (scan → bucket → weight → propose), `Sources/BatonForge/*` (read reactions via the Reactions
  API and review threads via GraphQL through the injected `GHRunning`; open/update the rolling
  draft PR), `Sources/BatonKit/Database/*` (optional local `feedback` cache table),
  `Sources/BatonCLI/Commands/LearnCommand.swift`, `stats` surfacing, and
  `.github/workflows/learn.yml`.
- Unchanged dependency: `rendering` (the marker + 👍/👎 affordance) already satisfies the
  signal-collection prerequisite and is not modified here.
- Out of scope: agent editing of source code/tests/CI/deps; auto-merging the draft PR;
  network-egress sandboxing of the agent; accumulating signal beyond `lookback_days` on CI.
