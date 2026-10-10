# ADR 0022: Native reference phase handoffs

- **Status:** Accepted
- **Date:** 2026-10-06
- **Authority:** User approval of all changes in FIX_003.
- **9 October 2026 amendment authority:** Explicit user instruction to implement complete role decisions under [Z_FIX01 §9.8](../../fixes/Z_FIX01.md#98-complete-role-decisions-critical-review--9-october-2026).
- **10 October 2026 amendment authority:** Explicit user instruction to implement
  summary union coverage and proven duplicate normalization, followed by validated
  single-child carry-forward, under
  [FIX01 §9.20 recommendations 1–2](../../fixes/FIX01.md#920-cross-model-response-variation-and-summary-recovery--10-october-2026).
- **10 October 2026 iteration correction authority:** Explicit user instruction
  to replace the summary-reuse retry limit with iteration bounded by validated
  partitions and required forward progress; amends pipeline contracts §§6.2–6.3.
- **Amends:** Reference ingestion §16.4, model boundary §12.9, repair §22,
  ADRs 0016 and 0020 for extraction/reconciliation handoffs.

Semantic decisions remain model candidates. YAML explicitly requests, collects,
validates and repairs each reconciliation phase before requesting its descendants.
Native typed phase facts, rather than schema-admitted JSON prerequisites, supply
accepted dispositions and signal selections. Pending phases cannot be accounted
as complete. Checked phase facts retire resolved repair receipts in the same
runner-applied delta; receipts owned by a later validator remain pending.
The generic JSON composer remains structural; it receives no domain
validation policy or hidden scheduler. Named definitions in one response schema
own the phase shapes. Summary composition continues using that schema.

Signal selections reuse the existing execution-local repair occurrence IDs. They
are distinct from final canonical signal IDs and stay with surviving groups after
insertion or deletion. Each assignment binds reference state, partition, revision
and the exact accepted phase facts through the existing dependency snapshot owner.
Final canonical IDs still follow validated array order. One initial role request
returns the complete required decision map defined by
[ADR 0020](0020-derived-exact-reference-lineage.md#complete-role-decision-amendment-approved-9-october-2026).
Native admission projects supported selections to group-role assignments in
offered-group and registered-role order. Roles may be shared across groups; a group
may have several roles or none. A changed upstream phase retires its complete role
assessment, producer origin and derived assignments, and YAML requests them again
before full validation. Pending assessments cannot default to unsupported. Engine
staleness is never reported as a model's invalid role decision.

Summary statement membership covers the partition by union; each statement has a
nonempty unique authorized selection. Combined, split and overlapping expressions
are allowed. After full statement validation, the normalized summary projection
keeps the first occurrence of identical validated content with the same claim
membership, using the existing typed-content equivalence owner. It retains the
original-to-surviving occurrence map and producer origins without mutating the raw
candidate, repair indexes or retry identity. Invalid entries cannot be hidden;
different source occurrences and paraphrases are not equivalent merely because
their displayed text is similar. Surviving response order determines canonical
statement order, followed by native token statements in partition claim order.
Stable repair occurrence IDs remain independent of canonical IDs and array
positions; no model local keys or token metadata are needed. Canonical token
identities and exact-value readback remain unchanged. Admission, history and repair
revalidation apply the same union coverage, without changing disposition cardinality,
signal membership or repair scope. Coverage is not semantic proof.

YAML explicitly checks summary reuse before constructing a model packet. A
non-final, nonempty partition with one current validated child and identical claim
membership carries that child's content forward through the existing summary
validation, identity allocation and construction actions. Eligibility resolves the
child from canonical execution history, checks the supplied child against it and
revalidates the proof binding its projection, source evidence and text dependencies.
Stale or altered history fails. Leaf, empty and multiple-child partitions retain
their existing model path; final global reconciliation still performs its semantic
phase sequence.

The native iteration cycle uses the shared finite-iteration contract in
[§6.3](../contracts/06-pipeline-nodes.md#63-reordering-and-composition-rules).
Validated partitions initialize one pass whose limit is its non-final partition
count. Accepted summary construction advances the current cursor exactly once;
the binding requires the assignment's exact immutable current progress. Runner
state binds these facts to the current plan and progress generations and commits
them with the delta. Stale, repeated, skipped or exhausted advancement fails.
Initialization cannot cycle without an independent retry guard. Upstream repair
may produce a new validated plan and a fresh pass. Each committed advancement
adds one graph traversal to the runner's existing retry-derived allowance.
Summary reuse declares no retry limit; explicit model/repair retry allowances
and the workflow token budget remain unchanged. YAML still owns every transition.

The native parent retains the child's statement order, memberships and exact-token
references and records its child lineage. Parent summary/statement identities are
allocated normally. The original producer, normalization map and repair provenance
remain on the child in immutable history; the parent has no fabricated provider
origin or copied repair receipt. Carried typed content is revalidated before
acceptance. This introduces no generic-engine scheduling policy, persisted schema
change or claim that reused meaning has been independently reviewed.

Native assignment projection distinguishes selectable claims from the complete
evidence catalogue. Summary `assignment.claim_ids` lists only model-content
claims. Signal assignments use that same selection owner and the canonical
nonconflicting eligibility check over accepted dispositions. Token claims,
citations and exact values remain visible evidence, without becoming semantic
authoring targets. Only the current phase's context is constructed. Conflict
explanations receive group handles and coverage guidance, with no claim-selection
assignment. Protocol corrections retain these immutable packets; authorized
repairs retain their existing exact target and dependency contracts. Native
candidate validation still rejects unsupported selections; presentation never
normalizes a rejected token selection into acceptance.

Semantic assignment guidance names `assignment.claim_ids` as the sole selection
scope. Signal coverage concerns retained assigned claims not already covered by
accepted signals; native token coverage is stated once and remains engine-owned.
Signal content preserves supported meaning, conditions, triggers and obligation
strength. Complete duplicate member sets reject; different sets may overlap.
Summary and signal schema views derive available model-content categories from
the canonical selected-kind validator and membership cardinality from eligible
IDs through §12's generic unique-subset restriction. Empty eligible catalogues
admit only an empty authored collection. Atomic selection repairs use their
authorized compatible IDs and target-specific guidance, not initial-assignment
or whole-result coverage instructions. Content repairs retain their existing
selected-kind schema. Reference repair guidance labels the original candidate's
rejection as `failed_requirement`, distinct from the authorized replacement's
constraints. Full coverage and within-selection uniqueness remain required;
schema admission does not establish meaning preservation or model reliability.

Authoring-role choices use the same positive-support eligibility as their Spec
consumers: every claim in a selected group must be retained. The shared reference
support owner supplies this rule to phase packets, role validation, generation,
review, coverage and canonical readback. Historical duplicate/superseded signals
remain valid evidence without authoring roles. Filtering role choices preserves
their original occurrence IDs and complete claim evidence; it neither removes
members from a mixed group nor assigns missing roles. An ineligible model
selection rejects at its producing phase before dependent dispatch.
When the eligible catalogue is empty, tagged-variant projection removes every
supported branch before narrowing choices; the model may report only unsupported
decisions. Native code does not fabricate these verdicts or emit an empty ID enum.
Protocol corrections retain the complete map, selected schema and immutable phase
packet; existing bounds apply without a semantic correction loop. Unsupported is
a candidate support judgment, not a human gap or `not_applicable` authority. The
existing mandatory-role coverage gate still blocks authoring without positive
support. Canonical readback validates the derived positive assignments; captured
responses retain explicit negatives without a second persisted authority.

Conflict groups are semantic choices. Each supplied group declares all its pairs;
native code constructs reciprocal relationships only within that group. Overlap is
allowed; A–B and B–C never imply A–C. Explanations select accepted native group IDs,
with multiple conflict kinds allowed. Native code attaches membership and checks coverage. Conflict selection repairs
use the same group catalogue; removed claim-list and reciprocal-edge echoes reject.
A coupled false-conflict replacement may change semantic groups only inside its
existing authorized membership. Repairs retain exact dependency snapshots and retire affected descendants.

When the closed, admitted no-feature outcome forces every token irrelevant, or a
chunk has no token candidates, native code constructs the collection without a
model call. Native projections have no fabricated provider origin. An authorized
outcome-changing repair retires forced classifications and returns through the
classification gate; positive token-only extraction remains distinct from
no-feature extraction.

The user-authorized FIX01-01 Phase 2 cutover uses current accepted claims,
dispositions, groups and role assignments to bind preservation comparisons.
Comparisons assess actual consumed collections; supporting signal prose does not
replace original authoring claims. Upstream changes retire affected comparison
evidence along with existing descendants. Native attribution is checked again
against these facts before repair. This adds no semantic role/summary repair and
changes no role-admission or mandatory-coverage rule.

Principle citation granularity is unchanged: selecting a narrower policy passage
remains semantic. No precision-losing citation catalogue is introduced.

Offline unit, integration, architecture and packaged checks establish mechanical
behavior only. Each live E2E run still needs separate explicit approval and rubric
evaluation. This decision does not accept the overall Proposed design.
