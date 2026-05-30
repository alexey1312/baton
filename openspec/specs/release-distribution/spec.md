# release-distribution Specification

## Purpose
TBD - created by archiving change add-baton-mvp. Update Purpose after archive.
## Requirements
### Requirement: Tag-Triggered Release Build

The system SHALL provide a release workflow triggered by pushing a version tag matching `v[0-9]+.[0-9]+.[0-9]+` (with an optional prerelease suffix) that builds release `baton` binaries for macOS and Linux (Windows best-effort) and uploads them as workflow artifacts.

#### Scenario: Release builds platform binaries on a tag

- **WHEN** a tag matching `v[0-9]+.[0-9]+.[0-9]+` is pushed
- **THEN** the workflow SHALL build a release `baton` binary for macOS and for Linux
- **AND** SHALL upload each platform's archive as a build artifact

#### Scenario: macOS binary is universal

- **WHEN** the macOS release binary is built
- **THEN** it SHALL be a universal binary combining `arm64` and `x86_64` (via `lipo`)

#### Scenario: Prerelease tags are marked prerelease

- **WHEN** the pushed tag contains a prerelease suffix (e.g. `-beta.1`)
- **THEN** the resulting GitHub Release SHALL be marked as a prerelease

### Requirement: Changelog And GitHub Release

The system SHALL generate release notes with `git-cliff` from Conventional Commits and SHALL create a GitHub Release for the tag with those notes and the platform archives attached, and SHALL update the repository `CHANGELOG.md` for non-prerelease tags.

#### Scenario: Release is created with notes and artifacts

- **WHEN** the release workflow runs for a tag
- **THEN** it SHALL produce release notes via `git-cliff`
- **AND** SHALL create a GitHub Release carrying those notes and the built platform archives

#### Scenario: CHANGELOG updated for stable releases

- **WHEN** a non-prerelease version tag is released
- **THEN** the workflow SHALL regenerate `CHANGELOG.md` with `git-cliff` and commit it to `main`

### Requirement: Homebrew Tap Distribution

The system SHALL, on a non-prerelease release, update the Homebrew formula `Formula/baton.rb` in the tap repository `alexey1312/homebrew-tap` with the new version and the SHA256 of the released macOS and Linux archives, so users can install via `brew install alexey1312/tap/baton`.

#### Scenario: Tap formula bumped on a stable release

- **WHEN** a non-prerelease version is released
- **THEN** the workflow SHALL compute the SHA256 of the released macOS and Linux archives
- **AND** SHALL update `Formula/baton.rb` in `alexey1312/homebrew-tap` with the new version and those checksums
- **AND** SHALL commit and push the formula change to the tap

#### Scenario: Prerelease does not update the tap

- **WHEN** a prerelease version is released
- **THEN** the Homebrew tap SHALL NOT be updated

### Requirement: mise Install Channel

The system SHALL attach the platform archives to each GitHub Release so the tool is installable through `mise` using its github backend (e.g. `mise use -g github:alexey1312/baton`).

#### Scenario: Releases feed the mise github backend

- **WHEN** a release is published with platform archives attached
- **THEN** the archives SHALL be named and attached such that `mise` can install the `baton` binary via its github backend from that release

