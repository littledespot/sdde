# ADR 0022: Native reference phase handoffs

- **Status:** Accepted
- **Date:** 2026-10-06
- **Authority:** User approval of FIX_003, with user-approved amendments for
  summary union coverage, duplicate normalization and single-child carry-forward,
  and for partition-bounded summary iteration (10 October 2026); and for authored
  associations replacing the independent role phase (11 October, ADR 0020).
- **Amends:** Reference ingestion §16.4, model boundary §12.9, repair §22,
  pipeline contracts §§6.2–6.3, and ADRs 0016 and 0020 for
  extraction/reconciliation handoffs.
- **Amended by:** [ADR 0024](0024-native-exact-token-authority.md): native code,
  not the model, owns preserved-token dispositions and relevance for candidates
  with a native requirement-byte witness.

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
Final canonical IDs follow validated array order. The three global semantic
assignments are dispositions, signals and conflicts; no presentation-role request
or pending role assessment remains. Authoring receives canonical accepted group
occurrences and selects its support while drafting under
[ADR 0020](0020-derived-exact-reference-lineage.md#authored-associations).
Changed upstream facts retire affected groups and their dependent authored
associations; engine staleness is never attributed to a model's semantic decision.

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

Initial authoring choices preserve complete current groups whose members are
retained. The shared reference-support owner supplies eligibility to generation,
admission, review, coverage and canonical readback. Historical duplicate/superseded
groups remain evidence but cannot acquire positive authored associations. Filtering
preserves occurrence IDs and all members; it never trims a mixed group or chooses
semantic support. Positive values additionally retain the existing prohibition on
mapping open questions; clarification question evidence has its own scope.
An empty retained catalogue blocks native readiness before dispatch. Protocol
correction retains the same catalogue, selected schema and existing allowance.
No role list, unsupported-only schema or positive default is reconstructed.

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

Preservation comparisons bind current accepted claims, dispositions, groups and
admitted authored associations.
Comparisons assess actual consumed collections; supporting signal prose does not
replace original authoring claims. Upstream changes retire affected comparison
evidence along with existing descendants. Native attribution is checked again
against these facts before repair. This adds no semantic association/summary repair and preserves the existing
full-candidate coverage and publication rules.

Principle citation granularity is unchanged: selecting a narrower policy passage
remains semantic. No precision-losing citation catalogue is introduced.
