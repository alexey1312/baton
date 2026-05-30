# Changelog

All notable changes to this project will be documented in this file.

## [0.1.2] - 2026-05-29

### Bug Fixes

- Untrack accidental agent-worktree gitlink; ignore .claude/worktrees/ by @alexey1312


### Features

- **learn**: Make author-reaction exclusion configurable (count_author_reactions) by @alexey1312


### Other

- Remove second learn-signal probe by @alexey1312


### Testing

- Second learn-signal probe (force-unwrap) for a 2-thread theme  by @alexey1312 in [#3](https://github.com/alexey1312/baton/pull/3)


## [0.1.1] - 2026-05-29

### Bug Fixes

- **learn**: Align agent pass to blick's JSON-proposal model (fixes error_max_turns) by @alexey1312


### Miscellaneous Tasks

- Dogfood baton review on PRs + wire learn to the claude agent by @alexey1312

- Accept either ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN for the claude agent by @alexey1312

- Fix git 'dubious ownership' in containerized review/learn; drop redundant base fetch by @alexey1312

- Run review/learn on ubuntu-latest non-root; install baton via mise github backend by @alexey1312

- Grant attestations:read so mise can verify baton's SLSA provenance on install by @alexey1312


### Other

- Remove learn-signal probe by @alexey1312


### Testing

- Temporary probe to give baton learn a merged-PR signal  by @alexey1312 in [#2](https://github.com/alexey1312/baton/pull/2)


## [0.1.0] - 2026-05-29

### Bug Fixes

- **ci**: Force bash + pipefail for piped mise tasks (Linux lint job) by @alexey1312

- **ci**: Fall back to plain swift when xcsift is absent (Linux) by @alexey1312

- **windows**: Cross-platform process launch; gate POSIX-only tests by @alexey1312

- **windows**: Gate POSIX-path preflight test behind #if !os(Windows) by @alexey1312

- **cli**: Give stats / show informative errors when empty by @alexey1312

- **db**: Summary() no longer crashes with --review/--scope filters by @alexey1312

- **record**: Surface manifest.json encode failures instead of writing empty bytes by @alexey1312

- **cli**: Propagate git revParse(HEAD) failures instead of swallowing them by @alexey1312

- **db**: Throw when meta.schema_version is unparseable instead of returning 0 by @alexey1312

- **db**: Left-zero-pad short repo/finding hashes and centralise FNV-1a by @alexey1312

- **cli**: Guard TextTable.bar against negative values; group formatNumber by @alexey1312

- **skill-resolution**: Exclude README from inlining; reject symlinked .md escapes by @alexey1312

- **render**: Surface failed/timed-out tasks in terminal and markdown by @alexey1312

- **gemini**: Unwrap the JSON output envelope before parsing findings by @alexey1312

- **diff**: Correct untracked-patch line count, binary detection, diff_budget clamp by @alexey1312

- **agent**: SIGKILL escalation on timeout + lock ProcessExecutor stream reads by @alexey1312

- **agent**: Tolerate mistyped finding fields; route agent JSON through JSONCodec by @alexey1312

- **db**: Run duration as concurrent wall-clock span; bind/clamp history --limit by @alexey1312

- **diff,scope**: Surface git/FS failures instead of silently reviewing less by @alexey1312

- **skill**: Enforce full-SHA pins, bound single-file inlining, thread learn budget by @alexey1312

- **agent**: Scrub GitHub credentials from spawned agent environments by @alexey1312

- **learn**: Check agent exit, parse git status -z, frame untrusted prompt input by @alexey1312

- **cli**: Valid JSON on empty review, honor NO_COLOR/FORCE_COLOR, ordered stdout, wide-char tables by @alexey1312

- **agent**: Run the timeout terminator on a dedicated queue so it fires under pool starvation by @alexey1312

- **agent**: Drive ProcessExecutor completion off terminationHandler so timeouts survive GCD pool starvation by @alexey1312

- **agent**: Run ProcessExecutor on dedicated threads (waitUntilExit), not terminationHandler by @alexey1312

- **agent**: Shorten SIGKILL grace to 1s so the deadline is enforced on Linux by @alexey1312


### Build System

- **tooling**: Add mise tasks and lint/format configs (task 1.3) by @alexey1312

- **hooks**: Add hk.pkl + .githooks pre-commit and commit-msg (task 12.2) by @alexey1312

- **mise**: Commit mise.lock; openspec validate --strict passes (tasks 12.1, 11.1, 11.2) by @alexey1312

- **ci**: Bump all GitHub Actions to latest major versions by @alexey1312


### Documentation

- **openspec**: Bootstrap Baton with MVP specification (add-baton-mvp) by @alexey1312

- **openspec**: Add 👍/👎 usefulness signal + comment footer marker by @alexey1312

- **openspec**: Clarify swift-jinja is report/presentation templates only by @alexey1312

- Add DocC catalog (Baton.md + GettingStarted) and cliff.toml (tasks 12.5, 12.8) by @alexey1312

- **openspec**: Mark tasks 11.3 and 12.3 complete (83/83) by @alexey1312

- Add project CLAUDE.md (module boundaries, commands, gotchas) by @alexey1312

- Make README concise (features + compact quick start) by @alexey1312

- Humanize README (drop templated feature list and metaphor framing) by @alexey1312

- Record Windows portability in CLAUDE.md; trim README notes by @alexey1312

- Expand DocC + restructure README along xcsift's outline by @alexey1312

- **claude**: Note type_body_length limit, manual e2e, skill inlining model by @alexey1312

- **openspec**: Add `learn` self-improvement mode change by @alexey1312

- **openspec**: Refine learn change after spec review by @alexey1312

- **render**: Clarify templating parity is content/structure + snapshot-locked by @alexey1312

- **claude**: Note GHApiClient reuse, root-only config blocks, render/jinja split, openspec CLI flow by @alexey1312

- **claude**: Note ConfigParser.knownX on schema changes, multi-scope/multi-agent e2e tips by @alexey1312


### Features

- **scaffold**: Bootstrap SPM package with BatonKit/BatonForge/BatonCLI by @alexey1312

- **config-cascade**: Baton.toml schema, parsing, discovery, cascade (phase 2) by @alexey1312

- **support**: Add Glob matcher for review filters and skill allowlist by @alexey1312

- **diff-routing**: Base resolution, diff collection, routing, chunking (phase 3) by @alexey1312

- **agent-execution**: ProcessExecutor, AgentRunner adapters, isolation (phase 4) by @alexey1312

- **skill-resolution**: Local + SHA-pinned remote skills with security (phase 5) by @alexey1312

- **review-orchestration**: PromptBuilder, orchestrator, run records (phase 6) by @alexey1312

- **presentation**: Shared GitHub finding/check-run formatting in BatonKit by @alexey1312

- **rendering**: Terminal/markdown/json + github render formats (phase 8) by @alexey1312

- **cli**: Init/review/config/render/doctor commands + preflight (phase 9) by @alexey1312

- **github-publish**: GitHubForge via gh CLI + publish command (phase 7) by @alexey1312

- **skill**: Add disambiguation/immutability examples to swift style guide by @alexey1312

- **db**: Add SQLite-backed BatonDatabase + migrations v1 by @alexey1312

- **db**: Add Records DTOs, RepoIdentity, and RunDatabaseStore by @alexey1312

- **cost**: Plumb agent usage and a model price table by @alexey1312

- **cost**: Best-effort usage extraction for codex/gemini/opencode by @alexey1312

- **review**: Thread durationMs and usage through ReviewTaskResult by @alexey1312

- **db**: Hook RunDatabaseStore into the review flow by @alexey1312

- **db**: Add stats / history repositories and CLI render helpers by @alexey1312

- **cli**: Baton stats / history / show subcommands by @alexey1312

- **cost**: Thread the resolved model into agent usage extraction by @alexey1312

- **skill-resolution**: Inline supporting *.md alongside SKILL.md across all skill layouts by @alexey1312

- **skill-resolution**: Enforce byte budget and harden reference inlining by @alexey1312

- **skill**: Vendor swift-concurrency skill alongside swift-style by @alexey1312

- **skill-resolution**: Make references byte budget configurable by @alexey1312

- **learn**: Add `learn` self-improvement mode by @alexey1312

- **agent**: Hermetic sandbox mode (default on) to isolate agent CLIs by @alexey1312

- **publish**: Auto-resolve Baton's own outdated review threads (opt-in) by @alexey1312

- **render**: User-overridable Jinja templates for the markdown report and learn PR body by @alexey1312

- **config**: Per-review [[reviews]].agent override; fix inherited skill/prompt_file path anchoring by @alexey1312


### Miscellaneous Tasks

- Add CI, DocC-deploy, and release workflows + README (phase 12) by @alexey1312

- **openspec**: Archive add-baton-mvp; sync 78 requirements into openspec/specs by @alexey1312

- Add root baton.toml using local Airbnb Swift style skill via Claude Haiku by @alexey1312

- Apply swiftformat to ShowCommand/StatsCommand by @alexey1312

- **setup**: Add `mise run setup` task to install git hooks by @alexey1312

- **gitignore**: Ignore .baton/ (run records + local history db) by @alexey1312

- **openspec**: Archive add-learn-mode; sync learn + config-cascade specs by @alexey1312

- Drop the best-effort Windows build job by @alexey1312

- **openspec**: Archive auto-resolve-outdated-threads and templated-report-rendering by @alexey1312

- **release**: Gate Homebrew tap update on a public repo by @alexey1312

- **release**: Drop the Windows release asset (matches the CI build) by @alexey1312

- **release**: Install Swift 6.3 via mise on the macOS build by @alexey1312

- **release**: Build macOS natively (arm64), drop the universal --arch build by @alexey1312

- **release**: Grant pull-requests:read so git-cliff notes don't 403 by @alexey1312


### Other

- Fix formatting of license link in README by @alexey1312


### Refactor

- **baton**: Simplify review prompt now that skill carries examples by @alexey1312

- **db**: Return recordRun errors directly instead of a shared ErrorBox by @alexey1312

- **cost**: Use JSONCodec in Pricing per CLAUDE.md JSON policy by @alexey1312

- **learn**: Harden delivery, GitHub decoding, and config from review by @alexey1312

- **forge**: Drop dead LiveGHRunner.isInstalled() by @alexey1312

- **forge**: Extract GHApiClient; decouple learn delivery; test retry paths by @alexey1312


### Testing

- **config**: Cover the malformedTOML decode branch by @alexey1312

- **process**: Remove pool-saturation stress test that destabilized concurrent tests by @alexey1312



