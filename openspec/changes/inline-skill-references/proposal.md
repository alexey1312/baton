# Change: Inline supporting markdown alongside resolved skills

## Why

`SkillResolver` reads only `SKILL.md` (preferred) or `README.md` from the resolved skill
directory and silently discards everything else. The three live skill ecosystems all rely
on multi-file layouts:

- **Claude Code** — supporting files (`reference.md`, `template.md`, `examples/sample.md`)
  placed wherever the author likes, linked from `SKILL.md` and lazily fetched by the model
  through the Read tool.
- **Codex** — explicit `references/`, `scripts/`, `assets/` subdirectories.
- **Gemini CLI** — defers to the agentskills.io open standard; loads SKILL.md body plus
  folder structure on activation.

Baton's agent runs **headless** (`claude --print --max-turns 1`, no tool access; or even
no FS at all in `context = "diff"` mode). It cannot follow a "see references/concurrency.md"
pointer the way Claude Code can. Today the only workaround is to copy every supporting
file into `SKILL.md` by hand, which defeats the point of having a structured skill bundle.

This change makes the resolver inline every supporting `*.md` file from the skill
directory next to the main body, transparently and unconditionally — so skills authored
for any of the three ecosystems work in Baton out of the box.

## What Changes

- **MODIFIED** `Sources/BatonKit/Skill/SkillResolver.swift`: after reading the main body
  (`SKILL.md`/`README.md`), recursively walk the skill directory and inline every other
  `*.md` file into `ResolvedSkill.body`, alphabetically by relative path, under
  `## Reference: <relative-path-without-extension>` headers. Behaviour is unconditional
  (no TOML field, no flag). `.git/`, `.build/`, `node_modules/` are skipped.
- **MODIFIED** `SkillResolver` symlink-escape coverage: `assertNoSymlinkEscape` now
  applies to local skills too (today it runs only for remote-cloned skills) — a small
  pre-existing gap closed in passing now that the resolver reads multiple files from
  local skill dirs.
- **NEW** `### Requirement: Supporting Markdown Inlining` in the `skill-resolution`
  capability spec, with scenarios covering both layout conventions, ordering, mixed
  files, symlink-escape, and the body-file-not-double-inlined invariant.
- No schema change: `SkillConfig`, `ResolvedSkill`, `PromptBuilder` untouched. The
  `<<<BATON_UNTRUSTED_SKILLS>>>` security boundary is preserved — inlined references
  ride inside the existing untrusted block exactly like the main body.

## Impact

- Affected specs: `skill-resolution` (one new requirement; existing requirements unchanged).
- Affected code: `Sources/BatonKit/Skill/SkillResolver.swift`,
  `Tests/BatonKitTests/SkillResolverTests.swift`.
- Affected users: any `baton.toml` referencing a multi-file skill (local or remote) now
  gets the supporting markdown automatically in the review prompt. Existing single-file
  skills are unaffected — the resolver finds no extra `*.md` and the body is exactly as
  before.
- Out of scope: parsing markdown links inside `SKILL.md` and following them selectively;
  inlining non-markdown content (`scripts/`, `assets/`); per-review opt-out of references.
