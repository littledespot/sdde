# Supplied-spec rubric evaluator

Implements the evaluator-only path in [H-001–H-006](01-rubric-evaluator.md).
It sends captured requirements, a supplied specification and its rubric to
the permitted Bedrock GPT-OSS-20B target, validates the returned judgments, and writes
JSON/Markdown reports. The retained OpenAI adapter is tested offline.
It does **not** run Specify or require a deterministic definition of good prose.

The [live E2E harness](e2e.md) now joins production generation to this evaluator.
Human rubric calibration and broader live acceptance
are not claimed as completed or prerequisites for offline implementation.

## Run

1. From the repository root, prepare a candidate file, an existing report
   directory and a judge configuration.
2. If using `.env.e2e`, load it with `. ./.env.e2e` in this shell; see
   [E2E environment setup](e2e.md#environment-setup).
3. Review the complete declared source/spec/rubric inputs and explicitly
   authorize the live request.
4. Run:

   ```sh
   zig build evaluate-spec -- \
     --case test/e2e/wf-001-hello-world/node-vitest/spec.case.json \
     --spec evaluation-input/spec.md \
     --config evaluation-input/judge.json \
     --output evaluation-output \
     --live
   ```

### Input and environment rules

- `evaluation-input` and `evaluation-output` are operator-selected examples, not
  automatically created locations.
- All command and case-file paths are normalized relative to the invocation's current
  directory, **not** the case file's parent.
- Absolute paths, traversal and symlinked input/output directories are rejected.
- The candidate must be readable, nonempty UTF-8.
- Missing headings, unwanted prose and poor requirements remain judgeable; there is no
  `SpecificationIR` gate.

- Provide the selected provider's `TEST_` credential through the process environment,
  never in the command, case or judge configuration.
- `--live` is mandatory and sends the complete declared source/spec/rubric content to
  the selected provider; review these inputs before authorizing it.
- No principle directories or other repository content are discovered implicitly.
- There is no automatic provider switch, mock fallback or model default.

The internal test environment supplies the evaluation selection:

| Variable | Required value |
| --- | --- |
| `TEST_EVALUATION_PROVIDER` | Explicit `bedrock` for the permitted live cohort. The parser recognizes the retained OpenAI adapter, but the live policy rejects its selection. Unknown or missing providers reject. |
| `TEST_EVALUATION_MODEL` | Explicit `openai.gpt-oss-20b-1:0`. Missing, expensive, Luna and other IDs reject before credentials or network use. |
| `TEST_EVALUATION_REGION` | Explicit `ap-southeast-2` (Sydney) for the registered GPT-OSS-20B binding. |
| `TEST_OPENAI_API_KEY` | Retained OpenAI credential port, exercised offline; direct OpenAI live selection is disallowed. No fallback to `OPENAI_API_KEY`. |
| `TEST_AWS_BEARER_TOKEN_BEDROCK` | Credential when evaluating through Bedrock; no fallback to production AWS credentials or the OpenAI test key. |

- The test-only environment reader borrows the process's startup snapshot.
- It never reads `.env.e2e` itself.
- The deployed `sdde` executable does not import the reader/evaluator or consume any of
  these variables.
- The Bedrock test key is passed directly to the internal adapter.
- It is not forwarded to production credential loading.
- No environment values are compiled into either executable.
- The shared [cost policy](../../test/harness/model_cost_policy.zig) allows only
  `aws-bedrock` / `openai.gpt-oss-20b-1:0`.
  Environment selection checks it before credentials are read, and shared live
  composition checks it before constructing a provider adapter. Sonnet, Sol,
  Haiku, Luna, direct OpenAI and other model IDs or aliases cannot reach a live request.
  This development restriction supplies no default and does not restrict the
  production engine's independent model catalogue.

### Judge configuration

- The closed `evaluation-config/v1` JSON object requires every field below.
- Provider/model selection now belongs exclusively to the test environment: JSON `api`,
  `provider`, `model`, `region` and credential fields reject as unknown fields.

| Field | Value / responsibility |
| --- | --- |
| `schema` | `"evaluation-config/v1"` |
| `reasoning_effort` | The selected GPT-OSS-20B judge uses explicit `"low"`. The closed parser retains other registered effort values for adapter conformance; reports retain the independently configured judge setting. |
| `temperature` | The selected GPT-OSS-20B judge uses `0.1`, derived from the engine's fixed supported-temperature control. Bedrock resolves explicit `null` to the same required `0.1`; other values reject. The retained OpenAI parser supports `null` or a number from 0 through 2. |
| `timeout_ms` | Positive integer deadline for each network attempt. |
| `retry_limit` | Integer 0–65535; additional attempts, not total attempts. Zero disables retries. |
| `retry_delay_ms` | Nonnegative integer; must be positive when retries are enabled. |
| `total_token_budget` | Positive integer allowance for reported input + output tokens across this evaluation. |

- For reasoning effort and OpenAI temperature, `null` omits the API control.
- Under the user-approved 2026-10-11 §12.5 amendment, Bedrock temperature always
  resolves to `0.1` when supported, otherwise omission. The resolved value is retained
  in reports and validated before request encoding; callers cannot clear or alter it.
  OpenAI evaluation remains unchanged.
- Unsupported model/settings combinations are configuration errors, not permission to
  choose another model.
- Judge settings/accounting are independent of generation.
- The operator supplies the exact judge selection through the test environment; the
  implementation has no model default.

- This internal configuration change follows the user's 2026-09-08 direction to prefix
  both test credentials with `TEST_` and put evaluation provider/model selection in the
  test environment.
- The same day's Bedrock extension adds the explicit region and selected-provider
  credential.
- Reports retain the complete resolved configuration, including `api:
  "openai_responses"` or `"bedrock_converse"`, `region` and the selected `model`;
  credentials remain separate and never enter a request body or report.

### Provider behavior

- The OpenAI adapter uses only `POST https://api.openai.com/v1/responses`, without
  redirects or tools.
- It requests strict JSON Schema results, `store: false` and `truncation: "disabled"`.
- These controls are documented by [OpenAI
  Responses](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)
  and [Structured
  Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
- `store: false` is not a claim of zero provider retention.
- No SDK or production dependency was added.

- The internal Bedrock adapter uses
  [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html)
  with its [API
  key](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-use.html), reusing
  the production HTTPS transport, endpoint encoding, text request codec, response
  decoding and AWS exception classification.
- Bedrock grading requires native JSON Schema capability from the existing model
  registry in addition to the live-test policy. Explicitly select
  `TEST_EVALUATION_PROVIDER=bedrock`,
  `TEST_EVALUATION_MODEL=openai.gpt-oss-20b-1:0` and
  `TEST_EVALUATION_REGION=ap-southeast-2`. The selected GPT-OSS-20B profile satisfies
  both gates.
  No model or response mode falls back.
- Unknown, mismatched or schema-incapable selections reject before a provider call;
  no model, region, credential chain or endpoint is inferred.
- The compiled `BedrockRequestProfile` and capability owner admit only verified
  request fields. The selected GPT-OSS-20B judge sends explicit low effort through
  `additionalModelRequestFields.reasoning_effort` and temperature `0.1` through
  `inferenceConfig`. Offline fixtures may exercise other registered profiles
  without granting live selection.
- These are the repository's registered contracts, not a catalogue of all models
  available from the provider.

- The native-schema grading requirement remains in force. The canonical Converse
  encoder requests `outputConfig.textFormat.type: "json_schema"` and passes the
  schema string through `outputConfig.textFormat.structure.jsonSchema.schema`.
  The selected GPT-OSS profile does not add Luna's
  `additionalModelRequestFields.text.format.strict` field.
  Common supported controls use `inferenceConfig`. These are the
  [Converse structured-output fields](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).
- `packet.resultSchema` derives one schema from the native judgment type; that
  same schema supplies prompt guidance and the serialized native schema string.
  It uses the supported object/array/scalar/enum/nullable subset. No second schema
  definition or evaluator-specific provider transformation is introduced.
- Complete local judgment validation still owns criterion coverage, score bounds,
  dispositions and exact source/specification evidence. Native schema requests do
  not authorize accepting malformed or unsupported judgments.
- The evaluator supplies no output allowance, so its requests omit
  `inferenceConfig.maxTokens`. No tools, truncation or provider-specific retry policy is added.
- Stopped and malformed output never becomes a grade; validated usage is retained even
  when content is rejected.

- Both evaluator providers reuse the engine's [universal JSON framing
  instruction](../decisions/0014-universal-response-format-guidance.md) once per
  serialized request.
- There is no evaluator-specific copy of the framing text.
- The rubric and native-derived schema retain their existing authority.

- Attempt identity is a closed `unavailable` / `openai_response` / `bedrock_target`
  union.
- OpenAI retains the response's ID and actual model; Bedrock retains only the exact
  requested model/region plus the HTTP request ID when present.
- Optional provider model/ID metadata remains in raw response evidence; it does
  not replace the authorized target identity.
- A foreign provider identity or mismatched Bedrock target rejects before scoring.
- The report renderer labels these different kinds of evidence explicitly.

- The reader separates reasoning/intermediate commentary from the final judgment; it
  validates supported assistant phases without branching on a model name.
- See OpenAI's [phase
  guidance](https://developers.openai.com/api/docs/guides/latest-model#phase-parameter).

See [R8 development acceptance](acceptance.md) for critical vetoes, grader
qualification, human adjudication and the diagnostic run gate. Supplied-spec
calibration retains raw scores while acceptance remains unresolved.

## Contracts and scoring

- [contracts.zig](../../test/harness/contracts.zig),
  [configuration.zig](../../test/harness/configuration.zig),
  [openai.zig](../../test/harness/openai.zig) and
  [judgment.zig](../../test/harness/judgment.zig) own the closed native contracts.
- Cases and rubrics use distinct `/v2` identifiers; configuration remains `/v1`.
  Reports use `evaluation-report/v3` with typed judgment and acceptance evidence.
- Unknown keys, duplicate keys/IDs, unsupported versions and invalid values reject;
  there are no compatibility readers.
- A case declares its ID, source IDs/paths, rubric and grader-qualification paths.
- One invocation selects one case; there is no case registry.

- The rubric is the sole source of criteria, evidence guidance, integer score range,
  per-score anchors, positive integer weights, applicability permissions and optional
  percentage threshold and nullable per-criterion critical minimum.
- No criterion wording is copied into code or the shared judge instruction.
- The API's judgment schema is derived from the native result type rather than
  maintained as a second schema.

### Judgments and evidence

Every criterion must receive exactly one of:

- `scored`: a score within the rubric's range;
- `uncertain`: a null score and explanation;
- `not_applicable`: a null score and explanation, only if that criterion permits it.

- All results need reasons and exact quotations linked to captured document IDs.
- Source evidence is required.
- Candidate evidence is also required unless the judge explicitly reports
  `missing_from_specification`; absence must not be supported by a fabricated quote.
- IDs and quotations are checked mechanically.
- Their semantic relevance, and claims of absence, remain model judgments.

### Score calculation

For scored criteria, the percentage is:

```text
100 × sum(weight × (score − minimum)) / sum(weight × (maximum − minimum))
```

- Explicitly permitted non-applicable criteria are excluded from both sums.
- Any uncertainty leaves the overall score unresolved; excluding every criterion also
  produces no score.
- The stored score is not rounded before threshold comparison; the Markdown view
  displays two decimal places.
- A null rubric threshold means no pass/fail decision.
- Neither a low score nor a missed threshold is an API failure.

### Initial rubric and calibration

- The initial [Hello World
  rubric](../../test/e2e/wf-001-hello-world/node-vitest/rubric/spec.json) is an
  **uncalibrated draft**: 0–4 integer anchors, equal weights, 80% threshold, critical minima 3/4 and no
  non-applicable criteria.
- These are visible rubric-author choices, not engine defaults or approved release
  policy.
- Revision 2 adds UTC; revision 3 adds explicit critical-score metadata.
- Its seven criteria address startup, exact greeting, UTC date/time, grounding,
  clarity/testability, organization and proportionate business scope.
- It does not demand Node/Vitest implementation details, invented entities or filler for
  empty sections.
- Human review and live calibration remain open under H-002/H-016.

- The [calibration set and review
  procedure](../../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/README.md)
  provide equivalent wording plus missing behavior, changed greeting, unsupported scope
  and embedded-instruction specimens.
- They use this same evaluator and rubric; reviewer expectations are not included in
  judge inputs.
- Human approval and live results remain pending.

## Attempts and failures

- Authentication/configuration errors, rate limiting, deadlines, cancellation, refusal,
  incomplete output, invalid responses/judgments, unavailable usage, exhausted retries
  and exceeded budgets are explicit evaluator errors, never scores.
- Reports retain returned response/model identity, HTTP request identity when available,
  and validated actual token usage.
- Error bodies and credentials are not retained.
- Valid usage survives malformed judgment/output data.
- `evaluation-report/v3` carries the judgment validator's typed diagnostic in
  JSON and Markdown: parser byte/line/column for invalid JSON, or the affected
  criterion, zero-based evidence index and document ID for invalid evidence.
  Missing source and specification evidence are distinct. Valid JSON that fails
  the closed response contract reports `invalid_shape`. Diagnostics add no retry
  or authority to score an invalid judgment; the E2E report embeds the same value.

- Only transient provider failures/rate limits with known actual usage can retry, within
  the configured count, delay and remaining allowance.
- Unknown consumption stops further calls; ordinary HTTP 429 responses without usage
  therefore stop.
- Low scores, refusals and invalid judgments are not retried to obtain a pass.

- The total-token allowance is checked against actual responses; it cannot promise a
  hard billing ceiling for an in-flight request.
- An overshoot is retained and reported as `budget_exceeded`; no further request is
  sent.
- There is no guessed zero usage, output-token cap, persisted billing ledger or
  cross-run exactly-once claim.
- Cancellation/deadline handling joins the network operation before its memory is
  released; provider-side cancellation/billing cannot be guaranteed.

## Reports and origin

- Each invocation captures inputs once and receives a new random evaluation ID.
- The existing output directory receives exclusively created `eval-<id>.json` and
  `eval-<id>.md` files with owner-only file permissions.
- A matching `eval-<id>/` directory uses the same evaluation trace store as generated
  specification grading. Each attempt retains its serialized request, raw provider
  response, available final text and outcome with known credentials redacted. Capture
  failure aborts evaluation; a score is never reported without its required evidence.
- Existing files, including specifications and clarifications, are never replaced.
- Reports are retained until the operator removes them; no pruning, transaction store or
  resume path is created.
- An interrupted write can leave an incomplete report, which is not a completed
  evaluation.
- Output availability is checked before the API call.

- JSON retains exact source/spec bytes, original case/rubric bytes and their parsed
  projections, origin, prompt/schema revisions, judge configuration, per-attempt
  identity/usage, criterion results and aggregate outcome.
- Markdown is a readable, escaped projection of the same report value.
- Treat retained inputs as potentially sensitive local data.
- An input overwritten later cannot alter this capture.

- The CLI always labels its candidate `supplied` and workflow status `not_run`.
- It never claims to have generated that file.
- The shared grading call accepts explicit recorded/scripted/live provenance; fresh
  generation requires a completed execution identity and live generation records each
  configured slot/provider/model in `generation.models`.
- The E2E entry point supplies this identity and the exact published artifact directly.
- Recorded artifacts can preserve a previous failed/needs-user status without changing
  that status through grading.
- Full workflow execution and its failure reports are not implemented by this entry
  point.

- To regrade, explicitly supply the retained candidate and corresponding source/ rubric
  copies as a new invocation.
- There is no automatic latest-file selection, generation rerun or
  report-as-workflow-authority import.

| Exit | Meaning |
| --- | --- |
| `0` | Reserved for authoritative acceptance; model evaluation remains advisory. |
| `2` | Unresolved acceptance, including every advisory model judgment pending human review. |
| `1` | Failed acceptance, input, configuration, provider, judgment or reporting failure. |

- The machine report keeps workflow status separate from `evaluated` /
  `evaluator_error`.

## Implementation and verification

- The development build root is [harness.zig](../../harness.zig); implementation lives
  under `test/harness/`.
- It is not installed as part of `sdde`, registered as a workflow operation or imported
  by the production engine.
- Native HTTPS uses Zig's standard library.
- Shared strict JSON, normalized relative paths, descriptor-based file capture,
  provider/model identities and `ProviderUsage` validation are reused.
- Closed native JSON decoding now also lives in the shared `strict_json` owner, used by
  both evaluator contracts and specification candidates.
- The old evaluator-local wire-kind checker has been removed.

- `LLMProviderInterface` requires workflow request identities and authorization leases.
- The standalone evaluator does not fabricate those to grade a supplied file: its narrow
  provider port returns only observations.
- It has no feature publication or workflow state capability.
- Attempt observations are its sole usage record; no production lifecycle/ledger is
  copied.

```sh
zig build test-rubric-evaluator
zig build build-rubric-evaluator
zig build smoke-rubric-evaluator
zig build evaluate-spec -- --help
zig build verify
```

- Tests use scripted results for the original rubric and unrelated criterion IDs, score
  ranges and weights.
- They exercise closed parsing, evidence/absence joins, uncertainty, provider errors,
  retry/budget accounting, allocation failures, immutable file capture, unsafe paths and
  report escaping.
- The clean-directory smoke runs the standalone binary without credentials or
  development assets.
- Ordinary `test`/`verify` include offline evaluator checks; they never invoke an API.

- Passing mechanical tests does not establish that a live judge grades correctly.
- Live execution evidence is recorded with the [E2E results](e2e.md).
- Human H-016 calibration remains outstanding.
- The handoff is implemented, but the latest live generation failed before a
  specification was available to grade.
