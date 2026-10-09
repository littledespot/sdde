# Authoring-role calibration

Development diagnostic under design §28.8, separate from integration tests and
live E2E. It measures role selection before R10's coverage gate; it does not run,
correct or publish a workflow. Production prompts and role purposes are unchanged.

## Labels and comparison

Both cohorts were reviewed and approved by the project user on 9 October 2026.
The focused pilot is complete: 12 corrected development, four captured-input and
16 held-out trials ran with explicit bounded approval. For revised cohorts, review
source meanings, claim kinds, grouped inputs and labels before recording human
review. Label review alone does not approve an API invocation.

| Family | Split | Reviewed expectation |
| --- | --- | --- |
| UTC display | Development | All six roles supported by behavior; copied greeting alone supports none. Entities can be not applicable. |
| Loan renewal | Development | All six roles supported; member/loan concepts required. |
| Runtime context | Development | All roles unsupported: an implementation environment supplies no product behavior. |
| Countdown | Held out | All roles supported; entities not applicable. |
| Stock transfer | Held out | All roles supported; item/location relationships required. |
| Isolated copied value | Held out | All roles unsupported. |
| Undecided notification storage | Held out | Intent/records supported; entity-basis assignment optional because the premise is ambiguous. |
| Captured greeting + UTC | Development, separate cohort | Retained call 7's behavioral group supports all roles; copied greeting supports none. |

`required: true` requires the role on at least one `allowed_signal_ids` group.
Multiple allowed IDs permit alternatives. `required: false` with allowed IDs
permits an ambiguous choice; with an empty list it means unsupported. Every
assigned pair outside its allowed set counts as unsupported, even if another
assignment supports the same role. Exact assignment order/group count is not a
semantic target. Native membership and retained-claim rules still apply first.

Controlled premises use native fixture helpers and the production packet/schema
builders, not LLM upstream results. Captured inputs retain upstream errors; the
retained greeting includes an added “current,” so local routing and upstream
fidelity must be judged separately. Labels and rationales never enter model content.
Source-family splits prevent paraphrases appearing in both sets. Reserve the
held-out split for a fixed candidate; do not tune against its results. Human
disagreement requires revising or marking a label optional, not treating model
agreement as ground truth. These assistant-authored examples cannot establish
population reliability or replace whole-workflow E2E/rubric evidence.

## Prepare without API calls

Select an explicit captured binding by exact call ID, not the log event sequence:

```sh
mkdir -p zig-out/role-calibration
zig build calibrate-roles -- \
  --cohort test/calibration/authoring-roles/cohort.json \
  --output zig-out/role-calibration \
  --feature zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/project/specs/hello-world \
  --run RUN-cbac788ebaac52369795c48e68656ea0 \
  --call request-7-inference-1 \
  --split development --repeats 2 \
  --guidance test/calibration/authoring-roles/candidate.prompt.md
```

This prepares **12 trials**: three cases × two repeats × baseline/candidate
guidance. Each pair retains identical model, settings, role definitions, evidence
and response schema. The retained binding is Bedrock 20b, low reasoning,
temperature 0, native schema, `ap-southeast-2`. No binding/case is selected by default.
The candidate is experimental, not a production fix. Omit `--guidance` for
baseline-only repeats.

The first 12 development calls had a harness input-ownership defect and are
excluded from semantic comparisons. The defect is fixed and covered by a
multiple-case lifetime regression; the corrected comparison has executed.
[R7 results](../../../fixes/FIX01.md#r7--high-focused-role-calibration-complete-broader-calibration-remains-open)
retain all captures and costs, including those invalid trials. The candidate
reduced unsupported assignments but regressed on the captured input and did not
reduce total omissions. Production guidance remains unchanged. All approved calls
have executed; future live invocations require fresh bounded approval.

Select `captured.cohort.json` for four additional trials of the retained production
input. Its path/run/call name explicit historical evidence; missing logs fail
without fallback. Relabel different captures rather than reusing these labels
arbitrarily. `--split held_out` on the controlled cohort prepares 16 held-out trials.

Each invocation creates a fresh directory containing `plan.json`, `report.json`,
`report.md` and immutable requests in `logs/debugger`. Offline outcomes are
`not_run`. Inspect these concrete inputs before requesting live approval.

## Live runs and reports

After human label review **and explicit bounded user approval**, set
`TEST_AWS_BEARER_TOKEN_BEDROCK` and add `--live` to the approved command. No `.env`
file is loaded; production credentials are not a fallback. The existing Bedrock
replay adapter owns encoding/decoding, validation and one-send execution. Every
trial makes at most one send, with no retry, correction or repair. These are
first-pass results, not repaired success or E2E evidence.

Missing roles / required roles and unsupported pairs / assigned pairs are
conditional on admitted answers. Protocol, native and operational failures remain
beside them and in the declared trial count. Reports retain paired rows, unchanged
repeats, byte contributions, normalization, observed usage/provider latency and
measured replay duration. Missing usage is unknown, not zero cost. Failed-trial
evidence is retained where available. There is no aggregate pass threshold,
automatic winner, prompt promotion or workflow continuation rule. Inspect both
error classes and costs; repeated trials within a family are correlated.
