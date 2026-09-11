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
  project/
    ...declared inputs and actual engine output...
```

The timestamp uses `YYYY-MM-DDTHH-MM-SSZ`; the unique suffix separates concurrent
runs. Output paths come from validated project configuration. Reports are
reserved before API calls. Captured inputs and the isolated project are retained
on failure; input capture failures can leave only the case and failure report.
Credentials are never serialized. An interrupted process may leave incomplete
reports and does not establish a completed run.

Reports preserve execution identity, engine outcome, selected generation models
by slot, accounted usage, publication checks and separate provider/model
rejections. Completed evaluations also retain exact source/spec/rubric bytes,
judge configuration, attempts, criterion judgments, evidence and aggregate score.
Source changes during execution fail the run without modifying retained inputs.

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
No reasoning narrative is imported as workflow data or copied into the report.

## Live evidence — 2026-09-11

The live development command is:

```sh
./scripts/e2e-spec.sh
```

Both generation configuration and judge settings select Bedrock GPT-OSS 20B in
`ap-southeast-2`. These reports retain the failure progression:

| Run directory under `zig-out/e2e-spec/` | Result | Calls | Accounted tokens |
| --- | --- | --- | --- |
| `2026-09-11T21-15-59Z-d6f2ad50042c58acc9d463f6c9b7d8b0` | `input_invalid`; missing evaluator environment before launcher correction | 0 | 0 |
| `2026-09-11T21-28-48Z-d473557d1f1954f109202bc05adf38fe` | `workflow_failed`; Bedrock returned `max_tokens` at extraction, before selecting low reasoning | 1 | 7,106 |
| `2026-09-11T21-38-34Z-b8ea7a8854fb4aa250fd44bb77804e72` | `workflow_failed`; `InvalidModelEnvelope` at reconciliation with low reasoning | 3 | 8,472 |

The launcher now loads the checkout's `.env.e2e`. The second run reached
Bedrock, which reported 3,010 input and 4,096 output tokens with an output-limit
stop despite the absence of `maxTokens` in the request. This is a provider
cutoff, not the cumulative workflow budget or an engine-imposed output cap.

With explicit low reasoning, extraction completed. The latest run stopped at
`g2-rc-assign` because the reconciliation response was not a valid JSON object
even after its configured protocol retry. The final call used 2,251 input plus
481 output tokens. No provider stop was reported. It published no specification
and has `semantic_quality: not_evaluated`. The captured sources still match the
repository inputs. These runs prove live failure detection and usage reporting;
**successful generation followed by a live rubric grade remains unverified**.
The reports identify where to investigate workflow prompts and model behavior;
they contain no semantic grade for unpublished output. The harness does not
weaken gates or substitute candidate text to obtain a pass.

## Mechanical verification — 2026-09-11

- `zig build test-provider-conformance test-e2e-harness test-rubric-evaluator build-e2e-harness --summary all`
  — 11/11 steps; 468/468 tests passed.
- `zig build verify --summary all`
  — 120/120 steps; 1,311/1,311 tests passed, including lint, architecture,
  standalone harness/evaluator smoke and clean native engine packaging.
- `git diff --check` — passed. Local links in the edited harness documentation
  resolve; obsolete scripted-generation and expected-specification fixtures
  are absent. The user's source change is preserved.

These are mechanical checks and do not replace the unmet live result above.
