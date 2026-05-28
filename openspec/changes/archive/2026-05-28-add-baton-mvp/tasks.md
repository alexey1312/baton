# Tasks: Bootstrap Baton — MVP + GitHub publish

## 1. Project scaffolding

- [x] 1.1 Create `Package.swift` (Swift 6.3, executable `baton`, targets `BatonKit`/`BatonForge`/`BatonCLI` + tests)
- [x] 1.2 Add dependencies: swift-argument-parser, swift-log, Noora, mattt/swift-toml, swift-yyjson, swift-jinja
- [x] 1.3 Add `mise.toml` (swift 6.3, swiftlint, swiftformat, xcsift, gh, git-cliff) and tasks (build/test/lint/format)
- [x] 1.4 Port ExFig scaffolding: `TerminalUI/` (Noora wrapper, `TTYDetector`, output coordination), logger bootstrap
- [x] 1.5 Port error model: `LocalizedError` + `recoverySuggestion` + formatter
- [x] 1.6 CI workflows: build-macos, build-linux (swift:6.3), build-windows (best-effort), lint
- [x] 1.7 Windows spike: verify `mattt/swift-toml` builds; record fallback to `LebJe/TOMLKit` if needed

## 2. config-cascade

- [x] 2.1 Define `baton.toml` Codable schema (`[agent]`, `[defaults]` incl. `timeout` (default 600), `[[skills]]`, `[[reviews]]`, `[security]`)
- [x] 2.2 Parse with swift-toml; validation with `recoverySuggestion` on malformed config
- [x] 2.3 `discover`: walk tree, collect every `baton.toml`, skip `.git/node_modules/target/dist/build/.venv`
- [x] 2.4 `inherit`: ancestor-chain merge — agent (block), skills (union+closest), defaults (field), reviews (inherit+override+disable)
- [x] 2.5 Auto-discover local skills (`.baton/skills/<name>/SKILL.md`), prepended before explicit entries
- [x] 2.6 Track provenance per effective value
- [x] 2.7 Tests: cascade rules, reviews inheritance/disable, provenance

## 3. diff-routing

- [x] 3.1 `base` resolution: `--base` > scope default > `HEAD`
- [x] 3.2 Collect diff (`git diff --find-renames` + untracked) with careful `diff --git` header parsing
- [x] 3.3 `owner`: deepest-ancestor scope; drop files outside any scope
- [x] 3.4 `grouping`: partition diff by scope
- [x] 3.5 focus-mode: detect PR context from GH Actions env; recover previous review SHA from PR (Baton check runs, fallback `baton:last-reviewed` marker); compute focus diff
- [x] 3.6 Structural chunking by file/hunk when scope diff exceeds `diff_budget` (never mid-file)
- [x] 3.7 `glob` filtering of files to a review within a scope
- [x] 3.8 Tests: routing, grouping, chunking boundaries, glob filters, focus-mode

## 4. agent-execution

- [x] 4.1 `ProcessExecutor` (concurrent stderr read, termination handler before run, timeout) — port from ExFig
- [x] 4.2 `AgentRunner` protocol + uniform `makeInvocation` (binary/args honored for ALL agents — blick PR #20)
- [x] 4.3 Adapters: claude, codex, gemini, opencode — pin per-CLI headless flags (claude `--print --output-format json --max-turns 1 --dangerously-skip-permissions`; gemini `--approval-mode=yolo --skip-trust`; opencode `run`), prompt via stdin, model flag (+ strip `provider/` prefix), parser
- [x] 4.4 Isolation: fresh temp working dir (not the repo tree, no working-tree writes) + prompt instruction to use only provided material; `context = "repo"` adds a repo copy; network egress NOT blocked (agent needs its model)
- [x] 4.6 Enforce per-invocation `timeout` (from effective `[defaults].timeout`, default 600s) in `ProcessExecutor`
- [x] 4.5 Tests: invocation building (binary/args override, args rejection cases), prompt delivery, parsing

## 5. skill-resolution

- [x] 5.1 Local sources (`./ ../ / ~`) relative to declaring `baton.toml`
- [x] 5.2 Remote `owner/repo` + `owner/repo/skill` (skills.sh convention) shallow-clone into cache (`BATON_CACHE_DIR`)
- [x] 5.3 Enforce SHA `ref` for remote skills (unless `--allow-unpinned`); check `allowed_skill_sources`
- [x] 5.4 Read body from `SKILL.md`/`README.md`; embed in delimited untrusted block in the prompt
- [x] 5.5 Tests: resolution forms, pin enforcement, allowlist, untrusted-block isolation

## 6. review-orchestration

- [x] 6.1 `PromptBuilder`: role + review instructions + isolated skills block + output-format + diff
- [x] 6.2 Orchestrator: one task per `(scope, review)`; sliding-window concurrency (`max_concurrency`)
- [x] 6.3 Response parser: plain JSON → fenced → brace-balanced (string-literal aware) → findings
- [x] 6.4 `RunRecord`: write `<scope>--<review>.json`, `.log`, `.prompt.md`, `manifest.json` (records `base` + review-time head SHA), `latest`
- [x] 6.5 Severity model (low<medium<high) and `fail_on` exit semantics
- [x] 6.6 Tests: prompt assembly, concurrency limit, parser robustness, run-record layout

## 7. github-publish

- [x] 7.1 `Forge` protocol; `GitHubForge` via `gh` CLI (preflight: `gh` present + authenticated)
- [x] 7.2 PR-context detection (repo, PR number, head SHA) from GH Actions env + `--gh-repo`/`--head-sha`/`--pr` overrides; no PR number → post only check runs; persist reviewed SHA (check runs + `baton:last-reviewed` marker)
- [x] 7.3 Post PR review (event COMMENT, empty body, inline comments in diff hunks) — resolvable
- [x] 7.4 Create one Check Run per `(scope, review)`; conclusion failure/success/neutral by severity
- [x] 7.5 Resolve review threads (GraphQL `resolveReviewThread`); dedupe already-posted comments
- [x] 7.6 Tests: payload building, dedupe, conclusion mapping (mock `gh`)

## 8. rendering

- [x] 8.1 `render` formats: terminal, markdown, json (local)
- [x] 8.2 `render` formats: github-review, check-run, github-summary (from a saved run, no LLM); github-review/check-run require `--head-sha`
- [x] 8.3 Severity badges, file/line, collapsible "Instructions for AI agents" block
- [x] 8.4 Tests: each format from a fixture run record

## 9. cli

- [x] 9.1 `@main baton` (AsyncParsableCommand) + global options (`--verbose`, `--quiet`)
- [x] 9.2 `init` — write starter `baton.toml` (`--agent`, `--model`, `--path`, `--force`)
- [x] 9.3 `review [name]` — `--base --agent --model --json --max-concurrency --repo --allow-unpinned`
- [x] 9.4 `config [--explain]` — print effective per-scope config with provenance
- [x] 9.5 `render --format` and `publish` over the latest/selected run
- [x] 9.6 `doctor` — check git / gh / configured agent binaries (present + authenticated), report status
- [x] 9.7 Preflight: `review` checks the agent binary; `publish` checks `gh`; fail fast with a recovery suggestion
- [x] 9.8 Tests: argument parsing, end-to-end on a fixture monorepo (mock agent + mock `gh`)

## 10. Robustness, edge cases & tool preflight

- [x] 10.1 Tool preflight + `doctor`: distinct errors for missing/unauthenticated agent, missing `gh`, missing `git`
- [x] 10.2 config: no `baton.toml` found; no resolvable `[agent]`; duplicate review/skill names; review references undefined skill; `disabled_reviews` unknown name (no-op); unknown TOML keys (lenient warn)
- [x] 10.3 scope discovery: do not follow symlinked directories; never escape the repo root
- [x] 10.4 diff: invalid/unfetched base ref; empty diff (exit 0); rename across scope boundary (new path wins); binary & deleted files; quoted/space/unicode paths in `diff --git` headers
- [x] 10.5 chunking: single file > budget → by-hunk fallback → whole-hunk + `truncated` flag + warning
- [x] 10.6 focus-mode: previous review SHA unreachable (force-push) → fall back to full base diff + warn
- [x] 10.7 agent: binary missing / non-zero exit / exit-0-with-empty-stdout (auth/billing error on stderr) / unauthenticated / user `args` conflicting with required flags
- [x] 10.8 skills: clone failure, missing `ref`, ref not found, missing `subpath`, symlink escape, `allowed_skill_sources` glob semantics, git unavailable
- [x] 10.9 orchestration: dedupe findings merged across chunks; clamp/drop invalid finding fields; sanitize scope/review names in artifact filenames; disk-write failure
- [x] 10.10 publish: token without write permission (fork PR), Check Run needs GitHub App token (local PAT) → degrade to PR-review-only + warn, rate limit / 5xx with backoff, stale head SHA, comment-count limits, idempotent re-run
- [x] 10.11 render: missing/corrupt run record; dangling `latest`; zero findings emits valid output

## 11. Validation

- [x] 11.1 `openspec validate add-baton-mvp --strict` passes
- [x] 11.2 `swift build` / `swift test` green on macOS and Linux (piped through xcsift)
- [x] 11.3 README quick start verified against a sample monorepo fixture

## 12. Tooling, CI, documentation & distribution (port from ExFig)

- [x] 12.1 `mise.toml`: pin tools (swift 6.3, swiftlint, swiftformat, dprint, hk, actionlint, git-cliff, xcsift) + tasks (`build`/`test`/`lint`/`format`/`format-check`/`docs`/`changelog`); commit `mise.lock`
- [x] 12.2 `hk.pkl` + `.githooks/`: `pre-commit` (swiftformat, swiftlint --strict, dprint, actionlint; auto-fix + restage) and `commit-msg` (conventional commits); delegate via `mise x -- hk run`; honor `HK=0`; align hk pin between `mise.toml` and `hk.pkl`
- [x] 12.3 Linter/formatter configs: `.swiftlint.yml`, `.swiftformat`, `dprint.json` (drop ExFig PKL/llms-specific bits)
- [x] 12.4 CI `ci.yml`: triggers push `main` + PR, concurrency-cancel; `lint` job (`format-check` + `lint` + `actionlint`) → `build-macos` + `build-linux` (swift:6.3, xcsift, `.build` cache) + `build-windows` (best-effort)
- [x] 12.5 DocC: `Baton.docc` catalog on the executable target; `swift-docc-plugin` (`#if !os(Windows)`); `docs` task generates static-hosting site (base path `baton`) + redirect `index.html`
- [x] 12.6 `deploy-docc.yml`: build + deploy DocC to GitHub Pages on `v*` tags + manual dispatch (`pages: write`, `id-token: write`)
- [x] 12.7 `release.yml`: on `v*` tags build macOS universal (`lipo` arm64+x86_64) + Linux (static stdlib) + Windows (best-effort); set version into the command source; `git-cliff` notes; `softprops/action-gh-release` with archives; prerelease when tag has `-`
- [x] 12.8 `cliff.toml`: conventional-commit groups; remote `owner/repo` = your repo
- [x] 12.9 `update-version` job: regenerate `CHANGELOG.md` + commit to `main` (non-prerelease only)
- [x] 12.10 `update-homebrew` job: compute SHA256 of macOS/Linux archives, bump `Formula/baton.rb` in `alexey1312/homebrew-tap` (secret `HOMEBREW_TAP_TOKEN`); non-prerelease only
- [x] 12.11 README install docs: `mise use -g github:alexey1312/swift-baton` and `brew install alexey1312/tap/baton`
- [x] 12.12 No code signing/notarization in MVP (document as future, as in ExFig)
