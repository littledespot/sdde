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
- **Amended by:** [ADR 0046](0046-complete-dispositions-at-admission.md) (31 October
  2026): response admission binds one disposition to every assigned semantic claim, so
  an omitted or repeated disposition is corrected with the whole assignment and is not
  a phase repair; disposition repair only replaces one disposition.
- **Amended 20 November 2026** (C10 in `fixes/Z_SPEC01.md`, decided 15 November 2026; user: "preflight and
  implement C10: skip the conflicts call when the only valid answer is empty. This lands with
  the ADR 0022 amendment."): the conflicts phase has no request when no conflict group
  exists. See "Forced conflicts answer".
- **Amended 25 November 2026** (ENGINE01 §10 item 3, §12 Phase 2; user: "implement phase 1 and phase 2"): a
  conflicts answer explains each declared group exactly once. It carries one conflict kind for the group, and the
  engine keeps one conflict record for each claim set. See "Conflict groups" below.
- **Amended 27 November 2026** (ENGINE01 §10 item 13, decisions A and T1; user: "accept recommendations A and T1",
  then "implement A and T1"): the source-omission conflict-group repair replaces one record alone when it shares a claim
  with another, and a signal or conflict subject is offered no `candidate_invalid`. It amends §12 (the source
  `candidate_invalid` finding), §16.4 and §22.1. See "Overlap and the repair of one record" and "No `candidate_invalid`
  for a record" below.

Semantic decisions remain model candidates. YAML explicitly requests, collects,
validates and repairs each reconciliation phase before requesting its descendants,
except a conflicts phase with no group to explain ("Forced conflicts answer").
Native typed phase facts, rather than schema-admitted JSON prerequisites, supply
accepted dispositions and signal selections. Pending phases cannot be accounted
as complete. Checked phase facts retire resolved repair receipts in the same
runner-applied delta; receipts owned by a later validator remain pending.
The generic JSON composer remains structural; it receives no domain
validation policy or hidden scheduler. Named definitions in one response schema
own the phase shapes, and the summary request selects its `summary` definition natively.

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
phase sequence, a conflicts phase with no group excepted ("Forced conflicts answer").

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
admit only an empty authored collection; the conflicts catalogue is the exception,
which is not requested at all when empty ("Forced conflicts answer"). Atomic selection repairs use their
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
one explanation for each group and one conflict kind for it (25 November 2026).
Native code attaches membership and checks coverage. Removed claim-list and
reciprocal-edge echoes reject. A coupled false-conflict replacement may change semantic groups only inside its
existing authorized membership. Repairs retain exact dependency snapshots and retire affected descendants.

When the closed, admitted no-feature outcome forces every token irrelevant, or a
chunk has no token candidates, native code constructs the collection without a
model call. Native projections have no fabricated provider origin. An authorized
outcome-changing repair retires forced classifications and returns through the
classification gate; positive token-only extraction remains distinct from
no-feature extraction.

**Conflict groups** (25 November 2026). Several kinds for one group made several records over the same claims,
and the claim an answer keeps must be in no other record ([ADR 0025](0025-clarification-answer-authentication.md) "What
it applies to"), so no such pair could be answered.
- **Binding.** The conflicts assignment binds its group IDs as an `exact_members` choice on
  `conflicts[].group_id`, as ADR 0046 does for dispositions. Admission rejects a repeated group as
  `duplicate_member` and an omitted one as `missing_member`, and the existing bounded protocol correction
  resubmits the whole assignment under the conflicts request's `retry-limit`. It adds no counter, insertion or
  deletion. The schema states no count, so the request the model receives changes only by the prompt line.
- **Canonical rule.** The conflict records of one reconciliation have distinct claim sets, whatever their kind
  (`conflictSelectionAvailable`, also checked when a snapshot is read back). A second record over one claim set is a
  `duplicate_conflict`, and the existing repair deletes it only when its summary is equivalent.
- **The kind.** A record keeps one kind. No code branches on its value; it is printed in `reference-context.md`
  and sent to review.
- **Readback.** A reference snapshot written before this amendment with two records of different kinds over one claim
  set no longer validates (`InvalidReferenceSnapshot`). No state version advanced, and there is no reader for it:
  the run starts again.
- **Scope** (amended 25 November 2026). The statement and signal coverage inserts of ADR 0046 Decision 6 are
  unchanged. The conflict-selection replacement (target, claim-pair facts and `repair_conflict_selection`) and the
  coverage insert for a conflicting claim in no group are deleted: a record's claims are a validated group's
  members, so only its summary text is repairable, and any other rule on a record is an engine invariant failure
  (`InvalidAtomicRepair`). A conflicting claim in no group stays a `no_required_member` block. The coverage insert
  for a group with no record and the duplicate-record deletion stay, because the source-omission conflict-group
  repair (§16.4) binds its group claims but not its `conflicts[].group_id` set, so its answer can omit or repeat
  an explanation.
- **Overlap and the repair of one record** (27 November 2026). Overlapping groups are allowed, so a false record can
  share a claim with a genuine one. The source-omission conflict-group repair replaces the selected record, its group
  and the dispositions of the claims no other record holds, the claims it *releases*. A claim another record holds keeps
  its disposition, and native code re-derives its relations from the records that stand. The record is found by its
  claims, never by its first claim. The mechanics (authorization, retry identity, progress) are owned by
  [§16.4](../contracts/16-reference-ingestion.md#false-conflict-repair-boundary) and
  [ADR 0046](0046-complete-dispositions-at-admission.md) Decision 3.
- **No `candidate_invalid` for a record** (27 November 2026). Source review that dismisses a signal or a conflict
  subject has found candidate loss, which the producer repairs, so the subject's view offers no `candidate_invalid`.
  The dismissal is `candidate_omission`. The rule is owned by
  [§12](../contracts/12-model-boundary.md#source-invalid-content-finding).

**Forced conflicts answer** (20 November 2026). When the validated dispositions declare no
conflict group, the only admissible conflicts answer is the empty collection: the schema
owner already narrows it to `maxItems 0`, and with no group there is nothing to cover.
It is computable structure, so the engine makes no request for it. This is a closed
policy for the conflicts phase alone; the dispositions, signals and summary requests are
always sent, even where their catalogue is empty.
- **Predicate and owner.** The declared conflict groups are empty, read by the stage module
  (`reference_reconciliation_stage.zig`) when it collects the signals. A group makes the
  answer a model choice, as before.
- **Effect.** The signals collection leaves the phase complete, so the YAML phase check
  routes to `validate-conflicts` and no conflicts packet is built, sent, collected or
  released; the stage module refuses to build or collect one for a prior with no group.
  Every validator and gate still runs on the candidate, in order.
- **A phase fact, not a step.** The completion is a typed phase fact that the YAML phase
  check routes on, as the collected conflicts answer already is. A native construct step
  would return through `validate-dispositions`, forming a cycle with no retry guard, which
  graph validation refuses; and `validate-conflicts` reads the phase from the re-validated
  signals.
- **Origin and repair.** The empty conflicts collection has no provider origin, as native
  projections have none, so the conflicts record carries none. It has nothing to repair. A
  repair that changes dispositions returns the phase to dispositions, so the predicate is
  read again at the next signals collection.
- **Accounting.** No request exists, so there is no ledger entry, token or step event for
  it; tokens are reported, never the reason. The class is successful completion, by removing
  a request whose only valid answer was fixed. No failure had been observed, so no benefit is
  demonstrated.

Preservation comparisons bind current accepted claims, dispositions, groups and
admitted authored associations.
Comparisons assess actual consumed collections; supporting signal prose does not
replace original authoring claims. Upstream changes retire affected comparison
evidence along with existing descendants. Native attribution is checked again
against these facts before repair. This adds no semantic association/summary repair and preserves the existing
full-candidate coverage and publication rules.

Principle citation granularity is unchanged: selecting a narrower policy passage
remains semantic. No precision-losing citation catalogue is introduced.
