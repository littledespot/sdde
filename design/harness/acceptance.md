# Development acceptance (R8)

This policy judges development cases. It grants no workflow, publication, approval,
or semantic-proof authority. Production `needs_user` remains a normal typed
workflow outcome; the selected development case decides whether it was expected.

## Accepted policy

Approved by the user on 17 October 2026: **80% aggregate**, with a minimum of
**3/4 for every behavior, source-grounding, clarity/testability and proportionate
scope criterion**. `organization` contributes to the aggregate without a separate
veto. Any uncertainty remains unresolved. These values are explicit in the two
case rubrics, never native defaults.

Both source-complete cases expect `publication`. A clarification fails their
expected outcome. Future cases may explicitly expect `clarification`; success
then requires native `needs_user`, validated partial publication and actual
registered open clarification handles.

Raw model grades in the harness cannot authoritatively accept or reject a published
specification. The existing cost policy is unchanged; no alternate model,
calibration call or new workflow diagnostic is authorized by this policy.

**Amended 19 October 2026 (user decision):** the advisory grader is removed from
E2E. An E2E run makes no judge call. GPT-OSS-20B grading remains only in the
standalone [supplied-spec evaluator](evaluator.md) and its qualification panels.

**Amended 3 November 2026 (user decision):** the `/evaluate-e2e` Claude Code skill,
outside the harness and its cost policy and triggered only by the user, adjudicates a
published run: it scores the retained report under the case rubric and the user's
rulings in the skill, writes the record below and applies it. Its record is the only
rubric evaluation of a published run.

## Deterministic mechanics

[acceptance.zig](../../test/harness/acceptance.zig) owns rubric acceptance. A score
below any non-null `minimum_acceptable_score` fails regardless of aggregate score.
Critical criteria cannot allow not-applicable. A configured aggregate threshold is
inclusive and uses the unrounded score. A missing threshold, uncertainty or no
applicable criteria cannot pass; known critical/aggregate failures remain visible
alongside unresolved evidence.

For the supplied-spec evaluator,
[acceptance_gate.zig](../../test/harness/acceptance_gate.zig) retains raw model
quality and grader qualification as diagnostic facts. Its decision is always
unresolved: `human_adjudication_required`, `input_changed` or `not_evaluated`.
A supplied specification proves no generator identity, so the evaluator records
no judge independence. Known raw model failures remain visible but are advisory.
No calibration flag upgrades model opinion into acceptance.

The [E2E gate](../../test/harness/e2e/acceptance.zig) additionally requires the
case's expected native outcome, validated artifacts, an intact source/provenance
join and measured zero admission escape. Missing admission evidence is unknown,
not zero. Lifecycle status `generated` alone has no success authority. Finalized
JSON and Markdown carry a separate typed acceptance decision; finalization errors
cannot produce successful commands.

The E2E command returns zero only for accepted cases. A mechanically valid
publication remains `human_adjudication_required` and exits nonzero until separately
adjudicated; failed and unresolved remain distinct in JSON. The supplied-spec
evaluator also retains raw calibration diagnostics and exits 2 for pending human
acceptance. Provider/input failures still exit 1. Model scoring never changes
production state.

## Adjudicate a published run offline

The `/evaluate-e2e` skill writes `spec-adjudication-record/v1`: `reviewer` (the skill
and its SHA-256), `reviewed_at_utc` in UTC ISO 8601, and `proposal:{"results":[...]}`
using the same complete criterion/evidence contract as model judgments. Nothing else
writes or applies one (AGENTS.md). Evidence cites inclusive, 1-based line ranges of the
captured documents (`rubric-judgment/v2`). CR, LF and CRLF each end a line, and a final
terminator starts no extra line ([evaluator](evaluator.md)). An editor may show an
empty last line after a final newline; citing it is out of range. The skill scores the
exact captured sources and published specification.

```sh
zig build adjudicate-spec -- \
  --report zig-out/e2e-spec/<run>/report.json \
  --review evaluations/e2e/<run>/adjudication-record.json \
  --output evaluations/adjudications
```

The output directory must already exist. This command has no provider calls or
credentials. It writes a new exclusive adjudication directory containing the exact
original report, the record and deterministic JSON/Markdown decision. It never
rewrites the original report. Exit 0 means accepted, 1 rejected/error, 2 unresolved. A
rejected record leaves the run unadjudicated; it is reported, not corrected and
re-applied. A run gets one record per `/evaluate-e2e` skill version (the record's
`reviewer` names its SHA-256): the first one counts, and no later record under that
version is written or applied. After the skill changes, the run's new adjudication
supersedes the earlier one (user decision, 3 November 2026).
The proposal is revalidated against the report's captured published inputs;
case outcome, publication, admission audit and rubric policy are reapplied. Neither the
record nor the decision (`spec-adjudication/v3`) carries a hash: `--report` names the run,
and the directory's copies of the report and the record show what was judged (user
decisions, 3 November 2026). Unsupported evidence and substituted identities reject.

The baseline useful-completion calculation reuses rubric acceptance. It retains supplied model assessments as advisory diagnostics requiring human
adjudication, including any calibrated model. Human assessments stay explicit. Historical
frozen experiments, including the v1 semantic-simplicity rubric, are unchanged;
they must be refrozen against current contracts for new acquisition. There are
no old-version compatibility readers.

## Review and qualify the grader

The refreshed panels contain nine Hello World specimens (including UTC omission
and wrong timezone) and fifteen loan-renewal specimens. Each includes two faithful
paraphrases, omissions, contradictions, unsupported scope and embedded instructions.
These are assistant-prepared diagnostic specimens, not golden workflow outputs.

Each evaluation case names a `grading_qualification` panel, human-review record
and qualification record. The panel binds source IDs/bytes, rubric bytes, specimen
bytes and proposed verdicts by SHA-256. Human review must approve that exact panel,
including its labels, with reviewer identity and UTC date. Both real review records
remain `pending`. Assistant or agent review is not human approval.

After exact judge configuration and paid calls are separately approved, run the
ordinary supplied-spec evaluator for every specimen. Expected labels, specimen
paths, review records and generation prompts never enter its judge packet. Retain
all errors and uncertainty. Do not select favorable attempts or adjust labels to
match observed scores.

Qualification requires human adjudication of the actual reports and a declaration
binding the approved panel, human review, complete nonsecret judge configuration,
judge instructions/result schema and every report's exact bytes. A report may
contain transient retries and the one correction of a mechanical judgment defect
([evaluator](evaluator.md#attempts-and-failures)); its final attempt is the grade.
The validator rechecks report identities, accounting, exact captured sources/rubric/specimens,
native judgment arithmetic and pass/fail agreement for every panel member. A panel
must contain at least two positives and one negative. Missing, malformed, changed,
uncertain or disagreeing evidence cannot qualify the grader. Passing this panel
is bounded calibration evidence, not a measured general accuracy rate.

Qualification is diagnostic under the approved human-authority policy. Missing
or pending qualification does not block an approved advisory diagnostic. Evidence
is checked before and after grading; source/settings/proof changes invalidate
the run’s input integrity. Changing a bound input requires renewed review
and qualification. No real grader is currently qualified by these pending records.

## Closed schemas

- `evaluation-case/v2`: required qualification paths for the supplied-spec evaluator.
- `evaluation-rubric/v2`: required nullable critical minima.
- `evaluation-report/v7`: raw assessment, line-locator evidence, per-attempt purpose
  and diagnostic, the `evaluation-config/v2` judge configuration, and explicit
  grader/acceptance evidence with an always-unresolved decision.
- `spec-e2e-case/v3`: required expected outcome; no judge configuration.
- `spec-e2e-report/v14`: the single total token budget and aggregate actual usage,
  each attempt's request purpose and owner, ADR 0041's incomplete-publication marker,
  expected outcome, captured evaluation inputs, replayable admission evidence and
  separate acceptance. It embeds no model evaluation.
- `spec-adjudication-record/v1`, `spec-adjudication/v3`: the `/evaluate-e2e` skill's
  rubric judgment and derived development acceptance.
- `grader-calibration-panel/v1`, `grader-calibration-review/v1`,
  `grader-qualification/v1`: closed evidence records.

The engine design remains Proposed. This development policy does not amend
accepted production workflow contracts.

## Offline verification

Required checks are `zig build test-rubric-evaluator`, `zig build test-integration`,
`zig build test-architecture` and `zig build verify`. The complete verification
includes `smoke-adjudicator`, which runs the copied native adjudicator in an empty
environment, alongside the existing packaged-engine and harness smoke checks.
These prove mechanics and isolation; they do not prove semantic quality or grader
accuracy.
