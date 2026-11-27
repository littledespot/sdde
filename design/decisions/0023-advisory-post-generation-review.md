# ADR 0023: Required source review only; post-generation review removed

- **Status:** Accepted
- **Date:** 2026-10-17
- **Decision authority:** User decisions, 3, 17 and 18 October and 1, 26 and 27 November 2026
- **Amends:** Design §§3.3 (invariants 20 and 22), 9, 12.2, 12.6–12.8, 17.3–17.4, 18.1, 22 and
  24; [ADR 0019](0019-single-request-debugger.md)'s request description
- **Amended by:** [ADR 0046](0046-complete-dispositions-at-admission.md)

## Decision

Spec runs no semantic review after generation. Required source review runs only
before generation: source readiness when the references are not generation-ready (no
retained claim, or a conflict record, which makes the reconciliation `blocked`), and the
optional source-preservation comparison ("Source-preservation review" below).

- **No replacement check.** The judgments a post-generation review would own (business or
  technical placement, scenario-coverage meaning, support of each generated field) rest on
  the human who reviews and edits the published `spec.md`, the source of Plan and Tasks, and
  on [R8](../harness/acceptance.md) adjudication for E2E acceptance. No native check replaces
  them. Publication requires the native checks that already run: generation complete,
  coverage validated and the rendering round trip.
- **Kept paths.** Authorized pre-generation source repair, native generation repair, bounded
  protocol correction and deterministic coverage validation remain.

### Readiness projection by pass

- In a first pass over a reconciliation that holds a conflict record, the source-readiness
  projection holds the conflict records alone, so each conflict has one decision, owned by its
  record's subject and answered by its `select_one` form.
- A dependent pass, the review that validates a pending source repair, and a reconciliation
  without a conflict keep the full projection: a repair is validated by the subjects that cover
  what it touched (§22), and a conflict-only pass omits them.
- A repair that names the claims it decided again, the source-omission conflict-group repair,
  touched only those claims' dispositions and the signals rebuilt over them. Its dependent pass
  (`decided`) projects the conflict records and the signals holding those claims. Every other
  repair, the extraction-owned one included, keeps the full projection.
- The repair's progress check still needs a supported finding over every decided claim, so a
  review that leaves one out reads `recurring`.
- This is a typed rule of Specify's projection, keyed on the conflict records and the pass, and
  no success or continuation rule. `Inputs` carries a typed `Pass` (`first`, `dependent`, or
  `decided` with the decided claims, which the merge records on the reconciliation) that the
  runner's pending repair selects and the gate re-derives with. It is execution-local: ids are
  unchanged and no closed persisted or captured contract changes shape.
- A source-readiness repair's target population is the full projection's seed count whichever
  pass authorizes it first, because the scope freezes its population at first authorization
  ([§22](../contracts/22-repair.md)).

### Findings and policy

Required source review's findings keep their required authority and repair rules. An admitted
semantic finding is a model judgment, not deterministic evidence: a positive finding cannot
discharge a native defect, and a negative finding cannot create or discharge a native authority
gap. A finding may drive automatic content repair only when an independently established defect
at its deterministic owning validator authorizes that repair. Citation existence, matching
subject IDs and model-assisted loss comparisons are not semantic corroboration.

Native requiredness, current authority, provenance, schema/family floors, exact
coverage, citation/selection validity, repair bounds and publication checks remain
mandatory and independent of any semantic verdict.

The closed native review context determines the policy. Source readiness and
pre-generation source preservation have required authority and repair rules; no
other review policy exists. The native projection distinguishes readiness from
generated content; model bytes, workflow names and caller flags cannot select a
policy. (The `owner` parameter of [ADR 0033](0033-generic-repair-operations.md)'s
generic repair operations is checked against the native owner and selects no
policy.) Registered readiness and preservation projection builders must prove the
current pre-generation phase from the native session/content facts. A late
preservation request or an initialized-but-unassembled generation session rejects
before a required semantic review can run. Projection builders and source-repair
operations share phase derivation; a custom graph cannot recreate required review
policy by retiring an earlier projection. Generation initialization also requires
the canonical authority projection, support, ledger, observations, result and gate
to have been retired. It declares and inspects that same native retirement set. A
retained pre-generation review cannot cross the source-consumption transition; the
default workflow already retires it explicitly. This adds no conditional
invalidation or generic dependency-on-absence rule.

### Assignment membership at response admission (18 October 2026)

- **Classification:** for a request whose response must return exactly one item per
  assigned member, that rule is part of the response contract. Missing, repeated and
  foreign members are malformed responses, not finding-evidence defects or native
  authority failures. They are checked at response admission, before any member is
  appended.
- **Mechanism:** the packet binds the member ordinals as an `exact_members`
  integer choice on the result schema, a native-only rule beside the derived provider
  schema. That fixes the item count, narrows each ordinal to an assigned member, and
  rejects a repeated member natively (`duplicate_member`). For preservation comparisons
  the guidance schema states the count. A provider structural projection may keep only
  its own array floor. Uniqueness stays native.
- **Correction:** the existing bounded protocol correction resubmits the complete
  request with the typed diagnostic, under its original allowance. It adds no
  counter, partial merge, insertion or deletion.
- **Scope:** preservation comparisons bind their comparison IDs at response
  admission. [ADR 0046](0046-complete-dispositions-at-admission.md) extends the rule to
  reconciliation dispositions and the source-omission conflict-group repair; there the
  member count is native, the request states no count, and an omitted member is reported
  as `missing_member`. Protocol exhaustion stays terminal.
- **Diagnostics:** request descriptions (ADR 0019) record each applied member set, so
  debugger inspection and replay enforce the same admission as the original request.
- **Unchanged:** native collection still rejects partial, repeated or foreign
  membership atomically, as the authority behind admission; finding-evidence
  defects and repair exhaustion keep their terminal outcomes.

## Source-preservation review

The optional `.sddtoolkit.json` setting `validation.sourcePreservationCheck` is a boolean,
disabled when omitted. When enabled, complete, generation-ready references undergo a focused
semantic review before specification generation. When disabled, the extra review and its
repairs are skipped. Required review of blocked references is unchanged, and this setting
cannot relax publication authority.

- **Obligations.** The original captured corpus supplies one preservation obligation per
  source, including sources with no extracted claims. Review compares original meaning with
  extraction and reconciliation. It does not assess specification fields that do not yet exist
  or resolve uncertainty already present in the source.
- **Findings.** The closed findings are `supported`, `candidate_omission` and `inconclusive`;
  model-assisted review remains candidate evidence, not deterministic proof.
- **Owners.** The immutable configuration service remains the only configuration authority. A
  narrow action returns the configured branch outcome; YAML owns sequencing. Source obligations
  join the existing required-authority ledger, evidence admission and gate.
- **Repair.** Identified loss uses the existing producer localization, revision-bound repair
  authorization, merging, dependent rebuilding and bounded retry path. Source identities
  survive rebuilding and establish whether the repaired obligation was re-reviewed.
  Inconclusive or unlocalized findings cannot invent user decisions, bypass failure or
  authorize an unbounded repair.
- **Model slots.** Every authorized candidate repair in the supplied Spec definition is a
  `request-model` step that names the distinct `models.slots.repair` slot. Generation, review
  and loss localization use `spec_generation`. A protocol retry keeps its original request and
  model binding ([ADR 0012](0012-workflow-owned-model-request.md)). Both slots may select the
  same provider and model or different registered models; each selection must join the
  captured provider catalogue. There is no fallback between slots. Whole-graph binding
  requires both referenced slots even when the optional check is disabled.
- **Workflow-neutral.** The setting and the model-slot name are workflow-neutral. Any validated
  workflow can select the registered policy action and the repair slot in its definition. Each
  workflow supplies its own typed review subjects and repair validators; the engine does not
  infer applicability or provide a default repair path. The supplied Spec definition is the
  initial consumer.

## Pre-generation source repair

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
review settles the native repair obligation.
Generation initialization blocks while any native repair permit is active,
including a child that suspends an unresolved source-repair parent. Retiring a
review projection cannot erase the runner's repair obligation.

### Approved source-only readiness evidence

Before authoring, the native `source_readiness` projection assesses whether
original sources establish an assigned business purpose; which subjects a pass assesses is
[F0100 §3.10](../features/F0100-SpecWorkflow.md)'s. A positive source-purpose
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

The packet, wire decoder, admission and collection validation share this evidence
rule (state persists no review evidence). The model receives no claim-selection or provenance field. Authored values
retain their exact bound provenance; source-preservation and reference-subject
exact claim sets remain unchanged. This amends §12's restriction of source-only
evidence to negative findings for this native pre-generation source-purpose context
only. It does not make semantic review deterministic proof.

## Principles

Spec runs no principle assessment; [ADR 0015](0015-specification-principle-review.md) owns
principle capture and its use.

## Persistence and evidence

Completed and clarification-pending `specification-state` holds no post-generation review,
principle assessment or incomplete-advice evidence, and keeps the captured principle registry
identity as its own `principle_registry` field, which the next run's capture reads as its prior
registry. Earlier contracts reject without migration or a compatibility reader. Stored
validation recomputes native policy, authority currentness, provenance and coverage.
Execution-local receipts and their origins remain separate from persisted workflow authority; a
fresh invocation starts at `start`.
