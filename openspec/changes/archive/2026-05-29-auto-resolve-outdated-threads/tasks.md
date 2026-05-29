## 1. BatonKit — marker and config

- [x] 1.1 Add `BatonMarker.autoResolved = "<!-- baton:auto-resolved -->"` and `autoResolvedReplyBody(reason:)` (must NOT contain `BatonMarker.finding`) in `Sources/BatonKit/Review/GitHubPresentation.swift`.
- [x] 1.2 Add `PublishConfig` struct with `resolveOutdatedThreads: Bool?` (snake_case `resolve_outdated_threads` CodingKey) and a `publish: PublishConfig?` field on `BatonConfig` in `Sources/BatonKit/Config/Schema.swift`.
- [x] 1.3 Add `ConfigDefaults.resolveOutdatedThreads = false`.
- [x] 1.4 Add `EffectivePublish` (root-only resolution, like `[learn]` delivery) resolving `resolveOutdatedThreads` against the default in `Sources/BatonKit/Config/EffectiveConfig.swift` + `Cascade.resolvePublish`.
- [x] 1.5 Unit tests: marker constant + reply body excludes `finding`; effective default is false; cascade root-only.

## 2. BatonForge — shared thread reader

- [x] 2.1 Create `Sources/BatonForge/ReviewThreadReader.swift`: a struct over `GHRunning` with `pullRequest(owner:name:number:)` returning the decoded threads (node `id`, `isResolved`, `isOutdated`, `resolvedBy.login`, `comments[{databaseId, body, path, line}]`).
- [x] 2.2 Centralize the `reviewThreads` GraphQL query + decoder here; page comments with `first: 100`; reuse `GHApiClient` for transport.
- [x] 2.3 Remove the moved types from `LearnAPIBodies`.

## 3. BatonForge — auto-resolve in publish

- [x] 3.1 Add `ReplyComment { body; in_reply_to }` to `Sources/BatonForge/GitHubAPIBodies.swift`.
- [x] 3.2 Add `threadsResolved` and `threadsResolveSkipped` to `Sources/BatonForge/PublishReport.swift`.
- [x] 3.3 Add `ForgeError.threadResolveForbidden(detail:)` (degradable, mirrors `checkRunForbidden`).
- [x] 3.4 Add `Options.resolveOutdatedThreads: Bool = false` to `GitHubForge`.
- [x] 3.5 Add `resolveObsoleteThreads(context:report:)`, `resolveOne`, `postReply`, selection predicate (`isOutdated && !isResolved && hasMarker(finding) && !hasMarker(autoResolved)`), reply-then-resolve, permission degradation (same-file `extension GitHubForge`).
- [x] 3.6 Call `resolveObsoleteThreads` at the end of `GitHubForge.publish` when `resolveOutdatedThreads && context.hasPR`.

## 4. BatonForge — learn honors the marker

- [x] 4.1 In `GitHubLearnForge.makeSignal`, scan ALL `comments.nodes` for `BatonMarker.autoResolved`; set `resolvedByAutomation = node.hasComment(containing: autoResolved) || isAutomation(actor)`.
- [x] 4.2 Route the learn read through the shared `ReviewThreadReader` (paged comments) so the marker is visible.

## 5. BatonCLI — flag and surfacing

- [x] 5.1 Thread the effective `resolveOutdatedThreads` into `GitHubForge.Options` in `Sources/BatonCLI/Commands/Publisher.swift`; surface `threadsResolved`/`threadsResolveSkipped` in the summary.
- [x] 5.2 Add `--resolve-outdated-threads` / `--no-resolve-outdated-threads` to `Sources/BatonCLI/Commands/PublishCommand.swift`, overriding config; show `[publish]` in `baton config`.

## 6. Tests and verification

- [x] 6.1 `BatonForgeTests`: resolves an outdated Baton thread (reply with `auto-resolved`, not `finding`; then mutation; `threadsResolved == 1`).
- [x] 6.2 `BatonForgeTests`: skips non-outdated / already-resolved / non-Baton / already-marked threads; flag off → no thread read; permission failure → `threadsResolveSkipped == 1`, `reviewPosted` still true, warning, no throw.
- [x] 6.3 `LearnForgeTests`: marker present + human resolver login → `resolvedByAutomation == true`; no marker + human → false; `[bot]` suffix regression preserved.
- [x] 6.4 Run `mise run format` → `mise run lint` → `mise run test` (through xcsift) green.
- [x] 6.5 `openspec validate auto-resolve-outdated-threads --strict` passes.
- [x] 6.6 Manual: `baton config` shows the effective `resolve_outdated_threads`.
