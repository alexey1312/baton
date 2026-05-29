## ADDED Requirements

### Requirement: Auto-Resolve Baton's Own Obsolete Threads

The system SHALL, when the root `[publish].resolve_outdated_threads` setting is enabled, resolve the Baton-authored review threads that GitHub has flagged outdated, and SHALL mark each such resolution as Baton automation in a token-independent way by posting a reply comment carrying the `<!-- baton:auto-resolved -->` marker before invoking the GraphQL `resolveReviewThread` mutation. The setting SHALL default to `false`. The system SHALL resolve only threads whose comment carries the `<!-- baton:finding -->` marker, that GitHub has flagged outdated, and that are neither already resolved nor already carrying the `<!-- baton:auto-resolved -->` marker. The system SHALL NOT resolve a thread merely because its finding is absent from the current run's findings.

#### Scenario: Outdated Baton thread is auto-resolved

- **WHEN** publish runs with `resolve_outdated_threads` enabled and a Baton-authored review thread is flagged outdated by GitHub and is not yet resolved
- **THEN** the system SHALL post a reply comment carrying the `<!-- baton:auto-resolved -->` marker
- **AND** the system SHALL invoke the GraphQL `resolveReviewThread` mutation for that thread

#### Scenario: Disabled by default

- **WHEN** publish runs without `resolve_outdated_threads` enabled
- **THEN** the system SHALL NOT read or resolve any review thread for the purpose of auto-resolution

#### Scenario: Still-valid threads are not resolved

- **WHEN** a Baton-authored thread has not been flagged outdated by GitHub
- **THEN** the system SHALL NOT resolve it, even if its finding is absent from the current run's findings

#### Scenario: Re-run does not duplicate the auto-resolve reply

- **WHEN** publish re-runs against a thread that already carries the `<!-- baton:auto-resolved -->` marker
- **THEN** the system SHALL NOT post a second reply
- **AND** the system SHALL NOT re-invoke the resolve mutation for that thread

#### Scenario: The auto-resolve reply is not a finding comment

- **WHEN** the system posts the `<!-- baton:auto-resolved -->` reply
- **THEN** the reply body SHALL NOT contain the `<!-- baton:finding -->` marker
- **AND** the reply SHALL NOT be counted as a posted finding for dedupe or signal purposes

#### Scenario: Permission failure degrades to a warning

- **WHEN** the available token cannot post the reply or invoke the resolve mutation
- **THEN** the system SHALL NOT abort the publish
- **AND** the system SHALL emit a warning that thread auto-resolution was skipped
- **AND** any PR review and Check Runs already posted in the same publish SHALL remain posted
