# ci Specification

## Purpose
TBD - created by archiving change add-baton-mvp. Update Purpose after archive.
## Requirements
### Requirement: Lint, Build, And Test on Push and PR

The system SHALL provide a CI workflow triggered on push to `main` and on pull requests that runs a lint job and per-platform build-and-test jobs, where the build jobs depend on the lint job passing first.

#### Scenario: CI runs on a pull request

- **WHEN** a pull request targeting `main` is opened or updated
- **THEN** CI SHALL run a lint job (`format-check` plus `lint`) and, on its success, build-and-test jobs
- **AND** the build and test steps SHALL pipe `swift` output through `xcsift`

#### Scenario: In-progress runs are superseded

- **WHEN** a newer commit is pushed to the same ref while CI is running
- **THEN** the in-progress run for that ref SHALL be cancelled via a concurrency group

### Requirement: Cross-Platform Build Matrix

The system SHALL build and test on macOS (Swift 6.3) and Linux (the `swift:6.3` container), and SHALL build on Windows on a best-effort basis, caching the SPM `.build` directory keyed on the Swift version and `Package.resolved`.

#### Scenario: macOS and Linux build and test

- **WHEN** CI runs the build matrix
- **THEN** the macOS job SHALL build the tests and run `swift test` through `xcsift`
- **AND** the Linux job SHALL build the tests and run `swift test` through `xcsift`

#### Scenario: Windows is best-effort

- **WHEN** CI runs on Windows
- **THEN** it SHALL resolve dependencies and build in release/debug
- **AND** a Windows build failure SHALL be treated as best-effort per the project's Windows policy

#### Scenario: SPM build cache is reused

- **WHEN** CI runs and `Package.resolved` is unchanged from a prior run on the same Swift version
- **THEN** the `.build` cache SHALL be restored to speed up the build

### Requirement: Workflow Linting

The system SHALL lint its GitHub Actions workflow files with `actionlint` as part of the lint job.

#### Scenario: actionlint runs in CI

- **WHEN** the lint job runs
- **THEN** it SHALL run `actionlint` over the workflow files
- **AND** an `actionlint` error SHALL fail the lint job

