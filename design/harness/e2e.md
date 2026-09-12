# Live Spec E2E test

After configuring `.env.e2e`, run one selected case from the repository root:

```sh
./scripts/e2e-spec.sh
```

The script selects the checked-in Hello World case by default. An explicit
case uses the same path:

```sh
zig build e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

This command makes live API calls for both generation and rubric grading. There
is no mock mode. The script requires the pinned Zig compiler and locates the
checkout from its own path; case paths are repository-relative. The
executable does not automatically load an environment file. The development script
loads the checkout's `.env.e2e` for live invocations; `--help` does not source it.
The local file replaces values for names it exports. When the file is absent,
caller-injected variables are used. Direct `zig build e2e-spec` still requires
explicit environment setup, such as `. ./.env.e2e` in the invoking shell.

## Execution and quality assessment

The harness captures the case's declared inputs and copies them into one new,
isolated project. It runs one ordinary workflow invocation through production
bootstrap, provider catalogue validation, request preparation, authorization,
HTTPS transport, YAML transitions, deterministic validators and publication.
Generation uses the model slots selected by that test's `.sddtoolkit.json`.
The current production provider is Bedrock; its internal test credential is
`TEST_AWS_BEARER_TOKEN_BEDROCK`. Test credentials are passed directly to the
provider adapter and are never copied into production environment variables.

After successful generation, the harness reads the specification actually
published by that invocation and grades those exact captured bytes against the
case's rubric. The judge uses `TEST_EVALUATION_PROVIDER=openai|bedrock`,
`TEST_EVALUATION_MODEL`, the selected `TEST_` credential and, for Bedrock,
`TEST_EVALUATION_REGION`. The case's `evaluation_config` supplies explicit
reasoning, timeout, retry and total-budget settings; no provider or model is
selected by a fallback. Judge settings and
credentials are validated before generation starts.

Neither generation nor evaluation sends a per-call output token cap. The
engine enforces the workflow's cumulative actual-token budget; the evaluator
has its separate cumulative budget. Provider-owned response limits still
apply and are reported as provider stops. GPT-OSS supports explicit `low`,
`medium` and `high` reasoning effort through the shared Bedrock serializer;
the Hello World generation slot and judge select `low`.

Every generation call and both evaluator providers use the engine's short
[universal JSON framing instruction](../decisions/0014-universal-response-format-guidance.md).
The serializer emits it once, including retries; workflow templates retain only
task-specific guidance. The actual emitted instruction is retained in each
call's `request.json`. Closed schemas and strict response validation remain
independent of whether the model follows that instruction.

The Hello World case runs `spec-generation` with `--feature hello-world
--reference hello-world`. It exercises Specify; Plan, Tasks and Implement need
their own workflow cases. The copied resources are declared test inputs, not
production source-tree fallbacks. Changes to the reference, including its UTC
date/time requirement, are captured directly for both engine and judge.

## Case and publication contract

The closed `spec-e2e-case/v1` declares workflow/feature/reference selection,
configuration, explicit file mappings, empty directories, all four expected
artifact kinds, `evaluation_case` and `evaluation_config`. The evaluation case
names source documents and a rubric. Every selected reference must map exactly
once to an evaluation source. Unknown or duplicate fields, unsafe paths,
symlinks, destination collisions and pre-seeded feature output reject.
Scripted provider responses and expected specifications are not case inputs.

The harness requires an `ok` workflow outcome, runner-observed publication and
all four readable, nonempty artifacts: specification, reference context,
clarification state and workflow state. Each file must match the bytes prepared
for that publication. This checks artifact identity, not semantic quality. A
stale file, partial publication or in-memory candidate cannot satisfy the check.
Only the engine's registered writer publishes output; the harness never exports
or renders candidates to manufacture a specification.

The rubric assesses semantic quality. A readable poor specification is passed
unchanged to the judge after the engine's own gates accept it. There is no
harness semantic prefilter or retry-until-good loop. Scores do not alter workflow
state, resolve clarifications or authorize publication. Rubric revision 2 includes the user-added UTC date/time requirement and remains
an uncalibrated draft; mechanical validation of a judgment is not proof that its
semantic assessment is correct.

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

The timestamp uses `YYYY-MM-DDTHH-MM-SSZ`; the unique suffix separates concurrent
runs. Output paths come from validated project configuration. Reports are
reserved before API calls. Captured inputs and the isolated project are retained
on failure; input capture failures can leave only the case and failure report.
Known test credentials are redacted from captured bodies; authorization headers
and environment maps are excluded. Captured bodies are untrusted diagnostic
data, not workflow authority. Evidence files are created exclusively with
owner-only access and flushed as each exchange is observed. Every attempt gets
its own directory; a retry cannot overwrite the rejected response.

No response file is invented when the transport did not return a body, and no
final-text file is invented for an unavailable or rejected provider result.
Interruption, incomplete network reads, allocation failure or a failed evidence
write can leave incomplete artifacts. Evidence write failures fail the E2E run;
they cannot produce a successful quality result. Normal engine feature logging
retains its separate configured capture and redaction policy.

Reports preserve execution identity, engine outcome, selected generation models
by slot, accounted usage, publication checks and separate provider/model
rejections. Completed evaluations also retain exact source/spec/rubric bytes,
judge configuration, attempts, criterion judgments, evidence and aggregate score.
Source changes during execution fail the run without modifying retained inputs.

For malformed model JSON, the shared engine decoder retains the native parser
reason and available byte offset, line and column. The same diagnostic reaches
the workflow's protocol retry, `events.jsonl`, both reports and terminal output.
Offsets are zero-based; lines and columns are one-based. These are parser cursor
positions, not inferred field names. The terminal links to the retained model
text and event stream. See the [prompt and response flow](../diagrams/17-model-prompt-response-flow.md)
for the instructions actually sent to the model.

Schema failures retain `schema_error.reason` and `schema_error.path`, an escaped
JSON Pointer (for example `/statements/0/content/kind`), in the same event,
report and terminal outputs. The engine's validator supplies this diagnostic;
the harness does not infer or revalidate it. Protocol retries include the full
rejected response as untrusted evidence, the original schema, and examples
generated from that schema. Empty permitted arrays no longer hide item shapes
in syntax examples; schema errors show the expected shape's alternatives.

`passed` and exit 0 mean generation, publication checks and a scored evaluation
completed. A low score is still a completed evaluation; inspect `score_percent`
and the separately reported threshold result. No quality threshold has been
adopted by the draft rubric. Workflow failure, clarification, cancellation,
missing/changed output, evaluator error and unresolved quality produce nonzero
exit status. Evaluator failure preserves a successfully published specification.

## Verification

- `zig build test-e2e-launcher --summary all` verifies local environment loading,
  help without credentials, invocation from another directory, argument forwarding
  and failure exit status without provider calls.
- `zig build test-e2e-harness test-rubric-evaluator --summary all` checks harness
  and judge mechanics offline. Those results are unit/integration evidence.
- `zig build smoke-e2e-harness --summary all` checks the standalone executable's
  startup and mandatory case selection in a clean directory without credentials.
- `zig build verify --summary all` includes mechanical tests, lint, architecture
  and native packaging checks. It does not launch live E2E cases.
- `zig build e2e-spec -- --case ...` runs live generation and grading. Only its
  retained results establish what happened in that E2E execution.
- `zig build evaluate-spec -- ... --live` separately grades a supplied file;
  it does not establish engine generation. See [evaluator.md](evaluator.md).

Human rubric calibration and broader workflow/rerun/failure acceptance remain
tracked in [H-016 and H-017](03-harness-verification.md). Earlier reports based
on scripted generation or golden comparison are not live E2E evidence.

## Provider normalization discovered by live execution

The first network-enabled run on 2026-09-11 failed with `response_invalid` on
`g2-ex-assign`. A separate small Bedrock diagnostic request returned HTTP 200
with empty `usage.serverToolUsage` and a reasoning block plus final text.
The shared provider decoder now validates those metadata shapes and keeps only
the single final text block as candidate data. It continues to reject missing
or multiple text results, malformed/unknown fields and nonempty server-tool
usage. Both generation and grading use this decoder. The diagnostic request is
provider evidence only; it is not substituted for a workflow or rubric result.

The reasoning shape follows [AWS ReasoningContentBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ReasoningContentBlock.html).
The empty server-tool usage shape was observed in the live service response.
No reasoning narrative is imported as workflow data. A captured raw provider
response can contain provider reasoning blocks; these remain diagnostic data.

## Live evidence — 2026-09-11

The live development command is:

```sh
./scripts/e2e-spec.sh
```

Both generation configuration and judge settings select Bedrock GPT-OSS 20B in
`ap-southeast-2`. The locally retained runs inspected for this change are:

| Run directory under `zig-out/e2e-spec/` | Result | Calls | Accounted tokens |
| --- | --- | --- | --- |
| `2026-09-11T21-45-21Z-4c93154c4ab8b29e0be305b2a95d9ed3` | `workflow_failed`; `InvalidModelEnvelope` at extraction; raw responses were not saved | 2 | 6,536 |
| `2026-09-11T22-10-04Z-d6dd90e6d157886ea40552316c800245` | `workflow_failed`; `SyntaxError` at byte 0, line 1, column 1; both responses contained Markdown fences | 2 | 6,808 |

The older run's exact JSON defect cannot be recovered from its saved report.
Do not attribute the newer run's diagnosed cause to it.

The newer run retains request context, wire request, wire response, final text
and transport outcome for both attempts, plus 67 step events. Each saved final
text was compared byte-for-byte with the final text in its saved provider body;
both start with a Markdown JSON fence. The parser rejected the first backtick.
The terminal and report show the same native parser reason and location. No
response was stripped or repaired by the harness.

It published no specification and has `semantic_quality: not_evaluated`.
**Successful generation followed by a live rubric grade remains unverified.**
The new run proves live failure capture, not completed generation or quality.

## Universal response guidance — 2026-09-12

After adding [ADR 0014's universal instruction](../decisions/0014-universal-response-format-guidance.md),
`./scripts/e2e-spec.sh` produced run
`2026-09-11T22-37-01Z-22b097899e82c70bca7be7cb19b78bf8`.
Both saved requests contain the shared framing instruction exactly once.
Both saved final texts match their provider response bodies and begin directly
with a JSON object; neither contains a Markdown fence.

The run still failed after two calls and 6,760 accounted tokens. The initial
response passed JSON syntax but required a schema retry. The retry ended with
`"token_classifications":[]"}`: an extra quote follows the closing array.
The engine reported `SyntaxError` at byte offset 980, line 1, column 981;
the complete response and diagnostic remain in the run's evidence and reports.
No specification was published and no rubric grade was produced. This verifies
the actual emitted instruction and observed fence-free responses, not reliable
model compliance or completed E2E generation.

## Candidate validation and atomic repair

`candidate_error` records the native validator's structured diagnostic independently
of JSON/schema errors and independently of whether the model request has already
been released. For classification rejection it contains the chunk scope, revision,
affected field, and all missing, duplicate, unknown and forbidden candidate IDs.
Terminal output, `report.json`, `report.md` and `events.jsonl` project the same
retained evidence. Successful repairs clear current rejection data; earlier step
events remain available.

Classification and specification repairs use the normal live provider path.
Each attempt retains its request, context, provider response, final text and
transport outcome like generation. The harness neither invents classifications
nor rewrites responses. A repaired candidate must pass native validation before
publication, and only the published output can receive a rubric grade. Unit tests
of repair contracts and fake-provider integration tests are not live E2E evidence.

## Mechanical verification — 2026-09-12

- `zig build test-provider-conformance test-model-envelope test-model-payload-schema test-rubric-evaluator --summary all`
  — 12/12 steps; 142/142 tests passed, including universal framing in both
  response modes, initial calls, retries, counting and both judge providers;
  strict malformed-JSON rejection remains covered.
- `zig build verify --summary all`
  — 120/120 steps; 1,322/1,322 tests passed, including lint, architecture,
  standalone harness/evaluator smoke and clean native engine packaging.
- `git diff HEAD --check` — passed. Local links in the edited harness documentation
  resolve; obsolete scripted-generation and expected-specification fixtures
  are absent. The user's source change is preserved.

These are mechanical checks and do not replace the unmet live result above.

## Shared atomic-repair verification — 2026-09-12

`zig build verify --summary all` passed 120/120 steps and 1,325/1,325 tests,
including native packaging smoke tests. Regression cases cover classification
repair through publication, malformed replacement retry, exhaustion without
publication, unchanged claims/other chunks, stale revisions, foreign request
associations and source-authority changes after repair. These are mechanical
unit/integration results, including fake-provider cases.

The live `./scripts/e2e-spec.sh` run
`2026-09-12T00-16-32Z-4d08e91382e3f11752d8f0713cf7550f` failed before classification
validation: its first response has an extra closing brace at byte 890, and the
protocol retry adds an unknown `ordinal` field inside
`token_classifications[0].preserve`. Two calls used 6,627 tokens. Both calls retain
all five evidence files; saved model text matches the provider body byte-for-byte,
and 67 step events are retained. No specification was published or graded.
That run did not reach the classification-repair branch.

## Shared model-input and protocol-retry verification — 2026-09-12

`zig build verify --summary all` passed 120/120 steps and 1,329/1,329 tests,
including architecture checks and clean native packaging. Regression coverage
includes the reported reconciliation response shapes, all reference content
kinds, nested schema paths, unknown-field rejection, schema-derived examples,
exact retry evidence, request association and allocation-failure cleanup.
`git diff HEAD --check` passed.

The live `./scripts/e2e-spec.sh` run
`2026-09-12T01-05-47Z-53b5927d74935d8407dddfb857e12230` failed during extraction.
Both responses contain an undeclared field at
`/token_classifications/0/preserve/ordinal`. The second request retains the
first response exactly, reports that path, and provides the expected containing
object at `/token_classifications/0/preserve` from the original schema. The
model repeated the error and the existing protocol retry exhausted.

Two calls used 6,970 tokens. Both calls retain request, context, provider response,
model text and outcome files; 67 step events and both reports are present.
The exact schema error also appears in terminal output. No specification was
published or graded. This run verifies live diagnostic/retry evidence, but
does not demonstrate successful reconciliation, publication or rubric evaluation.
