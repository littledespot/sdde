# Live Spec E2E test

Run one explicitly selected live case from the repository root:

1. Configure credentials and judge selection under [Environment setup](#environment-setup).
2. Obtain explicit user approval for this E2E run under
   [AGENTS.md](../../AGENTS.md#testing-expectations).
3. Run the launcher for the checked-in Hello World case:

   ```sh
   ./scripts/e2e-spec.sh
   ```

   Or supply an explicit case through the same production path:

   ```sh
   zig build e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
   ```

4. Inspect the retained generation, publication and rubric results under
   [Retained results](#retained-results).

### Launcher behavior

- The command makes live API calls for generation and grading; there is no mock mode.
- The script requires the pinned Zig compiler and locates the checkout from its own path.
- Case paths are repository-relative.
- The development script loads the checkout's `.env.e2e` for live invocations;
  `--help` does not source it. The executable does not load an environment file.
- The local file replaces values for names it exports. If absent, the script uses
  caller-injected variables.
- Direct `zig build e2e-spec` requires explicit shell environment setup, such as
  `. ./.env.e2e`.

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
4. Select grading with `TEST_EVALUATION_PROVIDER` and `TEST_EVALUATION_MODEL`.
   Supply `TEST_OPENAI_API_KEY` for OpenAI; supply
   `TEST_AWS_BEARER_TOKEN_BEDROCK` and `TEST_EVALUATION_REGION` for Bedrock.
   Leave the region empty/unset for OpenAI. Supported controls and model pairs
   are in the [evaluator contract](evaluator.md#run).
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

- The harness captures the case's declared inputs and copies them into one new, isolated
  project.
- It shares `composition/root.zig.Runtime` with the CLI for adapter construction,
  bindings and cleanup, then runs one ordinary invocation through production bootstrap,
  provider catalogue validation, request preparation, authorization, HTTPS transport, YAML
  transitions, deterministic validators and publication.
- Generation uses the model slots selected by that test's `.sddtoolkit.json`.
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
- The judge uses `TEST_EVALUATION_PROVIDER=openai|bedrock`, `TEST_EVALUATION_MODEL`, the
  selected `TEST_` credential and, for Bedrock, `TEST_EVALUATION_REGION`.
- The case's `evaluation_config` supplies explicit reasoning, timeout, retry and
  total-budget settings; no provider or model is selected by a fallback.
- Judge settings and credentials are validated before generation starts.

- Neither generation nor evaluation sends a per-call output token cap.
- The engine enforces the workflow's cumulative actual-token budget; the evaluator has
  its separate cumulative budget.
- Provider-owned response limits still apply and are reported as provider stops.
- GPT-OSS supports explicit `low`, `medium` and `high` reasoning effort through the
  shared Bedrock serializer; the Hello World generation slot and judge select `low`.

- Every generation call and both evaluator providers use the engine's short [universal
  JSON framing instruction](../decisions/0014-universal-response-format-guidance.md).
- The serializer emits it once, including retries; workflow templates retain only
  task-specific guidance.
- The actual emitted instruction is retained in each call's `request.json`.
- Closed schemas and strict response validation remain independent of whether the model
  follows that instruction.

- The Hello World case runs `spec-generation` with `--feature hello-world --reference
  hello-world`.
- It exercises Specify; Plan, Tasks and Implement need their own workflow cases.
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

- `evaluated` means generation, publication checks and a scored evaluation completed.
- `awaiting_clarification` preserves native `needs_user` as a normal pause. Both
  CLI entrypoints exit 0 and show registered open clarification IDs and paths.
  Harness paths point into the retained run's `project/`; JSON paths are relative
  to that project. Unattempted specification publication and grading are `not_run`.
  After validated answers, a fresh workflow invocation starts at `start`.
- Exit 0 alone does not establish the published/scored baseline: require `evaluated`.
- A low score is still a completed evaluation; inspect `score_percent` and the
  separately reported threshold result.
- No quality threshold has been adopted by the draft rubric.
- Invalid candidates, workflow failure, blocked/cancelled execution, missing/changed
  output, evaluator error and unresolved quality produce nonzero exit status.
  Native `invalid`, `blocked` and `cancelled` retain distinct report statuses.
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
credentials are excluded. Git runs only in the development provenance build step.
This identity is diagnostic evidence and never participates in workflow gates.

`total_token_budget`, `retry_settings` and `attempts` project the executed graph
and native accounting. Per-call usage survives budget rejection before candidate
text projection. `exchange_evidence` links retained response bytes and distinguishes
absent responses, budget stops, other missing text and capture failure. Known
transport phases/causes remain separate from delivery and retry policy; unknown
causes stay unknown. Recognized provider failures survive request release.
`last_protocol_rejection` keeps its own call/request/attempt when a later exchange
fails for another reason. None of these projections creates another counter.

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

- Classification and specification repairs use the normal live provider path.
- Each attempt retains its request, context, provider response, final text and transport
  outcome like generation.
- The harness neither invents classifications nor rewrites responses.
- A repaired candidate must pass native validation before publication, and only the
  published output can receive a rubric grade.
- Unit tests of repair contracts and fake-provider integration tests are not live E2E
  evidence.

## Verification

- `zig build test-e2e-launcher --summary all` verifies local environment loading, help
  without credentials, invocation from another directory, argument forwarding and
  failure exit status without provider calls.
- `zig build test-e2e-harness test-rubric-evaluator --summary all` checks harness and
  judge mechanics offline.
- Those results are unit/integration evidence.
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

## Historical verification records

- Dated commands, results, failure analyses and run tables are retained in [E2E
  verification history](e2e-verification-history.md).
- They do not establish current verification or successful generation and grading.
- Active work remains in [FIX_001](../../fixes/IMP_001.md).

<a id="source-selection-verification--2026-09-12"></a>

- [Source selection verification —
  2026-09-12](e2e-verification-history.md#source-selection-verification--2026-09-12).

<a id="provider-normalization-discovered-by-live-execution"></a>

- [Provider normalization discovered by live
  execution](e2e-verification-history.md#provider-normalization-discovered-by-live-execution).

<a id="live-evidence--2026-09-11"></a>

- [Live evidence — 2026-09-11](e2e-verification-history.md#live-evidence--2026-09-11).

<a id="universal-response-guidance--2026-09-12"></a>

- [Universal response guidance —
  2026-09-12](e2e-verification-history.md#universal-response-guidance--2026-09-12).

<a id="mechanical-verification--2026-09-12"></a>

- [Mechanical verification —
  2026-09-12](e2e-verification-history.md#mechanical-verification--2026-09-12).

<a id="shared-atomic-repair-verification--2026-09-12"></a>

- [Shared atomic-repair verification —
  2026-09-12](e2e-verification-history.md#shared-atomic-repair-verification--2026-09-12).

<a id="shared-model-input-and-protocol-retry-verification--2026-09-12"></a>

- [Shared model-input and protocol-retry verification —
  2026-09-12](e2e-verification-history.md#shared-model-input-and-protocol-retry-verification--2026-09-12).

<a id="protocol-retry-ownership-verification--2026-09-12"></a>

- [Protocol retry ownership verification —
  2026-09-12](e2e-verification-history.md#protocol-retry-ownership-verification--2026-09-12).

<a id="fix_001-phase-2--proposal-boundaries"></a>

- [FIX_001 Phase 2 — proposal
  boundaries](e2e-verification-history.md#fix_001-phase-2--proposal-boundaries).
