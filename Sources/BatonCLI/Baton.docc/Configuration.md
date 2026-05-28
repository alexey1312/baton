# Configuration

The `baton.toml` schema and how settings cascade across a monorepo.

## Overview

Every subtree may declare a `baton.toml`. Baton walks the repository, treats each directory
containing a `baton.toml` as a *scope*, and computes an effective configuration per scope by
merging from the repository root down to that scope (closest value wins). `baton config
--explain` prints the effective values and the file each came from.

## Sections

### [agent]

Inherited closest-wins as a whole block (kind and model are coupled).

```toml
[agent]
kind    = "claude"            # claude | codex | gemini | opencode | custom
model   = "claude-opus-4-7"   # optional; mapped to the CLI's model flag
binary  = "/opt/homebrew/bin/claude"  # optional override — honored for every agent
args    = ["--verbose"]       # optional extra args — honored for every agent
context = "diff"              # diff (default) | repo
```

`kind = "custom"` drives any other CLI; it requires `binary`. With `context = "repo"` a
read-only copy of the repository is placed in the agent's working directory for cross-file
reasoning; `diff` (the default) sends only the scope's slice of the diff.

### [defaults]

Merged field-by-field, closest-wins. Unset fields fall back to the documented defaults.

```toml
[defaults]
base            = "origin/main"  # diff base; resolution: --base > scope default > HEAD
fail_on         = "high"         # low | medium | high (default high)
max_concurrency = 4              # default 4 (forced >= 1)
diff_budget     = 120000         # bytes per scope before structural chunking
chunk_strategy  = "by-file"      # by-file (default) | by-hunk
timeout         = 600            # seconds per agent invocation
```

### [[skills]]

Markdown instruction bundles injected into the prompt. Union across the chain; on a `name`
collision the closest scope wins. Skills under `.baton/skills/<name>/` are auto-discovered.

```toml
[[skills]]
name    = "owasp-top10"
source  = "org/skills"           # local path (./ ../ / ~) | owner/repo | owner/repo/skill
ref     = "a1b2c3d4e5f6"         # commit SHA — required for remote sources
subpath = "skills/owasp"         # optional
```

### [[reviews]]

Inherited down the chain; a same-`name` review in a closer scope overrides the ancestor's.

```toml
[[reviews]]
name    = "security"
skills  = ["owasp-top10"]
glob    = ["**/*.swift"]         # only route matching files to this review
fail_on = "high"                 # optional per-review override of defaults.fail_on
context = "repo"                 # optional per-review override of agent.context
prompt  = "Focus on auth and input validation."
# prompt_file = "./reviews/security.md"  # OR load the instruction from a file
```

Remove an inherited review within a scope with `disabled_reviews = ["legacy-style"]`. Place
top-level keys like `disabled_reviews` before any `[table]` header.

### [security]

Honored only at the repository-root scope.

```toml
[security]
require_pinned_skills = true                          # remote skills must set `ref`
allowed_skill_sources = ["org/*", "trusted/skills"]   # glob allowlist of remote sources
```

