# ADR 0022: Native reference phase handoffs

- **Status:** Accepted
- **Date:** 2026-10-06
- **Authority:** User approval of all changes in FIX_003.
- **9 October 2026 amendment authority:** Explicit user instruction to implement complete role decisions under [FIX01 §9.8](../../fixes/FIX01.md#98-complete-role-decisions-critical-review--9-october-2026).
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

Summary response order determines native statement order. Native token statements
follow semantic statements in partition claim order. Stable repair occurrence IDs
remain independent of array positions; no model local keys or token metadata are
needed. Canonical token identities and exact-value readback remain unchanged.

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

Principle citation granularity is unchanged: selecting a narrower policy passage
remains semantic. No precision-losing citation catalogue is introduced.

Offline unit, integration, architecture and packaged checks establish mechanical
behavior only. Each live E2E run still needs separate explicit approval and rubric
evaluation. This decision does not accept the overall Proposed design.
