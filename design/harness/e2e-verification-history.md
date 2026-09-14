# E2E verification history — September 2026

[Current E2E instructions](e2e.md). These records preserve the source, commands,
results and retained evidence inspected for each change. They are historical
observations, not new verification or current implementation status. The
[active rollout](../../fixes/IMP_001.md) records subsequent work. Local
`zig-out` and temporary artifacts are untracked and may be absent elsewhere.

## Historical verification records

## Source selection verification — 2026-09-12

The source-selection implementation passed `zig build verify --summary all`
(1,338 tests, lint, architecture and native packaging). Regression coverage
includes lossless Unicode/line-ending/chunk handling, invalid and stale IDs,
one-citation and missing-collection repair, unchanged siblings, revision/owner
rejection, repair exhaustion and producing-call attribution after release.
These are mechanical results, not evidence of generated specification quality.

Live repetitions used
`scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json`
with the case's configured Bedrock GPT-OSS 20B and unchanged judge settings.
All four network-enabled executions failed before publication; none reached
rubric grading. The preceding sandboxed attempt failed at transport.

| Run ID | Observed terminal failure |
| --- | --- |
| `2026-09-12T04-59-59Z-70b418738fdd3b609f4647f5bfd2fd64` | Sandboxed transport failure; excluded from the four network-enabled runs. |
| `2026-09-12T06-16-42Z-86de88bd36020b09665fe871e65a9e17` | Extraction and canonical citations accepted; cross-source reconciliation exhausted protocol retry with missing `/statements/0/content/kind`. |
| `2026-09-12T06-20-14Z-b2cdace9b811cc76956af8d5f3e3349b` | Extraction exhausted protocol retry with unknown `/token_classifications/0/preserve/ordinal`. |
| `2026-09-12T06-22-24Z-949a18b95dda68405c5c4cd964098d22` | Provider `response_invalid`; exact provider-body defect was not established. |
| `2026-09-12T06-25-53Z-83729e2001f8267b033c68053557ae6c` | Extraction repeated the unknown `preserve/ordinal` field; 2 accounted calls, 6,395 tokens, complete usage, no published output or grade. |

The first four directories disappeared during inspection; the cause was not
established. Their terminal outcomes above remain observed results, but their
missing raw artifacts cannot be claimed as retained evidence. The final run
was also copied to `/private/tmp/sdde-source-selection-live/` during inspection.
Both of its calls retain context, request, response, final text and outcome;
each final text was checked byte-for-byte against its provider response.
`capture-audit.json` in that temporary directory records hashes and checks.

This batch establishes failure visibility and one live passage through source
selection. It does **not** demonstrate reliable completion, live citation
repair, or acceptable published output. The existing model/schema failures
remain unresolved; the shared validators and rubric were not weakened.

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

## Protocol retry ownership verification — 2026-09-12

Protocol correction now uses the existing attempt-accounting limit and global
token budget; the builder's separate one-visit limit and YAML parameter are
removed. Each correction contains the retained original inputs plus only the
latest rejection. Runner exhaustion is terminal and reports its compiled owner,
limit and execution count. The E2E observer retains the latest call's protocol
diagnostic across transport retirement, and supersedes it on the next call.
These are diagnostic projections, not additional workflow authority.

Validation kept caches and temporary projects inside this checkout:

```sh
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg test-e2e-harness --summary all
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg test-atomic-execution --summary all
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg verify --summary all
git diff --check
```

Final verification passed **120/120 steps and 1,340/1,340 tests**, including
architecture checks and clean native packaging. Focused results were 30 payload
schema tests, 173 request-workflow tests, 385 harness/native integration tests,
and 121 atomic-execution tests. Regressions cover two consecutive syntax/schema
corrections for multiple logical requests through the same extraction,
reconciliation and generation steps; stable original input content; exact latest
rejection content; exhaustion without an extra call or a YAML success escape;
and retained diagnostic ownership after transport/observer teardown.

Three live executions used the unchanged case configuration and `.env.e2e`:

```sh
. ./.env.e2e
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

| Run/report | Calls / tokens | Observed result |
| --- | --- | --- |
| [07:15:23](../../zig-out/e2e-spec/2026-09-12T07-15-23Z-303ef1477f7d2f99830da358340360a6/report.md) | 5 / 15,589 | Global reconciliation passed JSON/schema checks, then `validate-dispositions` rejected nine dispositions repeating three claim IDs. |
| [07:17:26](../../zig-out/e2e-spec/2026-09-12T07-17-26Z-bb25aaba8067146972d5263d3a1e7b3f/report.md) | 8 / 23,452 | Extraction and cross-source reconciliation each recovered on attempt three. Correction content remained five blocks. Global reconciliation then returned retained claims with no signals; `validate-signals` rejected it. |
| [07:19:15](../../zig-out/e2e-spec/2026-09-12T07-19-15Z-109238cbc03e18934bb6e66361097d3c/report.md) | 4 / 8,638 | Repeated duplicate token classifications exhausted `g17-extraction-repair-account`, configured limit 1, completed executions 2. Terminal output, events and reports retain that owner/count and the candidate diagnostic's producing call. |

The runs retain 158, 192 and 125 step events respectively, both reports, and all
five evidence files for each returned call. The earlier sandbox-restricted
attempt at 07:14:13 is separately retained with `transport_failed`; it is not
live model-quality evidence.

No live run published a specification or reached rubric grading. The retry
defect is remedied, but reliable completion and output quality remain unmet.
Reconciliation's domain failures still surface as generic `failed` in reports;
the specific violations above were diagnosed from saved responses and their
canonical validators. They need shared typed diagnostics and authorized semantic
repair, rather than additional JSON retries or weaker validation.

Native generation constraints derive from the engine's compiled result schema;
complete bounds and semantic checks remain mandatory. Each captured call records
its response mode and actual wire request. JSON diagnostics include container
paths, active keys and duplicate-key occurrence locations; reports and protocol
corrections reuse this shared diagnostic. Compare retained runs using initial
JSON/schema acceptance, retries, token use, publication and rubric outcomes.
A structurally valid response alone does not satisfy E2E quality acceptance.

See the [2026-09-12 JSON quality verification](04-json-quality-2026-09-12.md)
for all retained run outcomes and the current native-mode activation limitation.

## FIX_001 Phase 2 — proposal boundaries

Model responses now select evidence; the engine constructs summary lineage and
aggregate citation unions. Canonical records and input evidence retain complete
provenance. Generation, repair and support use the reduced selection shape;
legacy echo fields reject. Tagged dispositions expose only the relevant
relationships, with concise guidance from the native constraint owner.

The [Phase 2 delivery record](../../fixes/IMP_001.md#phase-2-delivery-and-verification--13-september-2026)
contains exact commands: 408/408 targeted tests and full offline verification
with 120/120 steps and 1,374/1,374 tests, including clean native packaging.
No live E2E run was performed for
this phase. Existing reports remain historical evidence; live convergence,
publication and rubric quality remain unproven. At that phase close, semantic repair remained Phase 3 work. The
[active rollout](../../fixes/IMP_001.md) records subsequent repair delivery, reopened Phase 3 findings
and the remaining support/evidence work. Every live run still requires explicit approval.
