# 22. Atomic repair protocol

Part of the [proposed design](../design.md#22-atomic-repair-protocol). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 22.1 Definition of atomic

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

Atomicity means unrelated valid units cannot change. The explicitly approved
20 September amendment in [§16.4](16-reference-ingestion.md#false-conflict-repair-boundary--approved-extension)
permits one native-bound inseparable conflict-relation group across its affected
dispositions/conflict records. No other cross-record repair is authorized.

The user-approved chunk 14 amendment (18 September 2026) permits execution-private
repair of source-backed candidate omissions. The owning contract must establish a
unique defective producer and its smallest safe target from captured source and
review evidence. Source absence, ambiguous ownership and stale evidence do not
authorize repair. A review verdict itself is never a repair target.

The [clarification-admission boundary](12-model-boundary.md#1281-clarification-admission-and-candidate-failure-precedence)
does not relax that prohibition. An inconclusive finding without an identifiable
user decision must reject when existing authority cannot correct it; completing
its question text cannot grant clarification publication. Optional verdict
reassessment remains a separate unapproved decision in FIX_002.

- Reference extraction uses the shared replacement authorization for a chunk's coupled
  token-classification collection, one invalid source selection, or an empty claim-citation
  collection.
- Citation repair includes the unchanged claim and scoped source choices.
- Both selection checks run before derived claims are built.
- Merge invalidates the selection result; the same checks run again before token/claim
  construction, ledger validation and full-candidate publication.
- Missing semantic support remains an authority gap, not a selection repair.

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

**Approved redundant-projection amendment (25 September 2026):** native
reconciliation may delete one misbound extra summary statement or signal when
its current, unique, nonempty claim selection is valid (and non-conflicting for a
signal), every selected claim remains represented, the complete surviving
collection passes its existing validation, and the removed content is canonically
identical to a valid survivor under that survivor's actual claim scope. This
extends identical-evidence redundancy; it grants no evidence reassignment or
semantic inference. Bind the original diagnostic, old value, revision and complete
dependencies; retain surviving values/origins and rerun normal full validation.
No proof means no deletion. Existing retry and token accounting remain unchanged.

**Approved conditional-membership amendment (25 September 2026, FIX_002 §31):**
The specification session's existing entity decision may authorize replacement of
one contradictory entity with a source-grounded non-entity record, retaining its
exact evidence selection, or insertion of one missing required entity. It may not
change that decision, delete unique content, reclassify siblings or infer semantics.
Bind the current session, old value/absence, source/policy dependencies and stable
record occurrence. Subsequent invalid fields of that record retain the same
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

The repair guidance contains:

- the exact diagnostic code and rule;
- rejected value;
- expected values/patterns or concrete allowed candidates;
- the current repair unit only;
- minimal immutable context required to preserve meaning;
- the fixed target pointer;
- the exact replacement schema;
- the instruction that unrelated fields must not be returned or changed.

Unavailable passive/exact-copy diagnostics identify the rejected selection and
location. Existing native evidence choices drive both schema narrowing (§12.2)
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

Specification generation and native unit repair reuse the unit's configured purpose
prompt (§17.3); repair must not substitute a generic instruction that drops the
field's semantic purpose. The selected replacement schema and authorization still
limit writable content. Recover original source meaning within that scope while
preserving correct surrounding content. Mechanical repair acceptance does not prove
semantic recovery; full coverage and the existing semantic review remain mandatory.

The 25 September FIX_002 §36 coupled-evidence authorization applies to the
currently deployed token/citation tuple. ADR 0020 retires that tuple-specific
trigger at its coordinated format cutover and supplies the replacement
value-only bounds, including an invalid-handle baseline. It grants no general
coupled evidence add/remove repair. Independently authorized membership,
reviewed insertion and native exact reconstruction keep their own targets.
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
native evidence repair. The diagnostic and optional repeat-feedback work in
[FIX_002 §25](../../fixes/FIX_002.md#25-principle-citation-conformance--architecture-review)
is not authority to change retry limits, reconsider verdicts or persist new policy.

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

Upstream omission repair invalidates every dependent projection. Extraction changes
rebuild canonical token, claim and citation identities across the corpus, then
reconciliation, support review and downstream specification evidence. Preserve raw
candidate siblings even when their derived identities change. Semantic regeneration
uses explicit registered workflow steps and the shared progress-sensitive retry/token
accounting; repair does not create a hidden execution path or saved continuation.

The engine never trusts a model field such as `valid: true`.

### 22.6 Unparseable output

**Approved model-response normalization (21 September 2026):** first parse the
original complete response strictly. Only after a `SyntaxError`, if its first
three bytes are exactly `{"{`, the shared model-envelope decoder may remove the
first two bytes (`{"`) once and strictly parse the entire remainder. Accept the
normalization only when that remainder is one complete JSON object. Valid input
is never altered; no other prefix, fence, suffix, duplicate key or malformed
remainder is salvaged. Schema and domain validation remain mandatory.

The candidate retains a typed `removed_leading_brace_quote` fact and its original
invocation evidence. The runner logs `model.response_normalized` at warning level
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
IR is available. The user-approved missing-answer amendment also permits the
same continuation when sealed provider evidence establishes `missing_final_text`
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
  constraint; correction does not repeat its subtrees. This focused amendment was
  explicitly approved on 19 September 2026. Syntax correction uses that same complete
  schema. Guidance never selects a semantic branch, moves fields or synthesizes values.

The [approved child-object amendment](#2261-child-object-requirements)
below adds required names to immediate child-object descriptors only.

- The builder owns no retry counter or limit.
- Each correction returns through the existing `advance-model-attempt-accounting` step, whose
  compiler-validated local limit owns further attempts of that assignment (§22.7).
- The execution's total-token budget continues across all requests and corrections.
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
before continuation; unknown usage or an exhausted global budget prohibits a new call.

Runner retry exhaustion retains the owning compiled operation, declared limit
and completed execution count alongside the last response diagnostic. It is a
typed terminal rejection, never an ordinary YAML outcome that could continue
to success or `needs_user`. If JSON decoding or schema validation still fails when
correction is unavailable or exhausted, the workflow reports an error and exits
nonzero; it cannot publish either a completed or incomplete specification. Existing
open clarifications do not override that failure. A correction that passes admission
may continue through the remaining domain validators; a recovered earlier rejection
is not itself a publication veto. Whole-stage regeneration is not used.

#### 22.6.1 Child-object requirements

**Explicitly approved by the user on 20 September 2026.** Extend the
existing schema-derived correction outline at one boundary: every immediate field
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
The [feasibility trace](../reference-notes/model-request-guidance.md#nested-correction-feasibility)
and [Chunk 18 plan](../../fixes/IMP_001.md#focused-226-decision--child-object-requirements)
record evidence, limits and required verification. This amendment grants no new
repair capability and does not claim improved model compliance.

#### 22.6.2 Explicit error guidance

**User-requested amendment, implemented 20 September 2026.**
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
force. See [request-level tests](28-testing.md#284-model-fault-injection-tests) and
the [R45 implementation plan](../../fixes/IMP_001.md#r45-follow-up--brief-conformance-after-child-object-guidance).
Improved model compliance still requires separately approved live measurement.

### 22.7 Repair retry limit and escalation

The user-approved 2026-09-18 amendment makes successful repair progress independent
of another target's retry allowance:

- Each retry-capable operation instance still declares `retry-limit` in YAML.
  Atomic repair requests and repair merges count visits by compiled operation and
  native defect key. Ordinary model requests count visits by compiled operation
  and immutable assignment; other operations retain invocation-wide counts.
- The user-requested R32 amendment defines an assignment by execution, immutable
  unit, model operation and purpose, excluding request ordinal. Context followups
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
- Semantic omission progress requires complete dependent rebuilding and admitted review.
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

- Exhaustion returns:

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

The approved [§7.1 amendment](07-domain-representations.md#71-shared-types) uses the
same ordered segment shape for initial business values and selected value repairs.
An invalid reference diagnostic retains its segment location and rejected IDs;
permitted choices derive from the bound evidence under ADR 0020. Literal punctuation is not a
repair trigger. Repair keeps siblings, exact-byte obligations, dependency freshness,
full validation, retry identities and token accounting with their existing owners.
Native coverage repair remains limited to its existing whole-display equality proof;
this amendment does not authorize substring guessing or rewriting meaning.
