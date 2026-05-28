# Tasks: Add `learn` self-improvement mode

## 1. Spec & validation

- [x] 1.1 `openspec validate add-learn-mode --strict` passes
- [x] 1.2 Cross-check the `config-cascade` delta does not conflict with existing inheritance requirements

## 2. config-cascade — `[learn]` block

- [x] 2.1 Add `LearnConfig` Codable to the schema with explicit snake_case `CodingKeys` (delivery: `branch`/`base`/`reviewers`/`team_reviewers`/`labels`/`draft`; analysis: `lookback_days`/`min_signal`/`enabled`)
- [x] 2.2 Cascade: analysis fields field-by-field closest-wins (like `[defaults]`); delivery fields read only from the root scope, ignored on descendants
- [x] 2.3 Provenance tracking for effective `[learn]` values
- [x] 2.4 Tests: per-scope `min_signal`/`lookback_days` override + inherit; root-only delivery; `enabled = false` opt-out; `enabled` defaults to `true` when unset anywhere in the chain

## 3. BatonForge — GitHub reads

- [x] 3.1 Read 👍/👎 reactions on review comments carrying `<!-- baton:finding -->` via the Reactions API (through `GHRunning`, paginated), excluding the PR author's own reactions
- [x] 3.2 Read review-thread resolution/outdated state via GraphQL (through `GHRunning`), capturing the resolving actor so Baton-automation resolution can be excluded from human signal
- [x] 3.3 List pull requests merged within `lookback_days`
- [x] 3.4 Open/update one rolling draft PR on the `learn` branch (force-update existing branch/PR)
- [x] 3.5 Mock-`GHRunning` tests for each read/write path; permission-denied → degrade to preview + warning

## 4. BatonKit — `Learn/`

- [x] 4.1 Attribute each thread to a scope via the reused deepest-ancestor owner resolution
- [x] 4.2 Bucket threads (accepted/ignored/outdated/human-authored) and weight signal (reaction ±1 augmenting resolution state); ignore Baton-automation resolution and PR-author self-reactions
- [x] 4.3 Edit-allowlist guard, enforced by inspecting the agent's actual file changes (drop any out-of-allowlist path): only `baton.toml` prompts/skill lists, local skill dirs (`.baton/skills/**` and local `[[skills]]` sources), agent docs; refuse source/tests/CI/deps
- [x] 4.4 Per-scope agent pass over setup using the scope's effective `[agent]` + skills
- [x] 4.5 Gating by signal volume (attributed-thread count, not signed net weight) below `min_signal`, and skip scopes with `enabled = false`; a net-negative scope at/above volume is NOT skipped
- [x] 4.6 Stateless run path (no required local state); idempotent re-run into one rolling PR
- [x] 4.7 Tests for attribution, bucketing/weighting, allowlist refusal (incl. out-of-allowlist drop), gating by volume, exclusion of Baton-automation resolution + author self-reactions
- [x] 4.8 Feed human-authored missing-coverage signal into the scope agent pass; accept allowlist-bounded proposals that add/broaden a `[[reviews]]` entry or skill, with tests

## 5. Optional local cache

- [x] 5.1 New `feedback` table in the local SQLite (gitignored `.baton/`), keyed by finding identity `hash(file,line,title,severity)`
- [x] 5.2 Cache is non-authoritative and never required: it never widens the effective `lookback_days` window and feeds the agent the same signal + candidate ranking whether present or absent
- [x] 5.3 Tests: cache upsert idempotency; proposals identical with/without cache

## 6. BatonCLI

- [x] 6.1 `LearnCommand` (ArgumentParser): preview by default, deliver when configured/`--apply`
- [x] 6.2 Preview renderer (terminal/markdown) of proposed edits, reusing presentation patterns
- [x] 6.3 Surface most 👎/👍-weighted rules in `baton stats`

## 7. CI

- [x] 7.1 `.github/workflows/learn.yml`: `schedule:` (cron) + `workflow_dispatch`; `permissions: contents: write`, `pull-requests: write`
- [x] 7.2 Document the GitHub App token caveat for PR write (PAT degrades to preview)

## 8. Documentation

- [x] 8.1 Document the `learn` command, the `[learn]` block (delivery vs analysis fields, `enabled` default), and the 👍/👎 signal model in the CLI docc (e.g. `OutputFormats.md` and a Learn page)

## 9. Validation gates

- [x] 9.1 `mise run format-check` — clean
- [x] 9.2 `mise run lint` — swiftlint --strict + actionlint clean
- [x] 9.3 `mise run test 2>&1 | xcsift -f toon` — no regressions
- [x] 9.4 `openspec validate add-learn-mode --strict` — passes
