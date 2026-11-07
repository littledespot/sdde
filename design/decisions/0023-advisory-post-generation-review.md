# ADR 0023: Required source review only; post-generation review removed

- **Status:** Accepted amendment
- **Date:** 2026-10-17
- **Decision authority:** The user's instruction to implement FIX05 B2 and W1
  together, include W2 (`fixes/Z_FIX05.md`, git `194e29a`), and the explicit scope
  answer: "All post-generation semantic reviews", including principle findings. The
  user separately approved source-only positive readiness evidence on 17 October 2026.
- **Amends:** Design §§3.3 (invariants 20 and 22), 12.6–12.8, 17.3–17.4, 18.1, 22,
  24 and their acceptance criteria. Supersedes ADR 0015's promotion of semantic
  principle findings into mandatory Plan obligations and the post-generation
  semantic omission/rebuild paths described under ADR 0020. The overall design
  remains **Proposed design**.
- **Membership amendment:** 2026-10-18, by the user's instruction to "apply best
  recommendation" after the loan-renewal run blocked on an assignment response that
  omitted one member, with the follow-up option that opts preservation comparisons
  into the same admission rule. It amends §12.2 (a native-only `exact_members` rule
  beside the derived provider schema), §12.7, §17.3, §22.1, §22.4 and §22.6, and
  ADR 0019's request description. See
  "Assignment membership at response admission".
- **Amended by:** [ADR 0046](0046-complete-dispositions-at-admission.md) (31 October
  2026): the membership rule's scope extends to reconciliation dispositions and the
  source-omission conflict-group repair, with the member count native (the request
  states no count) and an omitted member reported as `missing_member`.
- **Removal amendment (FIX06 D13.1, 1 November 2026):** by the user's decision to
  remove both post-generation reviews (source and principle) in one change, which also
  reverted the 31 October advisory verdict-set amendment (record: `fixes/Z_FIX06.md` at
  git `388438e`) in full, and the
  user's approval of the policy edits. The earlier rule that post-generation source
  and principle findings remain advice, its budget and incomplete-advice contract,
  whole-unit assignments, record families, unresolvable-verdict withholding, the
  advisory verdict set and the post-generation upstream-finding rule are withdrawn,
  with the advisory request protocol that only they used (ADR 0030's advisory variant).
  ADRs 0040 and 0042, which governed only that review, were deleted as moot (last at
  git `8aa7fb5`). Spec runs no
  principle assessment ([ADR 0015](0015-specification-principle-review.md)). Judgments
  post-generation review was described as owning (business/technical placement,
  scenario-coverage meaning, support of each generated field) rest on the human who
  reviews and edits the published `spec.md`, the source of Plan and Tasks, and on H1
  adjudication for E2E acceptance; no native check replaces them. Publication
  requires the native checks that already run (generation complete, coverage
  validated, rendering round trip). `specification-state` advances to v21.

## Decision

Spec runs no semantic review after generation. Required source review runs only
before generation: source readiness when no claim is generation-ready, and the
optional source-preservation comparison (ADR 0021). Its findings keep their required
authority and repair rules. An admitted semantic finding is a model judgment, not
deterministic evidence: a positive finding cannot discharge a native defect, and a
negative finding cannot create or discharge a native authority gap. A finding may
drive automatic content repair only when an independently established defect at its
deterministic owning validator authorizes that repair. Citation existence, matching
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
  integer choice on the result schema. That fixes the item count, narrows each
  ordinal to an assigned member, and rejects a repeated member natively
  (`duplicate_member`). The guidance schema states the count, and a provider
  structural projection may keep only its own array floor. Uniqueness stays native.
- **Correction:** the existing bounded protocol correction resubmits the complete
  request with the typed diagnostic, under its original allowance. It adds no
  counter, partial merge, insertion or deletion.
- **Scope:** preservation comparisons bind their comparison IDs at response
  admission; ADR 0046 extends the rule to reconciliation dispositions and the
  source-omission conflict-group repair. Protocol exhaustion stays terminal.
- **Diagnostics:** request descriptions (ADR 0019) record each applied member set, so
  debugger inspection and replay enforce the same admission as the original request.
- **Unchanged:** native collection still rejects partial, repeated or foreign
  membership atomically, as the authority behind admission; finding-evidence
  defects and repair exhaustion keep their terminal outcomes.

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

The packet, wire decoder, admission and collection validation share this evidence
rule (state persists no review evidence). The model receives no claim-selection or provenance field. Authored values
retain their exact bound provenance; source-preservation and reference-subject
exact claim sets remain unchanged. This amends §12's restriction of source-only
evidence to negative findings for this native pre-generation source-purpose context
only. It does not make semantic review deterministic proof.

Delete the post-generation upstream-repair subgraph, duplicate upstream merge
operations, their registrations/bindings and unused semantic omission-repair
paths. Keep authorized pre-generation source repair, native generation repair,
bounded protocol correction and deterministic coverage validation.

## Principles

Spec captures the exact current principle registry and runs no principle assessment
([ADR 0015](0015-specification-principle-review.md)). No model-reported conflict or
uncertainty creates a Plan obligation or a Spec clarification. Plan validates current
project policy and all native required decisions at its own gate. Missing or invalid
principle capture remains a native failure.

This supersedes the semantic-finding-to-Plan-obligation handoff in ADR 0015,
without adding an assessment model, configuration option or principle loader.

## Persistence and evidence

Completed and clarification-pending state use `specification-state/v22` (v21 until
the principle category policy was removed, [ADR 0015](0015-specification-principle-review.md)): it holds
no post-generation review, principle assessment or incomplete-advice evidence, and
keeps the captured principle registry identity as its own `principle_registry`
field, which the next run's capture reads as its prior registry. Earlier contracts
reject without migration or a compatibility reader. Stored validation recomputes
native policy, authority currentness, provenance and coverage. Execution-local
receipts and their origins remain separate from persisted workflow authority; a
fresh invocation starts at `start`.
