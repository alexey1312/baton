## Why

`swift-jinja` has been a declared, linked dependency since the MVP (Decision 4: "swift-jinja for report templates only") but is never imported — all report rendering is hard-coded string-building. Users cannot customize how findings are presented in the human-facing report. This change activates the reserved dependency for its intended purpose: user-customizable report templates, without touching the security-critical prompt scaffold.

## What Changes

- Render the human-facing local formats — the `render` `markdown` report and the `learn` rolling-PR-body markdown — from Jinja templates instead of hard-coded strings.
- Ship bundled default templates (embedded string constants) that reproduce the previous built-in rendering's content and structure (snapshot-locked), so this is a content-preserving refactor by default.
- Allow a user to override a template via a new `[render]` config block (`markdown_template`, `learn_pr_body_template`) or a `--template <path>` flag on `render`.
- Keep all GitHub payload bodies (`github-review`, `check-run`, `github-summary`), `json`, and `terminal` built in code, so the `<!-- baton:finding -->` marker, the 👍/👎 affordance, and the collapsible AI-instructions block (which `learn` and dedupe depend on) cannot be removed by a user template.
- Fail with a typed `RenderError.templateInvalid` (carrying a `recoverySuggestion`) when a configured template has a syntax error.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `rendering`: adds user-customizable Jinja templates for the human-facing local report formats, with bundled defaults preserving current output and the GitHub-format marker/affordance/AI-block invariants held in code.

## Impact

- **Dependency**: `swift-jinja`'s `Jinja` product (already linked to BatonCLI) gets its first importer.
- **Config**: new `[render]` block (template paths, relative to the config directory), resolved closest-wins like `[defaults]`.
- **BatonCLI**: new `DefaultTemplates`, `TemplateContext`, `ReportTemplating`; `Renderer.markdown` and `LearnPreview.markdown` route through Jinja; `RenderError.templateInvalid`; `--template` flag on `RenderCommand` (rejected for GitHub formats).
- **BatonKit**: `RenderConfig` schema + `EffectiveRender` resolution.
- **No breaking changes**: default output is unchanged; GitHub/json/terminal formats are untouched.
