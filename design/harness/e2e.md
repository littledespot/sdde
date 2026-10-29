# Live Spec E2E test

The checked-in [greeting](../../test/e2e/wf-001-hello-world/node-vitest/workflow.case.json)
and [loan-renewal](../../test/e2e/wf-002-loan-renewal/workflow.case.json) cases have
separate sources and rubrics and share one workflow/model configuration. To run one
live case from the repository root:

1. Review the case's explicit Bedrock `openai.gpt-oss-20b-1:0` generation
   selection from `ap-southeast-2`, and set its credential under
   [Environment setup](#environment-setup). Both cases share the native JSON
   catalogue; Spec generation and repair select low reasoning. The case's
   `.sddtoolkit.json` sets `temperature` `0.1` and `temperatureRunawayRetry` `1`
   ([ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md)).
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

4. Inspect the retained generation and publication results under
   [Retained results](#retained-results). No model grades the run. Assess the
   published specification against the case rubric through
   [human adjudication](acceptance.md#adjudicate-a-published-run-offline); in
   Claude Code, `/evaluate-e2e <run>` drafts an advisory rubric assessment and
   traces defects to the generation calls and prompts that produced them
   ([Rubric assessment](#rubric-assessment)).

### Launcher behavior

- The command makes live API calls for generation; there is no mock mode.
- The script requires the pinned Zig compiler and locates the checkout from its own path.
- Case paths are repository-relative and must be supplied with `--case <path>`.
  The script has no default case.
- The shared [live-test cost policy](../../test/harness/model_cost_policy.zig)
  permits only `aws-bedrock` / `openai.gpt-oss-20b-1:0`. E2E preflight checks
  every configured generation slot before reading credentials or starting the
  workflow. Sonnet, Sol, Haiku, Luna, direct OpenAI
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
command above remains the generation and publication path.

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
count and defaults to `1`. `--edit <file>` optionally names a repository-relative
closed JSON file, `{"content":[...],"schema":"..."}` in the captured `context.json`
content shape, that every repeat sends instead of the captured content and schema:
the debugger's modified replay
([ADR 0019](../decisions/0019-single-request-debugger.md)), validated by the same
canonical schema compiler and provider serializer before any call. Provider, model
and settings stay as selected; the report (`call-diagnostic-report/v2`) records the
edit file's SHA-256. `--reasoning-effort none` explicitly omits reasoning
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
catalogue. Captured response mode and other inference controls are preserved. Unsupported combinations reject before
dispatch; no model, response mode or control silently falls back. The effective
binding must also pass the live cost policy before the credential is read.
A current GPT-OSS-20B capture with compatible temperature/reasoning controls is
eligible. Retained catalogues must already authorize the requested GPT-OSS-20B
tuple. A catalogue captured before the 24 October 2026 deadline move has no
`requestTimeoutMs` and rejects
([ADR 0030](../decisions/0030-engine-owned-model-request.md#request-deadline)).
Historical captures with incompatible response modes or temperature controls reject; the
command does not rewrite those controls or add catalogue entries. The capture
and its configuration remain unchanged. Browser exact and modified replay retain
their existing model/settings restrictions.

The launcher reuses the canonical Bedrock Converse encoder and decoder. The
registered `BedrockRequestProfile` selects provider-specific fields through
`additionalModelRequestFields`, while supported common controls use
`inferenceConfig`. GPT-OSS-20B uses its registered reasoning-effort field and the
configured temperature. The separate registered Luna profile retains its required
`text.format.strict: true` field and omits temperature and explicit reasoning.
Complete engine validation still applies. No model-name prefix selects a
serializer or grants a capability.

Each dispatched repeat makes exactly one provider request. There are no automatic
retries, repairs, upstream nodes, workflow continuation, publication or evaluator
calls. Repeats are independent diagnostics against the selected captured request, or its
`--edit` replacement.
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
zig build provider-compatibility -- --case <case> --live
```

The development launcher accepts the same selectors:

```sh
./scripts/provider-compatibility.sh --case <case> --live
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
low reasoning and the configured temperature `0.1` (`1` on a runaway re-send).
Each request sends the catalogue's
recorded model maximum and no smaller allowance
([ADR 0011](../decisions/0011-provider-owned-request-limits.md#model-maximum-output)).
The shipped wf-001/wf-002 configuration selects exactly these slot controls and
passes preflight; a drifted slot control rejects with `FrozenBindingRejected`. Any supplied reasoning remains separately captured diagnostic data.
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
Offline tests of this command do not authorize a run.

## Environment setup

1. From the repository root, create the optional local credential file:

   ```sh
   cp -n .env.e2e.example .env.e2e
   chmod 600 .env.e2e
   ```

2. Fill [.env.e2e.example](../../.env.e2e.example)'s declared values in the
   Git-ignored `.env.e2e`. Never put credentials in tracked configuration or
   command arguments.
3. Set generation to use `TEST_AWS_BEARER_TOKEN_BEDROCK`. E2E reads no
   `TEST_EVALUATION_*` selection; those variables configure only the standalone
   [supplied-spec evaluator](evaluator.md#run).
4. For direct build commands, load the file in the invoking shell:

   ```sh
   . ./.env.e2e
   zig build e2e-spec -- --help
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
  `reasoningEffort: "low"`. The configuration sets temperature `0.1` and runaway
  re-send temperature `1`.
- The current production provider is Bedrock; its internal test credential is
  `TEST_AWS_BEARER_TOKEN_BEDROCK`.
- The harness supplies a validated credential snapshot to the shared runtime. The CLI
  supplies its environment, read only after model-binding validation. The runtime owns
  snapshot cleanup; neither path copies test credentials into production variables.
- Fixture checks and evidence tracing wrap the existing invocation bindings. The harness
  does not construct a second production runtime or choose model responses or graph edges.
- In-process checks and packaged CLI smoke checks retain their separate entry boundaries.

- After successful generation, the harness reads the specification actually published by
  that invocation and retains those exact bytes, with the captured sources and rubric,
  as `evaluation_inputs` in `report.json`. No model grades the run; human adjudication
  of the retained report is its rubric evaluation (user decision, 19 October 2026).
- The case rubric must declare an acceptance threshold. A rubric without one could
  never be accepted, so the run stops before generation with `threshold_unconfigured`
  and `ACCEPTANCE_THRESHOLD_UNCONFIGURED`.

- Generation sends the model's documented maximum output (16,384 for GPT-OSS-20B)
  from its configuration, never a smaller allowance, and
  every provider stop is logged with its reason
  ([ADR 0011](../decisions/0011-provider-owned-request-limits.md#model-maximum-output)).
- The engine accounts every inference, including post-generation advice and
  correction, once against one execution budget.
- Provider-owned response limits still apply and are reported as provider stops.
- Bedrock generation, diagnostics and the standalone evaluator share the Converse codec. GPT-OSS-20B's
  registered profile supplies native JSON Schema, the selected reasoning effort
  and the configured temperature, and sends `inferenceConfig.maxTokens` 16,384. Provider
  reasoning counts toward output usage;
  the engine accounts actual reported tokens separately from provider quotas.
  The separate registered Luna profile retains its strict JSON flag and omitted
  temperature/reasoning overrides. Its production capability contract remains
  available, but the live-test policy rejects it. Registration does not establish
  live compatibility or semantic quality for either model.

- Every generation call, and both providers of the standalone evaluator, use the engine's short [universal
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
  directly for both the engine and adjudication.

## Case and publication contract

- The closed `spec-e2e-case/v3` declares workflow/feature/reference selection,
  configuration, explicit file mappings, empty directories, all four expected artifact
  kinds, `expected_outcome` and `evaluation_case`.
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
- A failed run that publishes a failed incomplete specification
  ([ADR 0041](../decisions/0041-failed-run-incomplete-publication.md)) still fails the
  case. The report records the published incomplete set as `incomplete_publication`
  (the artifacts written), beside its failed step and diagnostic, and the run retains
  its bytes in `project/` for inspection. Like ADR 0017's pending view, it is not
  scored. The member is in `spec-e2e-report/v11`; it stays null until ADR 0041 is
  implemented (FIX06 E0).

### Rubric assessment

- The rubric assesses semantic quality. Human adjudication of the retained report is
  the only rubric evaluation with acceptance effect ([R8](acceptance.md)).
- A readable poor specification is retained unchanged after the engine's own gates
  accept it. There is no harness semantic prefilter or retry-until-good loop.
- Scores do not alter workflow state, resolve clarifications or authorize publication.
- Rubric revision 2 includes the user-added UTC date/time requirement and remains an
  uncalibrated draft; mechanical validation of a judgment is not proof that its semantic
  assessment is correct.
- The [`/evaluate-e2e`](../../.claude/skills/evaluate-e2e/SKILL.md) Claude Code skill
  reads a retained run, scores the captured specification against its rubric with line
  citations, and traces each defect to the generation call, prompt and engine stage
  that produced it. Its output is advisory assistant analysis written under the
  Git-ignored `evaluations/` directory. It is not a grade, a human review or an
  adjudication input, and its causal attributions are hypotheses backed by cited
  evidence, not proof.

## Retained results

```text
zig-out/e2e-spec/<UTC-date-time>-<unique-id>/
  case.json       # exact selected workflow case
  inputs.json     # captured configuration/resources/source/rubric
  report.json     # generation result and captured adjudication inputs
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
- Published runs also retain the exact source, specification and rubric bytes that
  adjudication revalidates.
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

- Lifecycle status and development acceptance are separate. `generated` records
  publication; it cannot by itself return command success.
- Cases declare `expected_outcome`. Both current source-complete cases require
  `publication`, so an unexpected native `needs_user` does not pass acceptance.
  An explicitly clarification-expected case still requires valid native partial
  publication, registered clarification handles and measured zero admission escape.
- Exit 0 requires passed acceptance and finalized reports. Missing thresholds,
  critical human-score failures, uncertainty, missing human adjudication and
  unexpected terminal outcomes cannot pass. Native workflow state remains unchanged.
- See [R8 acceptance](acceptance.md) for approved numeric/human authority, refreshed calibration panels and the offline
  human adjudication command.

The terminal prints the development acceptance result explicitly.

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
fractional temperatures, rubric thresholds and scores. They are diagnostic
projections; the engine's integer-only canonical state contract does not apply.
The saver renders both report views before writing, preserves exclusive creation
and durable writes, and releases its intermediate buffers. A report-file failure
leaves the workflow status and cause unchanged: the CLI prints the workflow result,
separately reports the finalization error and potentially incomplete files, and exits
unsuccessfully even if generation succeeded. It does not retry writes or rerun the
workflow to repair reporting.

`token_accounting` (the single total budget and actual usage), `retry_settings` and `attempts` project the executed graph
and native accounting. Each attempt records `resends`, the attempt number it re-sends,
when it is a runaway re-send
([ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md)), and the
report records each incomplete review's reason and unassessed count
([ADR 0040](../decisions/0040-incomplete-review-published-marked-logged.md)), so runaways,
re-sends and incomplete reviews are counted separately. They advanced
`spec-e2e-report` to v10. Each attempt's request
`purpose` and `owner_kind`, read from its native request identity, and the
`incomplete_publication` member advanced it to v11 (user decision of 29 October 2026),
so stage costs can be measured and ADR 0041 adds no later version. A composed request's
identity carries its base packet's purpose and owner, so these match the baseline
trace's receipts, and baseline acquisition rejects a report whose attempt and receipt
differ. Reports of earlier versions stay readable only by the build that made them. `model_calls` counts reconciled inference operations,
including proven non-delivery; `not_sent_operations` identifies that subset.
Captured exchanges separately count physical sends. Missing receipts are permitted
only for explicit non-delivery or captured-evidence failure, never to invent paid
usage. Per-call usage survives budget rejection before candidate text projection. `exchange_evidence` links retained response bytes and distinguishes
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

The current closed formats are `spec-e2e-case/v3`, `spec-e2e-report/v11`,
`baseline-freeze/v3`, `baseline-acquisition/v8`, `baseline-score/v4` and
`baseline-budget-feasibility/v2`. Step events remain
`e2e-step-event/v2` (under [ADR 0030](../decisions/0030-engine-owned-model-request.md),
not yet implemented, model-request stages become events of one `request-model` step,
and this version advances if the event shape changes; retained runs and captures made
before then stay readable only by the build that made them); evaluator packets remain
`baseline-assessment-inputs/v2` and
assessor documents use numeric schema `3`. These versions advanced with
`rubric-judgment/v2` because they embed its judgments or the E2E report.
`spec-e2e-report/v7` and `baseline-acquisition/v5` advanced again with
`evaluation-report/v5`, which records per-attempt purpose and diagnostics, and
`spec-e2e-report/v8`, `baseline-acquisition/v6` and `evaluation-report/v6` with the
`evaluation-config/v2` judge maximum. Removing the advisory grader from E2E advanced
`spec-e2e-case/v3`, `spec-e2e-report/v9`, `baseline-freeze/v2` and
`baseline-acquisition/v7`. Retained runs captured before that change can no longer be
adjudicated by `adjudicate-spec`, replayed by `e2e-call` (their `case.json` is
`spec-e2e-case/v2` or older) or used as budget-feasibility evidence; a fresh run is
needed for each. `evaluation-report/v7` then removed the standalone evaluator's
judge-independence field and its never-produced passed or failed model decision.
`baseline-acquisition/v8` advanced with `spec-e2e-report/v11`, which it embeds.
`baseline-budget-feasibility/v2` and `baseline-freeze/v3` advanced when the workflow
budget became the configured `workflowTokenBudget`
([ADR 0037](../decisions/0037-configured-workflow-token-budget.md)). Every configuration
now requires that member, so a retained run's captured `.sddtoolkit.json` without it can
no longer be replayed by `e2e-call` or used as budget-feasibility evidence; adjudication
doesn't decode configuration and is unaffected.
The compatibility report's outer
format remains `provider-compatibility-report/v1`. Earlier captures remain immutable
historical evidence; current readers reject superseded report versions and fields.
Feasibility evidence retains the single total budget and aggregate actual usage.

### Reliability assessment

- For reliability assessment, repeat the same selected case using `scripts/e2e-spec.sh
  --case <workflow.case.json>` with a fixed engine build, captured case/workflow inputs,
  model settings and rubric.
- Retain every run and compare completion rate, first-pass and post-repair acceptance,
  typed failure categories, criterion scores, threshold results, and total usage
  including failed attempts.
- Report runs that are published but not yet adjudicated separately.
- Different cases/models need separate results before aggregation.
- Mechanical tests establish contracts; repeated live completion and acceptable
  published output are separate evidence.
- A few successful runs do not establish reliability across unimplemented workflows or
  unseen inputs.

### Run measures

`zig build e2e-measures -- --run <run> [--run ...] --out <dir> [--set <file>]` reads
retained runs offline, without the engine or a model call. It writes
`<dir>/<run>/measures.json` (`e2e-measures/v1`) and, with `--set`, one
`e2e-measures-set/v1` summary, never overwriting a file. `--out` and `--set` must lie
under `evaluations/`, and neither may equal, contain or lie inside a `--run` directory.
A missing report, call output or feature event log leaves its measures empty. A
record that can't be read or trusted makes the run `unmeasurable`, naming which kind
(`unreadable`, `configuration`, `report`, `call_evidence`, `feature_log` or
`ambiguous_feature_log`); the run still counts as attempted, and nothing else is
measured from it (FIX06 DT5). A run without a readable `case.json` can't be attributed
to a case, and an operational failure of the measurement itself (cancellation,
exhausted resources or an unexpected system error) isn't a property of the run; either
stops the command. Every run is measured and summarized before anything is written, so
a stop leaves no partial output.

- From `report.json`: outcome, terminal step, diagnostic and publication (`native`
  when the outcome is `ok` and the publication check passed, `incomplete` when the
  report marks ADR 0041's incomplete publication, otherwise `none`); sends and proven
  non-deliveries; actual tokens; protocol corrections (later attempts that aren't
  runaway re-sends); re-sends; the admission escape; repair merges; and each stage's
  sends, input, output and total tokens and shares, from each sent attempt's request
  purpose and owner through the baseline scorer's stage classification and
  accumulation. Only the `schema` member is read first. A missing report, or one of a
  known older version (v1 to v10), is recorded as `unavailable`, and the run still
  counts as attempted. A current-version report that doesn't decode, or any other
  version, makes the run unmeasurable.
- From the retained project's `.sddtoolkit.json`: the configured `logs.level`, read by
  the engine's configuration decoder, as `log_threshold`.
- From call evidence: records per records call, the `records` array length of each
  response whose `kind` is `records`, read by the production envelope parser.
- From the feature event log: runaways (`model.provider_stopped` for the output
  limit), re-sends, normalized responses, admission rejections by code
  (`model.protocol_failed`, `model.schema_failed`), validation failures by code, and
  latency, the monotonic span of the event records. Each segment must be the feature
  log format's own: its heading, a segment header, event records with consecutive
  sequences and, once closed, its trailer, every row complete and of the current
  schema, stream and column versions. Any other row, such as a last row cut off
  mid-write, makes the run unmeasurable. Runaways,
  re-sends and normalized responses are logged at every level (§26.5); the other
  counts and the latency hold only events the run's `log_threshold` kept.
- The set summary gives each case's minimum, median and maximum of each measure, and
  pools event counts with their opportunities: native publications per attempted run,
  with the attempts whose outcome is unknown counted beside it in `unmeasurable` and
  `report_unavailable`; corrections, re-sends, runaways and admission rejections per
  send; escaped values per admitted value; and changed repairs per repair. Each stage
  has its own sends and actual-token spreads: every measured run gives each stage a
  sends value, zero included, and a stage of unknown usage gives no token value. A
  case's measured runs must share one log threshold, which the summary records: the
  counts that depend on it compare only at one level, so a case of mixed thresholds
  stops the command, naming the case and both levels.
- An incomplete publication is never a publication; it is measured once ADR 0041 writes
  its marker (FIX06 E0). A marker on a run that isn't failed or blocked, or an empty or
  repeated artifact set, makes the run unmeasurable, as does an attempt whose usage
  total isn't its input plus output.

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

## Request projection

A change that must leave model input unchanged is proved offline by a byte diff of two
request-projection freezes, not by a live run.

- The offline Spec scenarios record every request the fake provider receives, at the
  provider port, as its `model_request_description` without `version`,
  `workflow_version` and `request_step`, which refactors change by design. Member order
  and number spelling stay the description's own.
- `SDDE_REQUEST_PROJECTION=<dir> zig build test-integration` writes
  `<dir>/<group>/scenario-NNN/call-NNNN.json`, one file per invocation in provider-call
  order within each scenario, grouped by scenario case so groups never overwrite each
  other's numbers, and `<dir>/manifest.json`, the group, scenario and call counts of
  the whole directory. Unset, projections stay in memory. Set to an empty value or a
  directory that can't be created or opened, each recording scenario panics, naming
  the value, and the run fails.
- A freeze needs a fresh run. `-Dreuse-test-runs` passes the test process only `PATH`
  and `HOME`, so a reused or fresh opt-in run writes no freeze.
- Take each freeze in a new directory, such as
  `evaluations/request-projection/<commit>/`: one on the base commit, one on the
  change. Both must contain `manifest.json`; then `diff -r <base> <change>` printing
  nothing is the proof. A missing manifest means the freeze didn't run.
- Call order keys each file because request ordinals restart for each unit. A change
  that only reorders requests therefore still shows as a diff.
- The projection is an observation and is never asserted against expected content.
  These scenarios count reference state namespaces rather than drawing them at random,
  so repeated freezes of one tree are byte-identical.

## Verification

- `zig build test-integration --summary all` runs fixed offline harness and
  launcher cases, including argument forwarding, publication identity, evidence
  capture and failure reports. It makes no provider calls.
- `zig build test-rubric-evaluator --summary all` checks the standalone evaluator's
  judge mechanics, rubric acceptance and human adjudication offline.
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
  Live generation runs separately through `./scripts/e2e-spec.sh`.
- `zig build smoke-e2e-harness --summary all` checks the standalone executable's startup
  and mandatory case selection in a clean directory without credentials.
- `zig build verify --summary all` includes mechanical tests, lint, architecture and
  native packaging checks.
- It does not launch live E2E cases.
- `zig build e2e-spec -- --case ...` runs live generation and captures the published
  output for adjudication.
- Only its retained results establish what happened in that E2E execution.
- `zig build evaluate-spec -- ... --live` separately grades a supplied file; it does not
  establish engine generation.
- See [evaluator.md](evaluator.md).

- Earlier reports based on scripted generation or golden comparison are not live E2E
  evidence.

The report records the one configured total budget for all model work, with
aggregate actual usage including full overshoots. Global-budget rejection is a
workflow failure during advice too. An explicitly incomplete review from an
eligible non-budget stop does not establish acceptance: R8's rubric thresholds,
expected publication and human adjudication remain independent.

Human calibration and broader rerun/failure acceptance are tracked in
[FIX06](../../fixes/FIX06.md).
