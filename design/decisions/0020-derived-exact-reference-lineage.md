# ADR 0020: Derive exact-reference lineage from one selected claim

- **Status:** Accepted
- **Date:** 2026-09-26
- **Decision authority:** Explicit user approval of Phase 0.2 in [LLM_REWORK](../../fixes/LLM_REWORK.md).
- **Amends:** Design §§7.1, 12.2, 16.3, 17.3, 22.4, 23.1 and 24.1. The overall design remains Proposed.

## Boundary and representation

For a registered typed-content operation with one bound, validated reference
ledger, model and canonical exact segments use
`{"kind":"exact_copy","claim_id":N}`. `N` selects one eligible preserved-token
**occurrence**, not matching bytes. The existing reference owner resolves its
token, citation, source scope and exact bytes. The request projects directly
claim-addressable choices from that owner; its selected schema and native
validator use the same eligibility facts. A missing, ambiguous or stale trusted
ledger/binding rejects before it offers choices. A well-shaped but unavailable
model selection is an invalid candidate.

For each attributed field or shared-provenance record, canonical
`provenance.claim_ids` stores only the explicitly selected reference claims `S`,
as the model field does. Derive `E` from all exact segments in that unit, then
`L = stableUnique(S + E)` and its citation union through the same reference
owner. The union orders explicit selections first, then first exact occurrence
in declared field/segment order. Duplicate explicit selections reject; repeated
exact segments deduplicate dependencies, not text. No independently writable
effective-claim or citation list remains; any materialized citations, review,
coverage or view projection are checked against recomputed lineage, never used
as selection authority.

Each domain supplies eligibility and its other accepted support. Source-backed
Spec content requires nonempty eligible effective reference support and derives
passive choices from `L`; `S=[]` is valid when an eligible exact segment supplies
support. Existing response-backed Spec content keeps its separate answer
authority; this decision does not admit unsupported zero-scope typed text. Other
workflows do not inherit Spec's support, coverage or review policy.
Pre-ledger extraction and reconciliation keep their current token/citation IDs;
operational paths, file IDs, commands, approvals and copy-source IDs remain
separate. Reference lineage establishes no semantic entailment or operational
capability.

## Repair and validation

The existing native repair authorization pins the target, exact old value,
revision, dependency generation, explicit `S`, siblings and retry identity.
After an authorized replacement, recompute lineage from the complete owning
unit, validate the affected dependencies, then validate the full candidate.

| Existing candidate | Value-only replacement bound |
| --- | --- |
| Valid old `L` | Keep `S` and the old effective claim **set** and derived citation **set**. Recompute canonical order; a reference addition/removal changing either set requires separately authorized coupled repair. |
| Invalid exact handle, valid `S` | Bind once to `B = stableUnique(S + independently valid, eligible exact handles already in the original owning unit)`. Invalid handles add nothing. Keep `S`; the replacement's effective claim/citation sets must equal `B` and its citation union. Do not rebuild `B` from later rejected attempts or the entire request catalogue. |
| Invalid `S` or insufficient `B` | Use existing evidence-repair authority first where applicable; otherwise block. An invalid handle cannot supply new authority. |
| Missing, corrupt or stale trusted ledger/binding | Terminal engine rejection, not a model repair or user clarification. |

The exact old value and revision still compare exactly; only effective evidence
uses set equality. A value-only replacement cannot change unrelated siblings or
borrow their reference choices. Retained exact obligations, membership,
omission, semantic/principle review and publication gates still apply. A prose
repair may pass field validation yet fail exact-token coverage; that is not
workflow recovery. Retry bounds and execution-wide token accounting do not
change.

Examples: `S=[1]` with eligible exact claim `2` yields `L=[1,2]`; removing the
segment in a value-only repair rejects because claim `2` leaves effective
evidence. With `S=[1,2]`, the same removal keeps `L=[1,2]` and may proceed to
full validation. With `S=[1]` and unknown exact claim `9`, `B=[1]`: supported
prose can replace the invalid segment, but a new claim `2` cannot enter on retry
and an unfulfilled exact obligation still blocks. Invalid `S` or a stale bound
ledger cannot be turned into a valid selection by value-only repair.

The former FIX_002 §36 authorization for a misbound token/citation tuple is
retired when this format activates; its old tuple trigger cannot become blanket
coupled add/remove authority. Existing separately authorized membership,
reviewed insertion and native exact reconstruction remain. Positive Spec source
findings compare with derived `L`; negative/loss evidence retains its distinct
rules. The engine derives citations only from explicit selections and exact
handles, never chooses semantic support or adds citations to satisfy a review.

## Coordinated cutover and readback

Activate the model/canonical shape, schema projection, native validation,
repair, rendering and persisted readback as one coherent change. Use
`specification/v2` and `specification-state/v6`; reject earlier versions without
a migration, dual reader or fallback. Completed readback resolves handles from
the captured ledger and rejects inconsistent lineage, coverage or review
projections. Pending state keeps its reference and clarification contract under
the bumped shared state version; it does not fabricate completed attributed
content. Changed reference or contract authority invalidates dependent state
through the existing runner and stage gates. No new retry mechanism, schema
registry, evidence store, provider mode or model prompt for reassembly is
authorized.

This decision approves the contract, not a claim that its later runtime cutover
or live quality evaluation has passed. The baseline and test checkpoints remain
in [LLM_REWORK](../../fixes/LLM_REWORK.md).
