## Context

All report rendering is hard-coded string-building in two places: `GitHubPresentation` (BatonKit, shared by `render` and `publish`) and `Renderer`/`LearnPreview` (BatonCLI). `swift-jinja`'s `Jinja` product is linked only to BatonCLI and never imported. MVP Decision 4 reserved swift-jinja for report templates only (the prompt scaffold stays in code for its security boundary). The `rendering` spec mandates that every GitHub comment carry the `<!-- baton:finding -->` marker and that inline comments carry a 👍/👎 affordance — contracts that `learn` and dedupe depend on.

## Goals / Non-Goals

**Goals:**
- Activate swift-jinja for the human-facing local report formats (`render` markdown + `learn` PR-body markdown).
- Bundled defaults reproduce current output byte-for-byte (pure refactor); user overrides allowed.
- Preserve the marker/affordance/AI-block invariants for GitHub formats.
- Keep module boundaries (BatonKit no-UI; Jinja stays in BatonCLI).

**Non-Goals:**
- Templating the GitHub payload bodies (`github-review`/`check-run`/`github-summary`), `json`, or `terminal`. (Shape B — a later change — would move templating into BatonKit and force-inject the invariants; out of scope here.)
- Templating the prompt scaffold (Decision 4 keeps it in code).

## Decisions

### Decision 1: Shape A — template only the local human-facing markdown
GitHub bodies stay code-built in `GitHubPresentation`, so a user template cannot drop the marker/affordance/AI-block. Jinja stays in BatonCLI (no module-boundary change). *Alternative (Shape B):* template everything including GitHub bodies with forced marker injection — larger blast radius on the publish write-path and BatonKit boundary; deferred.

### Decision 2: Bundled defaults as embedded string constants, not `Bundle.module`
The project uses zero SwiftPM resources today and ships relocatable single binaries (macOS/Linux/Windows). `Bundle.module` resource lookup is fragile for a moved/standalone binary (especially Windows). Embedded `.j2` string constants are portable, zero-IO, and snapshot-friendly. Only user overrides are read from the filesystem (a path the user controls). *Alternative:* SwiftPM resources — rejected for binary-portability risk.

### Decision 3: Content/structure parity locked by a snapshot test
A snapshot test asserts the templated default's exact output for representative runs (empty, failed task, finding), locking the rendering. The default reproduces the prior built-in output's content and structure; the templated output normalizes to a single trailing newline across all branches (the empty/failed branches were already byte-identical). Whitespace is controlled with `Template.Options(lstripBlocks:trimBlocks:)`. *Alternative:* chasing exact byte-parity with the prior irregular join-whitespace — rejected; it added brittleness for no value, since the markdown report is human-facing only and existing tests assert content via `.contains`.

### Decision 4: Config + flag, closest-wins like `[defaults]`
A `[render]` block (`markdown_template`, `learn_pr_body_template`; paths relative to the config dir) resolves closest-wins; a `--template` flag on `render` overrides it for the selected format and is rejected for GitHub formats. *Alternative:* per-format flags only — rejected; config cascade matches the rest of the tool.

### Decision 5: Typed error for a bad template; defaults can never ship broken
A user template syntax error maps `Jinja`'s thrown error to `RenderError.templateInvalid(path:detail:)` with a `recoverySuggestion`. The bundled defaults are covered by the parity snapshot test, so they can never ship broken.

## Risks / Trade-offs

- **[Jinja whitespace drift breaks byte-for-byte parity]** → The snapshot test is the gate; iterate `trimBlocks`/`{%- -%}` until it matches. Existing markdown tests use `.contains`, so they stay green regardless.
- **[Autoescaping mangles literal HTML in markdown]** → Do not apply an `escape` filter; the markdown contains literal `<details>`/`<sub>` and must render raw. (Another reason GitHub bodies, which carry the HTML AI-block, stay code-built.)
- **[A custom template omits content a downstream reader expects]** → Acceptable for the local human-facing formats (no machine contract). The machine-contract formats (GitHub) are not templatable in Shape A.
