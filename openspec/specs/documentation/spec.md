# documentation Specification

## Purpose
TBD - created by archiving change add-baton-mvp. Update Purpose after archive.
## Requirements
### Requirement: DocC Catalog

The system SHALL include a DocC catalog (`Baton.docc`) attached to the executable target and SHALL depend on `swift-docc-plugin` (guarded off on Windows where the plugin is unsupported), so documentation can be generated from the package.

#### Scenario: Documentation generates from the package

- **WHEN** `swift package generate-documentation --target <BatonCLI>` runs
- **THEN** it SHALL produce DocC documentation for the executable target from the `Baton.docc` catalog

#### Scenario: DocC plugin is excluded on Windows

- **WHEN** the package is resolved on Windows
- **THEN** the `swift-docc-plugin` dependency SHALL NOT be required

### Requirement: Static-Hosting Build

The system SHALL generate documentation transformed for static hosting under the `baton` hosting base path, writing the output to a `docs/` directory and a root `index.html` that redirects to the rendered documentation.

#### Scenario: Static site is produced under the base path

- **WHEN** the documentation is generated for static hosting
- **THEN** the output SHALL be written to `docs/` transformed for static hosting with hosting base path `baton`
- **AND** a `docs/index.html` SHALL redirect the site root to the rendered documentation path

### Requirement: GitHub Pages Deployment

The system SHALL provide a workflow that deploys the generated documentation to GitHub Pages on release tags (and via manual dispatch), using the Pages deployment actions.

#### Scenario: Docs deploy on a release tag

- **WHEN** a version tag matching `v[0-9]+.[0-9]+.[0-9]+` (including a prerelease suffix) is pushed
- **THEN** the workflow SHALL build the static documentation and deploy it to GitHub Pages

#### Scenario: Docs deploy can be triggered manually

- **WHEN** the documentation workflow is dispatched manually
- **THEN** it SHALL build and deploy the documentation without requiring a new tag

