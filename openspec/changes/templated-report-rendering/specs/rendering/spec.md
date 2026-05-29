## ADDED Requirements

### Requirement: User-Customizable Local Report Templates

The system SHALL render the human-facing local report formats — the `render` `markdown` report and the `learn` rolling-pull-request-body markdown — from Jinja templates, SHALL ship bundled default templates whose output is byte-for-byte identical to the previous built-in rendering of the same run, and SHALL allow a user to override a template via the `[render]` configuration block or a `--template` flag on `render`. The system SHALL keep the `github-review`, `check-run`, `github-summary`, `json`, and `terminal` formats built in code so that the required `<!-- baton:finding -->` marker, the 👍/👎 usefulness affordance, and the collapsible "Instructions for AI agents" block cannot be removed by a user template.

#### Scenario: Default template reproduces prior output

- **WHEN** a saved run is rendered to `markdown` with no custom template configured
- **THEN** the output SHALL be identical to the prior built-in markdown rendering of that run

#### Scenario: User template overrides a local format

- **WHEN** the user configures `[render].markdown_template` or passes `--template <path>` for the `markdown` format
- **THEN** the system SHALL render that format from the user's template rather than the bundled default

#### Scenario: Invalid template fails with a typed error

- **WHEN** a configured or passed template contains a syntax error
- **THEN** the system SHALL fail with a typed error
- **AND** the error SHALL carry a `recoverySuggestion` instructing the user to fix the template

#### Scenario: GitHub formats are not user-templatable

- **WHEN** the user passes `--template` together with `github-review`, `check-run`, or `github-summary`
- **THEN** the system SHALL reject the request with a typed error
- **AND** the GitHub formats SHALL continue to emit the `<!-- baton:finding -->` marker, the 👍/👎 affordance, and the AI-agent instructions block

#### Scenario: Required marker preserved regardless of render configuration

- **WHEN** any GitHub comment body is produced under any `[render]` configuration
- **THEN** it SHALL contain the `<!-- baton:finding -->` footer marker
