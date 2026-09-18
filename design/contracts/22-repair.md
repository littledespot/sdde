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

Atomicity means unrelated valid units cannot change.

The user-approved chunk 14 amendment (18 September 2026) permits execution-private
repair of source-backed candidate omissions. The owning contract must establish a
unique defective producer and its smallest safe target from captured source and
review evidence. Source absence, ambiguous ownership and stale evidence do not
authorize repair. A review verdict itself is never a repair target.

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
- The only model-assisted transition permitted for unsupported asserted content is the existing
  one-shot whole-operation-result replacement to `clarification_needed`.
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

When a model response fails JSON decoding or its bound result schema, no valid
IR is available. The YAML-declared protocol-retry builder prepares a narrowly
defined response-level correction containing:

- the original schema;
- the exact rejected response, retained through its original invocation
  association and supplied as untrusted evidence;
- decoder position and available object/key context, or schema rejection
  reason and JSON Pointer; duplicate-field diagnostics identify the first and
  repeated key locations without inferring a repair or accepting changed data;
- no request to reconsider semantics;
- for schema rejection, the exact expected compiled schema node, its JSON Pointer
  and value/parent scope, including all applicable alternatives and constraints.
  Syntax correction uses the original complete schema already supplied. Guidance
  does not synthesize candidate values or duplicate the complete schema in a
  separate example.

- The builder owns no retry counter or limit.
- Each correction returns through the existing `advance-model-attempt-accounting` step, whose
  compiler-validated local limit owns further model attempts.
- The execution's total-token budget continues across all requests and corrections.
- Request IDs cannot reset either authority.
- Every correction starts with the original retained task/schema/evidence inputs and the latest
  rejected response and diagnostic; previous correction prompts are not accumulated.
- All attempts remain available as execution evidence.

Runner retry exhaustion retains the owning compiled operation, declared limit
and completed execution count alongside the last response diagnostic. It is a
typed terminal rejection, never an ordinary YAML outcome that could continue
to success. Whole-stage regeneration is not used.

### 22.7 Repair retry limit and escalation

The user-approved 2026-09-18 amendment makes successful repair progress independent
of another target's retry allowance:

- Each retry-capable operation instance still declares `retry-limit` in YAML.
  Atomic repair requests, their required dependent requests and repair merges count
  visits by compiled operation and native defect key. Other operations retain
  invocation-wide counts.
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
  Rebuilding requests use that native pending parent's key; initial review attempts
  cannot consume its allowance. Repeated requests and corrections for the same parent
  retain their counts. The runner's native repair phase supplies this association,
  never a model value or a new request ordinal.
- Each native scope freezes its finite target/family population at first authorization;
  model replacements cannot enlarge it. The shared u32 key representation bounds the
  execution's distinct keys. The compiler uses that bound and declared per-operation
  allowances to retain a finite execution guard, including pure loops. The 512-step
  expansion ceiling is unchanged.
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
