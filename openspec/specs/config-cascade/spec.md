# config-cascade Specification

## Purpose
TBD - created by archiving change add-baton-mvp. Update Purpose after archive.
## Requirements
### Requirement: Scope Discovery

The system SHALL walk the directory tree from the repository root and treat every directory containing a `baton.toml` as a scope. The system SHALL skip the directories `.git`, `node_modules`, `target`, `dist`, `build`, and `.venv` while walking.

#### Scenario: nested baton.toml files each define a scope

- **GIVEN** a repository with `baton.toml` at the root and at `ios/` and `web/api/`
- **WHEN** the system performs scope discovery
- **THEN** it SHALL register three scopes rooted at the repository root, `ios/`, and `web/api/`
- **AND** the scope owning `web/api/handler.swift` SHALL be the `web/api/` scope (its deepest ancestor)

#### Scenario: excluded directories are not walked

- **GIVEN** a repository containing `node_modules/pkg/baton.toml` and `target/gen/baton.toml`
- **WHEN** the system performs scope discovery
- **THEN** it SHALL NOT descend into `.git`, `node_modules`, `target`, `dist`, `build`, or `.venv`
- **AND** no scope SHALL be registered for `node_modules/pkg/baton.toml` or `target/gen/baton.toml`

### Requirement: Agent Block Inheritance

The system SHALL resolve the effective `[agent]` block using closest-wins semantics, where the nearest scope's `[agent]` block replaces the ancestor's block as a whole rather than merging field-by-field.

#### Scenario: child agent block replaces ancestor block entirely

- **GIVEN** a root scope with `[agent]` `kind = "codex"`, `model = "o3"`, `context = "repo"`
- **AND** a child scope with `[agent]` `kind = "claude"` and no `model` or `context`
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[agent].kind` SHALL be `claude`
- **AND** the effective `[agent].model` and `[agent].context` SHALL NOT be inherited from the root block (the child block replaces the whole block; `context` falls back to its default `diff`)

#### Scenario: scope without an agent block inherits the nearest ancestor block

- **GIVEN** a root scope declaring `[agent]` `kind = "claude"` and a child scope declaring no `[agent]` block
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[agent]` block SHALL be the root scope's `[agent]` block in full

### Requirement: Skills Inheritance

The system SHALL compute the effective `[[skills]]` list as the union across the ancestor chain, and on a `name` collision the closest scope's entry SHALL win. The system SHALL prepend auto-discovered local skills found at `.baton/skills/<name>/SKILL.md` so that explicit `[[skills]]` entries with the same `name` override them.

#### Scenario: skills union with closest-wins on name collision

- **GIVEN** a root scope with `[[skills]]` `name = "owasp-top10"` `source = "org/skills"` `ref = "aaaa"`
- **AND** a child scope with `[[skills]]` `name = "owasp-top10"` `source = "org/skills"` `ref = "bbbb"` and `[[skills]]` `name = "swift-style"`
- **WHEN** the system computes the effective skills for the child scope
- **THEN** the effective skills SHALL contain exactly one `owasp-top10` whose `ref` is `bbbb`
- **AND** the effective skills SHALL also contain `swift-style`

#### Scenario: auto-discovered local skill is overridden by an explicit entry

- **GIVEN** a scope with a file `.baton/skills/owasp-top10/SKILL.md`
- **AND** the same scope declares an explicit `[[skills]]` entry `name = "owasp-top10"`
- **WHEN** the system computes the effective skills
- **THEN** the auto-discovered `owasp-top10` SHALL be prepended to the list
- **AND** the explicit `[[skills]]` entry named `owasp-top10` SHALL override the auto-discovered one

### Requirement: Defaults Inheritance

The system SHALL merge `[defaults]` field-by-field with closest-wins semantics, SHALL force `max_concurrency` to be `>= 1`, and SHALL apply the documented default values for any field not set anywhere in the chain: `base = HEAD`, `fail_on = "high"`, `max_concurrency = 4`, `diff_budget = 120000`, `chunk_strategy = "by-file"`, `timeout = 600` (seconds per agent invocation).

#### Scenario: defaults merge field-by-field closest-wins

- **GIVEN** a root scope with `[defaults]` `fail_on = "low"` and `diff_budget = 60000`
- **AND** a child scope with `[defaults]` `fail_on = "high"`
- **WHEN** the system computes the effective defaults for the child scope
- **THEN** the effective `fail_on` SHALL be `high` (closest scope wins)
- **AND** the effective `diff_budget` SHALL be `60000` (inherited field-by-field from the root)

#### Scenario: unset fields fall back to documented defaults

- **GIVEN** a scope whose `[defaults]` section is empty and has no ancestor overrides
- **WHEN** the system computes the effective defaults
- **THEN** `base` SHALL resolve to `HEAD`, `fail_on` SHALL be `high`, `max_concurrency` SHALL be `4`, `diff_budget` SHALL be `120000`, `chunk_strategy` SHALL be `by-file`, and `timeout` SHALL be `600`

#### Scenario: max_concurrency is forced to at least one

- **GIVEN** a scope with `[defaults]` `max_concurrency = 0`
- **WHEN** the system computes the effective defaults
- **THEN** the effective `max_concurrency` SHALL be `1`

### Requirement: Reviews Inheritance

The system SHALL inherit `[[reviews]]` down the ancestor chain. A review declared in a closer scope with the same `name` as an ancestor's review SHALL override the ancestor's review. The system SHALL remove inherited reviews whose `name` appears in a scope's `disabled_reviews` list.

#### Scenario: reviews are inherited from ancestors

- **GIVEN** a root scope declaring `[[reviews]]` `name = "security"`
- **AND** a child scope declaring no reviews
- **WHEN** the system computes the effective reviews for the child scope
- **THEN** the effective reviews SHALL include the inherited `security` review

#### Scenario: same-name review overrides the ancestor

- **GIVEN** a root scope with `[[reviews]]` `name = "security"` `prompt = "root prompt"`
- **AND** a child scope with `[[reviews]]` `name = "security"` `prompt = "child prompt"` `glob = ["**/*.swift"]`
- **WHEN** the system computes the effective reviews for the child scope
- **THEN** the effective `security` review SHALL be the child's definition with `prompt = "child prompt"` and `glob = ["**/*.swift"]`

#### Scenario: disabled_reviews removes an inherited review

- **GIVEN** a root scope declaring `[[reviews]]` `name = "legacy-style"`
- **AND** a child scope declaring `disabled_reviews = ["legacy-style"]`
- **WHEN** the system computes the effective reviews for the child scope
- **THEN** the effective reviews SHALL NOT include `legacy-style`

### Requirement: Security Section Scope

The system SHALL honor the `[security]` section only at the repository root scope and SHALL NOT inherit it to descendant scopes. A `[security]` section declared in a non-root scope SHALL NOT take effect.

#### Scenario: security at the root applies repository-wide

- **GIVEN** a root scope with `[security]` `require_pinned_skills = true` and `allowed_skill_sources = ["org/*"]`
- **WHEN** the system computes the effective config for any scope in the repository
- **THEN** the effective security policy SHALL be the root scope's `[security]` section

#### Scenario: security in a non-root scope is ignored

- **GIVEN** a child scope `ios/` declaring `[security]` `require_pinned_skills = false`
- **AND** a root scope declaring `[security]` `require_pinned_skills = true`
- **WHEN** the system computes the effective config for the `ios/` scope
- **THEN** the child's `[security]` section SHALL NOT take effect
- **AND** the effective `require_pinned_skills` SHALL be `true` from the root scope

### Requirement: Provenance

The system SHALL record, for each effective configuration value, the `baton.toml` file it was sourced from. The system SHALL expose this provenance so that `baton config --explain` can report which file contributed each effective value.

#### Scenario: explain reports the source file per value

- **GIVEN** a root scope `baton.toml` setting `[defaults] diff_budget = 60000`
- **AND** a child scope `ios/baton.toml` setting `[defaults] fail_on = "high"`
- **WHEN** the user runs `baton config --explain` for the `ios/` scope
- **THEN** the output SHALL attribute `diff_budget` to the root `baton.toml`
- **AND** the output SHALL attribute `fail_on` to `ios/baton.toml`

#### Scenario: provenance for a defaulted value

- **GIVEN** a scope where `chunk_strategy` is not set in any `baton.toml` in the chain
- **WHEN** the system records provenance for the effective config
- **THEN** the effective `chunk_strategy` value `by-file` SHALL be marked as originating from the built-in default rather than a `baton.toml` file

### Requirement: Config Validation

The system SHALL validate each `baton.toml` at parse time, and a malformed file SHALL produce a typed error conforming to `LocalizedError` that carries a `recoverySuggestion` describing how to fix the problem.

#### Scenario: malformed TOML yields a typed recoverable error

- **GIVEN** a `baton.toml` with invalid TOML syntax or an unknown `[agent].kind`
- **WHEN** the system parses and validates that file
- **THEN** it SHALL raise a typed domain error conforming to `LocalizedError`
- **AND** the error SHALL carry a `recoverySuggestion` explaining how to correct the file
- **AND** the error SHALL be rendered as `✗ <description>` followed by `  → <recovery>`

#### Scenario: remote skill missing required ref

- **GIVEN** a `baton.toml` with a `[[skills]]` entry whose `source` is a remote `owner/repo` and which omits `ref`
- **WHEN** the system validates the config under a policy requiring pinned skills
- **THEN** it SHALL raise a typed error whose `recoverySuggestion` instructs the user to pin a commit SHA via `ref` or to pass `--allow-unpinned`

### Requirement: No Configuration or Unresolvable Agent

The system SHALL fail with a typed error conforming to `LocalizedError` that carries a `recoverySuggestion` when no `baton.toml` exists anywhere in the repository, and when a scope has reviews but no `[agent]` block is resolvable anywhere in its ancestor chain.

#### Scenario: no baton.toml found anywhere

- **GIVEN** a repository containing no `baton.toml` at the root or in any subtree
- **WHEN** the system performs scope discovery
- **THEN** it SHALL raise a typed error conforming to `LocalizedError`
- **AND** the error SHALL carry a `recoverySuggestion` advising the user to run `baton init` to create a `baton.toml`

#### Scenario: scope has reviews but no resolvable agent block

- **GIVEN** a scope `ios/` declaring `[[reviews]]` `name = "security"`
- **AND** no `[agent]` block is declared in the `ios/` scope or any of its ancestors up to the repository root
- **WHEN** the system computes the effective config for the `ios/` scope
- **THEN** it SHALL raise a typed error conforming to `LocalizedError`
- **AND** the error SHALL name the `ios/` scope
- **AND** the error SHALL carry a `recoverySuggestion` advising the user to add an `[agent]` block at or above the `ios/` scope

### Requirement: Duplicate And Dangling References

The system SHALL reject duplicate `name` values within a single file's `[[reviews]]` or `[[skills]]` arrays; SHALL fail when a review's `skills` list references a skill name that cannot be resolved; and SHALL treat a `disabled_reviews` entry naming a non-existent review as a no-op.

#### Scenario: duplicate review name within one file

- **GIVEN** a `baton.toml` declaring two `[[reviews]]` entries both with `name = "security"`
- **WHEN** the system parses and validates that file
- **THEN** it SHALL raise a typed error conforming to `LocalizedError`
- **AND** the error SHALL carry a `recoverySuggestion` instructing the user to give each review a unique `name` within the file

#### Scenario: duplicate skill name within one file

- **GIVEN** a `baton.toml` declaring two `[[skills]]` entries both with `name = "owasp-top10"`
- **WHEN** the system parses and validates that file
- **THEN** it SHALL raise a typed error conforming to `LocalizedError`
- **AND** the error SHALL carry a `recoverySuggestion` instructing the user to give each skill a unique `name` within the file

#### Scenario: review references an undefined skill name

- **GIVEN** a scope `ios/` with a `[[reviews]]` entry whose `skills` list contains `"missing-skill"`
- **AND** no `[[skills]]` entry named `missing-skill` is resolvable in the scope's ancestor chain or auto-discovered locally
- **WHEN** the system computes the effective config for the `ios/` scope
- **THEN** it SHALL raise a typed error conforming to `LocalizedError`
- **AND** the error SHALL name the unresolved skill `missing-skill` and the `ios/` scope
- **AND** the error SHALL carry a `recoverySuggestion` instructing the user to declare a matching `[[skills]]` entry or correct the skill name

#### Scenario: disabled_reviews names a non-existent review

- **GIVEN** a scope declaring `disabled_reviews = ["does-not-exist"]`
- **AND** no inherited or local review is named `does-not-exist`
- **WHEN** the system computes the effective reviews for the scope
- **THEN** it SHALL NOT raise an error
- **AND** the `does-not-exist` entry SHALL be ignored as a no-op

### Requirement: Unknown Keys Are Lenient

The system SHALL ignore unrecognized keys in `baton.toml` and emit a warning for forward compatibility, while still hard-failing with a typed error on structural or type errors and on invalid enum values such as an unknown `[agent].kind`.

#### Scenario: unknown key is ignored with a warning

- **GIVEN** a `baton.toml` containing an unrecognized top-level key or an unrecognized key inside a known section
- **WHEN** the system parses that file
- **THEN** it SHALL ignore the unrecognized key
- **AND** it SHALL emit a warning naming the ignored key
- **AND** parsing SHALL continue and produce a valid configuration

#### Scenario: invalid agent kind hard-fails

- **GIVEN** a `baton.toml` with `[agent]` `kind = "gpt"` which is not a valid agent kind
- **WHEN** the system parses and validates that file
- **THEN** it SHALL raise a typed error conforming to `LocalizedError`
- **AND** the error SHALL carry a `recoverySuggestion` listing the valid kinds `claude`, `codex`, `gemini`, and `opencode`

### Requirement: Safe Tree Walk

During scope discovery the system SHALL NOT follow symlinked directories and SHALL never escape the repository root.

#### Scenario: symlinked directory inside the repository is not descended

- **GIVEN** a repository containing a symlinked directory `ios/link` that points to another directory inside the repository
- **WHEN** the system performs scope discovery
- **THEN** it SHALL NOT descend into `ios/link`
- **AND** no scope SHALL be registered through the `ios/link` symlink

#### Scenario: symlink pointing outside the repository root is not traversed

- **GIVEN** a repository containing a symlink `external` whose target is a directory outside the repository root
- **WHEN** the system performs scope discovery
- **THEN** it SHALL NOT traverse the `external` symlink
- **AND** discovery SHALL never visit a directory outside the repository root

### Requirement: Learn Block Inheritance

The system SHALL resolve the effective `[learn]` block by splitting its fields into two
classes. Delivery fields — `branch`, `base`, `reviewers`, `team_reviewers`, `labels`, and
`draft` — SHALL be read only from the repository-root scope and SHALL NOT be inherited by, nor
overridable from, any descendant scope (there is one rolling pull request per repository).
Analysis fields — `lookback_days`, `min_signal`, and `enabled` — SHALL cascade field-by-field
with closest-wins semantics, exactly like `[defaults]`. When `enabled` is not set anywhere in a
scope's chain, the effective `[learn].enabled` SHALL default to `true`, so `learn` runs in
preview without any `[learn]` block; delivery still requires the root delivery fields.

#### Scenario: Analysis field overridden closest-wins

- **GIVEN** a root scope with `[learn]` `min_signal = 3` and a child scope with `[learn]` `min_signal = 5`
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[learn].min_signal` for the child scope SHALL be `5`

#### Scenario: Analysis field inherited when child omits it

- **GIVEN** a root scope with `[learn]` `lookback_days = 14` and a child scope that declares `[learn]` without `lookback_days`
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[learn].lookback_days` for the child scope SHALL be `14`

#### Scenario: Delivery field is honored only at the root

- **GIVEN** a root scope with `[learn]` `branch = "learn"` and a child scope declaring `[learn]` `branch = "child-learn"`
- **WHEN** the system computes the effective delivery configuration
- **THEN** the effective delivery `branch` SHALL be `learn` from the root scope
- **AND** the child scope's `branch` value SHALL NOT take effect

#### Scenario: Per-scope opt-out via enabled

- **GIVEN** a child scope with `[learn]` `enabled = false`
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[learn].enabled` for that scope SHALL be `false`

#### Scenario: Enabled defaults to true when unspecified

- **GIVEN** a scope with no `[learn].enabled` set anywhere in its chain
- **WHEN** the system computes the effective `[learn].enabled` for that scope
- **THEN** the effective `[learn].enabled` SHALL be `true`
- **AND** `learn` SHALL run in preview for that scope while delivery still requires root delivery configuration

