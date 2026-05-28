# Tasks: Add `learn` self-improvement mode

## 1. Spec & validation

- [ ] 1.1 `openspec validate add-learn-mode --strict` passes
- [ ] 1.2 Cross-check the `config-cascade` delta does not conflict with existing inheritance requirements

## 2. config-cascade — `[learn]` block

- [ ] 2.1 Add `LearnConfig` Codable to the schema with explicit snake_case `CodingKeys` (delivery: `branch`/`base`/`reviewers`/`team_reviewers`/`labels`/`draft`; analysis: `lookback_days`/`min_signal`/`enabled`)
- [ ] 2.2 Cascade: analysis fields field-by-field closest-wins (like `[defaults]`); delivery fields read only from the root scope, ignored on descendants
- [ ] 2.3 Provenance tracking for effective `[learn]` values
- [ ] 2.4 Tests: per-scope `min_signal`/`lookback_days` override + inherit; root-only delivery; `enabled = false` opt-out

## 3. BatonForge — GitHub reads

- [ ] 3.1 Read 👍/👎 reactions on review comments carrying `<!-- baton:finding -->` via the Reactions API (through `GHRunning`, paginated)
- [ ] 3.2 Read review-thread resolution/outdated state via GraphQL (through `GHRunning`)
- [ ] 3.3 List pull requests merged within `lookback_days`
- [ ] 3.4 Open/update one rolling draft PR on the `learn` branch (force-update existing branch/PR)
- [ ] 3.5 Mock-`GHRunning` tests for each read/write path; permission-denied → degrade to preview + warning

## 4. BatonKit — `Learn/`

- [ ] 4.1 Attribute each thread to a scope via the reused deepest-ancestor owner resolution
- [ ] 4.2 Bucket threads (accepted/ignored/outdated/human-authored) and weight signal (reaction ±1 augmenting resolution state)
- [ ] 4.3 Edit-allowlist guard: only `baton.toml` prompts/skill lists, local skill dirs (`.baton/skills/**` and local `[[skills]]` sources), agent docs; refuse source/tests/CI/deps
- [ ] 4.4 Per-scope agent pass over setup using the scope's effective `[agent]` + skills
- [ ] 4.5 Gating: skip scopes below `min_signal` or with `enabled = false`
- [ ] 4.6 Stateless run path (no required local state); idempotent re-run into one rolling PR
- [ ] 4.7 Tests for attribution, bucketing/weighting, allowlist refusal, gating

## 5. Optional local cache

- [ ] 5.1 New `feedback` table in the local SQLite (gitignored `.baton/`), keyed by finding identity `hash(file,line,title,severity)`
- [ ] 5.2 Cache is non-authoritative and never required: a run with the cache absent produces identical proposals
- [ ] 5.3 Tests: cache upsert idempotency; proposals identical with/without cache

## 6. BatonCLI

- [ ] 6.1 `LearnCommand` (ArgumentParser): preview by default, deliver when configured/`--apply`
- [ ] 6.2 Preview renderer (terminal/markdown) of proposed edits, reusing presentation patterns
- [ ] 6.3 Surface most 👎/👍-weighted rules in `baton stats`

## 7. CI

- [ ] 7.1 `.github/workflows/learn.yml`: `schedule:` (cron) + `workflow_dispatch`; `permissions: contents: write`, `pull-requests: write`
- [ ] 7.2 Document the GitHub App token caveat for PR write (PAT degrades to preview)

## 8. Validation gates

- [ ] 8.1 `mise run format-check` — clean
- [ ] 8.2 `mise run lint` — swiftlint --strict + actionlint clean
- [ ] 8.3 `mise run test 2>&1 | xcsift -f toon` — no regressions
- [ ] 8.4 `openspec validate add-learn-mode --strict` — passes
