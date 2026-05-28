# Skill Resolution

Resolves `[[skills]]` declarations into trusted markdown instruction bundles — from local paths or SHA-pinned remote repositories — and embeds them safely in the review prompt.

## ADDED Requirements

### Requirement: Supporting Markdown Inlining

The system SHALL inline every supporting `*.md` file found anywhere inside the resolved skill directory (other than the chosen body file) into `ResolvedSkill.body`, regardless of whether the skill follows the Claude Code layout (`reference.md` at root, `examples/sample.md` under a subdirectory) or the Codex layout (`references/concurrency.md`). Inlined files SHALL be ordered alphabetically by their relative path, each appended under a `## Reference: <relative-path-without-extension>` header. Directories named `.git`, `.build`, and `node_modules` SHALL be skipped. The symlink-escape check SHALL apply to every inlined file as well as to the main body file, for both local and remote skill resolution. The chosen body file (`SKILL.md` or `README.md`) SHALL NOT be inlined a second time as a reference. Behaviour is unconditional — there is no TOML field or CLI flag controlling it.

#### Scenario: Codex layout inlined (local)

- **WHEN** a local skill directory contains `SKILL.md`, `references/a.md`, and `references/b.md`
- **THEN** the resolved body SHALL contain the original `SKILL.md` content followed by `## Reference: references/a` and `## Reference: references/b` sections, in that order

#### Scenario: Claude layout inlined (local)

- **WHEN** a local skill directory contains `SKILL.md`, a sibling `reference.md`, and `examples/sample.md`
- **THEN** the resolved body SHALL append `## Reference: examples/sample` and `## Reference: reference` sections, ordered alphabetically by relative path

#### Scenario: Codex layout inlined (remote)

- **WHEN** a remote skill is shallow-cloned at a pinned SHA and the checkout contains `SKILL.md` plus `references/security.md`
- **THEN** the resolved body SHALL append a `## Reference: references/security` section

#### Scenario: No supporting markdown

- **WHEN** the resolved skill directory contains only `SKILL.md` (or only `README.md`) with no other `*.md` files
- **THEN** the resolved body SHALL be exactly the contents of that file, with no `## Reference:` headers

#### Scenario: Non-markdown files ignored

- **WHEN** the skill directory contains `references/notes.txt`, `scripts/foo.py`, and `assets/logo.png` alongside `SKILL.md`
- **THEN** none of those files SHALL be inlined; only `*.md` files are inlined

#### Scenario: Deterministic alphabetical order

- **WHEN** supporting `*.md` files exist at varied depths and were created in arbitrary order
- **THEN** they SHALL be appended in ASCII-ascending order by relative path on every resolution

#### Scenario: Symlink escape rejected for a reference file

- **WHEN** a reference `*.md` inside the skill directory is a symbolic link whose target resolves outside the skill directory
- **THEN** resolution SHALL fail with `SkillError.symlinkEscape`

#### Scenario: README.md fallback still inlines references

- **WHEN** the resolved directory has no `SKILL.md` but does have `README.md` and one or more supporting `*.md` files
- **THEN** the body file is `README.md` and the resolved body SHALL still append `## Reference:` sections for the supporting files

#### Scenario: Body file is not double-inlined

- **WHEN** the chosen body file is `SKILL.md` (or `README.md`)
- **THEN** the resolved body SHALL contain that file's content exactly once and SHALL NOT include a `## Reference: SKILL` (or `## Reference: README`) entry
