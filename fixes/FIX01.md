# FIX01 — Outstanding Spec workflow reliability work

**Critical review:** 10 October 2026, Australia/Melbourne.

**Status:** sole active fix record. This review changes documentation only.
[Z_FIX01](Z_FIX01.md) now holds completed implementation, executed experiments,
their approvals and supporting historical reviews. Dated open/proposed statements
there are historical; the outstanding scope and priorities below govern tracking.
Accepted design/ADRs remain authority; the overall design remains **Proposed design**.

## 1. Verdict and review limits

The application has stronger native boundaries, clearer model assignments and better
diagnostics, but reliable specification publication across models remains unproved.
Implementation completion, successful experiments and semantic product quality are
different claims. Completed work is not reopened merely because a later live run fails.

The latest run inspected here is
[10 October, 11:32:22 AEDT](../zig-out/e2e-spec/2026-10-10T00-32-22Z-4b66d7fb9b7b4b4d9bce6f612fe04e41/report.md).
It stopped at the fourth physical call after 87 native duplicate deletions, with
`competing_entries`: the summary contained an overview and individual statements
referencing the same three claims. Its low-reasoning response finished normally.
No specification was published or graded. §9.20 retains the input/output evidence.

**Primary finding:** the summary contract equates complete claim accounting with
disjoint statement membership. That intentional representation rule can reject
compatible expressions without establishing incompatible source meaning.
A coordinated change is feasible; removing one validator or adding more retries
would leave the owning contract inconsistent.

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

These findings refine §9.20 rather than establish a successful production fix.
The review used current code, contracts, tests as source, retained exchanges and
recorded experiments. Historical test totals in Z_FIX01 were not rerun. No new
live model calls, implementation tests or external research were needed for this
repository-level audit.

## 2. Completed work moved out of active tracking

This is an archive index, not an implementation checklist.

| Completed bounded work | Historical record |
| --- | --- |
| R3 resolved policy-review subjects | [R3](Z_FIX01.md#r3--complete-resolve-the-assigned-policy-review-subject) |
| R4 shared family meanings, requiredness and collection projection | [R4](Z_FIX01.md#r4--explicit-shared-record-family-meanings) |
| R4/§8 selected repair-task and completed entity-review projections | [§9.6](Z_FIX01.md#96-r48-projection-follow-up-implementation--9-october-2026) |
| R7 focused/routing calibration and executed comparisons | [R7](Z_FIX01.md#r7--high-focused-role-calibration-complete-broader-calibration-remains-open), [§9.7](Z_FIX01.md#97-r7-routing-calibration-follow-up--9-october-2026) |
| Complete role-decision contract and its executed comparison | [§9.9](Z_FIX01.md#99-complete-role-decision-implementation--9-october-2026) |
| R9 main diagnostics, build capture and evaluator tracing | [R9](Z_FIX01.md#r9--medium-preserve-native-diagnostics-and-reconstruction-evidence) |
| R10 typed role-coverage blocking and attribution | [R10](Z_FIX01.md#r10--high-incomplete-authoring-role-coverage-stops-at-the-generation-handoff) |
| Authoring projection and native determined exact-reference IDs | [§9.11](Z_FIX01.md#911-authoring-input-simplification--9-october-2026) |
| Record projection and source-loss comparison evidence | [§9.12](Z_FIX01.md#912-call-12-authoring-projection-and-loss-evidence-follow-up--9-october-2026) |
| Signal assignment scope and schema projection | [§9.13](Z_FIX01.md#913-call-6-semantic-assignment-scope-and-response-projection--9-october-2026) |
| Entity purpose and purpose-neutral fragment guidance | [§9.14](Z_FIX01.md#914-entity-applicability-and-explanation-guidance--10-october-2026) |
| Story/record guidance and executed 28-call comparison | [§9.15](Z_FIX01.md#915-story-and-record-authoring-guidance--10-october-2026) |
| Executed 16-call composition-example experiment; production promotion withheld | [§9.16](Z_FIX01.md#916-call-10-composition-example-experiment--10-october-2026) |
| Shared summary and extraction guidance | [§9.17](Z_FIX01.md#917-shared-reconciliation-summary-guidance--10-october-2026), [§9.18](Z_FIX01.md#918-extraction-assignment-guidance--10-october-2026) |
| Tagged loss-localization response contract | [§9.19](Z_FIX01.md#919-loss-localization-response-contract--10-october-2026) |

**Stale item removed:** the former §8 listed determined exact-occurrence selectors
as outstanding. [Shared projection](../src/domain/reference_model_input.zig#L201)
already constructs the sole `exact_copy` ID natively; the selected schema and
[codec](../src/domain/model_candidate_json.zig#L14) omit/reconstruct it and reject
an obsolete echoed ID. Initial collection, composition and repair use that owner.
This completes that bounded transfer, not the wider responsibility audit.

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

The tagged localization schema and source/producer comparison evidence are implemented
and archived. They prove permitted shape and evidence association, not whether
meaning was lost at the chosen producer. A correct omission finding can still
cause an incorrect upstream repair when the requirement survived extraction.

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
**Feasibility:** targeted comparison and diagnostics are bounded; new reassessment or
coupled repair permissions require explicit contract decisions and negative tests.

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

1. Approve and implement the coordinated summary coverage/normalization contract in
   §9.20, including the limitations identified by this critical review. Prove its
   mechanical boundaries offline before live comparisons.
2. Implement native single-child carry-forward as a separate bounded change, preserving
   hierarchy and provenance. Compare independently so benefits and regressions remain
   attributable.
3. Complete the relevant R9 attribution/evidence fixes alongside measured investigations;
   do not require all observability work to precede a bounded summary change.
4. Use R7 to establish meaning preservation, false acceptance/rejection and recovery
   across models. Then demonstrate actual E2E publication and rubric quality.
   Do not automatically add group repair or a new reviewer when a trial fails.
5. Address R5 workload and remaining R6 localization defects using observed evidence.
   Complete R2 answer recovery as a separate required lifecycle feature; it cannot
   remain omitted from any claim of a complete clarification-capable workflow.
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
  treating that audit as authorization to implement those workflows.
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

The original §9.20 identifier is retained for links from this review. Earlier dated
§9.1–§9.19 implementation/review history now resides in [Z_FIX01](Z_FIX01.md).


### 9.20 Cross-model response variation and summary recovery — 10 October 2026

**Status: reviewed recommendations; not implemented.** The user requires an engine
that accommodates different models and capabilities without prescribing one wording
or grouping. Stable acceptance should depend on source-supported meaning and
authority. Invalid responses must receive predictable classification and bounded
recovery; model completion and semantic correctness cannot be guaranteed.
Different accepted payloads need not render identically; the same normalized input
and accepted payload must still produce byte-stable output.
This documentation update authorizes no production, accepted-policy or live-test
change. It refines R5/R6/R7 without reopening their completed bounded items. The critical
qualifications in §1 and below narrow the original feasibility claims.

#### Evidence and causal limits

The inspected [run](../zig-out/e2e-spec/2026-10-10T00-32-22Z-4b66d7fb9b7b4b4d9bce6f612fe04e41/report.md)
used `openai.gpt-oss-20b-1:0`, low reasoning, temperature 0 and a requested
16,384-token output allowance. It stopped after four calls and 7,941 accounted
tokens, before authoring, publication or rubric evaluation.

- [Call 3](../zig-out/e2e-spec/2026-10-10T00-32-22Z-4b66d7fb9b7b4b4d9bce6f612fe04e41/evidence/generation/call-000003/model_output.txt)
  produced an admitted within-source summary of startup, greeting and UTC output.
- [Call 4's assignment](../zig-out/e2e-spec/2026-10-10T00-32-22Z-4b66d7fb9b7b4b4d9bce6f612fe04e41/evidence/generation/call-000004/context.json)
  supplied that sole child summary and the original evidence. It explicitly required
  claims 1–3 exactly once. The missing-rule explanation therefore does not apply.
- [Its response](../zig-out/e2e-spec/2026-10-10T00-32-22Z-4b66d7fb9b7b4b4d9bce6f612fe04e41/evidence/generation/call-000004/model_output.txt)
  contained 91 statements: one combined `[1,2,3]` and 30 copies of each singleton.
  The provider finished with `stop`; JSON/schema admission passed. This was not
  output-limit exhaustion or missing final JSON.
- Native repair deleted 87 identical duplicates. The remaining aggregate and three
  singletons still referenced each semantic claim twice; the native token statement
  remained present. Authorization stopped at `competing_entries`, revision 88.
  The four distinct semantic expressions preserve compatible requirements on
  inspection. Their shared IDs establish overlap, not contradictory source meaning.

The trace establishes the rejection mechanism, not why the model repeated itself.
This run cannot isolate prompt, model or provider causation, establish a reliability
rate, or assess §9.19, which it did not reach.

#### Owning architectural gaps

The [feature contract](../design/features/F0100-SpecWorkflow.md#L564) intentionally
requires every summary claim exactly once. Both
[summary admission and history validation](../src/domain/reference_reconciliation_validation.zig#L429)
flatten statement memberships and enforce that partition. Relation analysis marks
overlap as competing; [repair authorization](../src/domain/reference_reconciliation_repair.zig#L185)
blocks it after exact redundancy checks. This is current policy faithfully enforced,
not an accidental missing retry.

That representation constraint is stronger than complete source accounting.
[Downstream input construction](../src/actions/reference/build_reference_reconciliation_input.zig#L9)
retrieves original claims from native partition membership, and shared guidance
treats summaries as supporting context. Multiple expressions of a claim do not
inherently create multiple source authorities. Signals already permit overlapping
evidence under their separately validated contract.

Two other constraints amplify the failure: the
[partitioner](../src/domain/reference_reconciliation_partition.zig#L23) creates a
cross-source summary even for one child, and the
[redundant-projection proof](../src/domain/reference_reconciliation_validation.zig#L356)
requires the whole surviving collection to be valid before that deletion can be
authorized. The latter can prevent a safe local repair when another independent
defect remains; exact-duplicate deletion has a separate existing path.

The selected schema permits `statements.maxItems: 4294967295`; projection bounds
each statement's selected IDs but not the enclosing collection. The Bedrock schema
profile omits `maxItems`. Tightening cardinality alone is not the remedy: a small
collection can still overlap or omit meaning. If overlapping propositions are
admitted, a maximum equal to claim count no longer follows from coverage and must
not become an arbitrary restriction. Preserve ADR 0011's provider-owned limits.

#### Recommended contract changes and order

1. **Separate summary coverage from grouping; normalize proven repetition.**
   Keep nonempty, unique, authorized IDs within each statement. Across statements,
   validate complete coverage using their union rather than disjoint membership.
   Allow combined, split and overlapping source-backed expressions through structural
   admission; downstream review and final validation still apply. There is no current
   per-summary semantic review or loss-repair target: the optional preservation check
   assesses final references, and specification review assesses generated subjects.
   Neither IDs nor downstream review certify every summary proposition. Compare
   adverse summary content with preservation enabled and disabled; do not add a
   summary reviewer implicitly or describe relaxed admission as semantic approval.
   Preserve category, citation, exact-token and lineage checks. Native normalization
   may collapse identical validated content
   only with equivalent evidence and obligations, reusing the existing equivalence
   owner and retaining the raw response and provenance. Different source occurrences
   or paraphrases cannot be discarded merely because their text looks similar.
   Apply normalization through the existing typed-content/equivalence owner before
   canonical summary identities. Define deterministic survivor order and a mapping
   from original to retained occurrences: repair occurrence IDs and field origins
   already exist before canonical IDs. Preserve raw evidence, old-value/revision
   bindings, active receipts and retry identity; invalid entries cannot disappear
   merely because a valid-looking duplicate exists. Prove idempotence and repair
   behavior after index shifts rather than adding a parallel normalization policy.
   Update admission, history, selection eligibility, guidance, normalization/repair
   facts, fixtures and tests together. Do not weaken `sameSet` globally: disposition
   completeness, identities and required-authority cardinality remain exact.

2. **Carry forward a validated child when no semantic transformation is needed.**
   For a non-final summary partition with one validated child, identical claim
   membership, unchanged source evidence and no additional semantic responsibility,
   construct the parent natively from that content. Preserve hierarchy, citations,
   lineage and native identity assignment. Construct from exact current history and
   source/policy/text dependencies, not a
   supplied child payload with a matching ID. Revalidate content, token ownership,
   allocation lifetime and candidate retirement; retain a genuine native origin.
   Use registered operations and explicit workflow transitions, not a call-number,
   model or fixture branch.
   Final disposition/signal/role/conflict work remains separate. Empty, multi-child
   and changed-membership cases must retain their appropriate existing paths.

3. **Classify meaning defects separately from representation and source gaps.**
   Reuse §12.8.1 and §22.2 rather than adding a new intent judge or retry owner.
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

The first bounded implementation is recommendation 1 at the shared summary owner;
recommendation 2 follows independently. Existing claim ledgers, typed text checks,
equivalence helpers, repair owners and workflow transitions provide the mechanisms.
No new engine registry, provider-specific semantic policy, parallel normalizer or
generic meaning-inference algorithm is justified. Domain components contribute
typed facts; the generic workflow engine remains capability-free, and the runner
retains node invocation and delta validation.

The proposed representation and normalization changes require coordinated amendments
to [§16.4](../design/contracts/16-reference-ingestion.md#164-semantic-extraction-flow),
[F0100](../design/features/F0100-SpecWorkflow.md),
[ADR 0022](../design/decisions/0022-native-reference-phase-handoffs.md) and applicable
[§22](../design/contracts/22-repair.md) language before or alongside implementation.
Native carry-forward must preserve the declared hierarchy and lineage contract.
Recommendation 4 is a separate repair-policy decision: current §22 limits cross-record
repair and requires a fully valid survivor for redundant-projection deletion.
This record proposes those changes; it does not enact them or authorize verdict
reassessment. The governing design remains Proposed with its accepted amendments.

Completion requires coordinated lifecycle implementation, accepted/rejected offline
tests, required repository checks and measured live acceptance under bounded approval.
Compatible variation must cease to cause representation-only blocking without
increasing unsupported acceptance. Reduced call counts, valid JSON or a single
successful run alone do not establish improved specification quality.

**Review verification:** current producers, consumers, validators, history, repair,
review and harness contracts were inspected with independent read-only audits.
Completed records moved to Z_FIX01; the active review, archive indexes and affected
documentation links were updated. No production code, contract semantics, tests or
live executions changed. `git diff --check`, all 59 active local links and all 26
incoming FIX01/Z_FIX01 anchors passed. Archived §§9.6–9.19 retain their original
text. The archive retains 21 pre-existing unavailable file/anchor references and
introduces none; those references are not fresh validation evidence.
