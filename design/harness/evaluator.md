# Supplied-spec rubric evaluator

Implements the evaluator-only path in [H-001–H-006](01-rubric-evaluator.md).
It sends captured requirements, a supplied specification and its rubric to
OpenAI or Bedrock, validates the returned judgments, and writes JSON/Markdown reports.
It does **not** run Specify or require a deterministic definition of good prose.

The [live E2E harness](e2e.md) now joins production generation to this evaluator.
Human rubric calibration and broader live acceptance
are not claimed as completed or prerequisites for offline implementation.

## Run

From the repository root, prepare a candidate file, an existing report directory
and a judge configuration. If using the optional local `.env.e2e` credential
file, load it into this shell with `. ./.env.e2e` first; see
[E2E environment setup](../../README.md#e2e-environment-setup).
Then explicitly authorize the live request:

```sh
zig build evaluate-spec -- \
  --case test/e2e/wf-001-hello-world/node-vitest/spec.case.json \
  --spec evaluation-input/spec.md \
  --config evaluation-input/judge.json \
  --output evaluation-output \
  --live
```

`evaluation-input` and `evaluation-output` are operator-selected examples, not
automatically created locations. All command and case-file paths are normalized
relative to the invocation's current directory, **not** the case file's parent.
Absolute paths, traversal and symlinked input/output directories are rejected.
The candidate must be readable, nonempty UTF-8. Missing headings, unwanted prose
and poor requirements remain judgeable; there is no `SpecificationIR` gate.

Provide the selected provider's `TEST_` credential through the process environment, never in the command,
case or judge configuration. `--live` is mandatory and sends the complete declared
source/spec/rubric content to the selected provider; review these inputs before authorizing it.
No principle directories or other repository content are discovered implicitly.
There is no automatic provider switch, mock fallback or model default.

The internal test environment supplies the evaluation selection:

| Variable | Required value |
| --- | --- |
| `TEST_EVALUATION_PROVIDER` | `openai` or `bedrock`; unknown or missing providers reject. |
| `TEST_EVALUATION_MODEL` | Exact operator-selected model ID; missing/empty IDs reject. OpenAI requires Structured Outputs support; Bedrock requires a registered model/region pair. |
| `TEST_EVALUATION_REGION` | Explicit registered Bedrock region; empty/unset for OpenAI. |
| `TEST_OPENAI_API_KEY` | Credential for internal evaluation calls only; no fallback to `OPENAI_API_KEY`. |
| `TEST_AWS_BEARER_TOKEN_BEDROCK` | Credential when evaluating through Bedrock; no fallback to production AWS credentials or the OpenAI test key. |

The test-only environment reader borrows the process's startup snapshot. It
never reads `.env.e2e` itself. The deployed `sdde` executable does not import
the reader/evaluator or consume any of these variables. The Bedrock test key is
passed directly to the internal adapter. It is not forwarded to production
credential loading. No environment values are compiled into either executable.

The closed `evaluation-config/v1` JSON object requires every field below.
Provider/model selection now belongs exclusively to the test environment:
JSON `api`, `provider`, `model`, `region` and credential fields reject as unknown fields.

| Field | Value / responsibility |
| --- | --- |
| `schema` | `"evaluation-config/v1"` |
| `reasoning_effort` | Explicit `null`, or `none`, `minimal`, `low`, `medium`, `high`, `xhigh`; must be supported by the selected model. |
| `temperature` | Explicit `null`, or a number from 0 through 2 supported by the selected model. |
| `timeout_ms` | Positive integer deadline for each network attempt. |
| `retry_limit` | Integer 0–65535; additional attempts, not total attempts. Zero disables retries. |
| `retry_delay_ms` | Nonnegative integer; must be positive when retries are enabled. |
| `total_token_budget` | Positive integer allowance for reported input + output tokens across this evaluation. |

`null` omits the corresponding API control; it does not select a hidden local
value. Unsupported model/settings combinations are configuration errors, not
permission to choose another model. Judge settings/accounting are independent
of any future generation run. No exact model or paid-run configuration has been
selected by this implementation.

This internal configuration change follows the user's 2026-09-08 direction to
prefix both test credentials with `TEST_` and put evaluation provider/model
selection in the test environment. The same day's Bedrock extension adds the
explicit region and selected-provider credential. Reports retain the complete resolved
configuration, including `api: "openai_responses"` or `"bedrock_converse"`, `region` and the selected `model`;
credentials remain separate and never enter a request body or report.

The OpenAI adapter uses only `POST https://api.openai.com/v1/responses`, without
redirects or tools. It requests strict JSON Schema results, `store: false` and
`truncation: "disabled"`. These controls are documented by
[OpenAI Responses](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)
and [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
`store: false` is not a claim of zero provider retention. No SDK or production
dependency was added.

The internal Bedrock adapter uses [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html)
with its [API key](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-use.html),
reusing the production HTTPS transport, endpoint encoding, text request codec,
response decoding and AWS exception classification. The existing registry
supports `openai.gpt-oss-20b-1:0` in `ap-southeast-2`, and
`anthropic.claude-3-5-haiku-20241022-v1:0` in `us-west-2`. Unknown or mismatched
pairs reject; no new model, region, credential chain or endpoint is inferred.
Both currently require `reasoning_effort: null`; temperature is null or 0–1.

Bedrock evaluation uses an explicit prompt-only JSON profile: the same complete
rubric, inputs and native-derived result schema go into the request, followed
by the same local judgment validation. This is not native schema enforcement
or a fallback from failed native mode. No tools, `maxTokens`, truncation or
provider-specific retry policy is added. Stopped and malformed output never
becomes a grade; validated usage is retained even when content is rejected.

Attempt identity is a closed `unavailable` / `openai_response` / `bedrock_target`
union. OpenAI retains the response's ID and actual model; Bedrock retains only
the exact requested model/region plus the HTTP request ID when present. Converse
does not echo an actual model or response ID, so neither is invented. A foreign
provider identity or mismatched Bedrock target rejects before scoring. The
report renderer labels these different kinds of evidence explicitly.

The reader separates reasoning/intermediate commentary from the final judgment;
it validates supported assistant phases without branching on a model name.
See OpenAI's [phase guidance](https://developers.openai.com/api/docs/guides/latest-model#phase-parameter).

## Contracts and scoring

[contracts.zig](../../test/harness/contracts.zig),
[configuration.zig](../../test/harness/configuration.zig),
[openai.zig](../../test/harness/openai.zig) and
[judgment.zig](../../test/harness/judgment.zig) own the closed native contracts.
Case, rubric, configuration and report use distinct `/v1` schema identifiers.
Unknown keys, duplicate keys/IDs, unsupported versions and invalid values reject;
there are no compatibility readers. A case declares its ID, source IDs/paths and
rubric path. One invocation selects one case; there is no case registry.

The rubric is the sole source of criteria, evidence guidance, integer score
range, per-score anchors, positive integer weights, applicability permissions
and optional percentage threshold. No criterion wording is copied into code or
the shared judge instruction. The API's judgment schema is derived from the
native result type rather than maintained as a second schema.

Every criterion must receive exactly one of:

- `scored`: a score within the rubric's range;
- `uncertain`: a null score and explanation;
- `not_applicable`: a null score and explanation, only if that criterion permits it.

All results need reasons and exact quotations linked to captured document IDs.
Source evidence is required. Candidate evidence is also required unless the
judge explicitly reports `missing_from_specification`; absence must not be
supported by a fabricated quote. IDs and quotations are checked mechanically.
Their semantic relevance, and claims of absence, remain model judgments.

For scored criteria, the percentage is:

```text
100 × sum(weight × (score − minimum)) / sum(weight × (maximum − minimum))
```

Explicitly permitted non-applicable criteria are excluded from both sums. Any
uncertainty leaves the overall score unresolved; excluding every criterion also
produces no score. The stored score is not rounded before threshold comparison;
the Markdown view displays two decimal places. A null rubric threshold means no
pass/fail decision. Neither a low score nor a missed threshold is an API failure.

The initial [Hello World rubric](../../test/e2e/wf-001-hello-world/node-vitest/rubric/spec.json)
is an **uncalibrated draft**: 0–4 integer anchors, equal weights, no pass threshold
and no non-applicable criteria. These are visible rubric-author choices, not
engine defaults or approved release policy. Revision 2 adds the user-authored UTC requirement. Its seven criteria address
startup, exact greeting, UTC date/time, grounding, clarity/testability, organization and proportionate
business scope. It does not demand Node/Vitest implementation details, invented
entities or filler for empty sections. Human review and live calibration remain
open under H-002/H-016.

The [calibration set and review procedure](../../test/e2e/wf-001-hello-world/node-vitest/calibration/README.md)
provide equivalent wording plus missing behavior, changed greeting, unsupported
scope and embedded-instruction specimens. They use this same evaluator and
rubric; reviewer expectations are not included in judge inputs. Human approval
and live results remain pending.

## Attempts and failures

Authentication/configuration errors, rate limiting, deadlines, cancellation,
refusal, incomplete output, invalid responses/judgments, unavailable usage,
exhausted retries and exceeded budgets are explicit evaluator errors, never
scores. Reports retain returned response/model identity, HTTP request identity
when available, and validated actual token usage. Error bodies and credentials
are not retained. Valid usage survives malformed judgment/output data.

Only transient provider failures/rate limits with known actual usage can retry,
within the configured count, delay and remaining allowance. Unknown consumption
stops further calls; ordinary HTTP 429 responses without usage therefore stop.
Low scores, refusals and invalid judgments are not retried to obtain a pass.

The total-token allowance is checked against actual responses; it cannot promise
a hard billing ceiling for an in-flight request. An overshoot is retained and
reported as `budget_exceeded`; no further request is sent. There is no guessed
zero usage, output-token cap, persisted billing ledger or cross-run exactly-once
claim. Cancellation/deadline handling joins the network operation before its
memory is released; provider-side cancellation/billing cannot be guaranteed.

## Reports and origin

Each invocation captures inputs once and receives a new random evaluation ID.
The existing output directory receives exclusively created `eval-<id>.json` and
`eval-<id>.md` files with owner-only file permissions. Existing files, including
specifications and clarifications, are never replaced. Reports are retained
until the operator removes them; no pruning, transaction store or resume path
is created. An interrupted write can leave an incomplete report, which is not a
completed evaluation. Output availability is checked before the API call.

JSON retains exact source/spec bytes, original case/rubric bytes and their parsed
projections, origin, prompt/schema revisions, judge configuration, per-attempt
identity/usage, criterion results and aggregate outcome. Markdown is a readable,
escaped projection of the same report value. Treat retained inputs as potentially
sensitive local data. An input overwritten later cannot alter this capture.

The CLI always labels its candidate `supplied` and workflow status `not_run`.
It never claims to have generated that file. The shared grading call accepts
explicit recorded/scripted/live provenance; fresh generation requires
a completed execution identity and live generation records each configured
slot/provider/model in `generation.models`. The E2E entry point supplies this
identity and the exact published artifact directly. Recorded artifacts can preserve a previous failed/needs-user status
without changing that status through grading. Full workflow execution and its
failure reports are not implemented by this entry point.

To regrade, explicitly supply the retained candidate and corresponding source/
rubric copies as a new invocation. There is no automatic latest-file selection,
generation rerun or report-as-workflow-authority import.

Exit status is `0` for a completed scored evaluation, including a low score or
missed threshold; `2` for an unresolved/no-applicable assessment; `1` for input,
configuration, provider, judgment or reporting failure. The machine report keeps
workflow status separate from `evaluated` / `evaluator_error`.

## Implementation and verification

The development build root is [harness.zig](../../harness.zig); implementation
lives under `test/harness/`. It is not installed as part of `sdde`, registered as
a workflow operation or imported by the production engine. Native HTTPS uses
Zig's standard library. Shared strict JSON, normalized relative paths,
descriptor-based file capture, provider/model identities and `ProviderUsage`
validation are reused.
Closed native JSON decoding now also lives in the shared `strict_json` owner,
used by both evaluator contracts and specification candidates. The old
evaluator-local wire-kind checker has been removed.

`LLMProviderInterface` requires workflow request identities and authorization
leases. The standalone evaluator does not fabricate those to grade a supplied
file: its narrow provider port returns only observations. It has no feature
publication or workflow state capability. Attempt observations are its sole
usage record; no production lifecycle/ledger is copied.

```sh
zig build test-rubric-evaluator
zig build build-rubric-evaluator
zig build smoke-rubric-evaluator
zig build evaluate-spec -- --help
zig build verify
```

Tests use scripted results for the original rubric and unrelated criterion IDs,
score ranges and weights. They exercise closed parsing, evidence/absence joins,
uncertainty, provider errors, retry/budget accounting, allocation failures,
immutable file capture, unsafe paths and report escaping. The clean-directory
smoke runs the standalone binary without credentials or development assets.
Ordinary `test`/`verify` include offline evaluator checks; they never invoke an API.

Passing mechanical tests does not establish that a live judge grades correctly.
Live execution evidence is recorded with the [E2E results](e2e.md). Human
H-016 calibration remains outstanding. The handoff is implemented, but the
latest live generation failed before a specification was available to grade.

Recorded offline verification (2026-09-06):

- `zig build test-rubric-evaluator --summary all`: 29 tests passed, including
  capture of all seven calibration specimens without semantic prefiltering.
- `zig build verify --summary all`: 781 tests, lint and native smoke checks passed.
- `zig build evaluate-spec -- --help`: passed without an API call.
- `git diff --check`: clean. Local documentation links resolve; original stories
  and principle files are unchanged.
