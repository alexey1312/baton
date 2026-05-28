# agent-execution Specification

## Purpose
TBD - created by archiving change add-baton-mvp. Update Purpose after archive.
## Requirements
### Requirement: Centralized process execution

The system SHALL run every agent invocation through a single `ProcessExecutor` that reads stderr concurrently before waiting for the process to exit, sets the termination handler before starting the process, and enforces a per-invocation timeout.

#### Scenario: Concurrent stderr drain before waiting for exit

- **WHEN** an `AgentRunner` invocation is dispatched to the `ProcessExecutor`
- **THEN** the executor SHALL begin reading the process stderr concurrently
- **AND** it SHALL set the process termination handler before calling `run()` on the process
- **AND** it SHALL only wait for the process to exit after the stderr reader is draining, so the agent cannot deadlock by filling the stderr pipe buffer

#### Scenario: Timeout enforcement terminates a hung agent

- **WHEN** an agent process runs longer than the configured `timeout`
- **THEN** the `ProcessExecutor` SHALL terminate the process
- **AND** it SHALL surface a timeout error carrying a `recoverySuggestion`

### Requirement: Uniform invocation building

The system SHALL build every agent's `ProcessInvocation` generically, where the executable is `agent.binary` when set and otherwise the adapter's `defaultBinary`, and the arguments are the adapter's `baseArguments` followed by `agent.args`; this rule SHALL hold identically for every agent kind (claude, codex, gemini, opencode), fixing the blick PR #20 class of bug where the third-party agent layer ignored `binary` and `args`.

#### Scenario: binary override takes effect for any agent

- **WHEN** an `AgentConfig` sets `binary = "/opt/homebrew/bin/claude"` for an agent
- **AND** the invocation is built via `makeInvocation`
- **THEN** the `ProcessInvocation.executable` SHALL be `/opt/homebrew/bin/claude` instead of the adapter's `defaultBinary`
- **AND** this SHALL apply regardless of which `AgentKind` (claude, codex, gemini, or opencode) the adapter represents

#### Scenario: Custom args are appended for any agent

- **WHEN** an `AgentConfig` sets `args = ["--verbose"]`
- **AND** the invocation is built via `makeInvocation`
- **THEN** the `ProcessInvocation.arguments` SHALL be the adapter's `baseArguments` followed by `["--verbose"]`
- **AND** the user-supplied `args` SHALL never be silently dropped for any agent kind

### Requirement: Prompt delivery via stdin

The system SHALL deliver the assembled prompt to the agent process via stdin by default, so that prompt length is not constrained by `ARG_MAX`/`E2BIG` argument-length limits.

#### Scenario: Prompt streamed over stdin by default

- **WHEN** an adapter declares `promptDelivery == .stdin`
- **AND** the invocation is built and run
- **THEN** the assembled prompt text SHALL be written to the process stdin
- **AND** the prompt text SHALL NOT be placed in the process arguments

#### Scenario: Large prompt avoids argument-length limits

- **WHEN** an assembled prompt is large enough that passing it as a single argument would exceed the platform `ARG_MAX`
- **AND** prompt delivery is the default stdin mode
- **THEN** the invocation SHALL still run successfully because the prompt is sent over stdin rather than as an argument

### Requirement: Agent adapters

The system SHALL provide an `AgentRunner` adapter for each agent kind (claude, codex, gemini, opencode), and each adapter SHALL declare its `defaultBinary`, its headless `baseArguments`, its `promptDelivery` mode, and an output `parse` function that converts the agent's output into `[Finding]`.

#### Scenario: Each supported agent kind has an adapter

- **WHEN** the agent registry is consulted for any `AgentKind` in {claude, codex, gemini, opencode}
- **THEN** an `AgentRunner` adapter SHALL exist for that kind
- **AND** the adapter SHALL expose a non-empty `defaultBinary` and the headless `baseArguments` for that CLI

#### Scenario: Adapter parses agent output into findings

- **WHEN** an agent invocation completes and produces `AgentOutput`
- **THEN** the adapter's `parse(_:)` SHALL convert that output into an array of `Finding` values
- **AND** unparseable output SHALL raise an error carrying a `recoverySuggestion` rather than silently yielding zero findings

### Requirement: Isolated execution

The system SHALL run each agent in a fresh temporary working directory that is not the repository working tree, so the agent cannot modify the working tree; the code-built role block SHALL instruct the agent to use only the material provided in the prompt. When `context = "diff"` the agent SHALL receive only the scope's diff slice and no copy of the repository SHALL be placed in the working directory; when `context = "repo"` the working directory SHALL additionally contain a copy of the repository for cross-file reasoning. The system SHALL NOT attempt to block the agent's outbound network access, because the external coding CLI requires network egress to reach its model provider; egress allowlisting is out of scope for this change.

#### Scenario: Agent runs in a temporary working directory, not the repo tree

- **WHEN** an agent invocation is executed
- **THEN** its working directory SHALL be a fresh temporary directory rather than the repository working tree
- **AND** the agent SHALL therefore be unable to modify the repository working tree
- **AND** the assembled prompt SHALL instruct the agent to rely only on the provided material

#### Scenario: diff context provides only the diff

- **WHEN** the effective `context` for a review is `"diff"`
- **THEN** the agent SHALL receive only the scope's slice of the diff
- **AND** no copy of the repository SHALL be placed in the working directory

#### Scenario: repo context adds a repository copy for cross-file reasoning

- **WHEN** the effective `context` for a review is `"repo"`
- **THEN** the agent SHALL receive the diff
- **AND** the working directory SHALL additionally contain a copy of the repository (not the live working tree)

#### Scenario: Network egress is not blocked

- **WHEN** an agent invocation is executed
- **THEN** the system SHALL NOT deny the agent process outbound network access
- **AND** the untrusted-skill defense SHALL rely on the delimited prompt block rather than on a network sandbox

### Requirement: Model Selection

The system SHALL select the agent model from `[agent].model`; because `[agent]` is inherited closest-wins as a whole block, different scopes MAY use different models; `--model` (used together with `--agent`) SHALL override the resolved model at the CLI; each adapter SHALL map `model` to its CLI's model flag, and when `model` is unset the agent CLI's own default SHALL be used.

#### Scenario: Per-scope models invoke each agent with its own model

- **WHEN** a `web/` scope resolves `[agent].model` to model A and an `ios/` scope resolves `[agent].model` to model B
- **THEN** the `web/` review SHALL invoke its agent with model A mapped to that CLI's model flag
- **AND** the `ios/` review SHALL invoke its agent with model B mapped to that CLI's model flag

#### Scenario: --model overrides the resolved model

- **WHEN** `--model` is passed together with `--agent` on the CLI
- **THEN** the invocation SHALL use the `--model` value instead of the model resolved from `[agent].model`

#### Scenario: Unset model uses the agent CLI default

- **WHEN** the effective `[agent].model` is unset and no `--model` override is given
- **THEN** the adapter SHALL omit the model flag from the invocation
- **AND** the agent CLI's own default model SHALL apply

### Requirement: Agent Tool Availability

Before running tasks the system SHALL verify that each distinct resolved agent binary is available in `PATH`, failing fast with a `recoverySuggestion` that names the agent and how to install it; where an agent's authentication state is checkable, an unauthenticated agent SHALL produce a distinct `recoverySuggestion` describing how to authenticate that agent.

#### Scenario: Configured agent binary not found in PATH

- **WHEN** a configured agent's resolved binary is not present in `PATH`
- **THEN** the preflight SHALL fail fast before any task runs
- **AND** the error SHALL carry a `recoverySuggestion` naming the agent and how to install it

#### Scenario: Agent present but unauthenticated

- **WHEN** an agent binary is present in `PATH` but its checkable authentication state is unauthenticated
- **THEN** the preflight SHALL fail with a distinct error
- **AND** the error SHALL carry a `recoverySuggestion` advising how to authenticate that agent

### Requirement: Agent Failure Handling

The system SHALL handle a non-zero agent exit by raising a typed error that includes a tail of the captured stderr and a `recoverySuggestion`; SHALL also treat a zero exit with empty stdout as a failure (some CLIs print authentication or billing errors to stderr yet still exit 0), raising a typed error that surfaces the stderr tail rather than yielding zero findings; user-supplied `args` SHALL never be silently dropped, and when user-supplied `args` conflict with the required headless/JSON flags such that the agent output becomes unparseable, the resulting error SHALL note the likely cause.

#### Scenario: Agent exits non-zero

- **WHEN** an agent process exits with a non-zero status
- **THEN** the system SHALL raise a typed error
- **AND** the error SHALL include a tail of the captured stderr
- **AND** the error SHALL carry a `recoverySuggestion`

#### Scenario: Agent exits zero with empty output

- **WHEN** an agent process exits with status zero but produces empty stdout (e.g. an unauthenticated or over-budget CLI that writes its error to stderr and still exits 0)
- **THEN** the system SHALL treat the invocation as a failure rather than zero findings
- **AND** the error SHALL surface a tail of the captured stderr
- **AND** the error SHALL carry a `recoverySuggestion`

#### Scenario: User args break the required output format

- **WHEN** user-supplied `args` conflict with the required headless/JSON flags and the agent output cannot be parsed
- **THEN** the system SHALL raise a parse failure error
- **AND** the error SHALL carry a `recoverySuggestion` that notes the likely conflicting user-supplied argument as the cause

