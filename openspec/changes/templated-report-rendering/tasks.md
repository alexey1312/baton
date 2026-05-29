## 1. Golden snapshot (lock current output)

- [x] 1.1 Add exact-equality snapshot tests for `Renderer.markdown` (finding, no-line, failed task, empty); run against the current code to confirm the goldens, then re-confirm after the refactor (templated output normalizes to one trailing newline; empty/failed stay byte-identical).

## 2. Templating infrastructure (BatonCLI)

- [x] 2.1 Create `Render/ReportTemplating.swift`: `import Jinja`; `render(template:context:path:)` mapping Jinja errors to `RenderError.templateInvalid`; `userTemplate(path:configDir:)` loader.
- [x] 2.2 Create `Render/TemplateContext.swift`: build `[String: Value]` from `LoadedRun`/`Finding` and from `LearnRunResult`/`ScopeProposal`.
- [x] 2.3 Create `Render/DefaultTemplates.swift`: embedded `.j2` constants for the markdown report and the learn PR body.
- [x] 2.4 Add `RenderError.templateInvalid(path:detail:)` and `.templateNotSupported(format:)`, each with a `recoverySuggestion`.

## 3. Config (BatonKit)

- [x] 3.1 Add `RenderConfig` (`markdown_template`, `learn_pr_body_template`) + `render: RenderConfig?` on `BatonConfig` in `Schema.swift`.
- [x] 3.2 Add `EffectiveRender` and resolve it root-only in `EffectiveConfig.swift` + `Cascade.resolveRender`.

## 4. Wire rendering through templates (BatonCLI)

- [x] 4.1 Route `Renderer.markdown` through `ReportTemplating` (user override path if set, else the embedded default); `terminal`/`json`/github formats unchanged.
- [x] 4.2 Route `LearnPreview.markdown` through `ReportTemplating`; thread the learn template override via `LearnCoordinator`.
- [x] 4.3 Add `--template <path>` to `RenderCommand`; reject it for non-markdown formats (`RenderFormat.supportsTemplate`); resolve `[render]` config when the flag is absent; show `[render]` in `baton config`.

## 5. Tests and verification

- [x] 5.1 Parity: templated default output equals the golden snapshots (snapshot-locked).
- [x] 5.2 Custom template override produces the custom output; an invalid template throws `RenderError.templateInvalid` (specific-case do/catch).
- [x] 5.3 Only `markdown` is templatable (`supportsTemplate`); GitHub bodies still contain the marker (existing `githubFormats` test).
- [x] 5.4 `mise run format` → `mise run lint` → `mise run test` (through xcsift) green.
- [x] 5.5 `openspec validate templated-report-rendering --strict` passes.
- [x] 5.6 Manual: `baton render --format markdown` (default), then with `--template`.
