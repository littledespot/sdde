# ADR 0020: Derive exact-reference lineage from one selected claim

- **Status:** Accepted
- **Date:** 2026-09-26
- **Decision authority:** Explicit user approval, with user-approved amendments:
  provenance-free source-bound per-unit assignments (27 September 2026); R6/R7
  loss evidence and authoring-input projection (9 October); authored
  associations, replacing the presentation-role classifier and prebinding gate
  (11 October); shared composition admission, field-specific exact-copy coverage,
  source-aware wire syntax and no exact copies in descriptive fields (16 October);
  native-bound preservation-comparison attribution (FIX01-01 Phase 2) and the shared
  invalid-content diagnosis (14 October); and native exact-value recognition,
  replacing model-authored exact-copy selection (17 October).
- **Amends:** Design §§7.1, 12.2, 16.3, 17.3, 22.4, 23.1 and 24.1.
- **Amended by:** [ADR 0023](0023-advisory-post-generation-review.md)
  (post-generation findings are advice) and
  [ADR 0024](0024-native-exact-token-authority.md) (token-only groups get no
  record task; native exact duties are independent of semantic kind).

## Native exact-value recognition

The model writes required exact values verbatim in ordinary prose. `exact_copy`
is absent from model-response wire contracts, decoding, encoding and schemas; neither an
explicit claim handle nor a singleton insertion object is a response alternative.
Canonical business values retain engine-derived `exact_copy` segments identifying
current preserved-token occurrences. Passive/source reference choices retain
their existing separate contracts. Field prose requirements and prohibited,
incidental and obligation-bearing exact roles remain authoritative.

Native evidence encoding may retain engine-derived identities as read-only input
facts. That explicit encoding purpose grants no response alternative; model-response
decoding always rejects authored derived nodes.

The current native request owns an immutable exact-occurrence scope: the bound
reference snapshot and eligible occurrence IDs with their captured exact bytes.
The shared reference owner derives that scope from current domain eligibility;
fixed repairs retain their authorization's narrower evidence bounds. It is not
an offered-catalogue guess, a same-source association, a model assertion or an
independent source of semantic support. Missing, stale, foreign or inconsistent
scope is an engine rejection. Request composition and protocol correction retain
the same scope; no evidence outside its fixed owning-unit bound, previous request
or retry may widen it.

Recognition compares raw decoded UTF-8 bytes before NFC, case folding, rendering
or escaping. Both outer delimiters must reach an actual field edge or pinned
Unicode whitespace, optionally through directly enclosing balanced quote/group
wrappers and conventional terminal prose punctuation. Punctuation attached to
further text is continuation: a version prefix, path extension and suffixed
identifier use the same lexical rule. A literal run ending beside a passive or
source reference has an opaque reference boundary, not a field edge; it cannot
lend a delimiter. Whitespace within that run can delimit an interior occurrence.
The closed wrapper/terminal tables belong to the shared boundary owner, with no
token-kind, domain, filename or fixture-specific branch.

Every disjoint eligible occurrence retains its byte span and claim identity.
Competing occurrence identities for one span or overlapping eligible spans reject
the entire field; no partial success, longest-match, first-match or catalogue-order
selection is permitted. Native code constructs canonical exact segments only from
unambiguous witnesses. It preserves unmatched prose and existing reference order,
then applies canonical normalization and existing composition validation.
Revalidating normalized prose must retain the same canonical exact-segment
identities and order. If NFC would create a new eligible match from raw
nonmatching spelling, or otherwise change the exact binding, admission fails with
a typed exact-value defect. Normalization cannot grant authority that the raw
response lacked; exact captured source bytes remain exempt from prose NFC.

Selected source support `S` stays unchanged. Recognized eligible occurrences may
add `E` beyond `S`; derive `L = stableUnique(S + E)` and its citation union through
the existing owner. This is exact occurrence lineage, not a new semantic
association or evidence that the text uses a value correctly. Negation, irrelevant
use and terminal-punctuation ambiguity remain semantic concerns. Only validated
obligation-bearing fields contribute mechanical exact coverage; incidental entity
names and prohibited exact roles cannot satisfy it.

One policy governs response admission, generation, protocol correction, authorized
repair, canonical progress comparison, coverage, rendering and stored validation.
Recognition precedes normalization and repair comparison; exact old-value,
revision, dependency, effective-evidence and sibling bounds remain unchanged.
Canonical readback validates occurrence bindings and recomputes lineage; it never
uses request logs, model-wire conversion or a matching display substring to repair
missing stored authority. Earlier state/description contracts reject without a
production compatibility reader.

## Composition and coverage

The accepted [field inventory](../contracts/text-field-composition.md) determines
whether a field requires prose and whether its exact-copy occurrences are
prohibited, incidental or obligation-bearing. All exact occurrences retain the
same handle, lineage, scope and byte-resolution contracts below. Only occurrences
in successfully validated obligation-bearing fields satisfy behavioral exact-copy
coverage. An incidental entity-name occurrence cannot discharge that duty.
Titles and the other descriptive fields in the inventory's second row carry no
exact-copy occurrence at all. The policy is shared across generation, correction,
repair and stored readback; it is not another model role classifier or support
decision. Wire syntax embedded in prose never creates an occurrence and follows
the source-aware protocol rule.

## Boundary and representation

For a registered typed-content operation with one bound, validated reference
ledger, canonical exact segments use `{"kind":"exact_copy","claim_id":N}`.
`N` identifies one eligible preserved-token **occurrence**, not matching bytes.
This is an engine-derived canonical shape, never a model selection. The reference owner resolves each recognized occurrence to its
token, citation, source scope and exact bytes. Missing, ambiguous or stale trusted
ledger/binding rejects; the model cannot repair that authority.

For each attributed field or shared-provenance record, canonical
`provenance.claim_ids` stores the explicitly selected reference claims `S`.
Initial Spec authors select complete accepted source groups together with content;
native code derives `S` from those occurrences. Fixed repairs retain that
association. Model responses do not contain
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

## Provenance-free responses

Reconciliation retains validated semantic groups without presentation-role lists.
Initial attributed Spec values select nonempty unique canonical `signal_ids`
alongside their business content. These handles identify current complete retained
group occurrences; they do not assert that any group semantically supports a field.
Native admission constructs canonical `source_group_ids`, resolves complete members
in catalogue order, deduplicates legitimate overlaps into `S` and then derives
exact lineage and citations. Several groups may jointly support one field and one
group may support several fields. The model supplies no claim list or provenance.

Each record task binds exactly one group containing a non-token member natively
and may return several records
or an empty array. Its response remains content-only; canonical records inherit
that group's complete ordered selection and retain exactly one `source_group_ids`
occurrence. Empty output supplies no positive coverage and cannot bypass aggregate
record families, entity membership, business mapping, exact coverage or review.
All-preserved-token groups receive no record task under ADR 0024; their original
identities and exact obligations remain. Current appearance-based duties and
equal-byte duplicate duties are independent of the representative's semantic kind.

Generation, source-review and repair responses reject `provenance` in every
selected schema. Selected initial groups, the current ledger and authorized repair target
supply claim identity; the response supplies business content, a semantic
verdict, and any genuinely selectable source. Bound preservation assessments
replace model-selected loss locations; diagnostic claims follow native attribution
under §22.1. Source-only negative
evidence constructs an empty canonical selection where its rule permits it.
No response may add claims to a sibling or turn the eligible catalogue into
support. Missing, stale, ambiguous or out-of-scope binding blocks or returns
to source reconciliation as an engine defect, never as missing user information.
Similar prose, a singleton eligible claim, a document name and shared batch
membership cannot establish a source association.

Model and canonical selection fields therefore differ, while `S`, `E`, `L` and
their evidence bounds are preserved. Semantic grouping and generated meaning
remain model-assisted and independently reviewed. Native group validation,
source-review admission, exact coverage and publication remain separate gates.
Value-only repair retains its group association and original explicit and
effective evidence bounds. Changing authored group membership requires separately
authorized authored-unit rebuilding; no such permission exists. Unresolved
association defects block without being rerouted to an upstream producer.
Readback validates captured groups and recomputes lineage. There is no
compatibility reader, second provenance store or new retry system.

## Authored associations

There is no role classifier, independent role request, `generation_roles` field,
role-coverage gate, legacy reader or dual binding registry.

Initial attributed values use `{signal_ids:[...],value:BusinessValue}`. Brief
requires title, description and goal; story requires its selected value; entities
retain disposition and a selected, explained basis. Initial clarification questions
use the same selected-group value with the existing reason and optional record
kind. Their native scope resolves only selected question-eligible groups, never the
whole available catalogue. Missing/duplicate/foreign/inactive group handles reject.
Positive authored associations cannot select groups containing an `open_question`;
question evidence has its distinct native eligibility. Other semantic categories
are not categorically excluded. An empty retained catalogue rejects readiness
before dispatch without fabricating a user gap, unsupported verdict or completion.

Canonical `AttributedValue` and `RecordProposal` embed required `source_group_ids`.
The captured group's occurrence identity is the association authority; claim lists
and citations are checked native projections. General `Selection` and `Provenance`
remain unchanged for source-only diagnostics and other authorized uses. Equal
claim membership or equal displayed bytes cannot substitute for an occurrence.
Readback resolves the current captured groups and rejects inconsistent projections;
it never repairs corrupt stored authority with a fresh union.

Protocol correction retains the selected initial schema, offered catalogue,
ancestry and existing allowance. Value-only repairs return their unchanged compact
content shape and preserve the old group association. Record insertion requires
one explicitly bound accepted occurrence, not claim-list matching. Missing or
ambiguous occurrence authority blocks. This adds no association-membership repair,
user-answer permission, semantic retry, model slot or publication exception.

Upstream change retires affected catalogues, authored associations, reviews and
comparison evidence through existing dependent invalidation. Optional pre-generation
preservation keeps its original-source assignment; it has no fabricated expected
field association before content exists. Authoring, correction, review, repair,
persistence and calibration share these current owners. Native admission proves
occurrence membership and projections, not authored meaning. Separate live
qualification must measure omitted obligations, wrong support, invented behavior,
clarification quality, actual publication and rubric quality.

## Repair and validation

The existing native repair authorization pins the target, exact old value,
revision, dependency generation, explicit `S`, siblings and retry identity.
After an authorized replacement, recompute lineage from the complete owning
unit, validate the affected dependencies, then validate the full candidate.

| Existing candidate | Value-only replacement bound |
| --- | --- |
| Valid old `L` | Keep `S` and the old effective claim **set** and derived citation **set**. Recompute canonical order; a reference addition/removal changing either set requires separately authorized coupled repair. |
| Invalid canonical exact handle or occurrence scope | Reject invalid native authority. The superseded model-authored exact-handle repair case grants no new eligibility or model selection. |
| Invalid `S` or insufficient effective evidence | Use existing evidence-repair authority first where applicable; otherwise block. Recognition cannot supply unauthorized support. |
| Missing, corrupt or stale trusted ledger/binding | Terminal engine rejection, not a model repair or user clarification. |

The exact old value and revision still compare exactly; only effective evidence
uses set equality. A value-only replacement cannot change unrelated siblings or
borrow their reference choices. Retained exact obligations, membership,
omission, semantic/principle review and publication gates still apply. A prose
repair may pass field validation yet fail exact-token coverage; that is not
workflow recovery. Retry bounds and execution-wide token accounting do not
change.

Examples: `S=[1]` with a uniquely recognized eligible exact claim `2` yields
`L=[1,2]`; removing the occurrence in a value-only repair rejects because claim `2` leaves effective
evidence. With `S=[1,2]`, the same removal keeps `L=[1,2]` and may proceed to
full validation. An unknown canonical claim `9`, invalid `S` or a stale bound
ledger rejects; value-only repair cannot turn it into current authority. A new
claim cannot enter on retry, and an unfulfilled exact obligation still blocks.

No misbound token/citation tuple authorization exists, and no tuple trigger can
become blanket coupled add/remove authority. Existing separately authorized membership
repair remains. Positive Spec source
findings compare with derived `L`; negative/loss evidence retains its distinct
rules. The engine derives citations only from explicit selections and exact
handles, never chooses semantic support or adds citations to satisfy a review.

## Persistence and readback

Canonical content is `specification/v3`; completed and clarification-pending
specification state share one version and reject earlier versions without
migration, dual reader or fallback. Canonical reference snapshots persist no
presentation roles. Completed readback resolves handles from the captured ledger,
recomputes lineage and rejects inconsistent lineage, coverage or review
projections. Pending state keeps its reference and clarification contract and
never fabricates completed attributed content. Changed reference or contract
authority invalidates dependent state through the existing runner and stage gates.

Native-bound preservation comparisons derive attribution under §22.1; collection
and readback reconstruct the same bindings, keep finding and comparison origins
distinct and reject mismatched derived locations. Invalid-content evidence keeps
its nullable source authority gap under §12. Fixed repair cannot derive support
from dispatch order or expand an association to remedy an aggregate gap. Native
request diagnostics (`model-request-debug/v6`) retain the immutable
exact-occurrence scope; they are evidence, never readback or continuation
authority. No new retry mechanism, schema registry, evidence store, provider mode
or reassembly prompt is authorized.
