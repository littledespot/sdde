# Hello World rubric calibration

**Status:** Specimens prepared; human review and live grading pending.

Human review and live grading are excluded from the current implementation task;
these unperformed checks do not block offline evaluator development.

These are assistant-authored, supplied test specimens for
[H-002/H-004/H-006](../../../../../design/harness/01-rubric-evaluator.md), not
generated workflow outputs or golden specifications. The source remains the
unchanged [stories.md](../../reference/stories.md). The existing
[spec.case.json](../spec.case.json) and [rubric](../rubric/spec.json) are reused.

## Review before grading

The following expected findings are **proposed reviewer guidance**, not observed
scores or another runtime rubric. Review them against the source and rubric
before authorizing calibration. No reviewer approval has been recorded.

| Specimen | Intended difference | Expected finding for review |
| --- | --- | --- |
| [faithful-a.md](faithful-a.md) | Concise scenarios and two explicit requirements. | Both source behaviors are covered without technical prescriptions or unsupported scope. |
| [faithful-b.md](faithful-b.md) | Equivalent meaning, different wording/order and combined acceptance criterion. | Comparable coverage, greeting fidelity and grounding to faithful-a; wording alone should not cause a material quality penalty. |
| [missing-startup.md](missing-startup.md) | Greeting remains, but successful startup and the display trigger are absent. | Lower startup coverage; greeting assessment should identify the missing startup relationship. |
| [missing-greeting.md](missing-greeting.md) | Successful startup remains; display behavior is omitted. | Startup coverage is retained; greeting fidelity identifies absence rather than inventing a candidate quotation. |
| [wrong-greeting.md](wrong-greeting.md) | Startup remains, with a consistently altered greeting. | Formatting does not compensate for lost literal fidelity; the source requires `Hello, World!`. |
| [invented-scope.md](invented-scope.md) | Adds account/sign-in requirements. | Grounding and proportionate scope identify unsupported requirements, even though the two original behaviors are mentioned. |
| [embedded-instructions.md](embedded-instructions.md) | Adds grading instructions to the wrong-greeting specimen. | The changed greeting is still found; instructions embedded in the candidate do not determine criteria or scores. |

Use the rubric's existing anchors to assess any score differences. Do not require
identical scores, silently introduce a numerical calibration threshold, or
change anchors just to make these cases pass. Reviewer disagreement and judge
uncertainty remain visible. Omitted optional sections do not require invented
business rules, entities, assumptions or error flows.

These review notes and specimen filenames are not sent to the judge. Each call
receives only the source, chosen specimen content and existing rubric through
the ordinary evaluator packet. No comparison prompt or second judge is added.
This follows the distinction between model scoring and human calibration in
the official [OpenAI evaluation guidance](https://developers.openai.com/api/docs/guides/evaluation-best-practices).

## Live procedure

1. Record the human review of these expectations and the draft rubric. Record
   the exact approved judge configuration, permitted calls/spend and report
   directory. Make `OPENAI_API_KEY` available securely; never commit or paste it.
2. Use the existing command below for each approved specimen, changing only
   `--spec`. An initial pass over this set is seven evaluations, not seven
   retries. Keep the same source, rubric, model and settings for comparability.
3. Inspect each JSON/Markdown report before starting another call. Retain every
   result, including low scores, uncertain judgments and errors. Track aggregate
   reported usage against the approved allowance; stop on unknown usage or an
   exhausted allowance. The existing per-evaluation budget is not a hard billing
   ceiling for this sequence or an in-flight call.
4. Record specimen-to-report paths, returned request/response/model identities,
   usage and reviewer findings. Compare the two faithful specimens and the
   deliberate defects using the table. A completed low-scoring judgment proves
   the evaluation path ran; it is not an API failure.
5. Repeats require an approved count/allowance and are retained alongside the
   initial results, never selected to obtain a preferred score. If a genuine
   rubric defect is found, record an explicit revision and compare all affected
   specimens; do not silently replace the original evidence.

Run from the repository root, with an approved config and existing output folder:

```sh
zig build evaluate-spec -- \
  --case test/evaluation/wf-001-hello-world/node-vitest/spec.case.json \
  --spec test/evaluation/wf-001-hello-world/node-vitest/calibration/faithful-a.md \
  --config evaluation-input/judge.json \
  --output evaluation-output \
  --live
```

`evaluation-input/judge.json` and `evaluation-output` are operator-selected
examples, not new defaults. See the [configuration contract](../../../../../design/harness/evaluator.md#run).
The calibration review belongs beside retained reports, not inside `spec.md` or
the rubric. These reports demonstrate supplied-spec evaluation only.

## Current evidence

- All seven specimens pass the ordinary capture/packet regression.
- `zig build test-rubric-evaluator --summary all`: 29 tests passed.
- `zig build verify --summary all`: 781 tests, lint and native smoke checks passed.
- Human review: pending. Judge model/configuration and paid-run allowance: pending.
- Live reports: none. `OPENAI_API_KEY` was not set in the execution environment
  when this work was attempted on 2026-09-06.
- H-002's remaining semantic comparison and H-004/H-006's live acceptance stay
  open until their actual review/report evidence exists.
