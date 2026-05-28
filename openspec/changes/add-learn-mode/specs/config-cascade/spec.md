# config-cascade

## ADDED Requirements

### Requirement: Learn Block Inheritance

The system SHALL resolve the effective `[learn]` block by splitting its fields into two
classes. Delivery fields — `branch`, `base`, `reviewers`, `team_reviewers`, `labels`, and
`draft` — SHALL be read only from the repository-root scope and SHALL NOT be inherited by, nor
overridable from, any descendant scope (there is one rolling pull request per repository).
Analysis fields — `lookback_days`, `min_signal`, and `enabled` — SHALL cascade field-by-field
with closest-wins semantics, exactly like `[defaults]`.

#### Scenario: Analysis field overridden closest-wins

- **GIVEN** a root scope with `[learn]` `min_signal = 3` and a child scope with `[learn]` `min_signal = 5`
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[learn].min_signal` for the child scope SHALL be `5`

#### Scenario: Analysis field inherited when child omits it

- **GIVEN** a root scope with `[learn]` `lookback_days = 14` and a child scope that declares `[learn]` without `lookback_days`
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[learn].lookback_days` for the child scope SHALL be `14`

#### Scenario: Delivery field is honored only at the root

- **GIVEN** a root scope with `[learn]` `branch = "learn"` and a child scope declaring `[learn]` `branch = "child-learn"`
- **WHEN** the system computes the effective delivery configuration
- **THEN** the effective delivery `branch` SHALL be `learn` from the root scope
- **AND** the child scope's `branch` value SHALL NOT take effect

#### Scenario: Per-scope opt-out via enabled

- **GIVEN** a child scope with `[learn]` `enabled = false`
- **WHEN** the system computes the effective config for the child scope
- **THEN** the effective `[learn].enabled` for that scope SHALL be `false`
