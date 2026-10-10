# SDDE

SDDE is a native Zig workflow engine under development. It loads validated
`*.workflow.yaml` definitions from the configured `paths.workflows` root and
executes a selected graph of registered operations. Workflow definitions supply
data and transitions, never executable code or capabilities.

The initial SDD suite is `specify -> plan -> tasks -> implement`. Those are
workflow definitions with predecessor gates, not a fixed engine registry.
Models propose candidate data; deterministic validators, explicit approvals
and publication evidence control workflow authority.

## Current implementation

- Configuration and root validation, workflow discovery/compilation, generic
  execution, toolchain composition and conditional provider bootstrap are implemented.
- Workflow-owned model requests retain their identity, binding, resources and
  schema across explicit YAML operations. Production Bedrock inference and
  optional token counting use the same provider boundary. Calls account actual
  API token usage against the execution budget; providers own per-call limits.
- Specify connects Markdown ingestion, source-backed extraction, reconciliation,
  specification generation, validation, authorized atomic repair and registered
  output publication. Evidence selections resolve to engine-owned citations;
  repair retains exact old values, revisions, dependencies and producing-call evidence.
- Authenticated clarification-answer application and remaining semantic-review,
  workload and publication assurance work are open. Connected
  generation does not establish complete Specify acceptance. See
  [F0100](design/features/F0100-SpecWorkflow.md) and the
  [current FIX01 review and remaining work](fixes/FIX01.md).
- The development harness runs real generation and grades the actual published
  specification through the selected OpenAI or Bedrock evaluator. A successful
  scored live baseline, human rubric calibration and broader acceptance remain
  outstanding. Offline tests are not E2E evidence.
- Plan, Tasks and Implement remain proposed workflow work.

Each invocation starts its selected workflow at `start`. Candidate output stays
private until complete validation permits publication. Publication failure may
leave replaced files, but cannot report success or record new successful
completion. There is no transaction/recovery store or saved continuation.
Reruns overwrite registered replaceable outputs and unresolved clarification
forms at the same paths, retain clarification identities and applicable answers,
and preserve user-closed forms byte-for-byte. See
[ADR 0009](design/decisions/0009-atomic-workflow-execution.md).

`needs_user` is a normal clarification pause: the CLI exits 0 and lists the open
form IDs and paths. It does not mean the workflow completed. The E2E harness
reports `awaiting_clarification` with publication/grading `not_run`; only
`evaluated` establishes its published/scored baseline.

## Build and verify

Use **Zig 0.16.0 exactly**, as pinned in [.zigversion](.zigversion),
[build.zig.zon](build.zig.zon) and [build.zig](build.zig).

```sh
zig build
zig build lint
zig build test
zig build smoke
zig build verify
```

`verify` runs formatting/AST checks, all unit and integration tests, architecture
checks and clean native packaging smoke tests. It makes no live API calls and
needs no credentials. Packaging smoke runs the executable in isolated temporary
projects with a cleared environment and no source-tree fallback. Smoke subprocesses
use the same application entry points with native model connections compiled out;
the production executables are also compiled. Live transport execution is reserved
for manually approved harness runs.

Use `zig build --help` for the repository's individual test steps. There is no
separate changed-scope aggregate; run the relevant owning-boundary steps during
iteration and `zig build verify` before completing cross-cutting work.

`zig build test` runs offline checks of engine internals.
`./scripts/test-integration.sh` runs the workflow scenarios, fixed offline harness
and launcher checks through `zig build test-integration`. The integration test
executable always uses `ReleaseSafe` optimization with runtime safety checks;
no command-line options are required.

Each script run prints a pass/fail summary and saves its complete output to a
unique `.zig-cache/test-integration.*` file, whose path is printed at startup.
Successful runs keep expected workflow-failure logs in that file; failed runs
also display the complete output and preserve the build's exit status.

Temporary-project workflow
scenarios live in `test/integration/workflow_tests.zig` and are excluded from the
unit-test import tree. `zig build verify` includes both
as separate steps, plus architecture and smoke checks. The numbered
specification scenarios exercise engine behavior with fake model responses;
they do not assess prompt quality. The separately invoked live `e2e-spec`
command runs the configured LLM and grades its published output against the
rubric.

The specification-generation integration matrix emits tab-separated
`scenario-cost` rows to stderr, with the zero-based scenario index, outcome and
milliseconds spent in fixture setup, bootstrap, runner setup, execution,
assertions and cleanup. `scenario-total` reports phase totals and measured/total
scenario counts, including partial runs. If a scenario fails early, its cleanup
time is included in the phase that failed. Capture a full run for comparison with:

```sh
zig build verify --summary all > .zig-cache/verify-costs.log 2>&1
```

## Configure and run a workflow

Run the executable from the target project's root. Bootstrap reads only that
working directory's exact `.sddtoolkit.json`, validates its configured locations,
and compiles every discovered workflow before selecting the requested ID.
It does not search parent directories or use repository examples as defaults.

Specify's registered invocation takes independent target and reference selectors:

```text
sdde <workflow-id> --feature <feature-directory> --reference <reference-selector>
```

The workflow ID comes from the definition's `id`, not its filename. The supplied
[Spec definition](design/workflows/spec.workflow.yaml) declares `spec-generation`.
`--feature hello-world` selects `<paths.specs>/hello-world/`; `--reference`
selects beneath `paths.references`. Other workflows use their own registered
invocation contracts. See the [path contract](design/paths.md) and
[workflow configuration](design/features/F0100-SpecWorkflow.md#2-closed-yaml-shape).

Provider configuration is captured only when the selected compiled graph needs
model binding or provider calls. Repository slots authorize exact catalogue
entries; binding data alone grants no provider capability. Production Bedrock
credentials come from `AWS_BEARER_TOKEN_BEDROCK`. Models, regions and supported
controls are described in [F0007](design/features/F0007-AWSBedrockProvider.md).
The engine does not load `.env.e2e` or use internal `TEST_` credentials.

## Debug one LLM request

Set `logs.level` to `debug` or `trace` to retain complete credential-redacted
requests, responses, prompt/context/schema and caller attribution. From the same
project root, open a captured feature with:

```sh
sdde --debugger <feature-directory>
```

Open the local session URL printed by the executable. Select a call to inspect
Prompt, Context (structured or exact raw content), Schema, Request and Response.
Calls are grouped by run and numbered in execution order using the captured log
sequence. Prominent call-type badges distinguish Initial, Repair, Retry, Context
follow-up and Replay. The call-type filter narrows the list; filtering preserves
call numbers. Source links name the related call, such as “Repair of Call 8”.
Retries and repairs remain in their execution positions and link to their original
and preceding calls. The always-visible Workflow origin panel identifies the
workflow, expanded calling YAML entry, registered action, request-preparation entry
and model slot. Sidebar entries label the workflow and YAML caller, and search
includes both call and preparation entries. Replays explicitly identify the user
Replay command as their initiator and retain the captured workflow origin. Response
inspection separates provider bytes, extracted text, parsed JSON and schema diagnostics.

The Replay tab sends **one selected prompt once**. Exact replay preserves request
bytes; modified replay lets you edit its prompt, context or schema. Each click may
incur provider charges and saves a new linked record under the feature's
`logs/debugger`; original captures remain unchanged. Current provider authorization
and credentials are required. Replay does not run workflow nodes or semantic
validators, publish artifacts, or change workflow state.

The UI is embedded in the executable. Captures use `prompt-columns/v3`; older
prompt formats are rejected. Request descriptions use `model-request-debug/v2`
and retain the exact selected response schema; older descriptions are rejected.
Replays use `request-replay/v4` records with a saved
session and dispatch sequence; older replay records are rejected. Replay sessions
are separate from workflow runs, each with its own execution order. Rejected replay
requests can leave gaps in session numbering. Stop the server with Ctrl-C. See
[ADR 0019](design/decisions/0019-single-request-debugger.md).

Workflow origin links open captured sources in the **Sources** tab. Follow the
call chain from the top-level YAML entry through nested subgraphs to the model
invocation, or follow request assembly to its bound prompt, schema, input and
composition resources. YAML entries have structural selectors (for example
`/subgraphs/request/steps/prepare`), a structured declaration view, and the exact
captured YAML file. JSON resources show selected schema definitions and composition
parts/paths when applicable. **Request** remains the exact assembled provider body.

Snapshots come from the execution's loaded files; editing or deleting current
workflow files does not change them. Credential redaction is marked. Replays retain
the original snapshots and identify modified input as overrides. Calls without a
source snapshot explicitly show that source navigation is unavailable.

## Development evaluation

[Live E2E instructions](design/harness/e2e.md) cover credential setup, case
selection, retained evidence and result interpretation. Each agent-initiated
E2E run requires explicit user approval under [AGENTS.md](AGENTS.md).

```sh
./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

Automated tests and verification cannot make live model calls. Test executables
compile out native model connections, and automated build steps reject dependencies
on live harness execution.

The launcher requires an explicit case and loads the checkout's optional
`.env.e2e`. It uses real APIs for both generation and grading. The
[supplied-spec evaluator](design/harness/evaluator.md) separately grades a given
specification; it cannot establish engine-generation success. Neither harness
ships with the production executable.

To test one captured generation request, use the separate
[call diagnostic](design/harness/e2e.md#test-one-captured-call) with an explicit
retained run, workflow ID, physical call ordinal, registered model and reasoning
effort:

```sh
./scripts/e2e-call.sh \
  --run 'zig-out/e2e-spec/<UTC-date-time>-<unique-id>' \
  --workflow spec-generation --call 1 \
  --model openai.gpt-oss-20b-1:0 --reasoning-effort high --repeats 3
```

Replace the run placeholder with a real capture; the command never selects the
latest run automatically. Each repeat sends one request, with no automatic retry,
repair, workflow execution, publication or grading. It preserves source captures
and saves protocol/schema inspection and usage beneath `zig-out/e2e-call/`;
semantic quality is not assessed. The launcher shares `.env.e2e` setup with
`e2e-spec.sh`; `--help` and offline builds make no API calls. Live diagnostics
require explicit approval for the selected calls and repeat count. They do not
establish full-workflow E2E acceptance or change browser replay behavior.

The separate [authoring-role calibration](test/calibration/authoring-roles/README.md)
uses `zig build calibrate-roles` to prepare explicit controlled/captured assignment
comparisons without API calls. Human-reviewed labels and bounded approval precede
`--live` diagnostic trials. It reuses production packets, role admission and request
replay; it is neither an E2E case nor workflow authority.

## Documentation

| Document | Purpose |
| --- | --- |
| [Governing design](design/design.md) | Proposed implementation baseline, invariants and acceptance criteria. Accepted ADRs amend the named contracts without accepting the whole design. |
| [Accepted decisions](design/design.md#32-accepted-and-deferred-implementation-choices) | Language, compiler, runtime, provider, request and publication decisions. |
| [Contract samples](design/code.md) | Illustrative shapes and links to their owners; not an alternate runtime schema. |
| [Feature contracts](design/features/) | Component responsibilities, implementation scope and verification requirements. |
| [Diagrams](design/diagrams/) | Markdown-fenced Mermaid views of the architecture and workflows. |
| [Harness backlog](design/harness/README.md) | Remaining integration, calibration and live acceptance work. |
| [FIX01](fixes/FIX01.md) | Current corrective focus, code findings, remaining work and required acceptance evidence. |
| [Fix records](fixes/README.md) | Active tracking and historical decision/evidence records. |

### Fix records

[FIX01](fixes/FIX01.md) is the sole active fix record. Keep outstanding work and
its implementation/verification status there; remove completed tasks from active
tracking. Completed FIX01 work and its supporting dated reviews live in
[Z_FIX01](fixes/Z_FIX01.md); older records and experiments remain under
`fixes/archive/`. Historical proposals and status statements do not
create current work, grant approval or establish successful live acceptance.

[Templates](design/templates/), [legacy preset source examples](design/toolchainPresets/)
and [configuration examples](design/examples/) are design inputs. They are not
an engine constitution, automatically installed policy or runtime fallback.
The [preset authoring guide](design/toolchainPresets/README.md) distinguishes the
source examples from the implemented closed input contract.
This checkout develops SDDE; running it against a target project requires an
explicit target and workflow.
