# Live Spec E2E test

Run one live case from the repository root:

The checked-in [greeting](../../test/e2e/wf-001-hello-world/node-vitest/workflow.case.json)
and [loan-renewal](../../test/e2e/wf-002-loan-renewal/workflow.case.json) cases have
separate sources and rubrics and reference the same workflow/model configuration.

1. Review the case's explicit Bedrock `openai.gpt-oss-20b-1:0` generation
   selection from `ap-southeast-2`, then configure the same GPT-OSS-20B judge under
   [Environment setup](#environment-setup). Both cases share the native JSON
   catalogue; Spec generation, repair and grading select low reasoning. The
   registered profile uses temperature `0.1`.
2. Obtain explicit user approval for this E2E run under
   [AGENTS.md](../../AGENTS.md#testing-expectations).
3. Run the launcher with an explicitly selected live case:

   ```sh
   ./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
   ```

   The equivalent direct build command is:

   ```sh
   zig build e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
   ```

4. Inspect the retained generation, publication and rubric results under
   [Retained results](#retained-results).

### Launcher behavior

- The command makes live API calls for generation and grading; there is no mock mode.
- The script requires the pinned Zig compiler and locates the checkout from its own path.
- Case paths are repository-relative and must be supplied with `--case <path>`.
  The script has no default case.
- The shared [live-test cost policy](../../test/harness/model_cost_policy.zig)
  permits only `aws-bedrock` / `openai.gpt-oss-20b-1:0`. E2E preflight checks
  every configured generation slot and the judge selection before reading
  credentials or starting the workflow. Sonnet, Sol, Haiku, Luna, direct OpenAI
  and other aliases reject; no target is substituted.
- Automated tests cannot open native model connections, including with credentials
  present. Smoke subprocesses use the same application entry points with model
  connections compiled out. Test/verification build steps reject transitive dependencies on live
  generation or evaluation. Building or testing the harness never opts into a live run.
- The development script loads the checkout's `.env.e2e` for live invocations;
  `--help` does not source it. The executable does not load an environment file.
- The local file replaces values for names it exports. If absent, the script uses
  caller-injected variables.
- Direct `zig build e2e-spec` requires explicit shell environment setup, such as
  `. ./.env.e2e`.

## Test one captured call

`e2e-call` is a development diagnostic within the E2E harness. It selects one
captured generation call from an explicitly supplied prior E2E run and sends that
request with an explicit registered model and reasoning effort. The full workflow
command above remains the generation, publication and rubric-evaluation path.

After obtaining explicit approval for the selected live diagnostic and repeat count:

```sh
./scripts/e2e-call.sh \
  --run 'zig-out/e2e-spec/<UTC-date-time>-<unique-id>' \
  --workflow spec-generation \
  --call 1 \
  --model openai.gpt-oss-20b-1:0 \
  --reasoning-effort low \
  --repeats 3
```

Replace the quoted run placeholder with an actual retained run directory. `--run`
is repository-relative; there is no automatic latest-run selection. `--workflow`
is the captured workflow ID: the supplied Spec definition uses `spec-generation`.
`--call` is the positive physical call ordinal in the selected run, not a YAML step
number. All five selectors are required. `--repeats` is an optional positive
count and defaults to `1`. `--reasoning-effort none` explicitly omits reasoning
effort; other values must be supported by the selected model.

The selected run must retain its project/configuration, generation context and
request, and a complete current-format debug/trace request capture. Missing,
ambiguous, redacted or inconsistent captures reject before dispatch. Current
workflow sources cannot replace missing historical request data.

The launcher loads the same optional `.env.e2e` as `e2e-spec.sh`, with the same
local-file override behavior. It uses `TEST_AWS_BEARER_TOKEN_BEDROCK` for the
captured Bedrock provider; evaluator settings are not required. A direct invocation
uses the caller's environment:

```sh
zig build e2e-call -- \
  --run 'zig-out/e2e-spec/<UTC-date-time>-<unique-id>' \
  --workflow spec-generation --call 1 \
  --model openai.gpt-oss-20b-1:0 --reasoning-effort low
```

The selected model must resolve through the selected run's retained provider
catalogue and the current registered model-binding contracts. The diagnostic
creates an ephemeral in-memory binding:
it inherits the captured provider and takes the selected model's region from the
catalogue. Captured response mode and other inference controls, including an
optional output allowance, are preserved. Unsupported combinations reject before
dispatch; no model, response mode or control silently falls back. The effective
binding must also pass the live cost policy before the credential is read.
A current GPT-OSS-20B capture with compatible temperature/reasoning controls is
eligible. Retained catalogues must already authorize the requested GPT-OSS-20B
tuple. Historical captures with incompatible response modes or temperature controls reject; the
command does not rewrite those controls or add catalogue entries. The capture
and its configuration remain unchanged. Browser exact and modified replay retain
their existing model/settings restrictions.

The launcher reuses the canonical Bedrock Converse encoder and decoder. The
registered `BedrockRequestProfile` selects provider-specific fields through
`additionalModelRequestFields`, while supported common controls use
`inferenceConfig`. GPT-OSS-20B uses its registered reasoning-effort field and
temperature `0.1`. The separate registered Luna profile retains its required
`text.format.strict: true` field and omits temperature and explicit reasoning.
Complete engine validation still applies. No model-name prefix selects a
serializer or grants a capability.

Each dispatched repeat makes exactly one provider request. There are no automatic
retries, repairs, upstream nodes, workflow continuation, publication or evaluator
calls. Repeats are independent diagnostics against the selected captured request.
Responses remain untrusted diagnostic data and never become workflow authority.
Transport failure, cancellation or storage failure stops the remaining repeats;
the report records the completed count and incomplete result. A failed exchange
is never retried to fill that count.

Each invocation retains dated `report.json` and `report.md` beneath
`zig-out/e2e-call/<UTC-date-time>-<unique-id>/`, with immutable debugger request and
available response records linked to the source call. Reports expose protocol and
schema inspection, provider outcomes and actual usage. Semantic validation and
rubric quality assessment are **not assessed**. A schema-valid response does not
establish workflow success, publication, semantic correctness or complete E2E
acceptance. Compare every requested repeat, including failed exchanges.

`./scripts/e2e-call.sh --help` and building the harness make no provider calls;
help does not source `.env.e2e`. Offline integration tests use fake transport and
launcher probes. Approval to implement or test this command offline does not
authorize paid calls; each live diagnostic needs explicit bounded approval under
the [model-conformance contract](../contracts/28-testing.md#288-model-conformance-comparisons).

## Test one fresh provider exchange

`provider-compatibility` prepares the first model request of an explicitly
selected case through the production configuration, workflow compilation, request
preparation, authorization, provider and capture owners. It does not require a
prior E2E run or debugger capture. The first request depends on the selected
workflow; the supplied Spec case normally starts with reference extraction.
The command measures the provider boundary, not record-generation quality.

After separate explicit approval for this one-send live diagnostic, use:

```sh
zig build provider-compatibility -- \
  --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json --live
```

The development launcher accepts the same selectors:

```sh
./scripts/provider-compatibility.sh \
  --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json --live
```

`--case` is mandatory and repository-relative; there is no default or latest-run
selection. `--live` is an explicit dispatch opt-in, not a substitute for the
required user approval. Building the executable and offline verification make
no provider calls. The launcher uses the checkout's optional `.env.e2e` with the
same override rules as the other live harness launchers; help does not load it.
The direct executable uses the caller's environment. Only
`TEST_AWS_BEARER_TOKEN_BEDROCK` is needed for the selected model; no judge credential
or evaluation request is used.

Configuration preflight requires complete `trace` or `debug` capture and checks
every configured slot against the shared GPT-OSS-20B-only cost policy before
credential access. Production preparation validates the catalogue and selected request;
the send boundary independently checks the frozen binding/settings before
transport. The allowed binding is
`aws-bedrock / openai.gpt-oss-20b-1:0 / ap-southeast-2`, with native JSON Schema,
low reasoning and registered temperature `0.1`. The request inherits its configured
provider-requested output allowance and must match Phase 0's frozen 16,384 tokens,
as the supplied Spec slot does. This is an experiment setting, not an engine size
ceiling. Any supplied reasoning remains separately captured diagnostic data.
No historical request is retargeted and no alternative model or response mode
is substituted.

The transport permits **at most one physical inference send**. The attempt is
charged at the send boundary, so a transport failure does not permit a replacement
request. After that exchange the runner stops through a typed cancellation,
preserving any original rejection; another dispatch is rejected before transport.
Supplied usage from the observed exchange is retained before the stop.
Cancellation, missing usage, malformed output and
provider failures remain explicit outcomes. There are no retries, repairs,
rubric calls, workflow artifact publication or completion authority. Production
workflow outcome and provider-compatibility status are reported separately.
Before any invocation/step executes, typed compiled output/replacement keys and
side-effect policy are checked for publication capability. A publication-capable
child stops at `publication_prohibited`, even before the first exchange.

Each invocation retains `report.json` (`provider-compatibility-report/v1`) and
`report.md` beneath `zig-out/provider-compatibility/<UTC-date-time>-<unique-id>/`.
The report links available immutable request/response captures and records the
revision, exact model/settings, request/response identity and bytes, protocol and
schema checks, stop reason, actual usage, physical sends and any provider-supplied
reasoning. Unknown actual consumption is `total_actual_tokens: null` with
`usage_complete: false`; `total_accounted_tokens` separately preserves native
accounting. HTTP rejection alone is inconclusive because credentials or service
availability may be responsible. The report distinguishes `compatible`,
`incompatible`, `inconclusive`,
`input_invalid` and `harness_error`; missing evidence cannot produce a compatibility
pass. Read-only inspection reconstructs the canonical request and joins exact
request/response bytes and native identities with the trace's closed transport
outcome and production accounting metadata. The transport outcome owns HTTP
status/request ID when the native prompt archive has no HTTP status. Request and
response SHA-256 values retained from the trusted transport observation bind
external readback to the observed bytes and reject substitutions. These are
diagnostic byte identities, not engine state or predecessor authority. Bodies
retained from interrupted or uncertain delivery remain inconclusive without
candidate validation or invented usage. Reasoning signatures/redacted blocks
remain opaque and never become source or workflow authority. Semantic quality
and useful publication are not assessed.
A compatible first exchange qualifies only that observed request/settings; it
does not qualify every workflow request shape or establish complete E2E acceptance.

The [FIX04 Phase 1 gate](../../fixes/Z_FIX02.md#phase-1-implementation-and-live-gate)
requires both offline checks and an authentic retained exchange. Implementing and
testing this command offline does not close the live gate or authorize a run.

## Environment setup

1. From the repository root, create the optional local credential file:

   ```sh
   cp -n .env.e2e.example .env.e2e
   chmod 600 .env.e2e
   ```

2. Fill [.env.e2e.example](../../.env.e2e.example)'s declared values in the
   Git-ignored `.env.e2e`. Never put credentials in tracked configuration or
   command arguments.
3. Set generation to use `TEST_AWS_BEARER_TOKEN_BEDROCK`.
4. Explicitly set `TEST_EVALUATION_PROVIDER=bedrock`,
   `TEST_EVALUATION_MODEL=openai.gpt-oss-20b-1:0` and
   `TEST_EVALUATION_REGION=ap-southeast-2`. The judge uses the same
   `TEST_AWS_BEARER_TOKEN_BEDROCK` credential port as generation, with independent
   settings and accounting. Judge JSON specifies `reasoning_effort: "low"` and
   `temperature: null`; the registered profile normalizes temperature to `0.1`.
   Native JSON remains required; no fallback exists.
   See the [evaluator contract](evaluator.md#run).
5. For direct build/evaluator commands, load the file in the invoking shell:

   ```sh
   . ./.env.e2e
   zig build evaluate-spec -- --help
   ```

- The launcher sources the file itself; direct commands do not.
- Sourcing replaces values for exported names. Already-running processes retain
  their original environment; CI may inject the variables directly.
- Help and offline verification make no API calls.
- The production executable neither loads the file nor consumes `TEST_` variables.
- Each agent-initiated E2E run requires explicit approval under
  [AGENTS.md](../../AGENTS.md#testing-expectations). Configuration or an earlier
  approval does not authorize another run.

## Execution and quality assessment

For a first-call HTTP 403 with an API-key authentication message, inspect the
retained `response.json` and correct `TEST_AWS_BEARER_TOKEN_BEDROCK` in the credential
source above. The launcher reloads `.env.e2e`, including any stale exported value.
Authentication/authorization failures are terminal; JSON correction cannot repair
credentials. No model answer means no evidence yet about schema conformance.

- The harness captures the case's declared inputs and copies them into one new, isolated
  project.
- It shares `composition/root.zig.Runtime` with the CLI for adapter construction,
  bindings and cleanup, then runs one ordinary invocation through production bootstrap,
  provider catalogue validation, request preparation, authorization, HTTPS transport, YAML
  transitions, deterministic validators and publication.
- Generation uses the model slots explicitly selected by that test's
  `.sddtoolkit.json`; all configured slots must pass the current small-model cost
  preflight. The provider catalogue must declare `openai.gpt-oss-20b-1:0`
  with `json: true` in `ap-southeast-2`; Spec generation and repair select
  `reasoningEffort: "low"`. The compiled profile uses temperature `0.1`.
- The current production provider is Bedrock; its internal test credential is
  `TEST_AWS_BEARER_TOKEN_BEDROCK`.
- The harness supplies a validated credential snapshot to the shared runtime. The CLI
  supplies its environment, read only after model-binding validation. The runtime owns
  snapshot cleanup; neither path copies test credentials into production variables.
- Fixture checks and evidence tracing wrap the existing invocation bindings. The harness
  does not construct a second production runtime or choose model responses or graph edges.
- In-process checks and packaged CLI smoke checks retain their separate entry boundaries.

- After successful generation, the harness reads the specification actually published by
  that invocation and grades those exact captured bytes against the case's rubric.
- The judge selection uses `TEST_EVALUATION_PROVIDER`, `TEST_EVALUATION_MODEL`, the
  selected `TEST_` credential and any required region. The current permitted live
  grading combination is Bedrock / `openai.gpt-oss-20b-1:0` / `ap-southeast-2`.
- The case's `evaluation_config` supplies explicit reasoning, timeout, retry and
  total-budget settings; no provider or model is selected by a fallback.
- Judge settings and credentials are validated before generation starts.

- Generation retains the selected slot's optional output allowance under
  [ADR 0011](../decisions/0011-provider-owned-request-limits.md#optional-provider-request-output-allowance).
  The evaluator supplies no output allowance and delegates the provider default.
- The engine enforces the workflow's cumulative actual-token budget; the evaluator has
  its separate cumulative budget.
- Provider-owned response limits still apply and are reported as provider stops.
- Bedrock generation, grading and diagnostics share the Converse codec. GPT-OSS-20B's
  registered profile supplies native JSON Schema, the selected reasoning effort
  and temperature `0.1`, and projects any configured output allowance to
  `inferenceConfig.maxTokens`. Provider reasoning counts toward output usage;
  the engine accounts actual reported tokens separately from provider quotas.
  The separate registered Luna profile retains its strict JSON flag and omitted
  temperature/reasoning overrides. Its production capability contract remains
  available, but the live-test policy rejects it. Registration does not establish
  live compatibility or semantic quality for either model.

- Every generation call and both evaluator providers use the engine's short [universal
  JSON framing instruction](../decisions/0014-universal-response-format-guidance.md).
- The serializer emits it once, including retries; workflow templates retain only
  task-specific guidance.
- The actual emitted instruction is retained in each call's `request.json`.
- Closed schemas and strict response validation remain independent of whether the model
  follows that instruction.

- The selected case supplies the workflow, feature and reference selectors.
- A Spec case exercises Specify; Plan, Tasks and Implement need their own workflow cases.
- The copied resources are declared test inputs, not production source-tree fallbacks.
- Changes to the reference, including its UTC date/time requirement, are captured
  directly for both engine and judge.

## Case and publication contract

- The closed `spec-e2e-case/v1` declares workflow/feature/reference selection,
  configuration, explicit file mappings, empty directories, all four expected artifact
  kinds, `evaluation_case` and `evaluation_config`.
- The evaluation case names source documents and a rubric.
- Every selected reference must map exactly once to an evaluation source.
- Unknown or duplicate fields, unsafe paths, symlinks, destination collisions and
  pre-seeded feature output reject.
- Scripted provider responses and expected specifications are not case inputs.

- The harness requires an `ok` workflow outcome, runner-observed publication and all
  four readable, nonempty artifacts: specification, reference context, clarification
  state and workflow state.
- Each file must match the bytes prepared for that publication.
- This checks artifact identity, not semantic quality.
- A stale file, partial publication or in-memory candidate cannot satisfy the check.
- Only the engine's registered writer publishes output; the harness never exports or
  renders candidates to manufacture a specification.

- The rubric assesses semantic quality.
- A readable poor specification is passed unchanged to the judge after the engine's own
  gates accept it.
- There is no harness semantic prefilter or retry-until-good loop.
- Scores do not alter workflow state, resolve clarifications or authorize publication.
- Rubric revision 2 includes the user-added UTC date/time requirement and remains an
  uncalibrated draft; mechanical validation of a judgment is not proof that its semantic
  assessment is correct.

## Retained results

```text
zig-out/e2e-spec/<UTC-date-time>-<unique-id>/
  case.json       # exact selected workflow case
  inputs.json     # captured configuration/resources/source/rubric/settings
  report.json     # generation result and joined rubric evaluation
  report.md
  events.jsonl    # ordered production step outcomes and diagnostics
  build-inputs.json # allowlisted build sources and reconstruction status
  evidence/
    generation/call-000001/
      context.json       # request origin, attempt, prompt/input and schema
      request.json       # serialized provider request body
      response.json      # received provider response body, including invalid data
      model_output.txt   # complete final text when the provider exposes one
      outcome.json       # transport result and response metadata
    evaluation/call-000001/
      ...request, response, model output and outcome when available...
  project/
    ...declared inputs and actual engine output...
```

- The timestamp uses `YYYY-MM-DDTHH-MM-SSZ`; the unique suffix separates concurrent
  runs.
- Output paths come from validated project configuration.
- Reports are reserved before API calls.
- Captured inputs and the isolated project are retained on failure; input capture
  failures can leave only the case and failure report.
- Known test credentials are redacted from captured bodies; authorization headers and
  environment maps are excluded.
- Captured bodies are untrusted diagnostic data, not workflow authority.
- Evidence files are created exclusively with owner-only access and flushed as each
  exchange is observed.
- Every attempt gets its own directory; a retry cannot overwrite the rejected response.

- No response file is invented when the transport did not return a body, and no
  final-text file is invented for an unavailable or rejected provider result.
- Interruption, incomplete network reads, allocation failure or a failed evidence write
  can leave incomplete artifacts.
- Evidence write failures fail the E2E run; they cannot produce a successful quality
  result.
- Normal engine feature logging retains its separate configured capture and redaction
  policy.

- Reports preserve execution identity, engine outcome, selected generation models by
  slot, accounted usage, publication checks and separate provider/model rejections.
- Completed evaluations also retain exact source/spec/rubric bytes, judge configuration,
  attempts, criterion judgments, evidence and aggregate score.
- Source changes during execution fail the run without modifying retained inputs.

- For malformed model JSON, the shared engine decoder retains the native parser reason
  and available byte offset, line and column.
- The same diagnostic reaches the workflow's protocol retry, `events.jsonl`, both
  reports and terminal output.
- When the runner exhausts a configured retry limit, those outputs also retain
  `retry_error`: the owning operation instance, configured retry limit and completed
  execution count.
- The original JSON/schema diagnostic remains separate, so the response defect and the
  reason continuation stopped are both visible.
- Offsets are zero-based; lines and columns are one-based.
- These are parser cursor positions, not inferred field names.
- The terminal links to the retained model text and event stream.
- See the [prompt and response flow](../diagrams/17-model-prompt-response-flow.md) for
  the instructions actually sent to the model.

- Schema failures retain `schema_error.reason` and `schema_error.path`, an escaped JSON
  Pointer (for example `/statements/0/content/kind`), in the same event, report and
  terminal outputs.
- The engine's validator supplies this diagnostic; the harness does not infer or
  revalidate it.
- Protocol retries include the full rejected response as untrusted evidence and the
  original complete schema.
- Schema corrections retain the expected JSON Pointer and parent/value scope.
  Nested expectations include their exact schema fragment; root expectations use
  the already supplied selected schema once.
- Syntax corrections add the decoder diagnostic.
- Duplicate-member corrections also include the native decoder's brief explanation of
  property-name uniqueness within one object, without inferring record boundaries or
  choosing which value survives.
- Neither correction path synthesizes a candidate example.

- Lifecycle status and development acceptance are separate. `evaluated` records
  that scoring completed; it cannot by itself return command success.
- Cases declare `expected_outcome`. Both current source-complete cases require
  `publication`, so an unexpected native `needs_user` does not pass acceptance.
  An explicitly clarification-expected case still requires valid native partial
  publication, registered clarification handles and measured zero admission escape.
- Exit 0 requires passed acceptance and finalized reports. Missing thresholds,
  critical human-score failures, uncertainty, missing human adjudication and
  unexpected terminal outcomes cannot pass. Native workflow state remains unchanged.
- See [R8 acceptance](acceptance.md) for approved numeric/human authority, refreshed calibration panels and the offline
  human adjudication command.
- Evaluator failure preserves a successfully published specification.

The terminal prints the score and threshold result explicitly.

- Source-selection failures retain their scope, candidate revision, claim/citation
  indices, rejected selection, admissible range and producing request/attempt.
- `candidate_model_call`, `candidate_model_step` and `candidate_model_output` join that
  origin to the captured call, even after the request has been released.
- They can differ from `last_model_*`.
- Repair preserves untouched siblings' origins.
- The event stream and terminal consume the engine diagnostic; they do not infer the
  cause or reparse the response.
- Unknown, missing and reversed selections use the existing atomic replacement path;
  stale source authority cannot enter it.

- Reconciliation failures retain their partition, affected record/collection, rule,
  observed/expected constraint, revision and origin.
- Specification failures retain the native field/record failure before repair
  authorization.
- Both reach the same `candidate_error` projection.
- Authorizers consume retained native rejections, check owner/revision/origin/old-value
  association and never rediscover domain rules.
- Reconciliation repairs use the shared atomic authorization and full revalidation path.

- Step events place actual-call identity, output and token usage in `exchange`, and
  rejected-candidate identity/output in `candidate_source`.
- A candidate can come from an older call.
- Missing, ambiguous or foreign joins fail evidence capture.
- Reports retain `terminal_step` and the typed `terminal_rejection` independently of
  `last_model_*`; unavailable output text is stated explicitly.
- These are opt-in harness diagnostics.
- Production metadata logging does not gain raw prompts, source text or candidate
  values.

Reports embed the development harness's build-time source digest, Git revision,
modified-source flag, Zig version, target and build mode. The digest covers build,
engine, harness, test, design and script inputs, including untracked source files;
`build-inputs.json` retains those UTF-8 bytes, tracked status, permissions and deleted
paths. Credential paths are excluded before reading. Known run credentials are
redacted before storage. Unavailable, excluded, non-UTF-8 or redacted inputs make
the bundle explicitly incomplete; `report.build.reconstruction` distinguishes that
from a captured snapshot or a snapshot not saved. Declared dependencies remain
identified by `build.zig.zon`; their downloads and the compiler/toolchain must still
be available to rebuild. Git runs only in the development provenance build step.
These bytes are development evidence, never workflow authority or recovery state.
The snapshot permits source reconstruction when complete, not a guarantee of an
identical binary or future provider response. Exact request replay remains a
separate byte-equality check and rejects redacted parents.

Harness reports and captured inputs use ordinary typed JSON serialization, including
fractional evaluator temperatures, rubric thresholds and scores. They are diagnostic
projections; the engine's integer-only canonical state contract does not apply.
The saver renders both report views before writing, preserves exclusive creation
and durable writes, and releases its intermediate buffers. A report-file failure
leaves the workflow status and cause unchanged: the CLI prints the workflow result,
separately reports the finalization error and potentially incomplete files, and exits
unsuccessfully even if generation and evaluation succeeded. It does not retry writes
or rerun the workflow/evaluator to repair reporting.

`total_token_budget`, `retry_settings` and `attempts` project the executed graph
and native accounting. Per-call usage survives budget rejection before candidate
text projection. `exchange_evidence` links retained response bytes and distinguishes
absent responses, budget stops, other missing text and capture failure. Known
transport phases/causes remain separate from delivery and retry policy; unknown
causes stay unknown. Recognized provider failures survive request release.
`last_protocol_rejection` keeps its own call/request/attempt when a later exchange
fails for another reason. `last_provider_rejection` independently retains provider
content diagnostics after request retirement; `provider_origin` is independent of
the latest exchange's identity. Failures before a physical call cannot inherit an
earlier exchange's call or origin. Events include `provider_content_diagnostic` directly.
None of these projections creates another counter.

Operation failures retain their closed native error names through bindings, runner,
CLI, telemetry and reports. Allocation failure crosses that boundary by value without
allocating a diagnostic or applying a failed delta. Expected domain rejections keep
their existing typed outcomes and may carry a native cause; that evidence cannot
accompany success. Omission-authorization rejection additionally retains the reviewed
revision, outstanding candidate-defect requirements and review origin. A review
origin is not attributed as the producer of the generation defect.

`first_native_rejection` identifies the earliest captured native rejection and event sequence,
not a proven initial semantic cause. `corrections` project accepted native repair
permits, target keys, revisions and actual invalidation/rebuild links. `outstanding_work`
lists invalidated data keys not rebuilt, with the event that invalidated each; it may
include intentionally retired transport data and does not independently determine
workflow completion. Rejected deltas create no applied-effect evidence. Each fresh
invocation starts a new projection; earlier recovered errors remain historical.

`admission_audit` records admitted extraction, reconciliation, specification,
source-review questions and source-validated clarification projections with their
native subject, field policy, canonical value and original source bytes. Its closed
`Producer` distinguishes a model call, a proven native projection and unavailable
provenance. A model producer retains its exact request/attempt origin and must join
its physical receipt. A reused summary retains the native `carried_from` identity,
validation digest and an exact earlier child-check link; an unknown model parent
cannot be relabelled as native. Refreshed clarification questions retain their
native clarification ID, state identity/revisions and state digest. That is the
current source-aware native readback operation, not an invented historical model
origin. Missing model origins, missing physical receipts and missing native parents
remain explicitly unavailable.

The audit reruns the shared composition and source-aware wire-syntax checks; it
supplies no semantic judgment or workflow authority. The baseline's primary
`admission_escape` rate uses `invoked_native_workloads`: workloads with a retained
native report or physical receipt, including native failures before the first send.
Never-invoked setup failures and budget-stopped trials are excluded and counted
separately. Missing or incomplete audits on invoked workloads count as unknown;
measured and unknown coverage stay explicit. Known native projections can support
measured zero without manufacturing model calls. This diagnostic denominator is
separate from the comparison scorecard's dispatched-arm convention.

The secondary `distinct_observed_producers` diagnostic counts known model origins
and native projection identities. Repeated retained or assembled observations of
the same subject/value/producer do not inflate it. Downstream sends and actual usage
cover exchanges after the first observed escaped admission in the workflow:
chronological exposure, not causal cost. Unknown usage stays unknown. The baseline
scorer verifies these facts independently of assessor labels and keeps
`representation_admission` failure attribution separate from native paid-resource
stages.

The current closed report formats are `spec-e2e-report/v4`,
`baseline-acquisition/v3` and `baseline-score/v3`. Step events remain
`e2e-step-event/v2`; evaluator packets remain `baseline-assessment-inputs/v2` and
assessor documents retain numeric schema `2`. The compatibility report's outer
format remains `provider-compatibility-report/v1`. Earlier captures remain immutable
historical evidence; current readers reject superseded report versions and fields.

### Reliability assessment

- For reliability assessment, repeat the same selected case using `scripts/e2e-spec.sh
  --case <workflow.case.json>` with a fixed engine build, captured case/workflow inputs,
  model settings and rubric/evaluator configuration.
- Retain every run and compare completion rate, first-pass and post-repair acceptance,
  typed failure categories, criterion scores, threshold results, and total usage
  including failed attempts.
- Report evaluator failures separately.
- Different cases/models need separate results before aggregation.
- Mechanical tests establish contracts; repeated live completion and acceptable
  published output are separate evidence.
- A few successful runs do not establish reliability across unimplemented workflows or
  unseen inputs.

## Candidate validation and atomic repair

The repair prompt requests only the selected replacement. Domain guidance omits
engine-only insertion positions, absent optional metadata and unrelated constraints;
native authorization, evidence, current values and dependencies remain intact.
Metadata echoes and whole-candidate wrappers still reject against the selected schema.

- `candidate_error` records the native validator's structured diagnostic independently
  of JSON/schema errors and independently of whether the model request has already been
  released.
- For classification rejection it contains the chunk scope, revision, affected field,
  and all missing, duplicate, unknown and forbidden candidate IDs.
- Terminal output, `report.json`, `report.md` and `events.jsonl` project the same
  retained evidence.
- Successful repairs clear current rejection data; earlier step events remain available.
- Correlation follows the [shared diagnostic attribution contract](../contracts/27-observability.md).
  An assembled-candidate rejection retains its diagnostic without a fictitious model-call
  link. Required response provenance still needs one exact captured association. The last
  exchange and its per-call text-capture status remain separate from candidate attribution.

- Model-assisted repairs use the normal live provider path.
- Each attempt retains its request, context, provider response, final text and transport
  outcome like generation.
- The harness neither invents classifications nor rewrites responses.
- A repaired candidate must pass native validation before publication, and only the
  published output can receive a rubric grade.
- Unit tests of repair contracts and fake-provider integration tests are not live E2E
  evidence.

## Verification

- `zig build test-integration --summary all` runs fixed offline harness and
  launcher cases, including argument forwarding, publication identity, evidence
  capture and failure reports. It makes no provider calls.
- `zig build test-rubric-evaluator --summary all` checks judge mechanics offline.
- `zig build test-e2e-call --summary all` checks captured-call selection, diagnostic
  bindings, dispatch and report behavior offline.
- `zig build test-e2e-call-launcher --summary all` checks argument forwarding,
  checkout discovery and environment handling with fake Zig.
- `zig build test-provider-compatibility --summary all` checks fresh-request
  argument/preflight rules, one-send and publication guards, classification,
  partial/error capture and report finalization offline.
- `zig build test-integration --summary all` also exercises fresh production
  configuration/request/authorization through the real runtime with a fake first
  exchange, covering unrelated domains, cancellation, uncertain transport failure,
  capture failure, missing usage, malformed responses, noncandidate stops and
  exact request/response/accounting identity checks. These are integration tests,
  not authentic Bedrock or E2E evidence.
- `zig build test-provider-compatibility-launcher --summary all` checks explicit
  argument forwarding, environment handling and failure exit status with fake Zig.
- `zig build build-provider-compatibility` builds without provider calls;
  `zig build smoke-provider-compatibility --summary all` exercises standalone
  startup with live model connections compiled out.
- `zig build provider-compatibility -- --case <explicit-case-path> --live` is the
  separately approved live compatibility diagnostic; it is not a verification
  dependency, workflow publication test or rubric-quality measurement.
- `zig build build-e2e-call` builds the call diagnostic without API calls;
  `zig build smoke-e2e-call --summary all` checks its standalone startup and
  required selectors without live connections.
- These results establish integration and evaluator behavior, not prompt quality.
  Live generation and grading run separately through `./scripts/e2e-spec.sh`.
- `zig build smoke-e2e-harness --summary all` checks the standalone executable's startup
  and mandatory case selection in a clean directory without credentials.
- `zig build verify --summary all` includes mechanical tests, lint, architecture and
  native packaging checks.
- It does not launch live E2E cases.
- `zig build e2e-spec -- --case ...` runs live generation and grading.
- Only its retained results establish what happened in that E2E execution.
- `zig build evaluate-spec -- ... --live` separately grades a supplied file; it does not
  establish engine generation.
- See [evaluator.md](evaluator.md).

- Human rubric calibration and broader workflow/rerun/failure acceptance remain tracked
  in [H-016 and H-017](03-harness-verification.md).
- Earlier reports based on scripted generation or golden comparison are not live E2E
  evidence.

Active corrective work and required evidence are tracked in [FIX05](../../fixes/FIX05.md).
