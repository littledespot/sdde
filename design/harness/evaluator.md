# Supplied-spec rubric evaluator

Implements the evaluator-only path in [H-001–H-006](01-rubric-evaluator.md).
It sends captured requirements, a supplied specification and its rubric to
OpenAI, validates the returned judgments, and writes JSON/Markdown reports.
It does **not** run Specify or require a deterministic definition of good prose.

The current implementation task explicitly excludes human calibration and live
API verification. The existing opt-in live command is unchanged; those checks
are not claimed as completed or prerequisites for offline implementation.

## Run

From the repository root, prepare a candidate file, an existing report directory
and a judge configuration. Then explicitly authorize the live request:

```sh
zig build evaluate-spec -- \
  --case test/evaluation/wf-001-hello-world/node-vitest/spec.case.json \
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

Provide `OPENAI_API_KEY` through the process environment, never in the command,
case or judge configuration. `--live` is mandatory and sends the complete declared
source/spec/rubric content to OpenAI; review these inputs before authorizing it.
No principle directories or other repository content are discovered implicitly.
There is no alternate provider, mock fallback or model default.

The closed `evaluation-config/v1` JSON object requires every field below:

| Field | Value / responsibility |
| --- | --- |
| `schema` | `"evaluation-config/v1"` |
| `api` | `"openai_responses"` |
| `model` | Operator-selected exact OpenAI model ID supporting Structured Outputs. |
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

The native adapter uses only `POST https://api.openai.com/v1/responses`, without
redirects or tools. It requests strict JSON Schema results, `store: false` and
`truncation: "disabled"`. These controls are documented by
[OpenAI Responses](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)
and [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
`store: false` is not a claim of zero provider retention. No SDK or production
dependency was added.

The reader separates reasoning/intermediate commentary from the final judgment;
it validates supported assistant phases without branching on a model name.
See OpenAI's [phase guidance](https://developers.openai.com/api/docs/guides/latest-model#phase-parameter).

## Contracts and scoring

[contracts.zig](../../test/harness/contracts.zig),
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

The initial [Hello World rubric](../../test/evaluation/wf-001-hello-world/node-vitest/rubric/spec.json)
is an **uncalibrated draft**: 0–4 integer anchors, equal weights, no pass threshold
and no non-applicable criteria. These are visible rubric-author choices, not
engine defaults or approved release policy. Its six criteria address startup,
exact greeting, grounding, clarity/testability, organization and proportionate
business scope. It does not demand Node/Vitest implementation details, invented
entities or filler for empty sections. Human review and live calibration remain
open under H-002/H-016.

The [calibration set and review procedure](../../test/evaluation/wf-001-hello-world/node-vitest/calibration/README.md)
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
explicit recorded/scripted/live provenance for H-015; fresh generation requires
a completed execution identity, with provider/model also required for live
generation. Recorded artifacts can preserve a previous failed/needs-user status
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

No paid OpenAI request or live rubric calibration was performed during this
implementation. Passing mechanical tests does not establish that a live judge
grades correctly. H-004's authorized live acceptance and H-016's calibration
remain outstanding; H-007–H-015 still own producing and handing off a fresh spec.

Recorded offline verification (2026-09-06):

- `zig build test-rubric-evaluator --summary all`: 29 tests passed, including
  capture of all seven calibration specimens without semantic prefiltering.
- `zig build verify --summary all`: 781 tests, lint and native smoke checks passed.
- `zig build evaluate-spec -- --help`: passed without an API call.
- `git diff --check`: clean. Local documentation links resolve; original stories
  and principle files are unchanged.
