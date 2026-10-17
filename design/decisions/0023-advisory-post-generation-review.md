# ADR 0023: Retain post-generation semantic review as advice

- **Status:** Accepted amendment; implemented and verified offline; live review benefit unmeasured
- **Date:** 2026-10-17
- **Decision authority:** The user's instruction to implement FIX05 B2 and W1
  together, include W2, and the explicit scope answer: "All post-generation
  semantic reviews", including principle findings. The user separately approved
  source-only positive readiness evidence on 17 October 2026.
- **Amends:** Design §§3.3 (invariants 20 and 22), 12.6–12.8, 17.3–17.4, 18.1, 22,
  24 and their acceptance criteria. Supersedes ADR 0015's promotion of semantic
  principle findings into mandatory Plan obligations and the post-generation
  semantic omission/rebuild paths described under ADR 0020. The overall design
  remains **Proposed design**.

## Decision

An admitted semantic finding is a model judgment, not deterministic evidence of
an authority gap or candidate defect. All post-generation source and principle
findings remain inspectable advice with their original type, detail, evidence,
subject, candidate revision and producing origin. Neither a positive finding nor
a negative finding supplies native proof of semantic support or loss.
Source findings remain inspectable in canonical `review.evidence`/`review.result`
and existing diagnostics. This change adds no source-advice Markdown section.
The existing principle projection labels adverse notes as advisory findings;
it no longer renders them as mandatory Plan obligations.

The shared authority owner distinguishes native authority resolution from native
assessment completion. An explicit `assessment_complete` outcome records that
the complete current assignment has admitted findings. Its `assessment` binding
identifies the candidate/subject revision and current registered applicability fact;
it does not declare the candidate supported. Findings are never rewritten as
positive evidence to obtain continuation. A native not-applicable entity decision
retains that fact even when its semantic assessment is adverse; the fact neither
changes the finding nor certifies its truth. Forged or missing applicability
bindings reject. Missing, duplicate, foreign, malformed
or stale findings cannot complete an assessment.

Native requiredness, current authority, provenance, schema/family floors, exact
coverage, citation/selection validity, repair bounds and publication checks remain
mandatory and independent of the semantic verdict. A positive review cannot
discharge a native defect, and a negative review cannot create or discharge a
native authority gap. A finding may drive automatic content repair only when an
independently established defect at its deterministic owning validator authorizes
that repair. Citation existence, matching subject IDs and model-assisted loss
comparisons are not semantic corroboration. This change adds no semantic
corroborator or model-controlled repair permission.

The closed native review context determines the policy. Source readiness and
pre-generation source preservation retain their required authority and repair
rules. Generated specification source review and principle assessment use the
advisory policy. The native projection distinguishes readiness from generated
content; model bytes, workflow names and caller flags cannot select a policy.
Registered readiness and preservation projection builders must prove the current
pre-generation phase from the native session/content facts. A late preservation
request or an initialized-but-unassembled generation session rejects before a
required semantic review can run. Complete generated content uses the advisory
projection. Projection builders and source-repair operations share phase derivation;
a custom graph cannot recreate required review policy by retiring an earlier projection.
Generation initialization also requires the canonical authority projection,
support, ledger, observations, result and gate to have been retired. It declares
and inspects that same native retirement set. A retained pre-generation review
cannot cross the source-consumption transition; the default workflow already
retires it explicitly. This adds no conditional invalidation or generic
dependency-on-absence rule.

## Whole-unit assignments

Review a complete canonical unit or collection in one assignment, for both source
and principle review. Native ownership groups the brief, story, entity
applicability, every field/member of a record, and each complete assessed
collection or reference subject. A model cannot select a subset or change that
partition. This replaces the acceptance-criterion-only grouping rule.

One assignment retains an exact ordered native member set, full assessment
context, current authorities, request identity and dependency witness. Admit
exactly one finding for every member before appending any finding. Preserve
per-subject evidence and origins; reject partial, duplicate or foreign membership.
Correction still targets one invalid finding with unchanged siblings and bounded
retry ownership. Reuse requires the complete current assignment and dependencies;
it never converts an assessment into semantic proof.

## Post-generation upstream findings and source repair

A finding that blames an earlier producer after generation is retained as a typed
diagnostic with its producer/evidence associations, or enters clarification only
for an independently established unresolved required decision. It never
automatically repairs an upstream stage, invalidates generated content and
regenerates the pipeline. Reviewer uncertainty alone cannot manufacture a user
question. Native upstream gaps still block and retain their earliest owner.

Source-repair authorization, packet construction and merge require a current
native pre-generation phase witness. Runner-owned bindings derive it from the
actual optional generation-session and generated-content facts. Bind it into the
existing authorization/dependency preconditions and recheck it when using a
retained authorization. A custom workflow cannot bypass this rule by routing
directly to an otherwise reusable operation.

An authorized source repair keeps its original required review projection in its
native retry scope, alongside producer, feature and captured reference state.
Becoming generation-ready does not close that dependent validation. The existing
readiness/preservation gates select the matching pending required review even
when the optional preservation scan is disabled. Admission of that required
review settles the native repair obligation; post-generation advice cannot do so.
Generation initialization blocks while any native repair permit is active,
including a child that suspends an unresolved source-repair parent. Retiring a
review projection cannot erase the runner's repair obligation.

### Approved source-only readiness evidence

Before authoring, the native `source_readiness` projection assesses whether
original sources establish an assigned business purpose. A positive source-purpose
finding requires explicitly selected, nonempty current original source IDs.
Its canonical claim, citation and clarification-response selections are empty,
regardless of whether the eligible claim catalogue has zero, one or many members.
Eligibility never becomes positive evidence by reconstruction.

This rule applies only to the validated readiness context before an authored
candidate exists. It retains the model-assisted method and the existing native
authority/applicability rules; it creates neither a supported-candidate resolution
nor authored `S`, `E` or `L`. Source IDs remain model-selected and native code
validates their identity and current captured authority. Empty, duplicate, foreign
or stale selections and forged nonempty canonical claims/citations reject.

The packet, wire decoder, admission and stored validation share this evidence
rule. The model receives no claim-selection or provenance field. Authored values
and all generated-content assessments retain their exact bound provenance;
source-preservation and reference-subject exact claim sets remain unchanged.
This amends §12's restriction of source-only evidence to negative findings for
this native pre-generation source-purpose context only. It does not make semantic
review deterministic proof.

Delete the post-generation upstream-repair subgraph, duplicate upstream merge
operations, their registrations/bindings and unused semantic omission-repair
paths. Keep authorized pre-generation source repair, native generation repair,
bounded protocol correction and deterministic coverage validation.

## Principle handoff

Retain the exact current principle registry, selection, citations and assessment
notes. Model-reported conflict or uncertainty alone no longer creates a mandatory
Plan obligation or a Spec clarification. Plan still validates current project
policy and all native required decisions at its own gate; early advice neither
approves policy nor erases the underlying authority. Missing or invalid principle
capture, selection, citations or assessment membership remains a native failure.

This supersedes the semantic-finding-to-Plan-obligation handoff in ADR 0015 and
§17.3.1, without adding an assessment model, configuration option or principle
loader. Model selection and the live-test cost policy are unchanged.

## Persistence and evidence

Completed and clarification-pending state use `specification-state/v16`; earlier
contracts reject without migration or a compatibility reader. Stored validation
recomputes native policy, authority currentness, complete review membership,
assessment bindings, provenance and coverage. It rejects forged deterministic
method tags, forged advisory bindings, semantic-success outcomes and stale candidates.
Execution-local receipts and their origins remain separate from persisted
workflow authority; a fresh invocation starts at `start`.

The committed B3 baseline admitted prose exact values with zero observed native
admission escapes in both development cases. Hello-world stopped on competing
records; loan-renewal passed generation and spent 76.1% of its tokens in review
before exhausting its budget. Those are baseline observations, not publication or
semantic-quality success. [FIX05](../../fixes/FIX05.md) records commands, retained
evidence, offline checks and the separately approved live comparisons. A later
generation failure remains a baseline result; it does not authorize another
presentation/rewording phase or an automatic rerun.

The separately approved comparisons on clean committed build `b4c7b07` both
stopped before review: hello-world on duplicate/competing records, and loan-renewal
on the provider output limit. Neither published or ran rubric evaluation. Both
reported zero observed admission escapes; hello retained five exact witnesses,
while loan retained none after upstream token classification. These attempts do
not establish review-cost savings, finding-type accuracy, original-source token
preservation or semantic benefit. FIX05 records the retained evidence and scope.
