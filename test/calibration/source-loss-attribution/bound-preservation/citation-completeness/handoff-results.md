# Actual source-review handoff qualification — 11 October 2026

**The frozen semantic handoff gate failed.** All 30 explicitly approved source-review
calls completed, but only **15/26** omission trials produced a faithful
`missing_obligation`. Both supported controls passed; both genuine-information-gap
controls failed. The separate [76-call citation comparison](results.md) passed.
Its supplied obligations did not establish that the source reviewer can generate
those obligations faithfully.

The [frozen plan](handoff.preparation.json) has SHA256
`f76bb58647d17a193650f34c675d1c10f07a9828326c9731cddb6edf4c4fd197`.
[Execution journal](../../../../../zig-out/source-loss-actual-review-comparison/run/results/execution.json),
[scorecard](handoff-scorecard.json) and two independent assessments
([A](../../../../../zig-out/source-loss-actual-review-comparison/assessment-agent-a.json),
[B](../../../../../zig-out/source-loss-actual-review-comparison/assessment-agent-b.json))
retain actual outputs, receipt/native hashes, origins, costs and judgments. Frozen
criteria and historical comparisons are unchanged. The allowance is consumed.
**No downstream loss call, repair or E2E run was dispatched.**

## Execution and separate measurements

Fifteen actual reviewer assignments ran twice: thirteen genuine omission cases,
one supported control and one genuine-information-gap control. Requests supplied
original sources and the current bound subject/purpose, with no oracle obligation.
AWS Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning, temperature 0,
native schema and 16,384 output allowance were unchanged. There were no retries,
corrections, repairs, additional model judges or whole-workflow E2E runs.

| Measurement | Observed | Frozen requirement |
| --- | ---: | ---: |
| Dispatched / received | 30 / 30 | 30 / 30 |
| JSON/schema valid after existing prefix normalization | 30/30 | Measured separately |
| Native mechanical admission | 30/30 | Measured separately |
| Correct finding kind | 21/30 | Does not establish faithful meaning |
| Omission kind on genuine omission cases | 19/26 | Does not establish faithful meaning |
| Faithful missing-obligation handoffs | **15/26** | **26/26** |
| Correct supported controls | 2/2 | 2/2 |
| Correct genuine-gap controls | **0/2** | **2/2** |
| False omission findings on controls | **2** | **0** |
| Changed admitted obligation or source IDs | 0 | 0 |
| Loss assignments from actual non-omission findings | 0/9 | 0 |
| Downstream loss calls / repairs / E2E runs | 0 / 0 / 0 | Not authorized by this panel |

All responses used the existing `removed_leading_brace_quote` normalization.
Protocol success describes admitted JSON after that normalization, not raw
unframed JSON. Raw provider bodies and model text are retained separately; no
semantically defective response was repaired for this assessment.

Native admission constructed **21 untrusted omission assignments** from actual
admitted values. Two came from the false gap-control findings. The other nine
responses were `supported` and constructed no assignment. The mechanically correct
conversion of a false finding is not semantic permission to rebuild upstream.
Derived loss requests remain unsent diagnostic exports.

The diagnostic receipt binds exact input, case/repetition, parent and authentic
replay identity. Its `response_sha256` binds raw `validation.model_text`; the HTTP
provider-body hash is independently retained. Reports explicitly disclose
`native_origin_available: false`; an accepted production ledger origin is not
fabricated. Offline production tests separately verify native-origin propagation.
Every admitted `missing_obligation` and selected source ID is retained unchanged.

## Per-case assessment

The table scores faithful omission targets, rather than requiring exact oracle
wording or every source ID. One genuine missing duty may be identified without
enumerating every defect. Equivalent wording and legitimate narrowing pass.

| Case | Repetition 1 | Repetition 2 | Assessment |
| --- | --- | --- | --- |
| Captured description | Pass | Pass | Correct exact greeting and startup trigger. |
| Loan candidate | Fail | Pass | First response accepts renewal without eligibility/no-reservation conditions; second retains them. |
| Extraction inherited | Fail | Fail | Checks recording only; misses original pump shutdown/until-recovery duty. |
| Fan direct signal | Pass | Pass | Preserves door closure and operator-readiness restriction on restart. |
| Joint two sources | Pass | Pass | Requires identity verification and payment confirmation. |
| Wrong role assignment | Fail | Fail | Targets already-described opening hours instead of cancellation-triggered patient notification. |
| Unresolved multiple producers | Fail | Fail | Checks display/recording only; misses cooling during power loss and backup-failure alarm. |
| Parking candidate | Pass | Pass | Retains settled-payment prerequisite and failed-payment active-session rule. |
| Captured story | Pass | Fail | Second obligation drops the startup condition. |
| Sterile door | Pass | Pass | Equivalent no-unlocking/stay-locked wording preserves pressure condition and strength. |
| Voucher release | Pass | Pass | Faithfully identifies missing manager approval; payment already survives, so source 2 need not be selected. |
| Dual Ready | Fail | Fail | Matching payer display misses inspection-triggered display to inspector. |
| Smoke/exit compound | Pass | Fail | Second response invents a must-display duty instead of missing alarm and exit duties. |
| Supported control | Pass | Pass | Correct support, no omission assignment. |
| Genuine-gap control | Fail | Fail | Converts unselected release policy and candidate unlock behavior into source must-unlock duties. |

Seven genuine omission trials were falsely `supported`. Four more returned
`candidate_omission` with a wrong or inadequate obligation: both wrong-role trials,
captured-story repetition 2 and smoke/exit repetition 2. Both gap trials returned
false omissions. Raw examples:

- [Loan repetition 1](../../../../../zig-out/source-loss-actual-review-comparison/run/results/loan-candidate-review-1.call.json)
  declares a condition-free renewal description supported while repeating the
  original eligibility and reservation conditions in its explanation. Mentioning
  conditions in the review does not restore them to the candidate.
- [Wrong-role repetition 1](../../../../../zig-out/source-loss-actual-review-comparison/run/results/wrong-role-assignment-review-1.call.json)
  returns `The service must display the clinic opening hours.` This is source-grounded
  text, but does not identify the absent patient-notification behavior. The panel
  accepts an indicative recording description elsewhere while rejecting an indicative
  hours description for lacking `must`; no distinct normative purpose explains that
  inconsistency. It does not justify a native must-word rule.
- [Captured-story repetition 2](../../../../../zig-out/source-loss-actual-review-comparison/run/results/captured-story-review-2.call.json)
  returns `The application must display Hello, World! and output current UTC date and
  time.` The source's startup condition is absent. Its additional UTC omission
  allegation is inadequately explained: the subject mentions UTC but uses `should`.
  The failure score rests on definite trigger loss, not exact wording or dismissal
  of every possible obligation-strength concern.
- [Smoke/exit repetition 2](../../../../../zig-out/source-loss-actual-review-comparison/run/results/smoke-exit-compound-review-2.call.json)
  returns `The controller must display the smoke reading.` Neither source requires
  that display; it is supplied by the defective candidate. This reverses the
  source-to-candidate omission direction. Adding the unrelated logging source does
  not establish support.
- [Gap repetition 1](../../../../../zig-out/source-loss-actual-review-comparison/run/results/handoff-source-gap-review-1.call.json)
  returns `After maintenance, the access controller must automatically unlock the
  door.` The source explicitly says the release policy has not been selected.
  Candidate behavior cannot supply the missing source decision.

## Cause, uncertainty and next bounded work

The observed blocker is **source-review obligation detection and faithful
formulation**, before the loss-assessment call. The citation-purpose change is
applied to the later loss call; these actual-review requests use unchanged shared
source-review guidance. This panel is not a before/after reviewer comparison and
does not show that citation guidance caused reviewer regression.

The reviewer sometimes grounds only behavior already represented by the subject,
instead of finding missing assigned meaning. It also sometimes treats candidate
additions as original obligations. These are measured outputs, not a claim about
the model's internal cause.

A plausible shared-input weakness is under-specified coverage ownership. The
description purpose says `A description of intended user-visible behavior.`
Current claim associations and `positive_claims: eligible_subset` govern evidence
permission; they do not explicitly declare all original obligations this field
must preserve. This is especially relevant to inherited extraction losses and
wrong-role cases, and potentially unresolved/dual-Ready cases. It warrants review
of the existing shared purpose and evidence presentation. It does not excuse the
definite dropped trigger or invented obligations, or permit post-hoc gate changes.

Next, review that shared source-review contract to distinguish:

1. Original-source obligations from generated candidate assertions.
2. Grounding of represented behavior from completeness for the assigned field's
   purpose; current associations must not silently exclude original-source loss.
3. A real omitted duty from a necessary source decision that has not been made.

Keep semantic relevance with model-assisted review and the existing shared
role/field-purpose owner. Do not make every field cover every source, infer
business ownership in the generic engine, require fixed modal words or source
counts, fill oracle obligations, or widen repair authority. A separately frozen
review comparison should measure missed defects, false omissions, faithful
conditions/strength and source support using these failures and unrelated
controls. Further calls require their own bounded approval. Only a passing actual
handoff can advance to separately authorized downstream attribution and E2E.

## Cost and verification

Actual usage was **41,072 input + 5,080 output = 46,152 tokens**, below the
200,000-token experiment stop. Summed replay round trips were **26,898 ms**;
provider inference latency was unavailable. There was no transport uncertainty,
unknown usage, request drift, automatic resend or uncounted dispatch.

The native target passed **294/294 tests** after retaining these actual receipts.
The preceding full `zig build verify --summary all -j2` passed **1,465/1,465 tests**,
**142/142 steps**, including integration and clean packaging checks. Structural
checks validate mechanics; root and two independent Codex subagents performed
unblinded semantic assessment of all 30 outputs. No extra live judge ran. This
qualification is limited to one model/settings pair and two repetitions, largely
on known regressions; it is neither deterministic semantic proof nor E2E evidence.
