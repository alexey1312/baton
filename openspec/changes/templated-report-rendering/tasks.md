## 1. Golden snapshot (lock current output)

- [ ] 1.1 Add exact-equality snapshot tests for the current `Renderer.markdown` (mixed severities, no-line finding, failed task, empty) and `LearnPreview.markdown`; run against the current code to confirm the goldens match today's output.

## 2. Templating infrastructure (BatonCLI)

- [ ] 2.1 Create `Render/ReportTemplating.swift`: `import Jinja`; `render(template:context:) throws -> String` mapping Jinja errors to `RenderError.templateInvalid`.
- [ ] 2.2 Create `Render/TemplateContext.swift`: build `[String: Value]` from `LoadedRun`/`Finding` and from `LearnRunResult`/`ScopeProposal`.
- [ ] 2.3 Create `Render/DefaultTemplates.swift`: embedded `.j2` constants for the markdown report and the learn PR body, authored to reproduce current output byte-for-byte.
- [ ] 2.4 Add `RenderError.templateInvalid(path:detail:)` with a `recoverySuggestion`.

## 3. Config (BatonKit)

- [ ] 3.1 Add `RenderConfig` (`markdown_template`, `learn_pr_body_template`) + `render: RenderConfig?` on `BatonConfig` in `Schema.swift`.
- [ ] 3.2 Add `EffectiveRender` and resolve it closest-wins in `EffectiveConfig.swift` + `Cascade.swift`.

## 4. Wire rendering through templates (BatonCLI)

- [ ] 4.1 Route `Renderer.markdown` through `ReportTemplating` (user override path if set, else the embedded default); `terminal`/`json`/github formats unchanged.
- [ ] 4.2 Route `LearnPreview.markdown` through `ReportTemplating`.
- [ ] 4.3 Add `--template <path>` to `RenderCommand`; reject it for `github-review`/`check-run`/`github-summary`; resolve `[render]` config when the flag is absent.

## 5. Tests and verification

- [ ] 5.1 Parity: templated default output equals the golden snapshots (byte-for-byte).
- [ ] 5.2 Custom template override produces the custom output; an invalid template throws `RenderError.templateInvalid`.
- [ ] 5.3 `--template` with a GitHub format is rejected with a typed error; GitHub bodies still contain the marker.
- [ ] 5.4 `mise run format` → `mise run lint` → `mise run test` (through xcsift) green.
- [ ] 5.5 `openspec validate templated-report-rendering --strict` passes.
- [ ] 5.6 Manual: `baton render --format markdown` (default == prior output), then with `--template`.
