# Design: Baton MVP + GitHub publish

## Context

Baton is a Swift 6.3 CLI that orchestrates AI code review across a monorepo. It is a reimagining of
[tuist/blick](https://github.com/tuist/blick) (Rust). blick's core idea is decentralized, cascading
review configuration: every subtree may declare a `blick.toml`; a PR diff is routed to the deepest
owning subtree; for each `(scope, review)` an external coding CLI is run against that subtree's slice
of the diff; findings are posted to the PR as resolvable review comments and Check Runs.

Baton keeps that idea and is built on the proven scaffolding of the ExFig project (Swift 6.3 design
asset exporter): an actor-based sliding-window orchestrator (`BatchExecutor` + `parallelMapEntries`),
a centralized subprocess runner, a terminal-UI stack (Noora + `TTYDetector` + output coordination),
and an error model where every error carries a `recoverySuggestion`.

**Stakeholders**: monorepo teams (especially multi-stack) using GitHub PR flow with an installed
coding CLI (claude/codex/gemini/opencode).

**Constraints**:
- Configs may be read from arbitrary, possibly untrusted repositories/forks (CI on fork PRs).
- The tool contains no LLM; it drives external CLIs as subprocesses.
- macOS + Linux primary; Windows best-effort.

## Goals / Non-Goals

**Goals (this change)**
- Discover per-scope `baton.toml` and compute the effective config via cascade, with provenance.
- Route a PR diff to scopes; run `(scope, review)` tasks concurrently against external agents.
- Produce structured findings; render locally (terminal/markdown/json) and publish to GitHub.
- Deliver four improvements over blick: cross-file context, glob filters + inherited reviews,
  skill security, structural diff chunking.
- Uniform agent invocation: `binary` and `args` overrides work for **every** agent.

**Non-Goals (future changes)**
- `learn` self-improvement mode.
- Non-GitHub forges (GitLab/Bitbucket).
- A native GitHub API client (this change uses the `gh` CLI).
- User-customizable prompt *scaffold* templates (the scaffold is built in code; only review
  instruction text and skills are user data).

## Key Decisions

### Decision 1: Configuration language is TOML, not PKL

**What**: `baton.toml` parsed with `mattt/swift-toml` (Codable, toml++). The cascade is computed in
code by walking the directory tree, not by config-language features.

**Why**:
- **Security through pure data.** Baton reads configs from arbitrary repos/forks in CI. PKL is a
  programming language; reading untrusted `.pkl` is a code-execution risk (ExFig had to whitelist
  module schemes to *block* remote imports). TOML is inert data — zero execution surface.
- **The cascade is in code, not the language.** blick's auto-discovery model means a child config
  must NOT need to know its parent's path. PKL `amends` requires exactly that, so PKL's main cascade
  feature is counterproductive here.
- **Adoption / Windows / performance.** No external `pkl` binary; native parsing; no process spawn
  per config file while walking the tree.
- Type-safety is preserved via `Codable` + validation at parse time; configs are small and flat, so
  PKL's computed values are unnecessary (YAGNI).

**Alternatives considered**: PKL (rejected — see above; great for *trusted* config like ExFig's own,
wrong for reading untrusted input); YAML (rejected — weaker typing than TOML, more verbose for the
nested `[[reviews]]`/`[[skills]]` arrays). Library fallback: `LebJe/TOMLKit` if `mattt/swift-toml`
proves problematic on Windows (both are toml++-based; TOMLKit advertises explicit Windows support).

### Decision 2: GitHub via the `gh` CLI (not a native API client)

**What**: `BatonForge` shells out to `gh api` / `gh` for reviews, Check Runs, and thread resolution.

**Why**: `gh` handles authentication transparently (env token, keychain, OAuth) and is preinstalled
and auto-authenticated in GitHub Actions. It is the lowest-friction path for the MVP. A native
`URLSession` client (removing the `gh` PATH dependency) is deferred to a future change.

**Alternatives considered**: native REST/GraphQL client (deferred — better Windows story and no PATH
dependency, but re-implements auth and pagination for little MVP benefit).

### Decision 3: Own `AgentRunner` abstraction; no opaque third-party agent layer

**What**: Each agent (claude/codex/gemini/opencode) is a thin `AgentRunner` adapter that *declares*
how to invoke its CLI (default binary, base args, prompt delivery, output parser). A single
`ProcessExecutor` builds and runs the invocation. `binary` and `args` overrides are applied
generically in the executor.

**Why**: there is no Swift equivalent of `cli-agents` (it is a Rust crate), so a Swift project cannot
reuse it regardless — the real question is what we must own and what that costs. blick delegates
**only claude/codex** to `cli-agents` and hand-rolls opencode/gemini itself (`agent/opencode.rs`,
`agent/gemini.rs` are manual `Command` invocations). That third-party layer (at blick's pinned
`0.2.10`) does not thread `binary`/`args` through, so those overrides were silently dropped for
claude/codex — blick PR #20 is the concrete example of the failure mode of an opaque agent layer.
By owning one invocation path, `binary`/`args`/`model` work uniformly for **all four** agents and
adding an agent is ~10 lines.

```swift
protocol AgentRunner: Sendable {
    var kind: AgentKind { get }                  // claude | codex | gemini | opencode
    var defaultBinary: String { get }
    var baseArguments: [String] { get }          // headless flags for this CLI
    var promptDelivery: PromptDelivery { get }    // .stdin | .argument | .tempFile
    func parse(_ output: AgentOutput) throws -> [Finding]
}

// Built by the core, uniformly — binary/args always honored (fixes the blick PR #20 class of bug):
func makeInvocation(_ r: AgentRunner, _ cfg: AgentConfig, _ defaults: EffectiveDefaults,
                    _ prompt: Prompt, workdir: URL) -> ProcessInvocation {
    ProcessInvocation(
        executable: cfg.binary ?? r.defaultBinary,
        arguments:  r.baseArguments + cfg.args,
        stdin:      r.promptDelivery == .stdin ? prompt.text : nil,
        workingDirectory: workdir, environment: agentEnv, timeout: defaults.timeout)
}
```

`ProcessExecutor` ports ExFig's pattern: read stderr concurrently before `waitUntilExit`, set the
termination handler before `run()`, enforce a timeout (`defaults.timeout`, default 600s — a Baton
addition over blick, which has no per-invocation timeout). Prompt is delivered via stdin by default
to avoid `ARG_MAX`/`E2BIG`.

**Does `cli-agents` solve more than `binary`/`args`? Yes — and we account for it.** It is a real,
maintained abstraction: streaming events (`TextDelta`/`Done`), tool-call handling, cancellation,
NDJSON result parsing, MCP server config, a permissions toggle, session management, a 10 MB output
buffer, and per-provider option blocks (`ClaudeOptions`/`CodexOptions`/`GeminiOptions`). Two things
keep that from deciding the choice for Baton: (1) it is **Rust-only**, with no Swift port, so it is
not on the table for us; (2) a batch PR reviewer needs only a **subset** — one-shot, single-turn,
non-interactive, capture text, parse JSON findings. We do **not** need streaming UI, interactive
tool approval, sessions, MCP, or mid-run cancellation for the MVP, so the surface we own is small.

What we therefore **take on as an explicit cost** is the part `cli-agents` centralizes for claude/
codex: the per-CLI headless incantation and output shape. Each `AgentRunner` adapter encapsulates
exactly that, distilled from how blick actually drives the CLIs:

| Concern | What the adapter pins (per CLI) |
|---|---|
| headless/skip-permission flags | claude `--print --output-format json --max-turns 1 --dangerously-skip-permissions`; codex exec flags; gemini `--approval-mode=yolo --skip-trust`; opencode `run` |
| prompt delivery | stdin (dodges `ARG_MAX`; the CLI reads stdin when no positional/`-p` prompt is given) |
| model flag mapping | claude/gemini `model` flag; strip a `provider/` prefix (e.g. `anthropic/…`) where the CLI wants a bare id |
| output → findings | `parse(_:)` per adapter (plain JSON → fenced → brace-balanced); see review-orchestration |
| failure detection | non-zero exit **and** the exit-0-with-empty-stdout case (opencode/gemini print auth/billing errors to stderr and still exit 0) |

These flags/formats drift, so adapters are **version-pinned and unit-tested** (tasks 4.3/4.5), and a
single CLI change touches one ~10-line adapter, not the codebase. Net: we trade `cli-agents`'
maintenance-for-free (Rust-only anyway) for a small, uniform, fully-overridable surface that also
covers opencode/gemini first-class — which blick hand-rolls outside `cli-agents` regardless.

### Decision 4: Prompt scaffold built in code; swift-jinja for report templates only

**What**: The system prompt (role + review instructions + skills + output-format + diff) is assembled
by a typed `PromptBuilder`. `swift-jinja` is used for *report* templates, not the prompt scaffold.

**Why**: The scaffold is logic tied to security (the untrusted skill markdown must sit in a clearly
delimited block, never in an instruction position). Building it in code makes the trust boundary
explicit and testable. User-editable parts (`prompt`, `prompt_file`, skills) are already data. This
mirrors blick (`review/prompt.rs`).

### Decision 5: Module layout

```
swift-baton/
├── Package.swift                      executable "baton"
└── Sources/
    ├── BatonKit/                      core, no UI deps
    │   ├── Config/                    baton.toml schema (Codable), EffectiveConfig, merge, provenance
    │   ├── Scope/                     discover (tree walk), inherit (ancestor-chain merge),
    │   │                              owner (deepest-ancestor), grouping (partition diff)
    │   ├── Git/                       base resolution, diff collection, focus-mode, chunking
    │   ├── Skill/                     local + owner/repo resolution, SHA pin, source allowlist
    │   ├── Agent/                     AgentRunner protocol + 4 adapters; ProcessExecutor; sandbox
    │   ├── Review/                    PromptBuilder, response parser, Finding types
    │   └── RunRecord/                 per-task artifacts, manifest.json, latest pointer
    ├── BatonForge/                    Forge protocol + GitHubForge (gh CLI): review, check runs,
    │                                  resolveThread, dedupe, PR-context detection
    └── BatonCLI/                      @main baton; commands; TerminalUI (ported from ExFig); render
```

The orchestrator (sliding-window concurrency over `(scope, review)` tasks) lives in `BatonCLI`,
reusing ExFig's `BatchExecutor`/`parallelMapEntries` patterns. A future change may extract shared
scaffolding into a standalone package consumed by both ExFig and Baton.

### Decision 6: Renames that cross scope boundaries

**What**: A renamed file is owned by the scope of its **new** path (the `b/` side of the diff header).

**Why**: The new location reflects where the code lives now and which team owns it going forward;
it matches blick's b-path attribution and avoids double-counting a rename in two scopes.

### Decision 7: Oversized files (a single file exceeds `diff_budget`)

**What**: Chunk a scope's oversized diff by file. If a *single file's* diff alone exceeds
`diff_budget`, fall back to `by-hunk` for that file. If a single hunk still exceeds the budget, send
it whole but mark that file `truncated` in the run record and emit a warning. Never cut mid-line.

**Why**: `by-file` chunking cannot split one giant file; a deterministic fallback ladder
(by-file → by-hunk → whole-hunk + truncated flag) preserves structure and is honest about loss,
replacing blick's raw-byte truncation.

### Decision 8: Unknown keys in `baton.toml` are lenient

**What**: Unrecognized keys are ignored with a warning (forward compatibility across versions).
Structural/type errors and invalid enum values (e.g. an unknown `[agent].kind`) still hard-fail.

**Why**: A newer `baton.toml` should not break an older binary outright; warn-and-continue is the
forward-compatible default, while genuinely wrong values still error.

### Decision 9: Missing tools — preflight + `baton doctor`

**What**: Baton drives external tools — `git` (always), the configured agent CLI (for `review`),
and `gh` (for `publish`). Each command runs a preflight that verifies its required tools are present
(and, where checkable, authenticated) **before** doing work, failing fast with a `recoverySuggestion`
naming the missing tool and how to install/authenticate it. A dedicated `baton doctor` command checks
all required tools at once and reports status. This adds a sixth command.

**Why**: "No tools" is three distinct situations — binary missing, present-but-unauthenticated, and
missing `gh`/`git` — each needing a distinct, actionable error rather than a generic failure.

### Decision 10: Model selection

**What**: The model is `[agent].model`. Because `[agent]` is closest-wins as a whole block, different
scopes may use different models. `--model` (with `--agent`) overrides at the CLI. Each `AgentRunner`
adapter maps `model` to its CLI's model flag; when `model` is unset the agent CLI's own default is used.

**Why**: Per-scope model choice is a core blick capability (e.g. a cheap model for web, a stronger
model for security-sensitive code); making it first-class keeps the cascade meaningful.

### Decision 11: Check Run conclusion is high-gated, independent of `fail_on`

**What**: A `(scope, review)` Check Run concludes `failure` when any finding is high-severity,
`success` when there are no findings, and `neutral` otherwise. This threshold is fixed at `high`
and is deliberately **independent** of the review's `fail_on`, which governs only the local CLI
exit status.

**Why**: They are two different signals. The Check Run is a shared, merge-gating status on the PR —
a green/red the whole team reads — so it should fire only on real blockers (high). `fail_on` is a
per-invocation CLI knob (a security-sensitive scope may want a `medium`-fail local gate without
turning every contributor's PR red). blick makes exactly this split (`render/check_run.rs`
`conclusion_for`: "non-high findings shouldn't fail the check"); Baton keeps it and documents it so
the two thresholds are not mistaken for an inconsistency.

### Decision 12: Focus-mode SHA is recovered from GitHub, not from local run records

**What**: `review` discovers the previous Baton review's head SHA by reading state on the PR itself
(Baton-authored Check Runs on prior commits, with a fallback to a `<!-- baton:last-reviewed=<sha> -->`
marker in the Baton PR-review body), after detecting PR context from the GitHub Actions environment
(`GITHUB_EVENT_PATH`, `GITHUB_REPOSITORY`). `publish` is what persists that SHA for the next run.

**Why**: Local `.baton/runs/` artifacts do not survive between CI jobs, so focus-mode state must
live on the PR. This is the cross-capability contract between `diff-routing` (reads the SHA) and
`github-publish` (writes it), mirroring blick's `resolve_focus_base` (`commands/review/base.rs`).
When the SHA is missing or unreachable (e.g. force-push), `review` falls back to the full base diff
with a warning.

## Canonical Configuration Schema (`baton.toml`)

```toml
# [agent] — closest-wins as a WHOLE block (kind+model are coupled)
[agent]
kind   = "claude"            # claude | codex | gemini | opencode
model  = "claude-opus-4-7"   # optional
binary = "/opt/homebrew/bin/claude"  # optional override — honored for ALL agents (blick PR #20 fix)
args   = ["--verbose"]       # optional extra args — honored for ALL agents
context = "diff"             # diff | repo  (improvement #1; default "diff")

# [defaults] — field-by-field closest-wins
[defaults]
base            = "origin/main"  # optional; resolution: --base > scope default > HEAD
fail_on         = "high"         # low | medium | high  (default "high")
max_concurrency = 4              # default 4 (forced >= 1)
diff_budget     = 120000         # bytes per scope before structural chunking (default 120000)
chunk_strategy  = "by-file"      # by-file | by-hunk  (improvement #4; default "by-file")
timeout         = 600            # seconds per agent invocation (default 600; Baton addition over blick)

# [[skills]] — union across the chain + closest-wins by name
[[skills]]
name    = "owasp-top10"
source  = "org/skills"           # local path (./,../,/,~) | owner/repo | owner/repo/skill
ref     = "a1b2c3d4e5f6"         # commit SHA — REQUIRED for remote sources (improvement #3)
subpath = "skills/owasp"         # optional

# [[reviews]] — INHERITED down the chain with override-by-name (improvement #2; blick does not inherit)
[[reviews]]
name        = "security"
skills      = ["owasp-top10"]
glob        = ["**/*.swift"]     # only route matching files to this review (improvement #2)
fail_on     = "high"             # optional per-review override of defaults.fail_on
context     = "repo"             # optional per-review override of agent.context
prompt      = "Focus on auth and input validation."   # inline instruction
# prompt_file = "./reviews/security.md"                # OR load instruction from a file

# disable inherited reviews by name within this scope:
disabled_reviews = ["legacy-style"]

# [security] — root scope only (not inherited)
[security]
require_pinned_skills = true                 # default true; remote skills must set `ref`
allowed_skill_sources = ["org/*", "trusted/skills"]   # glob allowlist of remote sources
```

### Cascade semantics (root → scope, closest-wins)

| Section | Merge rule |
|---|---|
| `[agent]` | closest-wins, whole block replaces ancestor's |
| `[[skills]]` | union across chain; on name collision the closest wins; auto-discovered local skills (`.baton/skills/<name>/SKILL.md`) are prepended so explicit entries override them |
| `[defaults]` | field-by-field closest-wins; `max_concurrency` forced `>= 1` |
| `[[reviews]]` | inherited down the chain; same `name` overrides ancestor; `disabled_reviews` removes inherited reviews by name |
| `[security]` | root scope only |

Each effective value records **provenance** (which file it came from) for `baton config --explain`.

## Diff Routing, Improvements, Errors

- **owner**: for a changed path, the scope whose root is the deepest ancestor owns it; files outside
  any scope are dropped. The diff is partitioned by `diff --git a/… b/…` headers (careful boundary
  parsing of rename headers).
- **focus-mode**: in CI on a PR (PR context detected from the GitHub Actions environment), recover
  the previous Baton review's head SHA from the PR (see Decision 12) and additionally compute the
  diff since then, so re-runs focus on new changes; fall back to the full base diff with a warning
  when that SHA is missing or unreachable.
- **Improvement #4 (chunking)**: when a scope's diff exceeds `diff_budget`, split by file (or hunk),
  never mid-file; run multiple agent passes and merge findings — instead of raw-byte truncation.
- **Improvement #1 (context)**: `context = "diff"` (default) gives the agent only the scope's diff
  slice in the prompt; the code-built role block instructs it to use only the provided material and
  not to reach for the repository, filesystem, or other tools (this mirrors blick's base system
  prompt). `context = "repo"` additionally drops a read-only copy of the repo into the working
  directory for cross-file reasoning. **Isolation model (matches blick, corrected from an earlier
  "no-network sandbox" framing):** the agent is an external coding CLI that *must* reach its model
  provider over the network, so Baton does not — and cannot — block egress without breaking the
  agent. Isolation is therefore: (a) run in a fresh temporary working directory, never the real
  repo, so the agent cannot write to the working tree; (b) for `context = "repo"`, a *copy* of the
  repo that is not the live tree; (c) prompt-level instruction to stay within the provided material;
  (d) the untrusted-skill defense is the delimited prompt block (improvement #3), not an OS sandbox.
  Hardening egress to an allowlist of model endpoints is a non-goal for this change (future work).
- **Improvement #2 (filters/inheritance)**: `glob` filters files within a scope to a review; reviews
  inherit with override/disable.
- **Improvement #3 (skill security)**: remote skills require a `ref` SHA unless `--allow-unpinned`;
  sources are checked against `allowed_skill_sources`; skill markdown is embedded in a delimited
  untrusted block, never as overriding instructions.
- **Errors**: domain errors are `LocalizedError` with `recoverySuggestion`; formatted as
  `✗ <description>\n  → <recovery>` (ported from ExFig).

## Run Artifacts

Per run under `.baton/runs/<run-id>/`: a machine record (`<scope>--<review>.json`), an agent log
(`.log`), the exact assembled prompt (`.prompt.md`), a `manifest.json`, and a `latest` pointer.
The `manifest.json` records the resolved `base` and the review-time head commit SHA
(`git rev-parse HEAD`) so `publish` can detect when the PR head has advanced past the reviewed
commit (the stale-SHA case). The SHA Baton *posts against* still comes from the publish context
(`--head-sha` or the GitHub Actions event), as in blick — it is a publish-time input, not stored
findings. `render` and `publish` operate over a saved run **without** re-invoking the LLM.

## Tooling, CI, Documentation & Distribution (ported from ExFig)

The repo-process scaffolding is lifted from ExFig (a proven Swift 6.3 setup) and re-pointed at Baton.

**Tooling.** `mise.toml` pins the toolchain (Swift 6.3, swiftlint, swiftformat, dprint, hk,
actionlint, git-cliff, xcsift) and defines the canonical tasks (`build`/`test`/`lint`/`format`/
`format-check`/`docs`/`changelog`); build/test pipe through `xcsift`. `hk` (configured in `hk.pkl`,
invoked through `mise` from `.githooks/`) runs `pre-commit` (swiftformat + swiftlint --strict +
dprint + actionlint, auto-fix and re-stage) and `commit-msg` (Conventional Commits). `HK=0` bypasses
hooks for automation. Two ExFig drifts to fix on copy: the `hk` version pinned in `mise.toml` vs the
one `hk.pkl` amends, and a hardcoded Swift toolchain path in `hk.pkl`'s sourcekit env.

**CI** (`ci.yml`): push-to-`main` + PR, concurrency-cancel; a `lint` job (`format-check` + `lint` +
`actionlint`) gates `build-macos` + `build-linux` (`swift:6.3` container) + best-effort
`build-windows`, with the SPM `.build` cached on `Package.resolved`.

**DocC** (`deploy-docc.yml`): a `Baton.docc` catalog on the executable target + `swift-docc-plugin`
(`#if !os(Windows)`); generated for static hosting at base path `baton` into `docs/` with a redirect
`index.html`, deployed to GitHub Pages on `v*` tags (Pages at `alexey1312.github.io/baton`).

**Release & distribution** (`release.yml` + `cliff.toml`): `v*` tag builds a macOS **universal**
binary (`lipo` arm64 + x86_64), a Linux binary (`--static-swift-stdlib`), and a best-effort Windows
binary; `git-cliff` produces notes; `softprops/action-gh-release` attaches archives (prerelease when
the tag has a `-`). A non-prerelease additionally regenerates `CHANGELOG.md` to `main` and bumps
`Formula/baton.rb` in **`alexey1312/homebrew-tap`** (SHA256 of the macOS+Linux archives; secret
`HOMEBREW_TAP_TOKEN`). Install channels: `mise use -g github:alexey1312/swift-baton` (mise github
backend, fed by the release archives) and `brew install alexey1312/tap/baton`.

**Deliberately dropped from ExFig** (not applicable to a generic CLI; YAGNI): the PKL config-language
schemas + `codegen:pkl` + `pkl project package` release step (Baton's config is TOML); the
`llms.txt` generation pipeline (optional, can be added later); ExFig's Linux link flags for
libxml2/curl/openssl/webp/png (Baton has no such native deps — keep only what `gh`/`git`-driven code
needs). **Not in scope for the MVP** (matching ExFig, which also omits them): code signing and
notarization of the macOS binary.

## Risks / Open Questions

- `mattt/swift-toml` Windows support is not explicitly advertised (toml++/C++ interop). Mitigation:
  spike on Windows; fall back to `LebJe/TOMLKit`.
- Exact headless invocation flags per CLI (claude/codex/gemini/opencode) evolve; they are pinned and
  tested inside each `AgentRunner` adapter, not hardcoded across the codebase.
- `mattt/swift-toml` existence/maintenance is not yet confirmed; verify before scaffolding (task 1.2)
  and fall back to `LebJe/TOMLKit` if it is unavailable or unmaintained.
- `gh` CLI must be present and authenticated; absence yields a `recoverySuggestion` to install/auth.
- **Check Runs require a GitHub App token.** The Checks API rejects plain PATs. In GitHub Actions the
  default `GITHUB_TOKEN` is a GitHub App token and works; a developer running `baton publish` locally
  with a PAT cannot create Check Runs. Mitigation: when Check Run creation is unauthorized, degrade
  to posting only the PR review (inline comments + a summary comment) and emit a warning, rather than
  failing the whole publish.
- Agent isolation is best-effort (temp working dir + prompt instruction), not an OS sandbox: the
  agent process necessarily has network egress to reach its model. Egress allowlisting and a true
  read-only mount for `context = "repo"` are deferred; document this limitation for users running
  untrusted skills.

## Future: `learn` (out of scope) — extension points to preserve

`learn` is deferred (see Non-Goals), but the MVP should not foreclose it. In blick, `learn` inspects
review threads on recently-merged PRs, buckets them (accepted / ignored / outdated / human-authored),
and asks the agent to propose edits to the *review setup* (config + skills) — never source code — as a
single rolling **draft PR** on a `learn` branch, gated by `min_signal` over a `lookback_days` window
and constrained to an edit allowlist. To keep that buildable later without rework, the MVP must
preserve three things:

1. **A recognizable comment footer.** blick attributes its own threads by a literal footer signature
   on each inline comment. `rendering`/`github-publish` MUST append a stable, machine-recognizable
   footer to every posted comment (alongside the `<!-- baton:last-reviewed=<sha> -->` marker) — else a
   future `learn` cannot distinguish its own threads from human ones.
2. **Thread→scope attribution reuses owner resolution.** A thread on `ios/App/View.swift` is iOS-scope
   signal; the same deepest-ancestor owner that `diff-routing` uses partitions `learn`'s signal per
   scope. Keeping owner resolution a reusable, side-effect-free function enables this.
3. **Per-scope agent/skills reuse.** A `learn` pass for a scope should drive that scope's effective
   `[agent]` and skills — already provided by Decision 3 + the cascade; no MVP change needed.
4. **Reaction-based usefulness signal (improvement over blick).** blick reads no reactions; its only
   signal is a thread's resolved/unresolved/outdated state plus reply text, which is ambiguous (a
   resolved thread may be a *fix* or a *dismissal*). Baton's comment template invites a 👍/👎 reaction
   ("React 👍/👎 if useful"; see `rendering`), and a future `learn` reads the `+1`/`-1` reactions on
   its own comments — identified by the `<!-- baton:finding -->` marker, via the GitHub reactions API
   — as a direct usefulness weight, **combined with** (not replacing) the resolved/unresolved signal,
   since reactions are sparse. This costs the MVP nothing beyond the template nudge + marker; reading
   and weighting reactions is a `learn`-time concern. A 👎-heavy rule is a strong candidate to relax
   or remove; a 👍-heavy one to reinforce.

### Inheritance for `learn`: split, not blanket (recorded intent, not built)

blick makes `[learn]` root-only. For a multi-stack monorepo that wastes Baton's main advantage; but
inheriting the whole block like `[defaults]` is also wrong, because its fields have two different
natures. The intended future design **splits** `[learn]`:

- **Delivery fields are root-only** (not inherited): `branch`, `base`, `reviewers`, `team_reviewers`,
  `labels`, `draft`. There is one rolling PR per repository — these are inherently global, and
  per-scope branches would mean N competing PRs.
- **Analysis fields cascade field-by-field, closest-wins** like `[defaults]`: `lookback_days`,
  `min_signal`, and an `enabled` opt-in — a high-traffic scope can demand more signal; a quiet one
  can widen the window or opt out.

The pass partitions PR signal by scope (point 2 above), drives each scope with its own effective
agent/skills (point 3), proposes edits to *that scope's* `baton.toml`/`.baton/skills/`, and still
funnels everything into the single root-owned rolling PR. This mirrors how Baton already made
`[[reviews]]` inherit where blick does not (improvement #2). This is recorded as **intent only** —
implementing it before `learn` is in scope would be premature (YAGNI). The one rule the MVP locks in
now is the general pattern that **repository-global sections live at the root** (today: `[security]`;
tomorrow: `[learn]`'s delivery half).

## Glossary

- **scope** — a subtree owning a `baton.toml`.
- **owner** — the deepest scope that is an ancestor of a changed file.
- **review** — one agent invocation against a scope's diff slice, producing findings.
- **finding** — `{ file, line, severity (low|medium|high), title, body }`.
- **skill** — a markdown instruction bundle (local or remote, SHA-pinned) injected into the prompt.
- **focus diff** — the diff since the previous Baton review on the same PR.
- **provenance** — the source file a given effective config value came from.
