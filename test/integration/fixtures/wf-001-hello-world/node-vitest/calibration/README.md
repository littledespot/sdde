# Hello World rubric calibration

**Status:** Nine refreshed specimens prepared on 17 October 2026. Human label
review and live judge qualification remain pending.

These assistant-authored supplied specimens exercise the current
[source](../../../../../../test/e2e/wf-001-hello-world/reference/stories.md),
[evaluation case](../../../../../../test/e2e/wf-001-hello-world/node-vitest/spec.case.json)
and [rubric](../../../../../../test/e2e/wf-001-hello-world/node-vitest/rubric/spec.json).
They are evaluation inputs, not generated workflow outputs or golden specifications.

The original seven specimens now include UTC date/time while preserving their
intended differences. `missing-utc.md` isolates the omission that previously
affected every specimen; `wrong-timezone.md` isolates an explicit UTC contradiction.
The two faithful specimens vary wording and order. Other defects cover missing
startup or greeting, changed greeting, invented account/sign-in scope, and
candidate-embedded grading instructions.

[REVIEW.md](REVIEW.md) lists all nine specimens, proposed labels and source-based
rationales. These labels are pending human review, outside judge inputs, and do
not predict numerical scores. The judge receives only source documents, specimen
content and the rubric through the ordinary evaluator. Filenames, label guidance
and human review records must not be added to that packet.

Human approval must bind the exact source, rubric, specimen and label hashes and
identify the reviewer and date. Missing, stale or disputed review remains visible
and cannot qualify a judge. Offline checks prove packet handling, not semantic
accuracy. No human approval or live qualification is recorded for this panel.

Each paid evaluation or repeat requires explicit approval under the repository's
live-test policy. This packet authorizes no calls, model changes or spend. Retain
all approved results, including errors and uncertainty; never select only preferred
scores or revise labels to fit a judge. See the
[evaluator contract](../../../../../../design/harness/evaluator.md#run) for the
ordinary `zig build evaluate-spec -- ... --live` command and explicit configuration.

Historical offline counts for the original seven specimens predate this refresh
and do not establish qualification of the current panel.
