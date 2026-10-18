# 22. Atomic repair protocol

Part of the [proposed design](../design.md#22-atomic-repair-protocol), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

### 22.1 Definition of atomic

**Post-generation findings:** under
[ADR 0023](../decisions/0023-advisory-post-generation-review.md), post-generation
semantic findings, including principle findings, authorize no automatic content
repair or upstream regeneration. They remain advice with their original evidence
and origins. Native defect validators retain their repair or
blocked outcomes; valid citations or model-assisted comparisons do not establish
semantic corroboration. A genuine native authority gap remains typed, never an
automatic upstream rebuild after generation. Pre-generation source repair and
native generation/protocol repair remain distinct authorized operations.

An atomic repair changes the smallest independently valid IR unit associated with one diagnostic. It is not necessarily one character. The unit may be:

- one scalar field, such as a proposed path;
- one list item, such as a requirement;
- one structured record, such as a task;
- one artifact section;
- one coverage entry;
- one dependency edge;
- one patch hunk or declaration;
- one complete file only when a parser/tool cannot localize the failure;
- one explicitly declared coupled group of pointers within one authorized IR record or one authorized file when those pointers cannot be valid separately.

Atomicity means unrelated valid units cannot change. [§16.4](16-reference-ingestion.md#false-conflict-repair-boundary)
permits one native-bound inseparable conflict-relation group across its affected
dispositions/conflict records. No other cross-record repair is authorized.

Execution-private pre-generation repair of source-backed candidate omissions is
permitted. The owning contract must establish a
unique defective producer and its smallest safe target from captured source and
review evidence. Source absence, ambiguous ownership and stale evidence do not
authorize repair. A review verdict itself is never a repair target.

The [clarification-admission boundary](12-model-boundary.md#1281-clarification-admission-and-candidate-failure-precedence)
does not relax that prohibition. In required pre-generation assessment, an inconclusive finding without an identifiable
user decision must reject when existing authority cannot correct it; completing
its question text cannot grant clarification publication. Optional verdict
reassessment is not approved.

- Reference extraction uses the shared replacement authorization for a chunk's coupled
  token-classification collection, one invalid source selection, or an empty claim-citation
  collection.
- Citation repair includes the unchanged claim and scoped source choices.
- Both selection checks run before derived claims are built.
- Merge invalidates the selection result; the same checks run again before token/claim
  construction, ledger validation and full-candidate publication.
- Missing semantic support remains an authority gap, not a selection repair.

**Reference handoffs ([ADR 0022](../decisions/0022-native-reference-phase-handoffs.md)):** use native
occurrence-bound selections and group catalogues in initial and repaired
reconciliation. Signal changes retire dependent authored associations; disposition
changes retire affected signals while preserving independent groups. Rebuild through the same
validated phases before canonical identity assignment and full-candidate checks.
Mandatory exact-token content is reconstructed from the authorized source claim,
without a model call. Summary ordering and retry occurrence identity are separate;
removed local keys and token metadata reject on the model boundary. Conflict
selection repairs return a group handle, and coupled group replacements declare
semantic membership once. Exact old-value, revision, dependency snapshots and
existing bounded retry accounting remain required. Outcome-changing extraction
repairs retire forced classifications and re-enter classification validation.
Initial summary/signal assignment selections follow ADR 0022's native projection;
atomic and omission repairs continue to use their authorized target and exact
dependencies, rather than borrowing a broader initial authoring selection.
Completed specification units use the authorized repair target and current review
evidence; their packets do not reuse a consumed authoring assignment. Pending
authoring still binds and validates its current source group.
Initial attributed authoring selects complete accepted group occurrences together
with content under ADR 0020. Fixed repairs retain required canonical
`source_group_ids`; their wire responses stay value/content-only. Value-only repair
cannot change group IDs, explicit `S`, effective evidence bounds or siblings.

Under [ADR 0020](../decisions/0020-derived-exact-reference-lineage.md#native-exact-value-recognition)
there are no model-authored exact-copy selections. Fixed replacements type exact values
in prose. Their retained native request scope derives eligible occurrences from
the authorization's current snapshot and effective-evidence bounds, never a sibling
or broader authoring catalogue. Raw-byte contextual recognition precedes canonical
normalization, old-value/revision merge checks and no-progress comparison. It may
derive `E` while `S` stays fixed, but the replacement still preserves its authorized
effective evidence and citations. Ambiguous recognition rejects the whole field;
missing or stale native scope is an engine rejection, not permission for a model
to choose a handle. Composition correction and retry limits remain unchanged.

A lost obligation outside that association has an explicit unresolved-association
outcome and blocks; no membership-changing rebuild permission exists, and the
outcome cannot blame extraction or grouping. There is no post-generation
reviewed-omission insertion (ADR 0023). A semantic omission note cannot authorize an invented association or
cross-group insertion. Independently authorized native membership repair retains
its current accepted group occurrence, complete selection and readback checks.

An omission must identify nonempty authorized sources at review admission, even
when its subject also fixes claim evidence. Loss comparison retains that admitted
omission, its subject, detail, selected sources and revision.

**Explicit source-obligation handoff:** the existing
source reviewer supplies a required nonblank `missing_obligation` for
`candidate_omission`. This is a direct statement of the omitted source requirement,
including its conditions, negation and obligation strength; `detail` explains the
candidate defect separately. The selected original sources support the obligation.
Native code carries the statement unchanged through admission, comparison,
correction, repair and persisted evidence; it cannot extract, infer or rewrite an
obligation from diagnostic prose. Non-omission and principle findings forbid it.
The comparison assignment binds the exact obligation together with the existing
subject, detail, source selections, revision and canonical evidence. Changed
obligation or evidence invalidates the old comparison. A selected source-omission
detail correction returns both explanation and obligation, retaining the verdict
and existing source/subject authorization. Correction precedes loss localization
and revalidates the current binding; it does not reassess an admitted verdict or
refresh a stale comparison through a semantic retry. A changed binding cannot
retain valid comparison evidence.

Native code binds complete evidence collections on the actual dataflow path to
that subject. Original source support and the deficient
subject are fixed premises; neither is reassessed. The loss packet's
`fixed_finding.missing_obligation` is its single semantic comparison target.
Diagnostic detail, final-field purpose and deficient-subject/producer outputs
remain separately labelled supporting evidence. The loss reviewer judges whether
each complete collection preserves the supplied obligation, allowing equivalent
wording and support jointly expressed by its members. It must not require a
standalone literal, final-field form or a description of the downstream defect.
The model returns exactly one
`preserved`, `lost` or `uncertain` assessment per assigned comparison ID, with
original-source spans and an explanation of where the obligation survives or what
is missing. The spans must collectively support the entire supplied source
obligation, including conditions, negation and obligation strength; multiple spans
may be necessary, while unrelated spans are omitted. The explanation assesses
preservation in the assigned collection; the source spans establish the original
obligation. `comparison_id` binds the whole native-assigned collection; the model
does not select a member subset. Complete member identities, evidence, obligations
and dependencies remain in the retained assignment. Shared identical views are
assessed once. Other producer outputs are supporting context, not selectable
culprits or permission to expand the finding.

Response admission first binds the assigned comparison IDs as an `exact_members`
choice, so a missing, repeated or foreign comparison takes bounded protocol
correction; exhaustion stays terminal under this required policy. Native admission
still rejects missing, duplicate, foreign or stale comparisons and
invalid source joins or native collection identities, including a changed obligation
binding. The closed response rejects the superseded `members` field; no reader,
correction or normalization fills member IDs into rejected responses. It derives
attribution backwards through the bound path: preserved input and lost output
establish the boundary's owner; lost input
and lost output establish only inherited absence. Required uncertainty, composite
ownership or unavailable facts leave attribution unresolved. Preserved original
claims assigned to authoring cut off upstream blame; signal paraphrases are not
substituted for those claims. Native checks do not prove the semantic labels or
explanations, or prove that the model considered every assigned member. Explanation
adequacy, citation completeness and relevance, and judgment correctness require
separate semantic assessment. Native admission does not require every offered
source to be cited or fill in missing citations: available source identity does
not establish semantic support. A forced
no-feature extraction owns its forced classifications;
a separately classified claims collection does not identify a unique extraction
or classification culprit merely because meaning is missing.

Attribution is separate from atomic permission. Before generation, derived upstream locations supply
the existing diagnostic claim sets and must pass the existing target, old-value,
revision and dependency checks. Known authored-association or summary defects
retain explicit unsupported-repair identities and cannot fall back to another
producer or candidate.
Unresolved attribution grants no upstream rebuilding; independently authorized
candidate-local checks remain available. No new exact-reference, association-membership, summary,
entity-decision, retry or verdict-reassessment permission is added.

Pre-generation collection, correction, authorization and readback use this one comparison
contract. Post-generation advisory findings request no loss comparison and grant
no content-repair authority. Canonical pre-generation evidence retains native facts, bindings, the complete response
and its comparison-call origin separately from the review-finding origin. Rebuild
bindings from current canonical facts before deriving any retained attribution;
request logs and stored digests are not authority. Changed producers or candidate
facts retire dependent evidence through existing invalidation. The cached location
must equal the rederived result. Native `invalid_loss` remains terminal; protocol
correction fixes only its existing permitted protocol defects.

Signal-content repair preserves the validated unique member set. That ordered set,
within the existing source-state and producer scope, identifies its review retry
across regenerated signal ordinals. Changed membership cannot resolve that defect
or reset its allowance. Other regenerated subjects retain their existing policy.

### 22.2 Repair classification

Every diagnostic declares one class:

- `canonicalize`: a documented semantics-preserving normalization, such as slash normalization, applied before candidate identity is established;
- `model_atomic`: the model produced an invalid repairable unit;
- `user_input`: a missing decision, unresolved authoritative conflict, or explicit approval is required;
- `environment`: configuration, reader, parser, repository, or command capability is missing/broken;
- `not_repairable`: retrying a model cannot make the operation safe.

Configuration and environment errors never consume LLM repair attempts.

- A missing or unreconciled authority is not a malformed candidate value and therefore is never
  repaired by generating a convenient replacement.
- The existing one-shot whole-operation-result no-invention replacement may yield
  `clarification_needed` only when §12.8.1 admits a genuine authority gap. Candidate
  loss or inconclusive review retains its own repair/rejection outcome.
- If a later stage detects the gap, repair stops and the shared reconciliation router selects
  upstream rework.
- Local repair resumes only after the owning stage has regenerated, passed reconciliation, and
  renewed every affected approval.

### 22.3 Repair authorization

- `CreateRepairAuthorizationAction` creates an immutable authorization after diagnostic ordering
  and selection actions have run.
- It copies the exact `compiledEnginePolicyStateId`, stable diagnostic code/rule IDs,
  validator-contract ID, discriminated mechanical authority provenance (preset, platform policy,
  or engine contract), and complete typed rule values used by that diagnostic into the
  authorization.
- `RepairRuleBinding` has closed variants for path/extension/filesystem rules, atomic
  schema/cardinality/enum/identifier constraints, exact registry references, coverage,
  graph/phase, dependency, command-selection, content-validator, and exact-value rules.
- An authorization is invalid if the selected diagnostic's validator declares a rule dependency
  that is absent; arbitrary principle prose cannot stand in for a binding.
- A semantic principle conflict instead follows semantic review and plan/task
  clarification/review.
- This makes mechanically repairable filename and non-filename repairs equally self-contained:

[View the Repair authorization sample](../code.md#repair-authorization).

- The operation and every target pointer/key/anchor are selected by the engine.
- The model cannot choose what to modify.
- Guidance is rendered only from authorization-bound rules and must not re-query an ambient
  “current” preset, so initial guidance, the diagnostic, validation, and repair remain on one
  exact policy revision.
- `candidateRevision` is run-local compare-and-swap control for concurrent repair attempts; it
  is not persisted as an artifact-freshness fingerprint.
- Omission authorization also binds the requirement, admitted review, producing
  origin, original value or absence anchor, and complete dependency snapshot.
  Reconciliation loss cannot authorize inserting an already extracted claim.

**Redundant projections:** native
reconciliation may delete one misbound extra summary statement or signal when
its current, unique, nonempty claim selection is valid (and non-conflicting for a
signal), every selected claim remains represented, the complete surviving
collection passes its existing validation, and the removed content is canonically
identical to a valid survivor under that survivor's actual claim scope. This
extends identical-evidence redundancy; it grants no evidence reassignment or
semantic inference. Bind the original diagnostic, old value, revision and complete
dependencies; retain surviving values/origins and rerun normal full validation.
No proof means no deletion. Existing retry and token accounting remain unchanged.

**Summary coverage:** the
[§16.4 summary contract](16-reference-ingestion.md#164-semantic-extraction-flow) validates
coverage by membership union and permits overlapping statements. Its exact-duplicate
normalization produces a validated summary projection before canonical identities;
it does not mutate the raw repair candidate or widen atomic authorization. Retain
the original-to-surviving occurrence map, producer origins, raw old values, revision,
dependency snapshots, active receipts and retry identity. Every raw entry must pass
its own validation before projection, and repairs re-run union coverage and the
same normalization. A new array position is never a new repair allowance. Existing
redundant-projection deletion keeps its separate authorization and proof; overlap
alone authorizes neither deletion nor coupled replacement.

**Conditional entity membership:** the feature-wide entities unit's fixed applicability decision
may authorize deletion of one contradictory entity or insertion of one missing
required entity. Record batches cannot author entities or use this authorization.
Repair may not change the decision, reclassify an entity as another record family,
change siblings or infer semantics.
Bind the current session, old value/absence, source/policy dependencies and stable
record occurrence. A replacement fixes the old record's authored source selection
`S`, source groups, effective evidence `L = S ∪ E`, and derived citations. Native
occurrence recognition over all of the old record's permitted fields establishes
`E` before the bound is captured, including unchanged sibling prose. Its packet,
merge and full validation use the same fixed occurrence scope; replacement cannot
add or remove effective evidence. Initial insertion has no old `L`: it uses the
fixed feature-basis source groups and authored selection, and the current native
eligible occurrence scope, then fixes the inserted record's resulting `L` and citations for later
replacements. Subsequent invalid fields of that record retain the same
whole-record assignment and retry bound. Reuse the native repair owner, selected
schema definitions, runner and accounting. Full unit validation, source/claim and
exact-token coverage, semantic assessment and publication validation remain required.

The repair algebra is closed:

- `replace(pointer, expectedValue, replacement)`;
- `insert(collectionPointer, stableKeyOrAnchor, replacement)`;
- `delete(pointer, expectedValue)`;
- `replace_group(unitId, exact {targetId, pointer, expectedValue, schema} set, replacementsByTargetId)`.

- `replace_group` is allowed only for a predeclared inseparable unit within one authorized IR
  record or one authorized `fileId`, and never as retry-scope expansion.
- A missing task uses `insert`; a removable dependency edge uses `delete`.
- Path renames remain planning operations and are not a code-repair group.

### 22.4 Repair request and response

Every repaired text value
passes the same [composition policy](text-field-composition.md) as initial
authoring and readback. Canonical equality with the rejected old value, under
the exact active permit and defect key, produces shared typed exhaustion
`unchanged_repair`. The runner discards the tentative delta before application,
retains actual consumption and prevents later work on the exhausted key. It does
not advance candidate revision, invalidate dependents, request semantic review
or resolve the defect. Changed repairs retain existing dependent/full validation.
This adds no route-specific rule or retry allowance.

Composition defects (required prose, prohibited insertions and embedded insertion
syntax) are no longer repair targets. They are rejected at response admission and
corrected through the existing bounded protocol correction with the complete
original request, as defined in the
[composition contract](text-field-composition.md#composition-defects-are-corrected-as-a-unit).
Repair responses apply the same admission rule within their own request's
correction bound. Other repair kinds and `unchanged_repair` exhaustion are
unchanged.

The repair guidance contains:

- the exact diagnostic code and rule;
- rejected value;
- expected values/patterns or concrete allowed candidates;
- the current repair unit only;
- minimal immutable context required to preserve meaning;
- the fixed target pointer;
- the exact replacement schema;
- the instruction that unrelated fields must not be returned or changed.

**Focused-review repair.** All produced findings are
individually validated before the next native assignment is requested. The
source unit/collection assignment in §17 produces all its native member findings
in one call; principle assessment produces the complete current subject set of
one selected principle set in one call. Exact complete native membership is checked
before appending any member; partial, duplicate, foreign or misbound responses
cannot contribute coverage. Response admission first enforces the same membership
through the packet's `exact_members` choice. A defect there uses the bounded
protocol correction of the complete assignment, never insertion or deletion
([ADR 0023](../decisions/0023-advisory-post-generation-review.md#assignment-membership-at-response-admission-18-october-2026)). Native ledger order owns canonical ordering.
A mechanically invalid finding may use the existing selected-value/field atomic
repair while other subjects remain pending; valid produced siblings remain
unchanged and future pending subjects do not produce missing-finding defects.
Authorization binds the current diagnostic, typed subject, original value,
revision and dependencies. An admitted negative or inconclusive finding remains
review data; repair cannot change its verdict. Protocol correction stays on the
same request assignment and selected schema. The collection's first admitted
native-candidate origin stays fixed through later findings and repairs, while each
finding retains its own origin. Batched siblings initially share their actual
accepted review-call origin; a selected repair changes only its target's origin,
never inventing a call for another field. Assignment protocol correction requests
the same complete native member set, while native detail/evidence repair
remains scoped to the selected singleton finding and retains its verdict.
In required pre-generation source preservation, multiple candidate omissions are localized serially from the earliest canonical
finding with no preservation evidence. Each keeps its own unchanged obligation,
complete comparison assignment and comparison-call origin; completing one does
not clear another. Selection derives from retained canonical findings, not a
second obligation queue. Revalidate after every comparison or repair and do not
request another review assignment while a current omission awaits localization.
Complete membership, evidence and relationship
validation run before reconciliation, publication or clarification. The existing
runner owns request retirement, per-assignment and native-defect retry allowances,
and global actual-token accounting; successful independent work does not reset an
unresolved target or replenish the finite budget.

**Within-execution review retention.** Candidate-local repairs still retire current support and
authority projections. An execution-private receipt reservoir may preserve clean
admitted `supported`/`not_applicable` source assignments as historical evidence.
It cannot satisfy a gate. Reconstruct the complete current assignment through
the existing packet owner and check the [§12.6 request witness](12-model-boundary.md#126-semantic-review),
original sources, canonical source producer, native subjects/requiredness and
applicability. Equal field bytes, aliases, ordinals or reference-state strings
alone do not authorize reuse. Fresh native admission appends the entire assigned
group in ordinary collector order, with its original finding values and actual
origins, and builds current revision-bound authority. An empty restart prefix
contains no finding and cannot complete a review.

Original review scope and native occurrence identities survive candidate-local
restarts; reassessing a changed subject cannot replenish its repair allowance.
Update historical snapshots after every admitted new or retained assignment and
loss-localization update or native finding repair. A changed value/origin retires its older receipt. Missing,
foreign, stale or invalid receipts provide no coverage; changed assignments take
the ordinary model path. Supported detail/evidence repairs and protocol-corrected
assignments are conservatively reassessed unless their additional complete
dependency witness is represented. Source omissions and their revision-bound
preservation comparisons are not reused. Loss localization, verdict prohibition
and repair attribution retain their existing contracts.

Upstream source/reconciliation producer changes prevent receipt reuse even when
an equal reference-state string survives. Full-candidate collection/entity context
changes require reassessment; policy context remains broad and is reassessed.
Receipts retain their immutable input/request/result owners until execution
teardown. They are native bookkeeping, never serialized review authority,
checkpoints or cross-run caches. Fresh invocations start with no receipts.
Impacted semantic review and complete native coverage, authority, policy and
publication validation still run. Mechanical reuse establishes unchanged
dependencies and admission, not the truth of the original semantic judgment.
The pure operation consumes only the finite unchanged collector prefix, rebuilding
each assignment after its predecessor is admitted. Membership must strictly grow
within the current native population. A miss returns to ordinary model preparation;
only a complete accepted source collection with no pending localization takes the
completion transition. No extra retry allowance or unguarded workflow loop applies.

Source-ID selection repairs project the diagnostic's native eligibility rule
through the shared [§12.2 schema restrictions](12-model-boundary.md#122-initial-guidance-packet).
Reference selection/disposition and grouped omission repairs likewise use their
current authorized claim/group scope. A broader initial catalogue cannot widen
that scope. Initial findings, correction and repair retain native provenance,
correlation and readback checks; a membership enum alone cannot authorize a merge.

Selected source-review and generation repair responses reject `provenance`,
including record insertion and coupled record repair. The engine reconstructs
canonical `provenance.claim_ids` from the bound source group or selected
diagnostic producer before old-value/revision and full-candidate checks.
Source-ID or detail corrections remain in their existing selected repair
families; source-omission detail correction uses the coupled explanation and
obligation shape in §22.1, and cannot change the verdict. The original source-group occurrence association, explicit `S`, effective evidence
bound and siblings stay pinned by the existing atomic authorization. A value-only replacement cannot expand them;
changing authored group membership requires separately authorized authored-unit
rebuilding, which does not exist. Before generation, genuine evidenced
upstream loss retains its existing producer repair path. After generation starts,
the native phase guard rejects authorization, packet preparation and merge under
ADR 0023. Malformed or corrupt stored evidence is rejected before
model-response reconstruction. Unbound authority is an engine block, not a
model repair or user clarification.

Unavailable passive diagnostics identify the rejected selection and location.
Invalid canonical exact occurrences or native scope reject at their authority
owner; they are not model-authored exact choices. Existing native evidence choices drive schema narrowing (§12.2)
and concise corrective guidance: state validation failed, name unavailable
alternatives, and identify source-backed text or permitted references as
appropriate. A value-only repair preserves its bound explicit support and
effective evidence under [ADR 0020](../decisions/0020-derived-exact-reference-lineage.md);
it cannot borrow an exact choice from a sibling or enlarge its bound on retry.
The same choice-guidance owner handles both reference kinds; when neither is
permitted, explicitly request source-backed text strings.
Keep the rejected value once when
its containing field adds no other content; retain record siblings when needed for meaning.
This does not grant new repair targets, semantic reassessment or additional retries.

Specification generation uses the unit's configured authoring prompt (§17.3).
Native unit repair uses the configured repair prompt and the field's semantic
purpose from its authorized task. The selected replacement schema and authorization
still limit writable content. Recover original source meaning within that scope while
preserving correct surrounding content. Mechanical repair acceptance does not prove
semantic recovery; full coverage and the existing semantic review remain mandatory.

ADR 0020 grants no general coupled evidence add/remove repair. Independently
authorized membership repair keeps its own targets.
Revalidate the full unit, affected dependencies, coverage, semantic/principle
review and publication/readback before acceptance. The engine derives reference
citations from permitted selections; it never chooses semantic support to make
a repair pass.

Evidence repair obtains the diagnostic and permitted references from their existing
validator/registry, including any applicable source-line bounds. The request builder
projects those facts; it does not revalidate citations or select supporting evidence.
Registry/selection integrity failures remain engine failures, distinct from an
invalid model-proposed citation. Principle citation diagnostics identify the citation
index, rejected chunk/line field and value, using the existing selection for allowed
IDs and the captured span for inclusive line bounds. These same facts reach repair
and reports; they are not a second persisted authority. JSON/schema correction (§22.6) does not replace
native evidence repair, change retry limits, reconsider verdicts or persist new policy.

Example:

[View the Repair request sample](../code.md#repair-request).

Valid response:

[View the Repair response sample](../code.md#repair-response).

- The response cannot include a pointer, operation kind, or extra replacement.
- Each operation has a distinct closed response schema.
- ADR 0006 removes echoed authorization, diagnostic and revision metadata from model output; the
  engine retains and checks those facts through the exact repair-call association before merge.
- Group replacements are keyed by engine-assigned `targetId`, never paired by array position,
  and the exact authorized key set is required.

### 22.5 Merge and revalidation

1. Validate authorization, diagnostic, candidate ID, and candidate revision.
2. Validate the exact response cardinality and replacements against the unit schema.
3. Compare every authorized old-value/key/anchor precondition against the current candidate.
4. Reject any attempt to change an immutable sibling or undeclared group member.
5. Apply the closed operation to an in-memory copy with compare-and-swap, then increment the candidate revision.
6. Run the validator that produced the diagnostic.
7. Run declared dependent validators. A planning path change, for example, reruns project ownership, kind, filename, placement, plan authorization, task collision, and render-reference checks.
8. If the unit passes, retain it and select the next diagnostic in stable order.
9. When no local diagnostics remain, run the full candidate validation suite.
10. Only a full pass can authorize rendering or commit.

Pre-generation source omission repair rebuilds its affected reference projections
and canonical token, claim and citation identities through registered steps.
Authorization, packet construction and merge require the current native
pre-generation phase, bound into existing dependency/CAS checks. Runner-owned
bindings derive that phase from the actual optional generation session/content;
model bytes and custom YAML routing cannot supply it. A retained authorization
cannot be used after generation starts. There is no post-generation upstream merge
or semantic specification-omission repair. Actual upstream changes require fresh validation; no
review finding grants hidden execution or saved continuation.

The native source-repair retry scope pins its original required review projection,
producer, feature and captured reference state. After rebuilding, becoming
generation-ready cannot skip that dependent review or substitute a different
review purpose. Existing readiness/preservation gates require the matching
pending review regardless of the optional preservation-scan setting. Only its
admission can settle the repair obligation; advisory review cannot. Generation
initialization blocks while any native repair permit remains active, including
a child suspending a source-repair parent. Projection retirement leaves those
runner-owned obligations intact.

The engine never trusts a model field such as `valid: true`.

### 22.6 Unparseable output

**Model-response prefix normalization:** first parse the original complete response strictly. Only after a `SyntaxError`,
the shared model-envelope decoder may recognize one of these exact opening
artifacts immediately followed by a JSON object:

- `{"`
- `{"name` (an unfinished member name)
- `{"name":"` (an unfinished string-value opener, with no intervening whitespace)

In the named forms, `name` is nonempty, unescaped UTF-8 and must exactly repeat
the following object's first quoted member name, followed by a colon. Only JSON
whitespace may separate that object's opener, member and colon. Thus
`{"{"value":1}`, `{"value{"value":1}` and `{"value":"{"value":1}` qualify
without a field-name, provider, model or workflow special case. The prefix parser
considers only the initial opener and is bounded by the captured response length.
At the first quote or object opener after `{"`, it requires the exact continuation
above. It rejects escapes, control bytes and any other closing-quote continuation;
it never searches past another fragment or discards string-value content.

**Partial member-name amendment (user-approved, 18 October 2026):** Bedrock GPT-OSS
also truncates the unfinished member name, for example `{"find{"findings":…}`.
- In the `{"name` form only, `name` may be a nonempty start of the first member name
  rather than the whole name. It must still be unescaped, control-free, valid UTF-8,
  so it cannot split a character.
- The key scan then ends at the first quote or backslash after `name`. A backslash
  rejects; a quote must be followed, after JSON whitespace, by a colon.
- The strict remainder parse still owns the validity of every key byte.
- The candidate records `removed_partial_field_prefix`.
- The string-value opener still requires the exact name.
- Every other rule in this section is unchanged.

Remove that one prefix and strictly parse the entire remainder. Accept normalization
only when it is one complete JSON object. Valid input is never altered; no leading
whitespace, recursive removal, other prefix, fence, suffix, duplicate key or malformed
remainder is salvaged. Schema and domain validation remain mandatory.

The candidate retains a typed `removed_leading_brace_quote`,
`removed_repeated_field_prefix` or `removed_partial_field_prefix` fact and its
original invocation evidence.
The runner logs `model.response_normalized` at warning level
with that rule, node, request and attempt; logging failure remains terminal.
Raw provider/text captures are unchanged. The shared domain handoff supplies the
decoder-consumed bytes; composition continues to use its validated tree. Neither
reinterprets raw malformed text or applies a second normalization.
Debugger inspection reuses this decoder
and displays the alteration separately from raw text. Rejected normalization
retains the original diagnostic/bytes for existing bounded protocol correction.
This exception changes neither provider-wire/configuration/persistence parsing
nor request, retry, token or publication authority. It is a workaround for the
observed Bedrock prefix, applied consistently to complete model responses without
a provider/model/workflow branch; it does not establish a provider-side fix.
The development rubric evaluator reuses this decoder for judge responses
([evaluator](../harness/evaluator.md)); that grants the judge no production authority.

For [configured response parts](../decisions/0016-configured-json-response-composition.md),
the response/schema below is the complete assigned part. Corrections retain its
request identity and current prerequisites; an unrelated admitted part remains
unchanged. Assembly adds no repair authority: after handoff, native domain owners
alone select targets and impacted validation/rebuilding. Configured part dependencies
apply to active staging. Current native repair rebuilds derived data without
converting it back into response parts or adding automatic part-generation calls.
Existing selected-unit model repairs remain available. Historical parts cannot
overwrite an already repaired candidate. Keep stable native candidate/defect identity
separate from changing per-field producer origins. This integration changes
no retry counter or global token rule.

When a model response fails JSON decoding or its bound result schema, no valid
IR is available. The same continuation applies when sealed provider evidence establishes `missing_final_text`
after wire, association and usage validation. Reasoning is never answer text;
no empty candidate, adapter retry or blanket provider-failure retry is introduced.
The YAML-declared protocol-retry builder prepares a narrowly
defined response-level correction containing:

- the original schema;
- the exact rejected response, retained through its original invocation
  association and supplied as untrusted evidence;
- the latest native validation error in the **model-visible correction guidance**:
  decoder reason, position and available object/key context, or schema rejection
  reason and JSON Pointer. Recording the error only in logs is insufficient.
  Duplicate-field diagnostics identify the first and repeated key locations
  without inferring a repair or accepting changed data;
- no request to reconsider semantics;
- for schema rejection, the expected candidate JSON Pointer and value/parent scope,
  a distinct JSON Pointer locating the exact expected node in the complete selected
  schema, and concise schema-derived immediate fields, required fields and allowed
  discriminator values. The single complete schema retains every alternative and
  every constraint that schema syntax can express; `exact_members` uniqueness stays
  native and is reported as `duplicate_member` with parent scope on the enclosing
  array. Correction does not repeat schema subtrees. Syntax correction uses that
  same complete schema. Guidance never selects a semantic branch, moves fields or
  synthesizes values. For an integer-enum rejection, guidance uses the exact schema locator and a short integer-type outline; it does not copy
  the allowed-ID list from the complete selected schema into the outline.

[§22.6.1](#2261-child-object-requirements) adds required names to immediate
child-object descriptors only.

- The builder owns no retry counter or limit.
- Each correction returns through the existing `advance-model-attempt-accounting` step, whose
  compiler-validated local limit owns further attempts of that assignment (§22.7).
- The execution's total-token budget continues across all requests and corrections.
  Under ADR 0023, exhausted malformed-response correction of bound optional
  advice closes the logical request failed without another provider operation
  and records incomplete advice. A provider/protocol stop during advisory atomic
  finding repair explicitly retires only the exact active permit, retaining
  counters and unresolved history without claiming that repair succeeded.
  Native finding-evidence validation and repair exhaustion remain terminal.
- Request IDs cannot reset either authority.
- Every correction starts with the original retained task/schema/evidence inputs and the latest
  rejected response and diagnostic; previous correction prompts are not accumulated.
- All attempts remain available as execution evidence.

For missing final text, retain the original task/input/schema and supply the precise
missing-answer diagnostic with a concise request for the complete assigned response.
There is no rejected body to attach: do not substitute reasoning, an empty string or
an older response. The existing admission and retirement owners consume this sealed
evidence without decoding a nonexistent candidate. Provider-operation failure remains
recorded; explicit request closure remains failed/invalid unless a later response
passes ordinary admission. Missing answers, JSON and schema failures share one
assignment allowance, including selected native-repair parents. Charge every exchange
before continuation; unknown usage or an exhausted global budget prohibits a new
call. All inference and corrections share the same `totalModelTokenBudget` and
aggregate usage ledger. Global-budget rejection remains fatal during advisory repair and cannot be
converted into incomplete advice.

Ordinary runner retry exhaustion retains the owning compiled operation, declared
limit and completed execution count alongside the last response diagnostic. It is
a typed terminal rejection, never an ordinary YAML outcome that could continue
to success or `needs_user`. ADR 0023's native-bound advisory protocol exhaustion
is the explicit exception described above: only its sealed current stop receipt
may record incomplete advice, without another attempt or provider call. Otherwise,
if JSON decoding or schema validation still fails when correction is unavailable
or exhausted, the workflow reports an error and exits nonzero; it cannot publish
either a completed or incomplete specification. Native finding-evidence or repair
exhaustion and global-budget rejection remain terminal. Existing open
clarifications do not override that failure. A correction that passes admission
may continue through the remaining domain validators; a recovered earlier rejection
is not itself a publication veto. Whole-stage regeneration is not used.

#### 22.6.1 Child-object requirements

Extend the existing schema-derived correction outline at one boundary: every immediate field
descriptor whose compiled type is `object` also lists that object's required
property names, in compiled order. Derive these names in the shared schema
projection; the protocol builder consumes the result without inspecting candidates
or selecting additional diagnostics. Reuse the existing required-field projection.

- This annotation is nonrecursive. It contains names, not child schema subtrees,
  synthesized examples or a second complete schema. No new configurable depth,
  token ceiling or truncation rule is introduced.
- Required names apply when that object is present; they do not make an optional
  parent field required. Emit an empty list for an object with no required children.
- Array descriptors remain type-only. Child tagged unions retain the existing
  allowed-tag summary; no branch is inferred. At an expected union node, retain
  the existing alternatives and apply the same object-field rule within each.
- Keep the canonical validator's first rejection and both candidate/schema
  pointers unchanged. Additional required names describe expected structure,
  not additional established defects or instructions to move evidence.
- Resolve only the original selected schema: complete/named result, configured
  part or narrowed repair response. Never widen a replacement into its parent
  candidate or import sibling schemas, fields, data or authority.

All other §22.6 behavior remains unchanged, including complete-response correction,
schema/native validation, request ownership, accounting and terminal rejection.
This grants no new repair capability and does not claim improved model compliance.

#### 22.6.2 Explicit error guidance

Extend the existing `build-model-protocol-retry` action, not the set of repair
actions. Its single responsibility remains preparing the corrected request.

- State explicitly that the previous response failed JSON decoding, schema
  validation or final-answer admission. Preserve the typed diagnostic and its
  available location; add a concise explanation through the existing diagnostic
  owner. For example, `unknown_property` means the property is not allowed at that
  location; `missing_required_property` means a required property is missing.
- Derive expected fields, types, discriminator values and relevant bounds only
  from the selected compiled schema through the shared schema projection. Keep
  the candidate path, parent/value scope and schema locator distinct. A
  parent-scoped discriminator error must not describe the parent's type as the
  discriminator's type. Do not invent actual values, additional defects or fixes.
  For length/range errors, project the relevant scalar bounds without duplicating
  item/child schemas; immediate child arrays otherwise remain type-only.
- Use one complete-response instruction: correct the reported errors, preserve
  unaffected entries and meaning, and return the complete assigned response
  matching the supplied schema. Replace redundant wording instead of appending
  another prompt, schema copy or example. Required child fields remain conditional
  on the parent being present; guidance never moves or selects evidence.
- A single notice such as “The previous correction still failed this validation”
  is permitted only when retained typed evidence proves a correction of the
  immediately preceding rejection failed with the same diagnostic identity.
  Confirm the same execution, immutable assignment and selected schema; compare
  diagnostic kind/reason and location/context, including schema scope/locator
  where applicable. An attempt ordinal alone proves no recurrence. Same diagnostic
  does not prove identical response bytes, and different errors receive only the
  current error guidance.
- The request handoff owns a copy of the rejection addressed by each prepared
  correction. It compares the next native rejection only after matching provider
  evidence to that exact prepared request, and passes the confirmed fact to the
  builder. No prompt parsing, semantic similarity classifier, second
  history store, unrestricted stack read or new counter is permitted. Keep only
  the latest rejected body in model context; missing answers retain the no-body
  rule. Without sufficient evidence, omit the repetition claim.

These rules apply to every admitted response shape, including configured parts
and selected native-repair responses. They do not make native semantic defects,
user clarifications, transport failures, invalid associations or runner failures
eligible for protocol correction. Existing authorization, full validation, retry
identities/limits, token accounting and terminal no-publication rules remain in
force. See [request-level tests](28-testing.md#284-model-fault-injection-tests).
Improved model compliance still requires separately approved live measurement.

### 22.7 Repair retry limit and escalation

Successful repair progress is independent of another target's retry allowance:

- Each retry-capable operation instance still declares `retry-limit` in YAML.
  Atomic repair requests and repair merges count visits by compiled operation and
  native defect key. Ordinary model requests count visits by compiled operation
  and immutable assignment; other operations retain invocation-wide counts.
- An assignment is identified by execution, immutable unit, model operation and purpose, excluding request ordinal. Context followups
  retain their parent's assignment and native followup ordinal. Equal payload
  bytes do not merge unrelated units. Reassignment cannot reset history.
- Successful JSON and schema admission completes protocol correction. Changed
  text, error kind/location, or syntax alone does not grant a new allowance.
  Independent assignments have independent allowances; prior counts remain for
  the execution. This changes no semantic validation or publication authority.
- Required dependent requests additionally bind their pending native parent key.
  Distinct rebuilding units can continue; repeating the same unit under the same
  parent retains its allowance. Atomic repair requests keep the native defect
  allowance, including schema-valid unsuccessful replacements.
- A defect key identifies the original candidate scope, stable authorized target and
  closed validator-owned diagnostic family. Mutable values, request IDs, authorization
  IDs and revisions cannot create a new allowance. Native occurrence identities
  survive array replacement/deletion; recurrence history lasts for the execution.
- Only the canonical validator can report `resolved` or `recurring` for the selected
  defect. A changed value, revision increment, fewer diagnostics or a different first
  error is insufficient. Other unresolved targets retain independent allowances.
  Both model-account and pure-merge guards follow this rule.
- Registered capability-free bindings publish typed authorization, merge and validation
  facts with their candidate delta. The runner validates that transition before applying
  it and owns all counters. Domain owners never grant retries or reset accounting.
- Pre-generation semantic omission progress requires complete dependent rebuilding
  and admitted review.
  Required child repairs may run while that validation is pending; resolving a child
  restores the pending parent, without declaring the semantic defect resolved.
  Rebuilding requests use that native pending parent's key and immutable assignment;
  initial review attempts cannot consume their allowance. Repeated requests and
  corrections for the same parent/assignment retain their counts. The runner's native repair phase supplies this association,
  never a model value or a new request ordinal.
- Each native scope freezes its finite target/family population at first authorization;
  model replacements cannot enlarge it. The shared u32 key representation bounds the
  execution's distinct keys. Assignment counters have the same finite u32 population
  bound. Both use the existing runner-owned retry state and report projections,
  never a builder/provider counter. The compiler uses these bounds and declared per-operation
  allowances to retain a finite execution guard, including pure loops. The compiler's
  1,024-step expansion ceiling does not change per-operation retry or token budgets.
- Protocol corrections retain the same logical request and selected defect allowance.
  A new authorization cannot erase earlier failures. Actual input/output token usage
  remains cumulative across every target, correction and successful fix; no further
  call is permitted at or above the workflow budget.
- Exhaustion blocks/fails without changing validation or broadening repair scope.

Exhaustion returns:

- last schema-valid candidate, if one exists;
- all stable diagnostics;
- attempted replacements and validation outcomes in redacted metadata form;
- the exact blocked unit;
- whether a different allowed model slot, workflow change, user decision, or environment change is required.

The engine never broadens repair scope automatically because attempts are running out.

### 22.8 Repair examples

#### Wrong planned filename

- In the normal path-intent flow the model never emits `src/loginTests.ts`.
- It selects one engine-authorized test intent option, one allowed semantic name source, and
  then a candidate such as `src/LoginForm.test.tsx` by `pathCandidateId`.
- The option indivisibly binds the semantic role, file kind, templates, and capability ceiling;
  the registered name transform and preset deterministically produce and validate the candidate.
- An invalid option, name-source, capability, or candidate selection is repaired as that one
  ID/set field before a `fileId` exists.
- Only a preset that explicitly enables raw fallback may receive a raw path; there,
  `src/loginTests.ts` fails the same preset validators and only
  `ProjectPathCandidate.repoRelativePath` is repairable.
- Tasks always receive the resulting `fileId`, never a filename.
- A defect found after approval invalidates descendants and requires new plan/task approvals.

#### Missing coverage

`FR-004` has no task. The repair unit is “one missing task record for obligation `FR-004`,” not the entire task list. The new record is validated, graph-merged, globally ordered, and then assigned an engine task ID.

#### Dependency cycle

If `task-a -> task-b -> task-a`, the diagnostic includes the cycle and selects one proposed edge for semantic reconsideration. The repair response may replace/delete only that edge. IDs and other tasks remain unchanged.

#### Compiler failure

- A compiler points to one declaration.
- The repair unit is that declaration/hunk in one authorized file.
- The engine discards the invalid operation savepoint, reapplies the repaired candidate to the
  same pre-operation snapshot, promotes it after local validation, then rebuilds and performs
  the full task check.

#### Scope expansion

A code repair requires an undeclared second file. This is not treated as a larger code repair. It is a task/plan scope defect and blocks implementation until the upstream artifact is corrected.

### Typed-content repair conformance

Initial business values and selected value repairs share the
[§7.1](07-domain-representations.md#71-shared-types) text wire. An invalid reference diagnostic retains its segment location and rejected IDs;
permitted choices derive from the bound evidence under ADR 0020. Literal punctuation is not a
repair trigger. Repair keeps siblings, exact-byte obligations, dependency freshness,
full validation, retry identities and token accounting with their existing owners.
Mechanical coverage defects have no independently supported repair target and
block; nothing guesses substrings or rewrites meaning.

### Meaning and repair ownership

A source `candidate_invalid` finding (§12) reports unsupported additions or
retained-obligation contradictions without claiming missing source meaning.
Its optional nested authority gap remains bound to its own original evidence.
Neither the invalid finding nor the nested gap authorizes loss attribution,
upstream rebuilding or semantic content repair. Existing structural review repair
may correct only its authorized explanation, evidence or question while preserving
the invalid verdict and nested gap kind. An unsupported repair retains the defect
and current evidence instead of manufacturing an omission or user question.

Aggregate membership repair must establish the source occurrence and writable
unit independently of dispatch order. The final record task is not evidence of
ownership. If the established semantic association cannot be represented within
the current authorized group, retain an explicit ownership denial. There is no
cross-batch mutation, association change or extra retry allowance.

The declared text wire conversion in §7.1 governs initial content and fixed
value/record repair together. Strings denote ordinary prose; a named fragments
object denotes exact composition. Canonical old-value and dependency comparisons,
reference admission, identity allocation and rendering remain native. Model-facing
fragments contain only their permitted passive/source references; native exact
occurrences follow the approved raw-byte scope and contextual-boundary policy.
There is no legacy array reader, automatic spacing or unscoped text-to-occurrence
inference.
