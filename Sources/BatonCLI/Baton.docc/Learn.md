# Learn

`baton learn` reflects on how findings landed and proposes edits to the review setup.

## Overview

`learn` closes the review loop. It scans pull requests merged within a lookback window, reads
the usefulness signal humans left on Baton's findings (👍/👎 reactions plus review-thread
resolution), attributes that signal to the owning scope, and asks each scope's agent to propose
edits to **the review setup only** — `baton.toml`, local skills, and agent docs. It never edits
source code, tests, CI workflows, or dependency manifests. All proposals across all scopes are
consolidated into a single rolling **draft pull request** per repository.

`learn` is safe by default: with no delivery configured and no `--apply`, it prints a read-only
preview and performs no GitHub writes.

```sh
baton learn                 # preview proposed edits (no GitHub writes)
baton learn --markdown      # preview as the rolling-PR markdown body
baton learn --apply         # open/update the rolling draft PR
baton learn --gh-repo owner/repo   # override the target repository slug
```

## How proposals are produced and contained

Unlike `review` — which runs each agent in a throwaway copy of the repository — `learn` runs the
scope's agent CLI **in the live working tree**, with the same non-interactive flags review uses.
This is deliberate: proposals are discovered by diffing git's dirty set before and after the run
(never trusted from the agent's self-report). While it runs, the agent can therefore read files in
the tree and reach the network, like any local CLI you invoke. Several guards contain it:

- **Edits are git-discovered, then allowlisted.** Only changes git reports are considered, and
  each is filtered against the scope's editable set (`baton.toml`, local skill directories, agent
  docs). Out-of-allowlist edits are reverted after the run, so refused edits never persist.
- **GitHub credentials are scrubbed** from the agent's environment (`GITHUB_TOKEN`/`GH_TOKEN`),
  which the agent never needs; only `gh` itself sees them.
- **Untrusted content is framed as data.** Skill markdown and GitHub-derived signal (finding
  titles, file paths) enter the prompt inside a delimited untrusted block, never as instructions.

Run `learn` only against a repository whose `baton.toml` and skills you trust, and prefer the
preview (no `--apply`) when trying it out.

## The signal model

For each merged PR, `learn` identifies Baton-authored threads by the `<!-- baton:finding -->`
marker and reads:

- **Reactions** (👍/👎) on the finding comment via the GitHub Reactions API. Each 👍 is `+1`,
  each 👎 is `−1`. The pull request author's own reactions are excluded so a self-reaction
  cannot manufacture signal.
- **Thread resolution** (resolved / unresolved / outdated) and the resolving actor via GraphQL.
  Resolution counts only when produced by a human — a thread Baton's own automation resolved is
  not treated as acceptance.

Threads are bucketed into **accepted** (human-resolved), **ignored** (unresolved), **outdated**
(weighted low), and **human-authored** (a missing-coverage signal where a human commented but
Baton did not). Reaction weight *augments* the resolution signal rather than replacing it: a
resolved thread carrying net 👎 is not a reinforce candidate. Rules with net-negative weight
become candidates to **relax or remove**; net-positive ones become candidates to **reinforce**.
Human-authored threads are fed to the scope's agent as candidates to **add or broaden** a review
or skill.

`baton stats` surfaces the most 👎-weighted and 👍-weighted rules so proposals are explainable.

## Stateless execution and the optional cache

GitHub is the source of truth. `learn` re-derives the signal from GitHub on every run, so a run
needs no persisted local state — ideal for ephemeral CI runners. An optional SQLite `feedback`
cache under the gitignored `.baton/` directory powers `baton stats` trends and avoids re-fetching
on a developer machine; it is never required, never committed, and never widens the effective
`lookback_days` window or changes the signal the agent analyzes.

## Gating and opt-out

Each scope is gated on **signal volume** — the count of Baton-authored threads attributed to it
in the window — against the effective `[learn].min_signal`. A scope below threshold yields no
proposal. Because the gate counts threads (not signed weight), a scope rich in 👎 signal is
never skipped for being "below threshold." A scope with `[learn].enabled = false` is skipped
entirely. See <doc:Configuration> for the split `[learn]` cascade (analysis fields cascade
closest-wins; delivery fields are read only from the repository root).

## Running on CI

The primary trigger is a scheduled GitHub Actions workflow (`.github/workflows/learn.yml`,
`schedule:` + `workflow_dispatch`). It needs `permissions: contents: write` (to push the `learn`
branch) and `pull-requests: write` (to open/update the draft PR); reading reactions and threads
is covered by the default `GITHUB_TOKEN`.

> Note: opening or updating the pull request requires a GitHub App token such as the Actions
> `GITHUB_TOKEN`. A plain personal access token that cannot write pull requests degrades the run
> to preview output plus a warning rather than failing — mirroring the Check Run caveat in
> `baton publish`.
