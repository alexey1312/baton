# Skill Resolution

Resolves `[[skills]]` declarations into trusted markdown instruction bundles — from local paths or SHA-pinned remote repositories — and embeds them safely in the review prompt.

## ADDED Requirements

### Requirement: Local Skill Resolution

The system SHALL resolve a skill whose `source` starts with `./`, `../`, `/`, or `~` as a local filesystem path relative to the directory of the declaring `baton.toml`, reading the skill body from `SKILL.md` or, if absent, `README.md` within the resolved directory.

#### Scenario: Relative path resolved against declaring config

- **WHEN** a `baton.toml` at `ios/baton.toml` declares a `[[skills]]` entry with `source = "./skills/style"`
- **AND** the directory `ios/skills/style/` contains a `SKILL.md`
- **THEN** the system SHALL resolve the source relative to `ios/` (the directory of the declaring `baton.toml`)
- **AND** read the skill body from `ios/skills/style/SKILL.md`

#### Scenario: Falls back to README.md when SKILL.md is absent

- **WHEN** a local skill `source` resolves to a directory that has no `SKILL.md`
- **AND** that directory contains a `README.md`
- **THEN** the system SHALL read the skill body from `README.md`

#### Scenario: Subpath narrows the resolved directory

- **WHEN** a local skill declares `source = "../shared"` and `subpath = "skills/owasp"`
- **THEN** the system SHALL look for `SKILL.md` (then `README.md`) under `../shared/skills/owasp/` relative to the declaring `baton.toml` directory

#### Scenario: Missing local skill fails with recovery guidance

- **WHEN** a local skill `source` resolves to a path that contains neither `SKILL.md` nor `README.md`
- **THEN** resolution SHALL fail with a `recoverySuggestion` indicating the expected path and that a `SKILL.md` or `README.md` is required

### Requirement: Remote Skill Resolution

The system SHALL resolve a skill whose `source` is a `owner/repo` or `owner/repo/skill` reference by shallow-cloning the repository into a cache directory rooted at `BATON_CACHE_DIR`, applying the skills.sh convention for `owner/repo/skill` (try `<repo>/skills/<name>` then `<repo>/<name>`), and reading the body from `SKILL.md` or `README.md`.

#### Scenario: owner/repo shallow-cloned into the cache

- **WHEN** a skill declares `source = "org/skills"` with a pinned `ref`
- **THEN** the system SHALL shallow-clone `org/skills` at the pinned commit SHA into a directory rooted at `BATON_CACHE_DIR`
- **AND** read the skill body from `SKILL.md` (then `README.md`) at the repository root, narrowed by `subpath` when present

#### Scenario: owner/repo/skill uses skills.sh lookup order

- **WHEN** a skill declares `source = "org/skills/owasp"`
- **THEN** the system SHALL shallow-clone `org/skills` into the cache rooted at `BATON_CACHE_DIR`
- **AND** look for the skill under `skills/owasp/` first (`<repo>/skills/<name>`)
- **AND** fall back to `owasp/` (`<repo>/<name>`) when the first path is absent
- **THEN** read the body from `SKILL.md` or `README.md` in the matched directory

#### Scenario: Cache reused for an already-cloned ref

- **WHEN** a remote skill at a given `source` and `ref` has already been cloned into `BATON_CACHE_DIR`
- **THEN** the system SHALL reuse the cached checkout instead of cloning again

### Requirement: Mandatory SHA Pinning for Remote Skills

The system SHALL require a commit `ref` (commit SHA) on every remote skill source, failing resolution when a remote skill omits `ref` while `[security].require_pinned_skills` is in effect, unless `--allow-unpinned` is explicitly passed.

#### Scenario: Unpinned remote skill rejected by default

- **WHEN** a skill declares a remote `source` such as `org/skills`
- **AND** the entry has no `ref`
- **AND** `--allow-unpinned` was not passed
- **THEN** resolution SHALL fail with a `recoverySuggestion` to add a commit SHA `ref` or pass `--allow-unpinned`

#### Scenario: Pinned remote skill resolves

- **WHEN** a remote skill declares `ref = "a1b2c3d4e5f6"`
- **THEN** the system SHALL clone the repository at that exact commit SHA and resolve the skill

#### Scenario: --allow-unpinned bypasses the requirement

- **WHEN** a remote skill omits `ref`
- **AND** the run was started with `--allow-unpinned`
- **THEN** the system SHALL resolve the skill against the default branch HEAD rather than failing

#### Scenario: Local skills are exempt from pinning

- **WHEN** a skill uses a local `source` (`./`, `../`, `/`, or `~`)
- **THEN** the system SHALL NOT require a `ref` and SHALL resolve the skill regardless of `require_pinned_skills`

### Requirement: Remote Skill Source Allowlist

The system SHALL reject any remote skill whose `source` does not match a pattern in the root scope's `[security].allowed_skill_sources` glob allowlist when that allowlist is set.

#### Scenario: Source outside the allowlist is rejected

- **WHEN** the root `baton.toml` sets `allowed_skill_sources = ["org/*", "trusted/skills"]`
- **AND** a skill declares `source = "attacker/evil"`
- **THEN** resolution SHALL fail with a `recoverySuggestion` stating the source is not in `allowed_skill_sources`

#### Scenario: Source matching a glob pattern is allowed

- **WHEN** `allowed_skill_sources = ["org/*"]` is set at the root
- **AND** a skill declares `source = "org/skills"` with a pinned `ref`
- **THEN** the system SHALL accept the source and proceed to clone and resolve it

#### Scenario: Allowlist applies only to remote sources

- **WHEN** `allowed_skill_sources` is set at the root
- **AND** a skill uses a local `source` (`./`, `../`, `/`, or `~`)
- **THEN** the system SHALL NOT apply the allowlist to that local skill

#### Scenario: No allowlist means no source restriction

- **WHEN** the root scope does not set `allowed_skill_sources`
- **THEN** the system SHALL NOT reject remote skills on the basis of source matching

### Requirement: Untrusted Markdown Isolation

The system SHALL embed every resolved skill's markdown inside a clearly delimited untrusted block in the assembled prompt and SHALL NOT place that markdown in an instruction position where it could override the review rules.

#### Scenario: Skill body placed in a delimited untrusted block

- **WHEN** the prompt is assembled with one or more resolved skills
- **THEN** each skill's `SKILL.md`/`README.md` body SHALL be wrapped in a clearly delimited untrusted block
- **AND** the block SHALL be positioned so it is treated as reference data, not as instructions that govern the review

#### Scenario: Skill markdown cannot override review rules

- **WHEN** a skill's markdown contains text that attempts to redirect or override the review instructions
- **THEN** the assembled prompt SHALL keep the review rules and output-format instructions outside and above the untrusted block
- **AND** the skill text SHALL NOT occupy an instruction position that can supersede those rules

### Requirement: Auto-Discovered Local Skills

The system SHALL make skills found under `.baton/skills/<name>/` available without an explicit `[[skills]]` entry, reading each skill body from its `SKILL.md` or `README.md`.

#### Scenario: Skill discovered without a config entry

- **WHEN** a directory `.baton/skills/owasp-top10/` containing a `SKILL.md` exists
- **AND** no `[[skills]]` entry names `owasp-top10`
- **THEN** the system SHALL make a skill named `owasp-top10` available, reading its body from `.baton/skills/owasp-top10/SKILL.md`

#### Scenario: Explicit entry overrides an auto-discovered skill of the same name

- **WHEN** an auto-discovered skill `.baton/skills/owasp-top10/` exists
- **AND** a `[[skills]]` entry also declares `name = "owasp-top10"`
- **THEN** the auto-discovered skill SHALL be prepended in the cascade so the explicit entry overrides it by name

### Requirement: Remote Resolution Failures

The system SHALL surface a typed error carrying a `recoverySuggestion` for every remote skill resolution failure, and SHALL require `git` to be available for cloning remote skills.

#### Scenario: git not available

- **WHEN** a remote skill must be cloned
- **AND** `git` is not present in the `PATH`
- **THEN** resolution SHALL fail with a typed error carrying a `recoverySuggestion` to install `git` and ensure it is on the `PATH`

#### Scenario: Clone fails — repository not found or network failure

- **WHEN** the shallow clone of a remote skill repository fails because the repository cannot be found or because of a network failure
- **THEN** resolution SHALL fail with a typed error carrying a `recoverySuggestion` to check the `source` and verify network connectivity

#### Scenario: Pinned ref not found in the repository

- **WHEN** a remote skill is pinned to a `ref`
- **AND** that commit SHA does not exist in the cloned repository
- **THEN** resolution SHALL fail with a typed error carrying a `recoverySuggestion` to verify the commit SHA `ref`

#### Scenario: Subpath does not exist in the cloned repository

- **WHEN** a remote skill resolves to a `subpath` (or to one of the skills.sh lookup paths) that does not exist in the cloned repository
- **THEN** resolution SHALL fail with a typed error naming the expected path and carrying a `recoverySuggestion` to correct the `subpath` or `source`

#### Scenario: Symlink escape inside a skill repository

- **WHEN** a skill path inside a cloned skill repository resolves, via a symlink, to a location outside its skill directory
- **THEN** resolution SHALL reject that path with a typed error carrying a `recoverySuggestion` to remove the escaping symlink or point the skill at a path within its skill directory
