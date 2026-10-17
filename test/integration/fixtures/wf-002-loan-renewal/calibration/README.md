# Loan renewal rubric calibration

**Status:** Fifteen specimens prepared on 17 October 2026. Human label review and
live judge qualification remain pending.

These assistant-authored supplied specimens exercise the current
[source](../../../../../test/e2e/wf-002-loan-renewal/stories.md),
[evaluation case](../../../../../test/e2e/wf-002-loan-renewal/spec.case.json)
and [rubric](../../../../../test/e2e/wf-002-loan-renewal/rubric.json). They are
evaluation inputs, not generated workflow outputs or golden specifications.

Two faithful specimens vary wording and organization without changing meaning.
The remaining thirteen isolate borrower entitlement, active status, one-renewal
limit, duration, calendar basis, existing-date basis, success/refusal exact text,
displayed new date, refusal behavior, unchanged refused due date, unsupported
conditions, and candidate-embedded grading instructions. Where a duty appears in
both requirements and acceptance conditions, both occurrences change so an
unrelated internal contradiction is not the grader's only clue.

[REVIEW.md](REVIEW.md) lists all fifteen specimens, proposed labels and source-based
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
[evaluator contract](../../../../../design/harness/evaluator.md#run) for the ordinary
`zig build evaluate-spec -- ... --live` command and explicit configuration.
