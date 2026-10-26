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
  schema across explicit YAML operations. Production Bedrock inference uses the
  provider boundary. Calls account actual API token usage against the execution
  budget; providers own per-call limits. ADR 0030 (accepted) removed provider
  token counting and moved the request deadline to each model's catalogue entry
  (`requestTimeoutMs`); its replacement of those operations with one
  `request-model` step is not yet implemented.
- Specify connects Markdown ingestion, source-backed extraction, reconciliation,
  specification generation, validation, authorized atomic repair and registered
  output publication. Evidence selections resolve to engine-owned citations;
  repair retains exact old values, revisions, dependencies and producing-call evidence.
- Authenticated clarification-answer application and remaining semantic-review,
  workload and publication assurance work are open. Connected
  generation does not establish complete Specify acceptance. See
  [F0100](design/features/F0100-SpecWorkflow.md) and the
  [current FIX05 review and remaining work](fixes/FIX05.md).
- The development harness runs real generation and retains the actual published
  specification, with its sources and rubric, for human adjudication; no model
  grades an E2E run. An adjudicated live run, a scored live baseline, human rubric
  calibration and broader acceptance remain outstanding. Offline tests are not E2E
  evidence.
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
reports `awaiting_clarification`; only `generated` records a completed
publication, whose development acceptance still requires human adjudication.

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

Every `zig build` reruns every test binary, even with an explicit `--seed`. While
iterating, `-Dreuse-test-runs` (for example `zig build test -Dreuse-test-runs`)
skips a test run that already passed, but only if none of the following changed
since that step last ran:

- the test binary, its arguments and its working directory;
- every file that Git lists through the repository's `.gitignore` files, tracked
  or untracked, by content and executable bit;
- the ignored locations that tests read, listed in `build/test_run_inputs.zig`;
- the Git revision and the `git` version;
- the passed environment, which is `PATH` and `HOME` only.

Credential-like paths, and paths hidden only by your own Git excludes, are keyed by
size and modification time and never read. Any other symbolic link or hard-linked
file makes an opt-in build fail, because its content can live outside what the key
reads.

Each keyed run is also confirmed. Before it starts, it is marked pending in the
build cache under a name unique to that build. The mark clears only if no
Git-listed file changed while the run executed, not even an edit that was then
reverted. A run that fails, is interrupted or can't be confirmed keeps its mark,
and any remaining mark changes every later key, so that result is never reused.
Changes inside the ignored locations during a build aren't checked, because the
tests write there themselves. Only one opt-in build at a time can use a given build
cache; a second one fails at start. Deleting the build cache clears its marks. Zig
never reuses a failing run.

With `--summary all`, the build summary marks a reused run `cached`; the default
summary prints nothing on success. `zig build verify` and
`./scripts/test-integration.sh` refuse the option, so verification evidence
always comes from fresh runs. `zig build test-build-reuse` proves these rules in a
throwaway repository.

Temporary-project workflow
scenarios live in `test/integration/workflow_tests.zig` and are excluded from the
unit-test import tree. `zig build verify` includes both
as separate steps, plus architecture and smoke checks. The numbered
specification scenarios exercise engine behavior with fake model responses;
they do not assess prompt quality. The separately invoked live `e2e-spec`
command runs the configured LLM and captures its published output for human
adjudication against the rubric.

Parser and schema matrices run at their owning unit boundaries; workflow tests
use representative cases to check routing, evidence and accounting. Historical
calibration inputs and results under `test/calibration` retain experiment evidence;
the automated suite does not pin every frozen panel's counts, model settings or
prompt bytes. Calibration and live E2E execution remain separately invoked.

The specification-generation integration matrix emits tab-separated
`scenario-cost` rows to stderr, with the zero-based scenario index, outcome and
milliseconds spent in fixture setup, bootstrap, runner setup, execution,
assertions and cleanup. `scenario-total` reports phase totals and measured/total
scenario counts, including partial runs. If a scenario fails early, its cleanup
time is included in the phase that failed. Capture a full run for comparison with:

```sh
zig build verify --summary all > .zig-cache/verify-costs.log 2>&1
```

Generate a repository-wide code heuristics report with:

```sh
zig build code-heuristics
```

Read [the Markdown report](zig-out/code-heuristics/report.md) or use
[the complete JSON measurements](zig-out/code-heuristics/report.json). The command
refreshes both files on every run (`--prefix` changes the output root).
It inventories tracked and unignored untracked Zig source in the repository root,
`src/`, `test/` and `build/`, excluding deleted files, generated output and
dependencies. Production, tests and development tooling are reported separately.
Git and the pinned Zig compiler are required; no model calls or credentials are used.

The report highlights file/function size, decision-token counts, brace depth and
identical function bodies after removing whitespace/comments. Thresholds are
advisory review signals, with their definitions and limits included in the report;
they do not assess semantic correctness or impose a CI gate. JSON contains all
measurements and candidates, including those omitted from the Markdown's ranked
function and duplicate lists. Test the reporter with `zig build test-code-heuristics`;
its tests also run in the canonical unit suite.

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

With `"logs": { "level": "debug", "console": true }` in `.sddtoolkit.json`,
the prompt stream beneath the feature's `logs/prompts` retains the entire available
provider response after credential redaction. Large responses span ordered chunks;
the chunk size does not truncate the response. Bedrock Converse reasoning is
retained as separate, owned diagnostics on complete, stopped and rejected provider
results, including when no final answer is available. The debugger's
**Response → Provider reasoning** card shows ordered readable blocks and identifies
provider-redacted blocks whose text is unavailable. **Raw provider response**
retains the original captured bytes; **Extracted model text** contains only the
candidate answer. Reasoning never becomes candidate JSON or workflow authority.
Interrupted transport retains all received bytes with explicit partial-response
provenance. `trace` also enables capture; `console` controls the console mirror,
not file capture.

The Replay tab sends **one selected prompt once**. Exact replay preserves request
bytes; modified replay lets you edit its prompt, context or schema. Each click may
incur provider charges and saves a new linked record under the feature's
`logs/debugger`; original captures remain unchanged. Current provider authorization
and credentials are required. Replay does not run workflow nodes or semantic
validators, publish artifacts, or change workflow state.

Older provider-specific chat captures remain inspectable as recorded evidence. Exact replay
rejects when their bytes differ from the current canonical Converse request;
there is no legacy wire codec or replay fallback.

The UI is embedded in the executable. Captures use `prompt-columns/v3`; older
prompt formats are rejected. Request descriptions use `model-request-debug/v13`
and retain the exact selected response schema, its native membership and coverage
constraints, the temperature each attempt sent, and the catalogue entry's `requestTimeoutMs`, which replay uses as its deadline; older descriptions are rejected.
Replays use `request-replay/v6` records with a saved
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

Live development tests permit only Bedrock `openai.gpt-oss-20b-1:0` from
`ap-southeast-2`, with native JSON Schema. Generation and the standalone
supplied-spec evaluator use the same explicit model tuple with separate settings
and accounting. `.sddtoolkit.json` supplies the temperature (`0.1`) and the runaway
re-send temperature (`1`) (ADR 0039); Spec generation and
repair select low reasoning. Sonnet, Sol, Haiku, Luna, direct OpenAI and unregistered selections
reject before credentials or network use. Luna remains registered for explicitly
configured production use; changing the test selection does not remove its codec.
These API contracts do not establish model quality or authorize a live run.

```sh
./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

Automated tests and verification cannot make live model calls. Test executables
compile out native model connections, and automated build steps reject dependencies
on live harness execution.

The launcher requires an explicit case and loads the checkout's optional
`.env.e2e`. It uses real APIs for generation only; no model grades the run. In
Claude Code, `/evaluate-e2e <run>` gives advisory rubric and defect-origin analysis
of a retained run. The
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
  --model openai.gpt-oss-20b-1:0 --reasoning-effort low --repeats 3
```

Replace the run placeholder with a real capture; the command never selects the
latest run automatically. Each repeat sends one request, with no automatic retry,
repair, workflow execution, publication or grading. It preserves source captures
and saves protocol/schema inspection and usage beneath `zig-out/e2e-call/`;
semantic quality is not assessed. The launcher shares `.env.e2e` setup with
`e2e-spec.sh`; `--help` and offline builds make no API calls. Live diagnostics
require explicit approval for the selected calls and repeat count. They do not
establish full-workflow E2E acceptance or change browser replay behavior.
Captured catalogues and controls must already admit the GPT-OSS-20B tuple and
selected reasoning effort; a catalogue captured before the 24 October 2026 deadline
move has no `requestTimeoutMs` and rejects.

The [historical authoring-role diagnostics](test/calibration/authoring-roles/README.md)
retain frozen experiment evidence. FIX03 Phase 5 removes that production classifier
and its development launcher. The pending representation panel preserves an
isolated old native executable; current authoring-association comparisons reuse
request replay and current admission. Labels, approvals and diagnostic results
remain separate from E2E and workflow authority.

## Documentation

| Document | Purpose |
| --- | --- |
| [Governing design](design/design.md) | Proposed implementation baseline, invariants and acceptance criteria. Accepted ADRs amend the named contracts without accepting the whole design. |
| [Accepted decisions](design/design.md#32-accepted-and-deferred-implementation-choices) | Language, compiler, runtime, provider, request and publication decisions. |
| [Contract samples](design/code.md) | Illustrative shapes and links to their owners; not an alternate runtime schema. |
| [Feature contracts](design/features/) | Component responsibilities, implementation scope and verification requirements. |
| [Diagrams](design/diagrams/) | Markdown-fenced Mermaid views of the architecture and workflows. |
| [Harness overview](design/harness/README.md) | Harness purpose, authority boundary and commands; open work is in FIX05. |
| [FIX05](fixes/FIX05.md) | Architecture review, current corrective focus, remaining work and required acceptance evidence. |
| [Fix records](fixes/README.md) | Active tracking and historical decision/evidence records. |

### Fix records

[FIX05](fixes/FIX05.md) is the sole active fix record. Keep outstanding work and
its implementation/verification status there; remove completed tasks from active
tracking. Completed work and its supporting dated reviews live in
[Z_FIX01](fixes/Z_FIX01.md) and [Z_FIX02](fixes/Z_FIX02.md); older records and
experiments remain under `fixes/archive/`. Historical proposals and status statements do not
create current work, grant approval or establish successful live acceptance.

[Templates](design/templates/), [legacy preset source examples](design/toolchainPresets/)
and [configuration examples](design/examples/) are design inputs. They are not
an engine constitution, automatically installed policy or runtime fallback.
The [preset authoring guide](design/toolchainPresets/README.md) distinguishes the
source examples from the implemented closed input contract.
This checkout develops SDDE; running it against a target project requires an
explicit target and workflow.
