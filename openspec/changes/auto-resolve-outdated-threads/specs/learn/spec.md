## MODIFIED Requirements

### Requirement: Signal Collection From Merged Pull Requests

The system SHALL collect usefulness signal by scanning pull requests merged within the
effective `lookback_days` window, identifying Baton-authored review threads by the
`<!-- baton:finding -->` marker, and reading both the 👍/👎 reactions on those comments (via
the GitHub Reactions API) and each thread's resolution state (via GitHub GraphQL). The system
SHALL determine whether a thread's resolution was produced by Baton's own automation in a
token-independent way: a thread any of whose comments carries the `<!-- baton:auto-resolved -->`
marker SHALL be treated as resolved by Baton automation regardless of the resolving actor's
login, and SHALL NOT be counted as a human usefulness signal.

#### Scenario: Baton threads identified by marker

- **WHEN** the system scans a merged pull request containing both Baton-authored and human-authored review threads
- **THEN** the system SHALL select the threads whose comment body contains the `<!-- baton:finding -->` marker as Baton-authored signal

#### Scenario: Reactions and resolution state are read

- **WHEN** the system processes a Baton-authored review thread
- **THEN** the system SHALL read the 👍/👎 reactions on its comment via the Reactions API
- **AND** the system SHALL read the thread's resolution state (resolved, unresolved, or outdated) via GraphQL

#### Scenario: Resolution by Baton's own automation is not human signal

- **WHEN** a thread's resolution or outdated state was produced by Baton's own automation rather than a human actor
- **THEN** the system SHALL NOT treat that resolution as a usefulness signal

#### Scenario: Resolution carrying Baton's auto-resolve marker is not human signal

- **WHEN** a review thread contains a comment carrying the `<!-- baton:auto-resolved -->` marker
- **THEN** the system SHALL treat the thread's resolution as Baton automation
- **AND** the system SHALL NOT count it as a usefulness signal, regardless of the resolving actor's login

#### Scenario: Human-authored threads count as missing-coverage signal

- **WHEN** a merged pull request contains a human-authored review thread that Baton did not author
- **THEN** the system SHALL record it as a signal of a review category Baton does not yet cover

#### Scenario: Pull requests outside the window are ignored

- **WHEN** a pull request merged earlier than the effective `lookback_days` window is encountered
- **THEN** the system SHALL NOT include its threads in the collected signal
