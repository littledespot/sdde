# ADR 0020: Derive exact-reference lineage from one selected claim

- **Status:** Accepted
- **Date:** 2026-09-26
- **Decision authority:** Explicit user approval of Phase 0.2 in [LLM_REWORK](../../fixes/archive/LLM_REWORK.md).
- **27 September 2026 amendment authority:** Explicit user approval of provenance-free, source-bound per-unit assignments in this session.
- **28 September 2026 amendment authority:** Explicit user instruction to clarify generation-role assignment and require nonempty role lists when supplied.
- **9 October 2026 amendment authority:** Explicit user instruction to implement the complete role-decision contract in [FIX01 §9.8](../../fixes/FIX01.md#98-complete-role-decisions-critical-review--9-october-2026), including shared admission, lifecycle and calibration paths.
- **9 October 2026 loss-evidence amendment authority:** Explicit user instruction to implement R7 authoring-input projection and R6 retained producer-loss evidence; no change to exact-reference lineage or retry policy.
- **Amends:** Design §§7.1, 12.2, 16.3, 17.3, 22.4, 23.1 and 24.1. The overall design remains Proposed.

## Boundary and representation

For a registered typed-content operation with one bound, validated reference
ledger, canonical exact segments use `{"kind":"exact_copy","claim_id":N}`.
`N` identifies one eligible preserved-token **occurrence**, not matching bytes.
When several occurrences remain eligible, the model selects one by this handle.
When the bound branch has exactly one eligible occurrence, the model returns
`{"kind":"exact_copy"}` and the engine constructs `N`; an echoed determined
handle rejects. A wholly determined field is constructed without model work.
The existing reference owner resolves the selected or constructed handle to
its token, citation, source scope and exact bytes. The selected schema and
native validator use the same bound eligibility facts. A missing, ambiguous
or stale trusted ledger/binding rejects before it offers choices. A well-shaped
but unavailable model selection is an invalid candidate.

For each attributed field or shared-provenance record, canonical
`provenance.claim_ids` stores only the explicitly selected reference claims `S`,
bound to that unit before its content request. Model responses do not contain
`provenance`. Derive `E` from all exact segments in that unit, then
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

## Provenance-free response amendment (approved 27 September 2026)

The model chooses source meaning during reconciliation; the engine retains the
validated claim group on each reconciliation signal. Reconciliation also records
the semantic generation roles of those groups for feature-level fields. The
complete role-decision amendment below supersedes sparse model role lists.
Canonical signals retain derived positive `generation_roles`; an unselected
context-only signal retains an empty list. The engine validates group membership
and role coverage, then binds each attributed field or record-generation task to
its current source obligation before
dispatch. It resolves that bound group through the existing reference ledger
to construct canonical `S`. A record task is scoped to one group and may
produce several requirements. A group may contain claims from several original
source requirements, and one claim may participate in several groups. This
supports both many-to-many directions without a model `provenance` field or a
second reference authority.
Model-facing generated records contain business content only; canonical
records retain engine-constructed `provenance.claim_ids` for traceability.

Generation, source-review and repair responses reject `provenance` in every
selected schema. The bound unit, current ledger and authorized repair target
supply claim identity; the response supplies business content, a semantic
verdict, and any genuinely selectable source or loss location. Fixed diagnostic
claims are constructed after a selected loss location. Source-only negative
evidence constructs an empty canonical selection where its rule permits it.
No response may add claims to a sibling or turn the eligible catalogue into
support. Missing, stale, ambiguous or out-of-scope binding blocks or returns
to source reconciliation as an engine defect, never as missing user information.
Similar prose, a singleton eligible claim, a document name and shared batch
membership cannot establish a source association.

This amends the earlier equality of model and canonical selection fields,
while preserving `S`, `E`, `L` and their evidence bounds. Semantic grouping and
generated meaning remain model-assisted and independently reviewed. Native
group validation, source-review admission, exact coverage and publication
remain separate gates. Value-only repair retains its original explicit and
effective evidence bounds; changing a bound association requires upstream
rework. Readback validates captured groups and recomputes lineage. The
cutover must update the closed schemas, parser, packet, repair, workflow
progress, reference snapshot, `specification-state/v7`, renderers and tests
together, without a compatibility reader, second provenance store or new retry
system.

The coordinated runtime cutover implements this amendment. Offline schema,
repair, readback and workflow checks establish mechanical conformance; live
semantic quality and reliability require separately approved execution.

## Complete role-decision amendment (approved 9 October 2026)

One initial reconciliation role request assesses every registered `GenerationRole`.
Its closed `role_decisions` map requires one property per role. Each decision is
either `{"kind":"supported","signal_ids":[...]}` with a nonempty unique selection
from the current eligible signal occurrence catalogue, or
`{"kind":"unsupported"}` with no selection. Requiredness is mechanically checked
against the existing role catalogue. Missing, unknown or duplicate role properties,
empty positive selections, duplicate/ineligible IDs and the superseded sparse wire
shape reject; no defaults, legacy reader or inferred selections apply. When no
group is eligible, the selected schema permits only unsupported decisions.

Native role admission shares the retained-claim eligibility owner and derives the
existing positive group-role assignments in offered-group and registered-role
order. It preserves many-to-many support and group boundaries, rejects duplicate
IDs before conversion and validates the derived bindings through the existing
validator. ID membership and complete representation do not prove semantic support.
The reported unsupported verdict remains candidate data: it neither establishes a
missing user fact nor authorizes clarification, `not_applicable`, a default binding
or semantic correction. Mandatory positive coverage still blocks authoring through
the existing shared source-binding gate.

Production, immutable protocol corrections and diagnostic calibration use the same
current contract and admission owner. Existing correction bounds apply only to
protocol rejection; a complete unsupported answer is structurally admissible.
Upstream repair retires the role assessment, producer origin and derived bindings
together before reassessment. Pending phases have no fabricated negative decisions.
Canonical snapshots retain their positive roles; negative verdicts remain in the
actual captured response, not a second persisted source of binding authority. This
wire cutover introduces no new state version, repair target, retry policy or model
slot. Historical captures remain immutable and their response contract must stay
associated with the appropriate diagnostic decoder.

Offline conformance establishes these mechanics. Semantic omissions, explicit false
unsupported verdicts and wrong selections must still be compared against baseline;
complete live publication and rubric assessment establish production quality. This
amendment accepts the contract change, not a demonstrated semantic improvement or
the overall Proposed design.

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

The original exact-reference cutover activated `specification/v2` and
`specification-state/v6`. The provenance-free amendment coordinates the
model/canonical shape, schema projection, native validation, repair,
rendering and `specification-state/v7` readback. Reject earlier versions without
a migration, dual reader or fallback. Completed readback resolves handles from
the captured ledger and rejects inconsistent lineage, coverage or review
projections. Pending state keeps its reference and clarification contract under
the bumped shared state version; it does not fabricate completed attributed
content. Changed reference or contract authority invalidates dependent state
through the existing runner and stage gates. No new retry mechanism, schema
registry, evidence store, provider mode or model prompt for reassembly is
authorized.

The R6 loss-evidence amendment advances the shared state to
`specification-state/v8`. Source-review findings retain the selected source lines
and producer-loss comparison required by §22.1; completed readback validates that
evidence through the same owner as live collection. Earlier state versions reject.
This changes neither `S`, `E`, `L` nor the exact-reference representation.

This decision records the runtime contract, not a claim that live quality
evaluation has passed. The baseline and test checkpoints remain
in [LLM_REWORK](../../fixes/archive/LLM_REWORK.md).
