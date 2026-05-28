# Tasks: Inline supporting markdown alongside resolved skills

## 1. SkillResolver implementation

- [ ] 1.1 Extract `assertNoSymlinkEscape` so both `resolveLocal` and `resolveRemote` call it
- [ ] 1.2 Add `inlineSupportingMarkdown(into:skillDir:skillName:)` helper: recursive walk of `*.md`, skip body file, skip `.git/` / `.build/` / `node_modules/`, alphabetical sort by relative path, symlink-escape per file, `## Reference: <relative-path-without-extension>` header
- [ ] 1.3 Call the helper from `resolveLocal` (after `readBody`) and `resolveRemote` (after the existing main-body symlink-escape check)

## 2. Test coverage

- [ ] 2.1 Codex-layout (local): `SKILL.md` + `references/a.md` + `references/b.md` → both inlined as `## Reference: references/{a,b}`
- [ ] 2.2 Claude-layout (local): `SKILL.md` + `reference.md` at root + `examples/sample.md` → headers in alphabetical relative-path order
- [ ] 2.3 Remote happy path: Codex-style references in a cloned remote skill
- [ ] 2.4 No supporting markdown: body equals raw SKILL.md content, no `## Reference:` headers
- [ ] 2.5 Mixed files: `notes.txt`, `scripts/foo.py`, `assets/logo.png` ignored; only `*.md` inlined
- [ ] 2.6 Deterministic order: files written in non-alphabetical order are still inlined alphabetically
- [ ] 2.7 Symlink escape rejected for a reference file (local), and main-body symlink escape rejected for a local skill (gap closed in passing)
- [ ] 2.8 README.md fallback still inlines supporting markdown when no SKILL.md is present
- [ ] 2.9 Body file never double-inlined (no `## Reference: SKILL` or `## Reference: README` entry)

## 3. Spec delta

- [ ] 3.1 `openspec/changes/inline-skill-references/specs/skill-resolution/spec.md` adds `### Requirement: Supporting Markdown Inlining` with scenarios mirroring tasks 2.1–2.9
- [ ] 3.2 `openspec validate inline-skill-references --strict` passes

## 4. Dogfood

- [ ] 4.1 Add temporary `.claude/skills/swift/references/concurrency.md` (Codex layout) with one specific actor-isolation rule
- [ ] 4.2 Add temporary `.claude/skills/swift/examples/forbidden-patterns.md` (Claude layout) with one anti-pattern rule
- [ ] 4.3 `mise run build:release`, then `.build/release/baton review --model sonnet` against `examples/StyleSample.swift`
- [ ] 4.4 Confirm `.baton/runs/latest/root--swift-style.prompt.md` contains BOTH `## Reference: examples/forbidden-patterns` and `## Reference: references/concurrency` inside the `<<<BATON_UNTRUSTED_SKILLS>>>` block, alphabetically
- [ ] 4.5 Confirm `baton show latest` lists findings citing the two new reference rules
- [ ] 4.6 Remove the temporary reference files if they were throwaway demos

## 5. Validation gates

- [ ] 5.1 `mise run format-check` — clean
- [ ] 5.2 `mise run lint` — swiftlint --strict + actionlint clean
- [ ] 5.3 `mise run test 2>&1 | xcsift -f toon` — no regressions
- [ ] 5.4 `mise run test:filter SkillResolverTests 2>&1 | xcsift -f toon` — all new cases green
- [ ] 5.5 `openspec validate inline-skill-references --strict` — passes
