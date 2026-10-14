# FIX01 — Outstanding Spec workflow reliability work

**Critical review:** 11 October 2026, Australia/Melbourne.

**Status:** sole active fix record. §9.20 recommendations 1 and 2 mechanics and R6's
bounded attribution change are implemented. R6's approved live comparison failed
its quality gate; semantic acceptance remains open. The subsequent explicit
source-obligation handoff is implemented and fully verified offline under the
user's separate request. Its approved 48-call Phase 3 comparison completed but
failed the semantic gate (baseline 18/24 correct, candidate 20/24 with
captured-story regression). Semantic acceptance and Phase 4 remain pending.
The separately approved 60-call isolation comparison also completed and failed
the unchanged gates: correct labels improved to 24/24, but native rejection left
correct admitted attribution at 22/24 in both arms. No production split was made.
Other proposed R6 repair-permission extensions remain unimplemented and
unapproved by this handoff change.
The user-approved native-owned assessed-collection amendment is implemented:
loss responses return judgments, source spans and explanations without a member
selection. Complete native assignments remain retained under state v12. Its new
controlled 72-call comparison completed on 11 October and passed the inherited
diagnostic gates: native admission/correct attribution **22/24 → 24/24**, with
correct preservation judgments **24/24 in both arms**. One candidate answer still
omits a required source citation. This qualifies the contract on known isolated
inputs. The subsequent **76-call** citation comparison passed, improving complete
citations **36/38 → 38/38**. The **30-call** actual source-review panel then failed:
only **15/26** faithful omission handoffs, **2/2** supported controls and **0/2**
genuine-gap controls. Source-review fidelity is now a demonstrated blocker;
production batching/isolation and E2E publication remain unqualified.
[Z_FIX01](Z_FIX01.md) now holds completed implementation, executed experiments,
their approvals and supporting historical reviews. Dated open/proposed statements
there are historical; the outstanding scope and priorities below govern tracking.
Accepted design/ADRs remain authority; the overall design remains **Proposed design**.

## 1. Verdict and review limits

The application has stronger native boundaries, clearer model assignments and better
diagnostics, but reliable specification publication across models remains unproved.
Implementation completion, successful experiments and semantic product quality are
different claims. Completed work is not reopened merely because a later live run fails.

The latest inspected [run, 10 October at 14:24:03 AEDT](../zig-out/e2e-spec/2026-10-10T03-24-03Z-2a2774d40362927ff90dc560ad009d3a/report.md)
exposes a recovery failure after authoring: defective description, incorrect upstream
attribution, unnecessary regeneration, repeated defect and invalid localization
evidence. R6 below records the chain and proposed response. This points to the Spec
workflow's semantic and recovery contracts; it does not establish a malfunction in
the generic runner. Stronger structural validation has not established reliable
semantic diagnosis or recovery.

The earlier summary diagnosis and approved implementation scope are retained in
[Z_FIX01 §9.20](Z_FIX01.md#920-completed-summary-recommendations-and-supporting-review--10-october-2026).
Their remaining meaning-preservation and workload acceptance is tracked below.

**Critical qualifications added by this review:**

- Summary admission checks structure, claim membership, content categories and typed
  text; it does not establish semantic support. No per-summary semantic review exists.
  The optional source-preservation review and later specification review assess
  downstream reference/specification records, not every intermediate summary.
- [Loss localization](../src/domain/source_omission.zig#L6) has no summary target.
  Existing review cannot be described as guaranteeing summary-local semantic repair.
  A new such capability would require separate scope and authority.
- Allowing overlap can retain misleading or contradictory paraphrases as context.
  Native coverage must remain distinct from meaning; test downstream contamination
  and false acceptance, not only whether the original failure now proceeds.
- Native duplicate normalization is feasible only with conserved evidence, obligations
  and occurrence identity. Same text from different sources is not sufficient.
- Single-child carry-forward must read the actual current validated history and
  dependencies. One child ID and equal membership alone are not an adequate witness.
- Safe repair with unrelated defects already exists in parts of the shared progress
  machinery. The overly restrictive full-survivor condition concerns the specific
  redundant-projection deletion path; do not replace the general repair owner.

## 2. Implementation history

The [completed-work index and records](Z_FIX01.md#completed-work-index) contain
implemented changes, finished experiments and their verification. A failed
experiment is completed execution, not completed semantic acceptance. Outstanding
work remains below.

## 3. Remaining work and feasibility

Feasibility describes architectural coupling, not an effort estimate or probability
of model success. Distinguish confirmed implementation gaps, empirical acceptance
gaps and proposals that require policy decisions.

### R1 — Group-level provenance precision: decision and measurement

[Record binding](../src/domain/specification_source_binding.zig#L134) assigns a
complete accepted group; [generation parsing](../src/domain/specification_generation.zig#L77)
attaches that group to every returned record. Citations remain exact, but membership
does not mean each record expresses every linked claim. This follows
[ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md); absent
minimal per-record support is not an implementation defect.

First measure whether grouping and source review meet the intended traceability
claim. If record-specific support is required, approve one binding change across
generation, review, repair, omission insertion, readback and rendering. Do not
create a second provenance store or infer support from text matching.
**Feasibility:** existing-link auditing is bounded; narrower semantic associations
require a coordinated contract change and production-path acceptance evidence.

### R2 — Original meaning and answer-supported recovery

Native [coverage](../src/domain/specification_coverage.zig#L44) accounts extracted
claims and exact obligations. It cannot discover facts never extracted or prove
that prose expresses attached claims. Preserve ADR 0021's optional pre-generation
source check and measure original-source omissions separately. Snapshot identities
remain snapshot-local; persistent semantic identity across edits needs an explicit
continuity contract, not line-number-derived IDs.

**Confirmed implementation gap:** fresh clarification answers cannot complete the
registered recovery path. [Refresh](../src/domain/clarification_refresh.zig#L31)
rejects new nonempty submissions with `AuthenticationRequired`;
[provenance](../src/domain/specification_provenance.zig#L84) rejects nonempty
response-ID sets. Workflow preparation validates forms without authenticating and
accepting answers; the resolved-needs action constructs empty needs. Generation
does not consume accepted answers, and
[passive literal origins](../src/domain/passive_literals.zig#L16) are source-only.

Complete the intended [§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
through concrete authentication, response publication, current applicability,
dependent invalidation, response-owned literals, generation, review and readback.
Do not treat a closed form as authenticated or fabricate reference citations.
**Feasibility:** substantial coordinated lifecycle work. Define missing operational
contracts first; this is independent of call 4's no-clarification failure.

### R5 — Complete review workload and resource evidence

[Policy review](../src/domain/principle_assessment.zig#L82) sends the selected
principles and business context for each subject. More fields increase required
calls and repeated context. Historical budget failures demonstrate an unfinished
workload, not the measured cost of a successfully completed specification.

Measure full coverage, generation/review/repair calls, actual tokens, latency and
retained memory. Consider grouping only with evidence that it preserves per-subject
findings, association, correction scope, origins and retry identity. The current
focused-review contract needs an amendment before such grouping. Do not discard
policies by keywords, truncate required evidence, add local token ceilings or claim
that raising the budget fixes reliability.
**Feasibility:** measurement is bounded; workload redesign is conditional on results.
ADR 0011 still governs provider limits and actual execution accounting.

### R6 — Semantic repair attribution and remaining recovery policy

The [completed attribution implementation and executed 16-call comparison](Z_FIX01.md#923-r6-attribution-mechanics-and-executed-comparison--10-october-2026)
are archived. **Semantic acceptance remains open:** both candidate trials still
misattributed the captured description defect to extraction, and both genuine
extraction-loss trials returned `unlocalized`. The comparison failed its quality
gate. Current packet, admission and repair mechanics do not prove semantic survival,
correct attribution or successful recovery.

Measure correct localization, unnecessary upstream rebuilding, candidate-local repair
success and repair-induced harm. Preserve source-only omissions with no extracted
claim. A valid source span or fluent explanation is insufficient evidence of entailment.
Reuse existing candidate-local repairs when their authority is established.

Verdict reassessment remains a separate unapproved decision under
[§22.1](../design/contracts/22-repair.md#221-definition-of-atomic).
Any proposal must specify trigger, current evidence, closed outcomes, one active
finding, stable allowance and disagreement handling. Do not add voting or retry
until positive. §9.20's normalization/repair proposals are distinct from reopening
a semantic verdict.
Candidate-local story repair already exists. Two other recovery limits must remain
explicit: semantic entity-applicability repair is not authorized to change the
entity decision, and exact-reference repair cannot add a previously unselected
claim merely because its displayed text matches. Any required extension needs a
bounded evidence/target contract across generation, coverage, repair and readback.
In this captured failure, the description never selected the exact-token claim.
Correct attribution therefore does not establish authority to introduce that token
during its existing local repair. Keep that separate repair limitation visible
rather than claiming the attribution change guarantees successful publication.
**Feasibility:** targeted comparison and diagnostics are bounded; new reassessment or
coupled repair permissions require explicit contract decisions and negative tests.

#### Latest E2E evidence — 10 October 2026

The [14:24:03 AEDT run](../zig-out/e2e-spec/2026-10-10T03-24-03Z-2a2774d40362927ff90dc560ad009d3a/report.json)
ended `workflow_invalid` after **44 physical calls and 77,818 of 100,000 tokens**.
No specification was published and no rubric evaluation ran. Call numbers below
identify exchanges in this run, not stable workflow stages.

| Exchange | Observed behavior and consequence |
| --- | --- |
| [8: brief](../zig-out/e2e-spec/2026-10-10T03-24-03Z-2a2774d40362927ff90dc560ad009d3a/evidence/generation/call-000008/model_output.txt) | The description contains a quoted `exact_copy` marker instead of the reference object. Structural admission permits the string; it does not express the greeting requirement correctly. |
| [14: loss attribution](../zig-out/e2e-spec/2026-10-10T03-24-03Z-2a2774d40362927ff90dc560ad009d3a/evidence/generation/call-000014/model_output.txt) | Selects extraction although the requirement survived extraction and reconciliation. The explanation restates the obligation without establishing loss in that producer. |
| [29: upstream repair](../zig-out/e2e-spec/2026-10-10T03-24-03Z-2a2774d40362927ff90dc560ad009d3a/evidence/generation/call-000029/model_output.txt), [35: regenerated brief](../zig-out/e2e-spec/2026-10-10T03-24-03Z-2a2774d40362927ff90dc560ad009d3a/evidence/generation/call-000035/model_output.txt) | Inserts already-extracted behavior, invalidates dependent work and recreates the same description defect. |
| [44: loss attribution](../zig-out/e2e-spec/2026-10-10T03-24-03Z-2a2774d40362927ff90dc560ad009d3a/evidence/generation/call-000044/model_output.txt) | Again selects extraction and cites lines 1–8 although the selectable catalogue ends at 7. Native loss admission rejects; `loss-collect` transitions to `end.invalid`. |

The earlier 02:17:38Z run and this run sent byte-identical call 8 provider requests
and received identical brief outputs. The attribution change did not change that
authoring request. Removing one failure mode or adding evidence checks is not proof
that the originating defect or the complete recovery path improved.

#### Proposed recovery follow-up and implementation order

**Status:** item 1's implementation and lifecycle cutover are complete under
[FIX01-01 Phase 2](FIX01-01.md#phase-2--complete-the-lifecycle-and-offline-verification):
395/395 focused tests and 1,454/1,454 full offline tests pass. Semantic comparison
and live recovery/publication remain Phases 3 and 4. The explicit-obligation
follow-up below is subsequently implemented; the remaining repair-permission
recommendations are not implemented. This status does not authorize
new repair permissions, verdict reassessment or live calls.
Reuse the current owners; do not introduce a second recovery framework or hardcode
this source, model, call number or extraction-to-spec sequence in the generic engine.

**Explicit-obligation follow-up — 10 October 2026:** after the context-removal
pilot failed (baseline 1/6 correct, candidate 2/6 with captured-case regression),
the user approved implementing a distinct `missing_obligation` handoff and the
Phase 3 rerun. The existing source reviewer now states the omitted requirement
separately from the diagnostic explanation. Schema admission, review evidence,
loss projection, correction, revision binding, repair consumers and persisted
v11 readback carry that statement unchanged. The loss call assesses complete
collections against it, retaining surrounding evidence as context. No new verdict,
repair permission, semantic retry or reviewer was added.
See [FIX01-02's implementation record](FIX01-02.md#explicit-obligation-follow-up--10-october-2026)
and the [new calibration package](../test/calibration/source-loss-attribution/bound-preservation/obligation/README.md).
`zig build verify --summary all -j2` passed **1,461/1,461 tests and 142/142 steps**.
All approved **48 loss calls** (12 cases × two arms × two repetitions) completed
on 10 October, 09:59:39Z–10:01:15Z. The
[results](../test/calibration/source-loss-attribution/bound-preservation/obligation/results.md)
record baseline **18/24** versus candidate **20/24** correct attribution, native
admission **24/24 versus 23/24**, and adequate evidence **17/24 versus 19/24**.
Both arms score 14/16 on the original eight cases and 13/16 on evidence; the
candidate misses the required improvement, retains two false upstream diagnoses
and scores only 6/8 candidate-loss cases against the 7/8 minimum. The captured
story regresses from 2/2 to 0/2, despite improvement from 2/6 to 6/6 on fresh cases.
The declared semantic gate therefore **failed**. The captured description also
remains incorrect in both arms and repetitions.

Usage was **60,910 input + 12,670 output = 73,580 tokens**. The 48-call allowance
is consumed, separately from the preceding 12-call pilot: 60 diagnostic calls in
this rollout at that panel's close. No additional live calls or Phase 4 E2E had
run at that point; its conditional gate remains unmet. The failed pilot is not promoted, and the explicit-obligation
mechanism is not an accepted semantic fix. Production source-review obligation
fidelity has only offline mechanical coverage; it needs separate live qualification.
Fixed supplied obligations cannot establish the full handoff's semantic quality
or E2E publication acceptance. Review the retained failure before selecting any
further change; no automatic experiment allowance follows.

**Isolation comparison execution — 10 October 2026:** the user subsequently
approved **60 physical calls**, comprising 24 batched baseline and 36 isolated
candidate calls, for the [prepared experiment](../test/calibration/source-loss-attribution/bound-preservation/isolation/README.md).
It reuses all twelve now-known cases and scores 24 complete decisions per arm
against the unchanged gates. The baseline is the current explicit-obligation
packet; the candidate assigns one complete comparison per call with unchanged
guidance, sources, supporting context and settings. All **60/60** calls completed;
the [results](../test/calibration/source-loss-attribution/bound-preservation/isolation/results.md)
and [scorecard](../test/calibration/source-loss-attribution/bound-preservation/isolation/scorecard.json)
retain the failed gate. Correct preservation labels improved **22/24 → 24/24**,
native admission fell **24/24 → 22/24**, correct admitted attribution stayed
**22/24**, and adequate evidence improved **21/24 → 22/24**. False upstream
attributions fell **2 → 0** and the captured story improved **0/2 → 2/2**;
the captured description was correct in both repetitions of both arms.

Candidate extraction repetition 1 and unresolved-producer repetition 2 had
correct loss judgments and source citations but returned `members: []` for
nonempty collections. Both reject with `InvalidPreservationComparison`.
Original-subset admission and correct attribution fell **16/16 → 14/16**,
failing the minimum admission, genuine extraction/unresolved and no-regression
gates. The required two-result improvement is also impossible against that
perfect subset baseline, but the native failures independently prevent passing.
No threshold changed. The captured-story benefit does not prove batching is the
sole cause: the already-single-comparison unresolved control had identical input
but failed once. Candidate cost rose **37,239 → 55,463 tokens (+48.9%)** and
24 → 36 calls; total usage was **92,702 tokens**.

The 60-call allowance is consumed, bringing this rollout to 120 diagnostic calls.
No production split or further live call followed that panel. The user subsequently
approved removing the redundant model-returned member selection across the shared
contract. The typed response, schema, admission, correction, persistence, fixtures
and calibration now agree: comparison IDs bind complete native collections, and
responses supply only judgments, original-source spans and explanations. State v12
rejects earlier snapshots; old responses with `members` reject as unknown fields.
No IDs are supplied to previously rejected answers. Collection freshness,
comparison completeness, source joins and repair permission remain native checks.

The [new native-scope comparison](../test/calibration/source-loss-attribution/bound-preservation/native-scope/README.md)
held isolated inputs and model settings fixed in both arms for **72/72** completed
physical calls. It used the actual frozen prior native owner for baseline admission
and the current owner for candidate admission; neither reads the other's response
contract. Retain historical failures unchanged. Measure judgment accuracy,
explanation adequacy and native admission separately: assigned scope does not prove
the model considered every member, and removing selected IDs removes one observable
cross-check. Its new allowance is consumed. The
[results](../test/calibration/source-loss-attribution/bound-preservation/native-scope/results.md)
show both arms' judgments correct **24/24**, but baseline empty selections caused
two rejections; candidate admission and correct attribution reached **24/24**.
The inherited gates passed, including original-subset attribution **14/16 → 16/16**,
captured-story **2/2** and the six known family regressions **6/6**. This is an
admission improvement, not a gain in judgment accuracy. Candidate unresolved
repetition 2 omits the alarm source citation: explanation/source adequacy fell
**24/24 → 23/24** despite correct safe attribution. The historical no-case-regression
gate measures attribution accuracy, separately from its evidence minimum; no
threshold changed. Do not describe the result as zero semantic regressions.
Production isolation remains conditional; live source-review fidelity, the actual
review-to-loss handoff and Phase 4 publication/rubric acceptance remain unqualified.

**Citation-completeness follow-up — 11 October 2026:** the user requested the
shared evidence clarification and qualification recommendations. The existing
loss prompt and §22 now distinguish citations establishing the entire original
obligation from explanations assessing preservation in the assigned collection.
The schema, native attribution and repair permissions are unchanged. The approved
76-call comparison passed its frozen gates: complete/relevant citations improved
**36/38 → 38/38**, with **38/38** correct verdicts and **26/26** correct admitted
attributions in both arms. Both previously missing alarm citations were complete
in the candidate. This demonstrates improvement on the supplied-obligation panel;
the separately approved actual source-review panel then completed and failed its
frozen gates. Only **15/26** actual omission handoffs were faithful: seven omissions
were missed and four returned an inadequate or wrong target. Both genuine-gap
controls invented source obligations; supported controls passed **2/2**. All thirty
responses passed native mechanical admission, with unchanged actual obligations,
source IDs and replay lineage. That verifies conversion, not semantics. No
downstream loss call, repair or E2E ran. See the
[implementation and qualification record](FIX01-02.md#citation-completeness-and-actual-handoff-follow-up--11-october-2026)
for the offline mechanics, [citation results](../test/calibration/source-loss-attribution/bound-preservation/citation-completeness/results.md)
and [actual source-review failures](../test/calibration/source-loss-attribution/bound-preservation/citation-completeness/handoff-results.md).
The historical native-scope results and acceptance thresholds remain unchanged.

**Next bounded work: review shared source-review direction and semantic coverage.**
The unchanged reviewer sometimes checks only candidate clauses that match sources,
missing assigned absent behavior, and sometimes promotes candidate additions into
original-source requirements. Clarify original-source authority, candidate target
and completeness for the assigned field purpose through the existing shared
purpose/evidence owner. Current claim associations and `eligible_subset` permission
must not silently define original-source coverage. Coverage ownership is plausibly
under-specified, especially for inherited/source-only losses; model-internal cause
is unproven. Startup-trigger loss and invented display/unlock duties are definite
semantic defects independent of that ambiguity.

Do not make every field cover every source, infer relevance in the generic engine,
force modal words/source counts, fill oracle obligations or expand repair authority.
Prepare a controlled actual-review comparison using these failures and unrelated
controls, measuring missed defects, false omissions, conditions/strength and
source-premise faithfulness. Further calls need separate bounded approval. Retain
the qualified loss-citation guidance; its later-stage change was not used by the
unchanged source reviewer and this panel cannot establish reviewer regression.

1. **Replace broad culprit selection with bound preservation comparisons.** R6
   already supplies actual producer outputs. The proposed change is to the task and
   response contract: native code binds the missing obligation to relevant producer
   inputs/outputs and source evidence; the model assesses `preserved`, `lost` or
   `uncertain` with producer-specific evidence. The existing loss owner derives a
   repair candidate from admitted comparisons and actual dependencies, rather than
   accepting an independently selected culprit label. Require complete responses
   for assigned comparisons; missing, contradictory or uncertain evidence must not
   silently authorize upstream rebuilding. Group jointly supporting evidence when
   that is the producer's responsibility; do not require every individual claim or
   signal to express the whole obligation. Retain source-only losses with no extracted
   claim. Domain projections supply dependencies; the generic runner owns no semantic
   inference. Reuse the existing loss call, not an additional judge or a call per
   producer. Associations and routing can be checked natively; preservation remains
   model-assisted and must be tested against the failed R6 baseline.
   **10 October status:** the contract and recovery mechanics are implemented and
   verified offline in [FIX01-01](FIX01-01.md). Its first 32-call comparison failed:
   7/16 candidate responses passed native admission and 2/16 yielded correct
   admitted attribution, with one false upstream attribution. The shared request
   projection follow-up removes competing IDs, source coordinates and assessed-subject
   ambiguity. Its [separately approved 32-call comparison](../test/calibration/source-loss-attribution/bound-preservation/projection/README.md#results--10-october-2026)
   improved admission to 16/16 and correct attribution to 14/16 (baseline 8/16 and
   6/16), but still failed two gates: it falsely diagnosed role loss when a business
   claim expressed the literal without a separate preserved-token member. Separate
   meaning preservation from canonical representation in the next candidate.
   That shared presentation follow-up is now implemented: resolved claim meanings
   omit extraction-category labels, and guidance distinguishes expressed behavior
   from its representation. Its [32-call comparison](../test/calibration/source-loss-attribution/bound-preservation/meaning/README.md)
   executed under fresh approval: both arms admitted 16/16 and correctly attributed
   14/16, repeating the same two false role-loss judgments. Category removal and
   clarified guidance did not improve outcomes. Semantic acceptance and conditional
   production E2E remain open. All three diagnostic
   allowances are consumed. Do not count measured improvement as completion.
2. **Enable the smallest justified repair while retaining unaffected work.** If
   comparison establishes that the obligation survived upstream, use candidate-local
   repair. An established upstream loss uses its existing producer repair and
   dependent invalidation. Do not adopt an unconditional candidate-first or
   upstream-first rule. Close the separate exact-reference permission gap through
   one explicit source-authorized rule: derive eligible repair choices from the
   target's current authorized assignment and omission evidence, not only the
   references the defective value selected. Reconstruct current authority through
   shared owners; do not reuse a consumed assignment or grant its whole catalogue
   indiscriminately. Preserve occurrence identity, exact old value, revision and
   dependencies; ambiguous same-text occurrences cannot grant selection. This needs
   coordinated initial/repair admission, provenance, coverage, merge and readback
   changes under §22 and applicable ADR 0020/0022 amendments. It grants no general
   permission to add claims or change an entity decision.
3. **Correct invalid diagnostic evidence without restarting authoring.** The current
   [support repair owner](../src/domain/specification_support_repair.zig#L94)
   rejects `invalid_loss`, and [loss collection](../design/workflows/spec.workflow.yaml#L716)
   terminates. Propose a narrowly authorized correction of malformed loss evidence,
   preserving the reviewed subject, fixed omission and current comparison scope.
   Use one selectable line catalogue; distinguish those selections from read-only
   provenance coordinates. Reuse atomic authorization, diagnostic identity, progress,
   retry and execution-budget accounting. Revalidate the complete corrected evidence
   before authorizing content repair; exhaustion or unresolved ownership still fails
   explicitly. A corrected span alone cannot establish that the chosen producer lost
   meaning. This is an explicit repair-contract/transition amendment, not permission
   to reopen the verdict or repeatedly regenerate the specification.
4. **Reduce model bookkeeping without prescribing business expression.** Retain
   native IDs, provenance construction, exact duplicate normalization and validated
   content reuse already implemented. Keep authoring focused on its field purposes
   and source-supported meaning; accept legitimate wording and grouping variation.
   Do not reinterpret JSON-looking prose as an intended reference. A simpler shared
   business-value representation is a separate measured candidate only if it preserves
   exact occurrences and permits unambiguous native conversion across generation,
   correction, repair and readback. Keep existing cohesive authoring boundaries;
   neither more prompt instructions nor more calls is an established remedy.
5. **Accept the change on complete recovery and published quality.** First prove
   mechanics at the shared boundaries, then compare semantic attribution and repair
   against frozen baseline requests with unrelated and held-out cases. Use R7 and
   the §5 gates to measure correct ownership, false upstream repairs, missing or
   invented obligations, exact literals, recurrence and total cost. Test candidate
   loss, genuine upstream loss and uncertain ownership separately. Finally execute
   the production recovery path, publication and rubric under fresh bounded approvals.
   Isolated replay, valid JSON, fewer calls or successful citation correction alone
   cannot satisfy this acceptance.

The immediate outcome to prove is: **defective description → established upstream
preservation → authorized description-only repair → impacted and full validation
→ continuation**, with unrelated upstream data unchanged. Genuine upstream losses
must still reach the correct producer. Retention is within the current invocation;
this proposes no checkpoint/resume subsystem or partial publication.

Reuse [source_omission](../src/domain/source_omission.zig),
[comparison projection](../src/domain/source_omission_context.zig),
[support evidence](../src/domain/specification_support_evidence.zig),
[atomic repair](../src/domain/atomic_repair.zig),
[candidate repair](../src/domain/specification_coverage_repair.zig) and
[workflow retry](../src/domain/workflow_retry.zig), with explicit YAML transitions.
Thread any revised contract through production, correction, repair, invalidation,
persisted readback, diagnostic origins and calibration; remove the superseded path
instead of keeping parallel attribution policies. Retain both finding and localization
origins through this lifecycle, addressing R9's missing separate attribution rather
than reporting only the original finding call.

**Feasibility and risk:** the owners exist, but comparison semantics, exact-reference
permission and invalid-evidence repair each need a closed contract and coordinated
tests. More comparison fields can burden weaker models and still yield incorrect
judgments; native consistency is not proof of entailment. Implement and measure
these bounded changes in order so their effects remain attributable. No increased
review count, model-specific fallback or semantic-quality guarantee follows from
this proposal. Amend governing contracts together with an authorized implementation;
this fix record remains a proposal.

### R7 — Semantic reliability across models: acceptance remains open

Completed pilots, role-contract mechanics and input changes are archived. Current
role requests require a complete decision map; missing fields are protocol defects,
while explicit false `unsupported` decisions and wrong eligible selections remain
semantic errors. R10's typed block is complete; automatic role reconsideration
would require a separate trigger, target, invalidation and allowance contract.

The recorded comparisons do not justify claiming general quality improvement or
promoting the composition example. Its production promotion was withheld because
the candidate introduced unsupported output ordering. Do not reopen completed
experiments or spend consumed approvals.

Prepared but unexecuted comparisons recorded in
[§9.12–§9.14](Z_FIX01.md#912-call-12-authoring-projection-and-loss-evidence-follow-up--9-october-2026)
cover record authoring (12 calls), signal grouping (12) and entity applicability (32).
These are historical prepared plans, not fresh execution authorization. Verify
their frozen inputs against the intended production candidate before proposing
any new bounded live run; rebuilding a candidate requires a new comparison record.

Broader evidence must cover initial/correction/repair/rebuild contexts, genuine
post-repair role inputs, unrelated source families, optional and mandatory fields,
supported paraphrases, negation/condition/modality changes and incomplete sources.
Score first-pass and recovered outcomes separately, including unusable responses,
false rejection, unsupported acceptance, wrong basis, omission and harmful repair.
A correct verdict with irrelevant evidence remains a defect.

Use repeated paired trials across declared models and reasoning settings, with
labels outside prompts and distinct development/held-out families. Correlated
subjects are not independent workflow trials. Whole-spec rubric agreement is not
independent ground truth for every intermediate semantic judgment.
**Feasibility:** use the existing diagnostic/calibration harness; empirical success
remains unknown. No new evaluation platform or production dependency is indicated.

### R8 — Development acceptance policy: explicit decision required

Current [E2E command success](../test/harness/e2e/contracts.zig) includes completed
evaluation and awaiting clarification. The rubric supports an aggregate threshold,
not a general critical-error veto; the case has no expected-terminal-outcome field.
A zero exit status therefore does not establish quality acceptance. This is existing
documented behavior, not permission to silently change CLI semantics.

Define expected terminal outcomes, critical failures, aggregate thresholds and
uncertainty before implementing new automated acceptance gates. Keep one development
evaluation policy owner, separate from production workflow authority. The judge sees
references, published specification and rubric; it cannot independently establish
internal repair causality or all selected-principle assessments.
The [whole-spec rubric calibration](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/README.md)
also remains unfinished: its seven specimens, including `faithful-a/b`, omit the
current UTC requirement. Refresh the cases and obtain human-reviewed positive/negative
labels before approved live grading or judge-acceptance claims; the old specimen
names are not ground truth.
**Feasibility:** reporting is bounded; enforceable policy needs closed-contract,
report and test changes. Measure rubric relevance as well as quoted-text presence.

### R9 — Remaining failure evidence and attribution

Keep these specific follow-ups active; the main R9 implementation is archived.

| Confirmed gap | Owning boundary and required change |
| --- | --- |
| Evaluator partial bodies disappear | [Observation](../test/harness/provider.zig#L19) lacks completeness/error-exit evidence. [Bedrock](../test/harness/bedrock.zig#L52) omits the transport's failure-body slot; [OpenAI HTTP](../test/harness/http.zig#L95) loses prefixes on read failure; [trace](../test/harness/evaluation_trace.zig#L23) records only a thrown error. Thread retained bytes/completeness through the shared observation, with redaction and adapter-to-trace fault tests. |
| Simultaneous failures overwrite earlier causes | [Accounting](../src/application/workflow_model_invocation.zig#L24) can supersede an invocation cause; [runner capture](../src/application/workflow_pipeline_runner.zig#L410) can supersede it again. Retain bounded primary/secondary evidence while preserving terminal precedence, ownership and allocation-failure handling. |
| Loss-localization call origin is not retained separately | [collectLoss](../src/domain/specification_support.zig#L240) accepts no origin and retains the original finding origins. Diagnostics can therefore identify the finding call instead of the localization call. Preserve both associations through collection, correction, repair authorization and reporting without inventing a new generation origin. |

Build snapshots capture allowlisted Git-visible bytes; they do not prove that the
compiler consumed exactly that snapshot under concurrent edits. Strengthen this only
if claiming exact executed-source reconstruction. Progress labels also include
routine invalidation/retirement; do not count every such event as a semantic repair.
**Feasibility:** each evidence fix is bounded at its owner but needs sibling-adapter,
error-exit and combined-failure tests. None changes semantic outcomes or continuation.

## 4. Recommended implementation order

1. Prioritize the [R6 recovery follow-up](#proposed-recovery-follow-up-and-implementation-order):
   bound preservation comparisons, source-authorized local repair eligibility and
   narrow correction of invalid loss evidence, in that order. Establish the required
   contract amendments and offline positive/negative evidence before live trials.
2. Use R7's paired comparisons to establish attribution and repair quality, followed
   by separately approved production E2E publication and rubric evaluation. Prove
   the complete local recovery path and genuine upstream-loss cases. Do not add a
   reviewer, group repair or a broader fallback merely because a trial fails.
3. Retain pending summary/carry-forward acceptance as separate work: execute the
   [prepared summary comparison](../test/calibration/summary-coverage/README.md)
   only under fresh approval and assess meaning preservation and downstream results
   from native reuse. Their implemented mechanics are not reopened by the later
   authoring failure, and lower call counts alone do not complete acceptance.
4. Complete relevant R9 attribution/evidence fixes alongside these investigations;
   do not require all observability work before a bounded recovery change.
5. Measure R5's full review/recovery workload. Complete R2 answer recovery as a
   separate required lifecycle feature; it cannot remain omitted from any claim
   of a complete clarification-capable workflow.
6. Decide R1 precision and R8 acceptance policy before promising stronger provenance
   or automated quality guarantees. Retain the wider §8 audit without silently
   expanding the immediate implementation.

This is proposed sequencing, not approval of code changes, policy amendments or
live invocations. The active record owns open work; completed execution history
belongs in Z_FIX01.

## 5. Acceptance and feasibility gates

| Boundary | Required positive evidence | Required negative evidence |
| --- | --- | --- |
| Summary representation | Combined, split and overlapping expressions; complete membership; stable native identities and evidence | Missing/foreign IDs, altered categories, false support, changed exact values and conflicting source interpretations |
| Normalization | Idempotence; complete same-evidence duplicates collapse; raw/provenance retention | Same text from different occurrences, distinct obligations, non-equivalent paraphrases; no destructive truncation |
| Native carry-forward | Empty/non-final/final and one/many-child routing; identical current child/evidence; complete lineage | Stale or forged child content, changed evidence, token duplication, fabricated provider origin or skipped final semantic work |
| Repair | Exact target/dependencies, protected siblings, progress and full final validation | Stale authorization, widened scope, repeat allowance reset, invalid survivor or unsupported verdict change |
| Loss attribution | Bound comparisons locate candidate-only and genuine upstream loss; current dependencies and supporting evidence retained | Missing/duplicate comparison assignments, contradictory outcomes, uncertain or multiple owners treated as certain, source-only omissions lost, false upstream rebuilding |
| Exact-reference repair eligibility | Current target/source authority admits a needed omitted reference; original occurrence identity survives repair and readback | Defective output grants new authority, unrelated claims, stale/consumed assignment, ambiguous same-text occurrences or changed obligations |
| Loss-evidence correction | Narrow correction preserves the subject/finding and current scope; native evidence validation reruns before repair | Nonexistent lines, stale producers, verdict replacement, budget/attempt reset, repeated defect or valid coordinates misrepresented as semantic proof |
| Cross-model behavior | Paired repeated trials and unrelated domains; all declared outcomes and costs | Meaning changed despite valid JSON/IDs; false rejection, unsupported acceptance, inconclusive and unusable results |
| Whole workflow | Real publication, complete required review and separately approved rubric evaluation | Early stop reported honestly; no golden outputs, fabricated E2E success or substitution of offline tests |

Offline tests verify native mechanics and propagation of supplied review outcomes;
live comparisons with reviewed labels assess detection of changed meaning. Semantic
negatives in this table do not require native code to infer intent or add a new judge.

Full repository verification and clean packaging checks apply when their implementation
boundaries change. Offline unit/integration tests remain separate from live E2E.
Live diagnostic comparisons require bounded approval; each E2E invocation requires
its explicit approval. No numerical acceptance thresholds or new judge authority
are established by this review.

## 8. Wider outstanding scope retained

- **Architecture-wide responsibility audit:** cover every registered model boundary
  and initial/correction/repair/rebuild/evaluator path under the
  [earlier mandate](archive/LLM_REWORK.md#152-architecture-wide-responsibility-and-change-matrix).
  Record ownership dispositions for proposed Plan/Tasks/Implement contracts without
  treating that audit as authorization to implement those workflows. The bounded
  model-bookkeeping recommendation in the [R6 follow-up](#proposed-recovery-follow-up-and-implementation-order)
  belongs to this audit; it does not introduce a parallel representation owner.
- **Evaluator responsibility transfer:** native criterion assignment/collection and
  captured quotation-occurrence choices remain proposals.
  [Current judgment](../test/harness/judgment.zig#L14) still accepts criterion IDs
  and quoted strings, then checks coverage and substring presence. Define the
  assignment/occurrence contract first; preserve semantic scoring and relevance.
- **Retained-memory and scale evidence:** measure growing review sets, retained bytes,
  allocations, validation/teardown time, cancellation/OOM and dependent rebuilding.
  Current structure motivates measurement but does not establish a leak or authorize
  dropping dependencies.
- Optional provider, reasoning-setting and principle-passage experiments remain
  historical proposals, not current implementation tasks or unused authorizations.

## 9. Current architectural recommendation

The original §9.20 identifier is retained for incoming design links. Completed
recommendations and dated implementation/review history reside in [Z_FIX01](Z_FIX01.md).


### 9.20 Cross-model response variation and summary recovery — 10 October 2026

**Status: recommendations 1 and 2 mechanics implemented; live acceptance pending.
Recommendations 3–5 remain proposed follow-ups.** The user requires an engine
that accommodates different models and capabilities without prescribing one wording
or grouping. Stable acceptance should depend on source-supported meaning and
authority. Invalid responses must receive predictable classification and bounded
recovery; model completion and semantic correctness cannot be guaranteed.
Different accepted payloads need not render identically; the same normalized input
and accepted payload must still produce byte-stable output.
The user's subsequent implementation instructions authorize recommendations 1 and 2
and their coordinated contract amendments. They grant no new live-call allowance or
approval for recommendations 3–5. This work refines R5/R6/R7 without reopening their completed
bounded items. The critical qualifications in §1 remain applicable.

The [historical diagnosis and approved recommendations 1–2](Z_FIX01.md#920-completed-summary-recommendations-and-supporting-review--10-october-2026)
are archived with their implementation records. Open acceptance must establish
meaning preservation, including adverse summary content with source-preservation
review enabled and disabled, and measure retained statement growth and downstream
cost. Summary admission is not per-summary semantic review; no summary-local loss
repair target is authorized. The full-survivor condition for redundant-projection
deletion remains a separate policy question under recommendation 4.

#### Outstanding recommendations — original numbering retained

3. **Classify meaning defects separately from representation and source gaps.**
   Reuse §12.8.1 and §22.2 rather than adding a new intent judge or retry owner.
   The [R6 recovery follow-up](#proposed-recovery-follow-up-and-implementation-order)
   defines the next proposed attribution and invalid-evidence correction changes.
   Supported variation continues through validation; proven repetition normalizes;
   source-backed candidate defects receive repair only where an accepted contract
   establishes a unique defective producer and minimal safe target. Otherwise they
   remain explicit candidate failures, including unsupported summary-repair targets.
   A genuine unresolved source conflict or missing required decision may clarify.
   Malformed/truncated output uses existing protocol handling; inconclusive
   interpretation remains a candidate/review failure unless an actual user choice
   is established. A grouping error must not become a user question. Good intent
   means preserving supported meaning, not guessing missing facts or accepting
   reasoning in place of a required answer.

4. **Extend repair only for defects that remain genuinely coupled.**
   This remains separate from the R6 candidate-local exact-reference proposal;
   closing that permission gap does not establish a need for cross-record repair.
   If several records must change together, first define typed coupling evidence,
   deterministic membership, maximum authorized scope and rejection of relationships
   crossing that scope. Shared claim IDs alone do not prove inseparability and must
   not expand a repair transitively. Native code then binds the affected group's old
   values, claim coverage, revision and dependencies. Reuse the established lifecycle
   of the existing narrowly authorized false-conflict repair where applicable.
   Preserve unrelated records, stable retry identity and existing accounting;
   rerun impacted and full validation plus applicable semantic review.
   Existing repair-progress handling already permits independently tracked defects.
   The separate proposed amendment concerns only redundant-projection deletion
   requiring the entire survivor collection to pass. Reassess whether that extension
   is still necessary after admitting overlap; do not add a second progress owner.
   Repair permission remains distinct from acceptance of the whole result.
   Neither change permits arbitrary regeneration or retrying until a positive verdict.
   Do not add group repair merely to restore exact-once summary formatting after
   adopting the more flexible coverage contract.

5. **Make cross-model variation part of acceptance evidence.**
   Offline tests must cover aggregate-only, singleton-only, aggregate-plus-detail,
   ordering changes, exact duplicates, distinct same-text source occurrences, token
   preservation, missing/foreign IDs, stale dependencies, independent sibling defects
   and genuine contradictions. Test all summary levels and initial/correction/repair
   paths, including native carry-forward, against unrelated domains. Include changed
   child payloads under unchanged IDs, released parent lifetimes, OOM, stale receipts,
   repair-created duplicates and exhausted allowances. Measure distinct overlapping
   statement growth, memberships, allocations, repeated equivalence checks, history
   validation and downstream request cost across hierarchy levels. Exact deduplication
   does not bound different paraphrases; introduce no arbitrary local byte/token cap.
   Repeated live comparisons across declared models and reasoning settings must measure valid
   meaning rejected, unsupported meaning accepted, recovery success, cost and
   completion separately. Include changed negation, conditions and obligation
   strength as semantic negatives. Assess meaning without golden wording/grouping;
   retain failures and review uncertainty. Use the existing diagnostic harness,
   then separately approved complete E2E publication and rubric evaluation.

#### Feasibility, authority and completion criteria

Existing claim ledgers, typed text checks, equivalence helpers, repair owners and
workflow transitions provide the mechanisms for the remaining proposals.
No new engine registry, provider-specific semantic policy, parallel normalizer or
generic meaning-inference algorithm is justified. Domain components contribute
typed facts; the generic workflow engine remains capability-free, and the runner
retains node invocation and delta validation.

Recommendation 4 is a separate repair-policy decision: current §22 limits cross-record
repair and requires a fully valid survivor for redundant-projection deletion.
The [completed-work archive](Z_FIX01.md#completed-work-index) records enacted
§9.20 recommendations 1–2 and R6 attribution mechanics. This record does not authorize verdict
reassessment or the proposed recovery follow-up. The governing design remains Proposed
with its accepted amendments.

Completion requires coordinated lifecycle implementation, accepted/rejected offline
tests, required repository checks and measured live acceptance under bounded approval.
Compatible variation must cease to cause representation-only blocking without
increasing unsupported acceptance. Reduced call counts, valid JSON or a single
successful run alone do not establish improved specification quality.
