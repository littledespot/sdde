# 13.5 Artifact, renderer, and traceability actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


## `ReadArtifactAction`

- **Input:** engine-owned artifact path
- **Output:** raw artifact
- **Responsibility:** Read one artifact.

## `AuthenticateActorAction`

- **Input:** runner-issued opaque single-use authentication-lease reference and required
  assurance-policy ID
- **Output:** authentication observation or diagnostic
- **Responsibility:** Invoke `AuthenticationPort.authenticateAndConsume` once.
- The runner-owned lease table—not the envelope—holds the credential, and the port finalizes it
  on every terminal branch.

## `ValidateAuthenticationObservationAction`

- **Input:** one authentication observation, provider registry, required assurance policy,
  trusted clock, and intended event kind
- **Output:** authentication-observation evidence
- **Responsibility:** Reject missing/unknown actors, provider or policy mismatches,
  impossible/expired times, extra credential-shaped fields, and event-incompatible assurance
  before an evidence ID is allocated.

## `AssignAuthenticationEvidenceIdAction`

- **Input:** current validated actor-evidence registry/next ordinal and one validated
  authentication observation
- **Output:** closed `AuthenticationEvidenceIdAllocation`
- **Responsibility:** Assign one monotonic engine ID and return its exact input/next-ordinal
  delta without authenticating, constructing evidence, or yet mutating the registry.

## `BuildAuthenticatedActorEvidenceAction`

- **Input:** authentication-evidence allocation and unchanged authentication observation
- **Output:** authenticated-actor evidence
- **Responsibility:** Bind the allocated engine identity to public provider/actor/assurance/time
  metadata; include no credential material.

## `ValidateAuthenticatedActorEvidenceAction`

- **Input:** one actor evidence, provider registry, required assurance policy, trusted clock,
  and intended event kind
- **Output:** actor-evidence validation
- **Responsibility:** Prove evidence ID/actor/context/provider/policy, freshness at event time,
  and event compatibility without authenticating again.

## `AssignActorEvidenceRegistryStateIdAction`

- **Input:** feature ID, optional prior registry, validated current feature `StateIdLedger`, and
  matching single-use namespace capability
- **Output:** actor-evidence-registry reservation plus successor ledger
- **Responsibility:** Reserve one immutable revision ID without deriving it from actor content.

## `BuildInitialActorEvidenceRegistryStateAction`

- **Input:** feature ID and registry identity
- **Output:** empty revision-zero actor-evidence registry
- **Responsibility:** Create the activation-time registry with the next authentication-evidence
  ordinal set to one.

## `AppendAuthenticatedActorEvidenceAction`

- **Input:** validated prior registry, next identity, exact allocation delta, and one validated
  nonduplicate actor evidence
- **Output:** next actor-evidence-registry candidate
- **Responsibility:** Append one event evidence, consume exactly the allocated next ordinal, and
  preserve immutable history; never accept credentials.

## `BuildActorEvidenceIdRetirementRegistryStateAction`

- **Input:** next actor-registry identity, validated prior registry, and specification-edit
  authentication-evidence retirement record
- **Output:** retirement-only actor-evidence-registry candidate
- **Responsibility:** Advance only registry identity/revision/next ordinal and append the exact
  evidence ID to `retiredAuthenticationEvidenceIds`; copy `entries` byte-for-byte and append no
  actor evidence.

## `ValidateActorEvidenceRegistryStateAction`

- **Input:** candidate, optional prior revision, feature identity, provider/policy registry,
  referencing records, and either accepted append evidence or a validated retirement-only record
- **Output:** registry evidence
- **Responsibility:** Prove unique monotonic IDs and append-only history; require either one
  actor/context/time-valid evidence append with total
  specification-acknowledgement/clarification-response/review/reference-feedback/reference-conflict-decision/manual-evidence
  joins, or byte-equal entries plus exactly one unreferenced allocated-ID tombstone, never both.

## `ParseActorEvidenceRegistryStateAction`

- **Input:** raw canonical actor-evidence bytes
- **Output:** unvalidated registry
- **Responsibility:** Parse one persisted registry revision only.

## `SerializeActorEvidenceRegistryStateAction`

- **Input:** validated actor-evidence registry
- **Output:** canonical registry bytes
- **Responsibility:** Serialize public actor/evidence metadata without credentials or tokens.

## `ScanPassiveLiteralCandidateAction`

- **Input:** one trusted reference/spec-edit/validated-clarification-answer scalar and
  version-bound superset path-token grammar
- **Output:** ordered exact-span candidates
- **Responsibility:** Detect bounded URI/path/filename-shaped spans without assigning meaning,
  identity, or operational authority; model output is never an origin.

## `ClassifyPassiveLiteralCandidateAction`

- **Input:** one exact candidate and closed precedence table
- **Output:** classified passive-literal candidate
- **Responsibility:** Apply `external_uri` before `display_path` before `display_filename`, or
  reject ambiguity.

## `ValidatePassiveLiteralScalarAction`

- **Input:** one classified candidate and scalar policy
- **Output:** passive-scalar evidence
- **Responsibility:** Require bounded strict UTF-8/NFC, single-line control-free bytes and
  allowed external URI scheme/syntax.

## `AssignPassiveLiteralIdAction`

- **Input:** one new `(kind, NFC bytes)` tuple and registry allocator
- **Output:** passive-literal identity
- **Responsibility:** Reuse an exact existing tuple or assign one monotonic never-reused ID.

## `BuildPassiveLiteralRecordAction`

- **Input:** passive identity and scalar-valid candidate
- **Output:** immutable literal record
- **Responsibility:** Bind the engine ID to exact display bytes and kind without an occurrence.

## `BuildPassiveLiteralOccurrenceAction`

- **Input:** literal record and exact reference origin evidence
- **Output:** literal occurrence
- **Responsibility:** Bind one existing record to one byte-exact trusted origin.

## `BuildUserSpecificationPassiveLiteralOccurrenceAction`

- **Input:** literal record, acknowledgement identity, and parsed specification record/span
- **Output:** pending user-spec occurrence
- **Responsibility:** Bind a newly edited display literal to the same authenticated
  acknowledgement output set as its record.

## `BuildUserClarificationPassiveLiteralOccurrenceAction`

- **Input:** literal record, exact validated clarification response, and answer byte span
- **Output:** pending clarification occurrence
- **Responsibility:** Bind display-only text to the assigned response ID; the same clarification
  output must persist the response, next passive registry, and next clarification state.

## `AssignPassiveLiteralRegistryStateIdAction`

- **Input:** feature ID, optional prior registry state, validated current feature
  `StateIdLedger`, and matching single-use namespace capability
- **Output:** passive-literal-registry reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry revision ID.

## `BuildPassiveLiteralRegistryStateAction`

- **Input:** state identity, optional validated prior registry, ordered records/occurrences, and
  scanner contract
- **Output:** registry-state candidate
- **Responsibility:** Preserve prior record cores and append/deduplicate authorized records and
  occurrences without assigning IDs.

## `ParsePassiveLiteralRegistryStateAction`

- **Input:** raw canonical registry bytes
- **Output:** unvalidated passive-literal registry
- **Responsibility:** Parse one registry revision only.

## `ValidatePassiveLiteralRegistryStateAction`

- **Input:** registry candidate, bound feature/request/reference/acknowledgement/clarification
  authorities, and allocator rules
- **Output:** registry evidence
- **Responsibility:** Prove immutable ID/core history, tuple uniqueness, exact origin spans,
  monotonic allocation, and no orphan occurrence.

## `SerializePassiveLiteralRegistryStateAction`

- **Input:** validated passive-literal registry
- **Output:** canonical registry bytes
- **Responsibility:** Serialize one registry revision.

## `SelectPassiveLiteralAllowlistAction`

- **Input:** one route unit's exact inputs and validated registry
- **Output:** ordered unit-local literal IDs
- **Responsibility:** Select only display literals evidenced by that unit's
  request/reference/spec records.

## `ValidatePassiveLiteralReferenceNodeAction`

- **Input:** one passive-reference node, exact bound registry, unit allowlist, and field schema
- **Output:** passive-reference evidence
- **Responsibility:** Require a current allowed display-only ID and forbid the node in every
  operational field.

## `ResolveEditableSpecificationPassiveLiteralAction`

- **Input:** one parsed spec literal span and current registry
- **Output:** existing passive ID or authenticated-registration requirement
- **Responsibility:** Resolve by exact `(kind, NFC bytes)` without silently creating authority.

## `ValidateSpecificationUnitProposalAction`

- **Input:** one operation-result-valid specification-unit proposal and unit descriptor
- **Output:** unit evidence
- **Responsibility:** Validate kind, cardinality, claim/citation fields, and unit-local business
  schema.

## `ValidateClarificationNeedProposalAction`

- **Input:** one operation-result-valid need, fixed stage/unit descriptor, current
  subject-authority allowlist, current clarification registry, and either direct-need evidence
  or the exact consumed no-invention replacement authorization/finding
- **Output:** clarification-need evidence with closed origin
- **Responsibility:** Prove a genuine current authority gap, exact stage-compatible subject,
  bounded closed answer schema, absence of smuggled assumptions/paths/status/identity fields,
  and exactly one origin: direct with no finding, or replacement with the validated embedded
  semantic finding.

## `BuildReferenceConflictClarificationNeedAction`

- **Input:** one validated unresolved behavior-changing source conflict, its structural subject
  coordinate/continuity keys, and exact current claim/citation IDs
- **Output:** deterministic specification-clarification need plus current conflict binding
- **Responsibility:** Build a closed select-one/select-many conflict question whose visible
  option keys are current engine-owned claim IDs while retaining the snapshot-independent
  continuity keys internally; invoke no model and invent no preferred answer.

## `BuildClarificationSubjectKeyAction`

- **Input:** validated target, earliest owner, registered requirement kind, stable unit/subject
  selector and required slot, or validated reference-conflict subject coordinate
- **Output:** engine-owned stable subject key
- **Responsibility:** Build the exact non-hash tuple across executions.
- Run IDs, regenerated authority IDs, evidence, gap reason and wording belong to current
  applicability, not identity.
- Preserve the reference-conflict continuity contract.

## `FindExistingClarificationBySubjectAction`

- **Input:** subject key, validated need origin, and validated current/prior clarification
  registry
- **Output:** exact existing record or absent result
- **Responsibility:** Perform one equality lookup across open and closed history; a reused
  record appends only a nonduplicate validated origin in a new record revision and never creates
  a second clarification.

## `ValidateClarificationSubjectUniquenessAction`

- **Input:** subject key, lookup result, and stage slot rules
- **Output:** reuse-or-allocate evidence
- **Responsibility:** Require reuse for an existing key and reject overlapping ownership of the
  same required slot; wording changes never create a second record.

## `AssignClarificationIdAction`

- **Input:** stage, absent-result evidence, and current persisted clarification ID ledger
- **Output:** execution-private `S01..S99`, `P01..P99`, or `T01..T99` identity plus prospective
  next ledger
- **Responsibility:** Select the next two-digit stage-local ordinal and block at 99 rather than
  changing filename grammar.
- The identity and prospective ledger may flow only inside the not-yet-committed
  registry/view/workflow candidate; no model request, log, diagnostic, path write, serializer,
  or adapter may observe it before the complete owning output is published.
- A failed uncommitted candidate is discarded with its prospective ledger; the unchanged durable
  ledger may deterministically reselect that ordinal.

## `BuildClarificationRecordAction`

- **Input:** reused/new identity, validated need with closed origin, subject key, and record
  revision
- **Output:** open clarification record
- **Responsibility:** Preserve the canonical question, canonically deduplicate/append its origin
  list, or construct one new record; never resolve it or duplicate the subject.

## `AssignClarificationStateIdAction`

- **Input:** feature ID, optional prior registry state, validated current feature
  `StateIdLedger`, and matching single-use namespace capability
- **Output:** clarification-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry revision ID.

## `BuildInitialClarificationIdLedgerAction`

- **Input:** closed stage prefix/limit policy
- **Output:** empty clarification ID ledger
- **Responsibility:** Initialize `S/P/T` ordinals and response/resolution ordinals at one.
- V1 has no clarification tombstone set because these owner-local IDs never cross a
  execution-private boundary before the complete owning commit.

## `BuildInitialClarificationRegistryAction`

- **Input:** state identity, feature/bootstrap/principle/revision-zero passive/actor authority
  bindings, and empty ID ledger
- **Output:** revision-zero clarification registry with no reference pointer
- **Responsibility:** Create restart authority before the first reference snapshot or
  clarification can be allocated.

## `BuildNextClarificationRegistryAction`

- **Input:** state identity, validated prior registry, next ledger, and one closed
  `ClarificationRegistryTransition`
- **Output:** next clarification-registry candidate
- **Responsibility:** Apply exactly one single-record/response/resolution transition, or one
  validated complete reference-conflict set transition containing every equal-key continuation,
  obsolete-key closure, and introduced-key opening; update current authority bindings without
  mutating history or exposing an intermediate registry revision.

## `ValidateClarificationRegistryAction`

- **Input:** registry candidate, prior revision,
  workflow/preset/principle/reference/spec/plan/task/passive/actor authorities, and ID policy
- **Output:** clarification-registry evidence
- **Responsibility:** Prove monotonic IDs/tombstones, prefix/stage/ordinal agreement,
  subject-key uniqueness, current joins, response actor-evidence joins, lifecycle legality, and
  exactly one active record revision per ID.
- The reference pointer may be absent only in revision zero before any record.

## `ParseClarificationRegistryAction`

- **Input:** raw canonical clarification-state bytes
- **Output:** unvalidated registry
- **Responsibility:** Parse one persisted registry revision only.

## `SerializeClarificationRegistryAction`

- **Input:** validated registry
- **Output:** canonical clarification-state bytes
- **Responsibility:** Serialize one restart-safe clarification authority.

## `DeriveClarificationViewPathAction`

- **Input:** clarification ID and validated workflow `clarify/` collection root
- **Output:** canonical clarification path
- **Responsibility:** Derive exactly `<featureDir>/clarify/<ID>.md`; accept no filename/path
  from a model, user, or config.

## `ValidateClarificationDirectoryAction`

- **Input:** collection root, current inventory, portability policy, and clarification registry
- **Output:** directory evidence
- **Responsibility:** Reject unknown matching files, case/NFC aliases, wrong prefixes/widths,
  subdirectories, symlinks, and duplicate IDs; recreate only a missing engine-known open form.

## `RenderClarificationViewAction`

- **Input:** one record, exact registry revision, derived path, and clarification renderer
  contract
- **Output:** discriminated `ClarificationView`
- **Responsibility:** For an open record render `ClarificationSubmissionView` with only
  `requestedStatus` and `answer` editable.
- For an unprotected authority-resolved/cancelled record render `ClarificationAuditView` with no
  editable regions.
- User-closed submissions are retained as `ClarificationUserClosedView`, never passed to this
  renderer (Section 23.2).
- On rerun, every writable view is completely overwritten at the same ID/path, even if its
  question is unchanged.
- Never expose an uncommitted newly allocated identity as a file.

## `ParseClarificationViewAction`

- **Input:** raw registered open `SNN.md`/`PNN.md`/`TNN.md` bytes and expected path/renderer
  contract
- **Output:** unvalidated user submission and immutable projection
- **Responsibility:** Parse one exact `open_submission` form; never infer closure from prose,
  import an extra file, or accept a new submission against a `closed_audit` or
  `preserved_user_closed` view.

## `ValidateClarificationViewStaticProjectionAction`

- **Input:** parsed open view and current open record
- **Output:** immutable-projection evidence
- **Responsibility:** Require filename, ID, stage, state/revision, question, rationale, answer
  schema, and open lifecycle discriminant to equal canonical values directly, without a hash.

## `ValidateClarificationViewLifecycleAction`

- **Input:** one rendered or retained clarification view and its exact registry record
- **Output:** clarification-view lifecycle evidence
- **Responsibility:** Require `open -> open_submission` with exactly the two controlled editable
  regions, `resolved_by_user -> preserved_user_closed` against the accepted response and
  original submission binding, and other unprotected resolved/cancelled records to
  `closed_audit`; both closed variants have no editable/submittable regions.

## `ValidateClarificationViewSetAction`

- **Input:** complete clarification registry, complete registered view set, expected open
  subject-key set, and per-view lifecycle evidence
- **Output:** clarification-view-set evidence
- **Responsibility:** Prove exactly one correctly pathed view per retained record, no
  extra/missing/case-equivalent file, and direct equality of the `open_submission` subject
  projection to the expected open set; the empty projection retains every required closed view,
  including byte-preserved user closures; retained members are not write entries.

## `ValidateClarificationUserSubmissionAction`

- **Input:** parsed submission, current open record, expected state/record revisions, and answer
  schema
- **Output:** structurally current submission evidence
- **Responsibility:** Before authentication, reject stale/immutable edits; require a nonempty
  matching answer for `closed`; for `select_many` require unique known keys within min/max and
  canonicalize only the response value to engine option order, never rewrite submitted bytes;
  validate bounded defer/cancel reason shapes.

## `BindAuthenticatedClarificationSubmissionAction`

- **Input:** structurally valid current submission and validated fresh actor evidence
- **Output:** authenticated submission binding
- **Responsibility:** Bind the exact actor/evidence to the already valid answer and intended
  event kind; perform no ID allocation or lifecycle change.

## `AssignClarificationResponseIdAction`

- **Input:** authenticated submission binding and current persisted response-ID allocator
- **Output:** execution-private response identity plus prospective next ledger
- **Responsibility:** Select one monotonic engine-owned response ID only inside the complete
  complete response/actor/view/workflow output candidate.
- A failed precommit candidate exposes no ID and discards the prospective ledger; a committed
  ordinal is never reused.

## `BuildClarificationResponseAction`

- **Input:** response identity, authenticated submission binding, current record/state, and
  trusted clock
- **Output:** clarification response
- **Responsibility:** Bind the selected option/text/defer/cancel variant, exact bounded
  submitted form bytes, actor/evidence equality, and compare-and-swap revisions.
- The accepted response is the sole durable owner of original submission bytes.

## `BuildReferenceConflictDecisionFromClarificationResponseAction`

- **Input:** current conflict-bound `SNN`, validated closed response, validated `current`
  fresh-reference correspondence, current snapshot/conflict, and decision identity
- **Output:** conflict-decision candidate
- **Responsibility:** Replace each prior selected option with its uniquely mapped current claim
  ID and copy only the response's actor/evidence/time; add no preference or rationale.

## `RefreshReferenceConflictClarificationAction`

- **Input:** validated exact same-key entry with no usable closed response or a stale-answer
  correspondence, existing conflict clarification, and current conflict binding/options
- **Output:** same-ID open record revision
- **Responsibility:** Preserve the structural subject key and clarification ID, refresh only
  unprotected snapshot-local bindings.
- A protected user closure blocks for direction without record/file replacement or duplicate
  allocation (Section 23.2).

## `BuildObsoleteReferenceConflictAuthorityResolutionAction`

- **Input:** one validated unprotected `P ∖ C` entry, its current record revision, an assigned
  resolution ID, fresh reference-state authority, and exhaustive absence correspondence
- **Output:** deterministic obsolete-subject authority resolution
- **Responsibility:** Close only that prior subject with an engine-owned “no longer present in
  current reference authority” resolution; consume no model prose and do not choose a
  replacement subject.

## `BuildIntroducedReferenceConflictOpeningAction`

- **Input:** one validated `C ∖ P` entry, deterministic conflict need, exact global subject-key
  lookup, and reused identity or a legally assigned absent-subject identity
- **Output:** current open record
- **Responsibility:** Reopen/rebind only an unprotected existing subject ID; a protected user
  closure blocks.
- Allocate only after exact global absence, and bind the current conflict/options without
  pairing it to an obsolete subject.

## `BuildReferenceConflictClarificationSetTransitionAction`

- **Input:** validated full set reconciliation, every validated equal-key decision/reopen
  outcome, every obsolete preserved-closure or authority-resolution outcome, every introduced
  opening, and the fully threaded successor clarification ID ledger
- **Output:** complete reference-conflict clarification-set transition
- **Responsibility:** Assemble all `P ∩ C`, `P ∖ C`, and `C ∖ P` effects in canonical key order
  as one registry mutation; perform no state-ID allocation or persistence.
- Resolution and new-record IDs are assigned one at a time in canonical difference-set order
  through the ordinary allocators.

## `ValidateReferenceConflictClarificationSetTransitionAction`

- **Input:** set transition, prior/current registries, fresh snapshot after validated
  current-answer decisions, exact global subject lookups, allocator/tombstone evidence, and
  rendered-form candidates
- **Output:** complete transition evidence
- **Responsibility:** Prove one outcome per reconciliation entry, same-ID reuse for all
  equal/existing keys, allocation only for globally absent introduced keys, exact ledger
  advancement, closure or preserved user closure of every obsolete key, and exactly one open
  form for every still-unresolved current key after decisions.
- Reject duplicate IDs/keys/forms, unrelated pairings, omitted entries, and any state in which a
  current unresolved conflict lacks its form.

## `BuildClarificationAuthoritySearchContextAction`

- **Input:** one open record and refreshed stage-specific authorities
- **Output:** bounded current authority index
- **Responsibility:** Select reference/principle/spec/plan/repository records permitted for that
  clarification stage; never synthesize missing facts.

## `EvaluateDeterministicClarificationResolutionAction`

- **Input:** open record and current authority index
- **Output:** exact resolution candidate or semantic-review-required
- **Responsibility:** Resolve only closed registry/identity/value cases that need no
  interpretation.

## `ValidateClarificationAuthorityResolutionProposalAction`

- **Input:** one workflow-declared clarification-resolution operation result, current open
  record, subject key, and bounded authority index
- **Output:** authority-resolution evidence
- **Responsibility:** Require current known IDs, subject/slot coverage, non-conflict, and no
  model-owned status, ID, or invented value.

## `AssignClarificationResolutionIdAction`

- **Input:** validated resolution and current persisted resolution-ID allocator
- **Output:** execution-private resolution identity plus prospective next ledger
- **Responsibility:** Select one monotonic authority-resolution ID only inside the complete
  complete resolution/view/workflow output candidate.
- A failed precommit candidate exposes no ID and discards the prospective ledger; a committed
  ordinal is never reused.

## `BuildClarificationAuthorityResolutionAction`

- **Input:** resolution identity, validated unchanged proposal/deterministic result, exact
  route-or-rule validation binding, record/state revisions, and trusted clock
- **Output:** canonical authority resolution
- **Responsibility:** Persist the exact canonical resolution text, current authority IDs, and
  self-contained validation-contract binding; close only the current record revision and depend
  on no transient evidence ID.

## `ReopenInvalidatedClarificationAction`

- **Input:** one closed record whose bound answer authority became stale or conflicting and
  current registry
- **Output:** same-ID open record revision
- **Responsibility:** Reopen the existing ID; never allocate a duplicate.

## `ValidateClarificationStageGateAction`

- **Input:** requested gate, current validated registry, and closed prefix matrix
- **Output:** gate evidence/diagnostic
- **Responsibility:** Require no open `S` before plan, no open `S/P` before tasks, and no open
  `S/P/T` before implementation; return a stable nonzero upstream-clarification error.

## `BuildClarificationProvenanceAction`

- **Input:** one response-valid affected spec record, exact current clarification registry, and
  exact ordered response-ID set plus optional validated reference attribution
- **Output:** provenance entry
- **Responsibility:** Record clarification-only or mixed origin, require every response ID, and
  forbid fabricated reference citations for user-supplied facts.

## `MergeSpecificationUnitProposalAction`

- **Input:** one valid unit and current specification-content candidate
- **Output:** next content candidate
- **Responsibility:** Insert one unit at its engine-known slot and reject duplicate ownership.

## `ValidateSpecificationContentCompletenessAction`

- **Input:** assembled specification-content candidate and enabled section policy
- **Output:** completeness evidence
- **Responsibility:** Prove every required singleton/collection unit has a deliberate result.

## `AssignGeneratedSpecificationIdsAction`

- **Input:** complete initial content candidate and new specification ID ledger
- **Output:** identified content candidate and next ledger
- **Responsibility:** Allocate gap-free monotonic IDs for initial repeatable records only.

## `BuildSpecificationIRAction`

- **Input:** identified complete content, fixed singleton keys, traceability evidence, and exact
  validated passive-literal registry
- **Output:** canonical specification IR
- **Responsibility:** Copy the registry state ID and construct one complete initial
  specification authority.

## `CompareSpecificationIRAction`

- **Input:** current normalized specification IR and one authoritative predecessor-bound
  specification IR
- **Output:** equality/difference evidence
- **Responsibility:** Compare the complete typed values directly and report changed record keys;
  do not use rendered bytes, hashes, or timestamps.

## `ParseSpecificationAction`

- **Input:** raw `spec.md`
- **Output:** specification parse tree with record keys and exact field bytes
- **Responsibility:** Parse the specification contract without normalizing field bytes.

## `CaptureSpecificationEditSubmissionAction`

- **Input:** raw specification-edit event with a typed
  `EditableSpecificationViewAuthorityBinding`, exact current editable-view path, bounded
  no-follow descriptor, and runner-held submission/lease table
- **Output:** immutable run-local specification-edit handle plus
  `SpecificationEditCaptureAuthority`
- **Responsibility:** Bind the exact expected workflow/provenance/acknowledgement revisions,
  complete editable-view authority, captured no-follow file identity, and capture time to one
  bounded file capture before parsing; retain the opaque lease only in the runner table and
  assign no durable ID.

## `BuildSpecificationEditChangeSetAction`

- **Input:** captured submission, parsed submitted specification, current normalized
  specification/ID ledger, and direct typed content comparison
- **Output:** specification-edit change-set candidate
- **Responsibility:** Enumerate every added/modified/removed record and prior/next canonical
  business-content identity without authenticating or accepting protected-structure changes.

## `ValidateSpecificationEditSubmissionAction`

- **Input:** captured submission, change-set candidate, current
  workflow/editable-view/specification/provenance/acknowledgement/passive/reference authorities,
  protected-structure contract, and edit policy
- **Output:** validated specification-edit change set retaining the exact
  `SpecificationEditCaptureAuthority`, or stale/structural diagnostic
- **Responsibility:** Before consuming authentication, prove every expected revision, complete
  view binding, and captured file identity is current, parse/round-trip succeeds, IDs/tombstones
  are legal, protected structure is unchanged, and the complete diff is bounded and nonempty;
  the valid output must retain that immutable authority projection.

## `AssignSpecificationEditSubmissionIdAction`

- **Input:** validated edit handle, validated fresh actor evidence for `specification_edit`,
  current specification-acknowledgement ID ledger, and feature ID
- **Output:** durable submission ID plus successor acknowledgement ID ledger
- **Responsibility:** Consume exactly one monotonic submission ordinal only after static
  validation and authentication; never accept a caller/model ID.

## `AssignSpecificationEditChangeSetIdAction`

- **Input:** assigned submission ID, validated change-set handle, the same validated fresh actor
  evidence, and current successor acknowledgement ID ledger
- **Output:** durable change-set ID plus successor acknowledgement ID ledger
- **Responsibility:** Consume one submission-local monotonic change-set ordinal only for the
  authenticated capture and never derive it from edited content.

## `BindAuthenticatedSpecificationEditSubmissionAction`

- **Input:** validated specification-edit change set, assigned durable submission/change-set
  IDs, and validated fresh actor evidence for `specification_edit`
- **Output:** run-local `AuthenticatedSpecificationEditBinding` containing both exact handles
  and one closed durable binding projection
- **Responsibility:** Bind the exact IDs/handles, unchanged capture authority, and actor
  evidence after static freshness/diff validation; mark the handle-bearing shell nonserializable
  and perform no acknowledgement or provenance mutation.

## `BuildAuthenticatedSpecificationEditEventAction`

- **Input:** run-local authenticated binding, unchanged validated change set, and trusted clock
- **Output:** immutable specification-edit event with
  `DurableSpecificationEditAuthenticationBinding`
- **Responsibility:** Reprove handle equality, project the complete capture authority and
  authentication binding into the durable event, preserve the complete add/modify/remove intent
  and exact expected input revisions/view/file identity, and structurally drop only handles,
  leases, credentials, and raw submitted bytes.

## `ValidateSpecificationEditAcknowledgementCoverageAction`

- **Input:** authenticated edit event, next normalized specification, all proposed
  acknowledgements, current acknowledgement state, current workflow/editable-view/provenance
  authorities, and policy
- **Output:** edit/acknowledgement coverage evidence
- **Responsibility:** Revalidate the event's durable capture authority against its
  captured-input revision preconditions; require exactly one binding-matching acknowledgement
  for each new or changed user-authored current record, none for removals/unchanged records, and
  total recording of deletions in the edit event.

## `RebindExactBusinessCopyAction`

- **Input:** one parsed field, current provenance, and preserved-token registry
- **Output:** typed business value
- **Responsibility:** Reconstruct one exact-copy value only after byte-exact token/citation
  validation; otherwise normalize or diagnose.

## `BuildBusinessContentIdentityAction`

- **Input:** one typed business value
- **Output:** canonical content identity
- **Responsibility:** Build NFC canonical identity or exact token/byte identity for one leaf.

## `ValidateExactBusinessCopyAction`

- **Input:** one exact-copy value and current token/citation registry
- **Output:** exact-copy evidence
- **Responsibility:** Prove token, citation, raw scalar, and record attribution agree.

## `ParseSpecificationIdLedgerAction`

- **Input:** raw ID-ledger bytes
- **Output:** unvalidated ID ledger
- **Responsibility:** Parse one feature ID ledger.

## `BuildInitialSpecificationIdLedgerAction`

- **Input:** enabled repeatable record kinds
- **Output:** empty specification ID ledger
- **Responsibility:** Initialize next ordinals and empty tombstones before generated ID
  assignment.

## `ValidateSpecificationIdLedgerAction`

- **Input:** parsed ledger and specification records
- **Output:** valid ID-allocation evidence
- **Responsibility:** Validate next ordinals, uniqueness, and tombstones.

## `AssignMissingSpecificationIdsAction`

- **Input:** parsed spec and valid ID ledger
- **Output:** identified spec plus next ledger
- **Responsibility:** Allocate only missing monotonic record IDs.

## `BuildFeatureRequestProvenanceAction`

- **Input:** one feature-brief-grounded record, validated feature-request state, and exact
  referenced claims/citations
- **Output:** provenance entry
- **Responsibility:** Record `reference_derived_feature_brief` attribution while preserving
  complete snapshot joins.

## `BuildReferenceExtractedProvenanceAction`

- **Input:** one record key/content identity, exact reference-state ID, and validated
  claim/citation join
- **Output:** provenance entry
- **Responsibility:** Record one reference-derived attribution without inventing source IDs.

## `ParseFeatureRequestStateAction`

- **Input:** raw feature-request-state bytes
- **Output:** unvalidated feature-request state
- **Responsibility:** Parse one canonical request authority.

## `ValidateFeatureRequestStateAction`

- **Input:** parsed request state, feature identity, reference snapshot, and clarification
  registry
- **Output:** feature-request evidence
- **Responsibility:** Validate request/state IDs and exact persisted
  invocation/reference/clarification bindings.

## `SerializeFeatureRequestStateAction`

- **Input:** validated feature-request state
- **Output:** canonical feature-request bytes
- **Responsibility:** Serialize one immutable request authority.

## `AssignSpecificationAcknowledgementIdAction`

- **Input:** authenticated edit binding, one changed current record, and current successor
  acknowledgement ID ledger
- **Output:** acknowledgement identity plus successor ID ledger
- **Responsibility:** Consume exactly one monotonic acknowledgement ordinal and return its
  successor; failed post-allocation construction retires the ID.

## `BuildSpecificationAcknowledgementAction`

- **Input:** acknowledgement identity, authenticated specification-edit binding, feature ID,
  changed record key, and next canonical business-content identity
- **Output:** acknowledgement candidate
- **Responsibility:** Bind one user acceptance to the exact validated edit/change set and
  current content without minting identity.

## `ValidateSpecificationAcknowledgementAction`

- **Input:** one acknowledgement, authenticated edit event, next specification, and exact
  actor-evidence registry
- **Output:** acknowledgement evidence
- **Responsibility:** Prove submission/change-set/actor/evidence equality, freshness-at-event,
  and the feature/key/content binding.

## `AssignSpecificationAcknowledgementStateIdAction`

- **Input:** feature ID, prior revision if any, validated current feature `StateIdLedger`, and
  matching single-use namespace capability
- **Output:** acknowledgement-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable acknowledgement revision ID.

## `BuildInitialSpecificationAcknowledgementStateAction`

- **Input:** first acknowledgement-state identity and initialized three-namespace
  acknowledgement ID ledger
- **Output:** empty acknowledgement-state candidate
- **Responsibility:** Create revision one with next ordinals at one, empty tombstones, no edit
  events, and no fabricated acknowledgements.

## `BuildNextSpecificationAcknowledgementStateAction`

- **Input:** next state identity, validated prior state, one authenticated edit event, its
  complete validated acknowledgement set, and exact successor ID ledger
- **Output:** next acknowledgement-state candidate
- **Responsibility:** Append exactly one edit event plus its authorized current-record
  acknowledgements and persist every allocation/tombstone transition without reusing state
  identity.

## `ValidateSpecificationAcknowledgementStateAction`

- **Input:** candidate, optional prior state, current specification/actor authorities,
  accepted-edit evidence or a validated retirement-only record, and ID-ledger accounts
- **Output:** acknowledgement-state evidence
- **Responsibility:** Prove monotonic submission/change-set/ack ordinals, total tombstones and
  append-only history; require either exactly one complete event-to-acknowledgement append or
  byte-equal events/entries with only the validated retirement delta, never both.

## `ParseSpecificationAcknowledgementStateAction`

- **Input:** raw acknowledgement-state bytes
- **Output:** unvalidated acknowledgement state
- **Responsibility:** Parse one acknowledgement-state revision.

## `SerializeSpecificationAcknowledgementStateAction`

- **Input:** validated acknowledgement state
- **Output:** canonical acknowledgement bytes
- **Responsibility:** Serialize one acknowledgement-state revision.

## `BuildUserAuthoredProvenanceAction`

- **Input:** one validated acknowledgement
- **Output:** provenance entry
- **Responsibility:** Record one explicit user-authored attribution without accepting a
  caller-supplied scalar ID.

## `BuildSpecificationClaimDispositionAction`

- **Input:** one snapshot claim and current specification/context/conflict/open-question
  registries
- **Output:** current claim-disposition entry
- **Responsibility:** Build exactly one spec-dependent disposition for one claim.

## `ParseSpecificationProvenanceStateAction`

- **Input:** raw provenance-state bytes
- **Output:** unvalidated provenance state
- **Responsibility:** Parse one provenance-state revision.

## `ValidateSpecificationProvenanceStateAction`

- **Input:** provenance state, specification records, feature-request, acknowledgement,
  clarification, required reference, exact passive-literal, and current
  context/conflict/question registries
- **Output:** provenance evidence
- **Responsibility:** Validate reference-only/clarification-only/mixed/user-authored cross-field
  rules, every response/passive-registry join, and exactly one current specification disposition
  per snapshot claim.

## `AssignSpecificationProvenanceStateIdAction`

- **Input:** feature ID, prior revision if any, validated current feature `StateIdLedger`, and
  matching single-use namespace capability
- **Output:** provenance-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable provenance revision ID.

## `BuildInitialSpecificationProvenanceStateAction`

- **Input:** first state identity, feature-request state, initial acknowledgement/clarification
  states, required reference state, exact passive-literal registry, and initial
  attribution/dispositions
- **Output:** initial provenance-state candidate
- **Responsibility:** Copy every authority ID and construct the first complete provenance
  authority.

## `BuildNextSpecificationProvenanceStateAction`

- **Input:** next state identity, validated prior state, current specification, exact current
  acknowledgement/clarification/passive-literal registries, and attribution/disposition changes
- **Output:** next provenance-state candidate
- **Responsibility:** Copy every current authority state ID and rebuild one immutable revision
  without mutating/reusing prior state identity.

## `BuildSpecificationAcknowledgementRetirementProvenanceStateAction`

- **Input:** next provenance-state identity, validated current provenance/specification and
  retirement-only acknowledgement state
- **Output:** acknowledgement-retirement provenance candidate
- **Responsibility:** Copy entries, claim dispositions,
  feature-request/reference/clarification/passive bindings byte-for-byte and change only
  provenance identity/revision plus `acknowledgementStateId`.

## `SerializeSpecificationProvenanceStateAction`

- **Input:** validated provenance-state candidate
- **Output:** canonical provenance bytes
- **Responsibility:** Serialize one provenance-state revision.

## `SerializeSpecificationIdLedgerAction`

- **Input:** valid next ID ledger
- **Output:** canonical ledger bytes
- **Responsibility:** Serialize the monotonic allocator/tombstones.

## `ParseCanonicalReferenceStateAction`

- **Input:** raw canonical reference bytes
- **Output:** unvalidated reference snapshot
- **Responsibility:** Parse one canonical reference payload.

## `ParseCanonicalPlanStateAction`

- **Input:** raw canonical plan bytes
- **Output:** unvalidated plan state
- **Responsibility:** Parse one canonical plan-state payload.

## `ParseCanonicalTaskDefinitionStateAction`

- **Input:** raw canonical task-definition bytes
- **Output:** unvalidated task-definition state
- **Responsibility:** Parse one complete canonical definition-state payload.

## `ParseCanonicalTaskRuntimeStateAction`

- **Input:** raw canonical runtime bytes
- **Output:** unvalidated runtime state
- **Responsibility:** Parse one canonical runtime payload.

## `ValidateCanonicalStateSchemaAction`

- **Input:** one parsed canonical payload and schema ID
- **Output:** schema-valid canonical state
- **Responsibility:** Apply one canonical-state schema.

## `AssignPlanStateIdAction`

- **Input:** validated plan result, validated current feature `StateIdLedger`, and matching
  single-use namespace capability
- **Output:** plan-state reservation plus successor ledger
- **Responsibility:** Reserve one engine-owned plan-state ID.

## `AssignPlanInputAuthorityStateIdAction`

- **Input:** current workflow/specification revision, optional prior plan-input authority,
  validated current feature `StateIdLedger`, and matching single-use namespace capability
- **Output:** plan-input-authority reservation plus successor ledger
- **Responsibility:** Reserve one immutable state revision and commit it before any plan model
  call.

## `ResolvePlanInputAuthorityStatePathAction`

- **Input:** plan-input state identity and workflow `PlanInputAuthorityStateCollection` root
- **Output:** versioned engine-owned child path
- **Responsibility:** Derive one contained immutable state path; accept no path from model,
  user, reference, or config.

## `BuildPlanInputAuthorityStateAction`

- **Input:** identity/parent, exact
  bootstrap/feature-request/reference/normalized-specification/spec-ID/acknowledgement/provenance/passive/clarification/principle-selection/repository-fact/baseline-file/research-evidence
  authorities, and current plan ID ledger
- **Output:** plan-input-authority candidate
- **Responsibility:** Bundle every ID/value that a plan route or `PNN` may cite; perform no
  generation and accept no partial `PlanState`.

## `BuildSpecificationAcknowledgementRetirementPlanInputAuthorityAction`

- **Input:** next plan-input-authority identity, validated current planning input,
  retirement-only acknowledgement state, and its exactly rebound provenance state
- **Output:** retirement-rebound plan-input-authority candidate
- **Responsibility:** Copy every business, repository, file, research, principle, clarification,
  bootstrap, passive, and plan-ID-ledger value byte-for-byte; advance only
  identity/revision/parent and replace the embedded acknowledgement/provenance pair.

## `ValidatePlanInputAuthorityStateAction`

- **Input:** candidate, optional prior revision, all bound canonical authorities/adapters, and
  plan-stage citation policy
- **Output:** plan-input-authority evidence
- **Responsibility:** Prove current revisions, normalized editable-spec round trip, complete
  repository/file/research/principle joins, monotonic research/plan IDs, and no citation outside
  the durable bundle.

## `SerializePlanInputAuthorityStateAction`

- **Input:** validated plan-input authority and canonical serializer contract
- **Output:** canonical plan-input bytes
- **Responsibility:** Serialize the complete immutable input bundle at its engine-derived child
  path.

## `ParsePlanInputAuthorityStateAction`

- **Input:** bounded canonical child bytes and recorded serializer contract
- **Output:** unvalidated plan-input authority
- **Responsibility:** Parse one persisted revision without trusting any nested state/record ID.

## `BuildPlanStateAction`

- **Input:** plan-state identity, validated plan IR/final plan-ID ledger, exact validated
  plan-input authority, complete
  file/grant/dependency-mutation/source-reference/contract-view/review-unit registries
- **Output:** validated plan-state candidate
- **Responsibility:** Construct one complete canonical plan wrapper with no duplicated file or
  reference authority and bind the exact precommitted plan-input state.

## `SerializeCanonicalPlanStateAction`

- **Input:** validated `PlanState`
- **Output:** canonical plan-state bytes
- **Responsibility:** Serialize one complete canonical plan state.

## `AssignTaskDefinitionStateIdAction`

- **Input:** validated task graph, validated current feature `StateIdLedger`, and matching
  single-use namespace capability
- **Output:** task-definition-state reservation plus successor ledger
- **Responsibility:** Reserve one engine-owned immutable definition ID.

## `BuildTaskDefinitionStateAction`

- **Input:** definition identity, exact input `PlanState`, validated
  obligation/shared-resource/task-file-capability registries, canonical graph, and
  fact-transition bindings
- **Output:** validated task-definition-state candidate
- **Responsibility:** Copy every restart authority and construct one complete immutable
  task-definition wrapper.

## `SerializeTaskDefinitionStateAction`

- **Input:** validated `TaskDefinitionState`
- **Output:** canonical task-definition bytes
- **Responsibility:** Serialize one immutable approved definition state.

## `AssignRuntimeFileStateIdAction`

- **Input:** task-definition/plan scope, optional prior runtime-file-state ID, validated current
  feature `StateIdLedger`, and matching single-use namespace capability
- **Output:** runtime-file-state reservation plus successor ledger
- **Responsibility:** Reserve one engine-owned state ID without hashing file content.

## `BuildInitialRuntimeFileStateAction`

- **Input:** runtime-file-state identity, exact approved `PlanState` file registry/grants, and
  current contained workspace metadata
- **Output:** revision-zero runtime-file state
- **Responsibility:** Initialize every registered file's current existence/descriptor revision
  and prove it agrees with the plan baseline.

## `ValidateRuntimeFileStateAction`

- **Input:** runtime-file state, immutable file registry, current overlay/workspace metadata,
  and optional transition registry
- **Output:** runtime-file-state evidence
- **Responsibility:** Prove total file-ID coverage, descriptor joins, revision, and transition
  chain.

## `SerializeRuntimeFileStateAction`

- **Input:** validated runtime-file state
- **Output:** canonical runtime-file-state bytes
- **Responsibility:** Serialize the current cross-task file lifecycle authority.

## `ParseRuntimeFileStateAction`

- **Input:** raw canonical runtime-file-state bytes
- **Output:** unvalidated runtime-file state
- **Responsibility:** Parse one persisted revision only.

## `AssignExecutionEvidenceRegistryStateIdAction`

- **Input:** task-definition identity, optional prior evidence-state ID, validated current
  feature `StateIdLedger`, and matching single-use namespace capability
- **Output:** evidence-registry reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry-revision ID.

## `BuildInitialExecutionEvidenceRegistryAction`

- **Input:** evidence-registry identity and task-definition identity
- **Output:** empty revision-zero evidence registry
- **Responsibility:** Create the durable execution evidence/diagnostic authority with an
  embedded ID ledger whose two ordinals start at one and tombstones are empty.

## `AssignVerificationEvidenceIdAction`

- **Input:** either one validated automated result, or one validated manual submission together
  with its exact authenticated manual-verification binding, plus the current prospective
  execution-evidence ID ledger
- **Output:** verification-evidence identity plus successor ID ledger
- **Responsibility:** Allocate one monotonic evidence ID only after all result-kind
  prerequisites (including manual authentication) exist, advance only `nextEvidenceOrdinal`, and
  leave result/binding content unchanged.

## `BuildVerificationEvidenceRecordAction`

- **Input:** evidence identity, one closed `ValidatedAutomatedVerificationResult` or validated
  manual result, and exact predicate/authority joins
- **Output:** verification-evidence record
- **Responsibility:** Bind the complete typed command/copy/operation/file-delta or
  actor/scenario result; raw exit/output/validator observations have no valid record variant.

## `ValidateVerificationEvidenceRecordAction`

- **Input:** one built record, current command/operation/copy/task/predicate authorities, and
  its exact safety/disposition observations
- **Output:** verification-evidence evidence
- **Responsibility:** Prove every scope/revision/result/predicate join and that only a validated
  success or exact expected-red outcome became evidence.

## `AssignExecutionDiagnosticRecordIdAction`

- **Input:** one validated engine diagnostic and current prospective execution-evidence ID
  ledger
- **Output:** execution-diagnostic identity plus successor ID ledger
- **Responsibility:** Allocate one monotonic diagnostic-record ID and advance only
  `nextDiagnosticRecordOrdinal`.

## `BuildExecutionDiagnosticRecordAction`

- **Input:** assigned identity, one engine diagnostic, its typed command-process or validator
  source outcome, and task/operation/command context
- **Output:** execution-diagnostic record
- **Responsibility:** Persist one typed diagnostic without changing its code/severity/repair
  class or treating raw output as evidence.

## `BuildNextExecutionEvidenceRegistryAction`

- **Input:** next state identity, validated prior registry, ordered new evidence/diagnostic
  records, and exact final prospective ID ledger
- **Output:** successor evidence-registry candidate
- **Responsibility:** Append immutable records and bind the batch's final allocator/tombstones
  without allocating or reusing identity.

## `ValidateExecutionEvidenceRegistryAction`

- **Input:** evidence registry, task definitions/predicates, command/validator registries, and
  prior revision
- **Output:** evidence-registry evidence
- **Responsibility:** Prove unique/monotonic IDs, resolvable predicate/diagnostic joins,
  immutable history, and no orphan evidence.

## `SerializeExecutionEvidenceRegistryAction`

- **Input:** validated execution-evidence registry
- **Output:** canonical evidence bytes
- **Responsibility:** Serialize one durable evidence revision.

## `ParseExecutionEvidenceRegistryAction`

- **Input:** raw canonical evidence bytes
- **Output:** unvalidated evidence registry
- **Responsibility:** Parse one persisted evidence revision only.

## `BuildInitialTaskRuntimeStateAction`

- **Input:** one task-definition state, validated revision-zero runtime-file state, and empty
  execution-evidence registry
- **Output:** initial runtime-state candidate
- **Responsibility:** Create pending task records at revision zero and bind both current
  authority IDs/revisions.

## `SerializeTaskRuntimeStateAction`

- **Input:** task definition ID, runtime revision/records, and exact current
  runtime-file/evidence registry IDs/revisions
- **Output:** canonical task-runtime bytes
- **Responsibility:** Serialize one mutable runtime revision.

## `ValidateGeneratedViewAction`

- **Input:** generated view, bound canonical wrapper, exact
  workflow-artifact/file/passive-literal registries, required reference snapshot, and recorded
  renderer contract
- **Output:** view-consistency evidence
- **Responsibility:** Validate every state binding and selector/path ownership, re-resolve typed
  references, rerender, and compare exact bytes.

## `AssignTaskIdsAction`

- **Input:** validated topologically ordered proposal internal keys
- **Output:** internal-key-to-`TNNN` map
- **Responsibility:** Assign canonical IDs before definition construction.

## `BuildRequirementIndexAction`

- **Input:** validated specification IR
- **Output:** typed requirement index
- **Responsibility:** Project acceptance-criterion, functional-requirement, edge-case,
  business-rule, and assumption/non-goal/prohibited-behavior records into their closed variants;
  `requirementId` is the unchanged engine-assigned specification record ID and no generic
  `Requirement` or new identity is invented.

## `AssignResearchEvidenceRegistryStateIdAction`

- **Input:** plan-input authority IDs, validated current feature `StateIdLedger`, and matching
  single-use namespace capability
- **Output:** research-evidence-registry reservation plus successor ledger
- **Responsibility:** Reserve one engine-owned state ID without hashing evidence.

## `AssignResearchEvidenceIdAction`

- **Input:** one validated evidence proposal, current plan ID ledger, and evidence order
- **Output:** research-evidence identity plus next ledger
- **Responsibility:** Assign one monotonic engine-owned evidence ID without capturing content.

## `BuildResearchEvidenceRecordAction`

- **Input:** evidence identity, one validated feature/reference/repository/principle/parser/user
  authority, and bounded source location/value
- **Output:** research-evidence record
- **Responsibility:** Bind one existing internal authority to the assigned evidence ID;
  principle evidence identifies an exact raw source span.

## `BuildRegistryAdapterResearchEvidenceAction`

- **Input:** evidence identity, one policy-authorized version-pinned read-only adapter result,
  trust/expiry evidence, and bounded captured value
- **Output:** registry-adapter evidence record
- **Responsibility:** Capture external evidence under the assigned ID without permitting a
  command, dependency mutation, or model-authored endpoint.

## `BuildResearchEvidenceRegistryAction`

- **Input:** registry identity, exact bootstrap/feature/provenance/passive/reference bindings,
  and ordered evidence records
- **Output:** research-evidence-registry candidate
- **Responsibility:** Assemble one closed plan-local evidence authority.

## `ValidateResearchEvidenceRegistryAction`

- **Input:** registry candidate and all bound canonical states/adapters
- **Output:** research-evidence-registry evidence
- **Responsibility:** Prove every ID/owner/subject/location/trust/expiry join, unique ordering,
  and no orphan or expired record.

## `ValidateResearchDecisionEvidenceAction`

- **Input:** one research-decision proposal, unit-local evidence allowlist, and exact
  research-evidence registry
- **Output:** decision-evidence evidence
- **Responsibility:** Require every evidence ID to resolve and be authorized;
  `unresolvedExternalEvidence=true` blocks plan approval, and false requires the configured
  minimum evidence.

## `AssignObligationLedgerStateIdAction`

- **Input:** exact plan-state input identity, validated current feature `StateIdLedger`, and
  matching single-use namespace capability
- **Output:** obligation-ledger reservation plus successor ledger
- **Responsibility:** Reserve one engine-owned ledger state ID.

## `BuildTypedObligationAction`

- **Input:** one exact specification/reference/plan source record and its typed obligation rule
- **Output:** one obligation
- **Responsibility:** Project one source-owned obligation variant without semantic regrouping.

## `BuildObligationLedgerAction`

- **Input:** ledger identity, spec/reference/plan registries, and all typed projections
- **Output:** full obligation ledger candidate
- **Responsibility:** Assemble every public/internal obligation under one namespace.

## `ValidateObligationLedgerCompletenessAction`

- **Input:** ledger candidate and exact required upstream registries
- **Output:** obligation-ledger evidence
- **Responsibility:** Prove one-to-one projection of requirements, visible states, exact copies,
  scope/non-goals/prohibitions,
  data/contracts/research/quickstart/accessibility/responsive/visual/value-treatment/coverage/repository
  prerequisites, with no omission/duplicate.

## `ValidateTraceReferenceAction`

- **Input:** one downstream source/obligation ID and ledger
- **Output:** reference evidence
- **Responsibility:** Validate one trace reference exists.

## `ValidateObligationCoverageAction`

- **Input:** one obligation and downstream records
- **Output:** coverage evidence/diagnostic
- **Responsibility:** Apply one obligation's typed coverage rule.

## `ValidateArtifactDecisionProposalAction`

- **Input:** one artifact-decision proposal and plan facts
- **Output:** applicability evidence
- **Responsibility:** Validate one kind/disposition/reason without accepting a path.

## `BuildArtifactDecisionAction`

- **Input:** validated proposal and workflow artifact registry
- **Output:** canonical artifact decision
- **Responsibility:** Copy the engine-owned file path for singleton views or `contracts/`
  collection root for contract views, with explicit path role.

## `ValidatePlanUnitProposalAction`

- **Input:** one operation-result-valid plan-unit proposal and unit descriptor
- **Output:** plan-unit evidence
- **Responsibility:** Validate the closed unit payload and local ID allowlists only.

## `ResolveExistingPlanFileSelectionAction`

- **Input:** one validated existing file ID and current file registry/unit scope
- **Output:** existing-file selection evidence
- **Responsibility:** Resolve one already registered record without allocating or mutating a
  registry.

## `ResolvePlannedPathCandidateSelectionAction`

- **Input:** one validated selected path-candidate ID, intent key, and path-candidate registry
- **Output:** accepted absent candidate
- **Responsibility:** Resolve one create candidate without assigning a file ID or checking
  another candidate.

## `JoinPlanFileSelectionAction`

- **Input:** one proposal key and exactly one existing/planned file record produced by the
  ordinary file pipeline
- **Output:** keyed canonical file selection
- **Responsibility:** Bind one proposal-local key to one file ID; allocate nothing and reject
  duplicate key ownership.

## `ValidatePlanIntentCapabilitySelectionAction`

- **Input:** one planned intent/requested capability set, file-intent-capability registry,
  file-kind ceiling, and global delete/copy policies
- **Output:** intent-capability evidence
- **Responsibility:** Enforce required-all/required-at-least-one/implication/sequence rules and
  reject unimplementable read-only updates or incoherent copy/create/replace sets.

## `BuildPlanFileGrantAction`

- **Input:** one resolved file selection, intent-capability evidence, file record, compiled
  kind/policy ceiling, and global delete policy
- **Output:** validated plan-file grant
- **Responsibility:** Require present existing IDs for read/update/delete, absent plan-declared
  IDs for create, and copy the exact authorized capability subset without mutating file
  authority.

## `ValidatePlanFileGrantCompletenessAction`

- **Input:** materialized implementation shape, touched/proposed/dependency-mutation file
  projections, and all grants
- **Output:** file-grant evidence
- **Responsibility:** Prove every selected/dependency file has exactly one compatible grant, no
  grant is orphaned, and all projections are exact.

## `AssignDependencyMutationSurfaceRegistryStateIdAction`

- **Input:** plan scope, validated current feature `StateIdLedger`, and matching single-use
  namespace capability
- **Output:** dependency-mutation-surface-registry reservation plus successor ledger
- **Responsibility:** Reserve one engine-owned registry ID.

## `AssignDependencyMutationSurfaceIdAction`

- **Input:** one validated dependency proposal, current plan ID ledger, and deterministic
  dependency order
- **Output:** mutation-surface identity plus next ledger
- **Responsibility:** Allocate one engine-owned surface ID without constructing the surface.

## `ResolveDependencyLockfileAction`

- **Input:** validated dependency proposal, project/package-manager facts, preset lockfile
  policy, path-intent-option registry, and current file registry
- **Output:** typed existing/required-absent/none lockfile resolution
- **Responsibility:** Resolve an existing `fileId`, report one required absent lockfile with the
  exact option/template/name-source IDs and fixed `[create]` capability, or prove none; never
  derive a path or mutate a ledger.

## `BuildDependencyLockfilePathIntentAction`

- **Input:** one required-absent resolution, engine-assigned path-intent key, and dependency
  proposal key
- **Output:** closed dependency-lockfile path intent
- **Responsibility:** Preserve the policy-selected option, required template, name source, and
  fixed create capability for the ordinary enumeration/path-validation pipeline; assign no
  candidate/file ID and admit no generic missing field.

## `BuildDependencyLockfileSelectionAction`

- **Input:** one existing resolution or ordinary-pipeline planned file record and matching
  dependency proposal
- **Output:** canonical existing/create/none lockfile selection
- **Responsibility:** Join one proven result to the dependency key without building a grant,
  registry, or implementation-shape projection.

## `BuildDependencyLockfileGrantAction`

- **Input:** materialized absent lockfile record, file-intent-capability evidence, file-kind
  ceiling, and global policy
- **Output:** validated create grant
- **Responsibility:** Build only the create/copy/replace capability grant required by the
  dependency command.

## `BuildDependencyMutationFileProjectionAction`

- **Input:** dependency proposal, exact manifest/lockfile records, setup design unit, and
  validated grants
- **Output:** dependency-mutation file projection
- **Responsibility:** Project existing manifest/lockfile IDs into touched files and absent
  lockfile IDs into proposed files/implementation shape.

## `MergeDependencyMutationFileProjectionAction`

- **Input:** current plan candidate and one validated projection
- **Output:** next plan candidate
- **Responsibility:** Union the dependency file IDs exactly once before
  implementation-shape/file-grant completeness checks.

## `BuildDependencyMutationSurfaceAction`

- **Input:** surface identity, one validated dependency proposal, exact manifest/lockfile
  result, and compatible command descriptors
- **Output:** dependency-mutation surface
- **Responsibility:** Bind every file/command that the later setup task may mutate without
  assigning identity.

## `BuildDependencyMutationSurfaceRegistryAction`

- **Input:** registry identity, ordered built surfaces, and final file-registry identity
- **Output:** mutation-surface registry candidate
- **Responsibility:** Assemble exactly one registry without validating it.

## `ValidateDependencyMutationSurfaceRegistryAction`

- **Input:** registry candidate, all dependency proposals, final file registry/grants, and
  command/dependency policies
- **Output:** validated mutation-surface registry
- **Responsibility:** Prove one surface per proposal and matching manifest/lockfile
  create/update grants/capabilities; reject a dependency whose required setup task would be
  impossible.

## `BuildInitialPlanIdLedgerAction`

- **Input:** enabled plan record kinds
- **Output:** empty plan ID ledger
- **Responsibility:** Initialize monotonic
  design-unit/entity/field/contract/scenario/research-evidence/research-decision/dependency/mutation-surface/path-candidate/review-unit
  allocators and all tombstones.

## `ValidatePlanLocalKeyAction`

- **Input:** one proposal-local key, key kind, and unit scope
- **Output:** local-key evidence
- **Responsibility:** Apply the closed grammar and prove uniqueness without treating the key as
  canonical identity.

## `BuildPlanProposalIndexAction`

- **Input:** all validated
  implementation-shape/data-model/contract/quickstart/research/dependency/coverage proposals
- **Output:** complete local-key index
- **Responsibility:** Join qualified keys to their proposal records and reject duplicate
  ownership.

## `ValidatePlanProposalReferenceAction`

- **Input:** one local-key or allowed upstream-ID reference and complete proposal/upstream index
- **Output:** proposal-reference evidence
- **Responsibility:** Resolve design/entity/relationship/scenario/obligation references without
  assigning IDs.

## `AssignPlanRecordIdsAction`

- **Input:** complete valid proposal index and current plan ID ledger
- **Output:** plan-local key map and next ledger
- **Responsibility:** Sort each kind by closed kind rank plus Unicode-scalar qualified key and
  assign monotonic engine IDs.

## `BuildImplementationShapeAction`

- **Input:** validated implementation-shape proposal, resolved file IDs, and key map
- **Output:** canonical implementation shape
- **Responsibility:** Replace unit keys with engine design-unit IDs and preserve validated
  prose/file IDs.

## `BuildDataModelIRAction`

- **Input:** validated data-model proposal and key map
- **Output:** canonical data-model IR
- **Responsibility:** Replace entity/field/relationship keys with engine IDs without changing
  business content.

## `ValidateContractProposalBodyAction`

- **Input:** one `ContractValueProposal`, exact registered schema/version, identifier grammars,
  unit file/source/passive/endpoint allowlists, and superset path-token grammar
- **Output:** schema-validated contract value
- **Responsibility:** Validate the complete closed shape and each typed leaf; reject raw
  path/URI-shaped identifiers and unresolved authority IDs.

## `BuildContractIRAction`

- **Input:** one contract proposal with schema-validated body and key map
- **Output:** canonical contract IR
- **Responsibility:** Replace its contract key with one engine ID and retain the
  validator-produced body.

## `BuildQuickstartScenarioAction`

- **Input:** one validated scenario proposal, key map, and validated command/requirement/file
  references
- **Output:** canonical quickstart scenario
- **Responsibility:** Replace the scenario key with one engine ID and retain only validated
  selections.

## `BuildResearchDecisionAction`

- **Input:** one evidence-valid research proposal and key map
- **Output:** canonical research decision
- **Responsibility:** Replace its decision key with one engine ID without changing validated
  evidence/content.

## `ValidateDependencyProposalPolicyAction`

- **Input:** one dependency proposal, project/manifest/file registries, compiled ecosystem
  package-name/version grammar, configured registry-source authority, and dependency policy
- **Output:** dependency-policy evidence
- **Responsibility:** Resolve the allowlisted target project and its exact manifest file ID,
  then validate registry source, ecosystem compatibility, package identity, version constraint,
  scope, duplication, and allow/deny policy without installing anything.

## `BuildDependencyPlanRecordAction`

- **Input:** one validated dependency proposal, its exact mutation-surface ID, and key map
- **Output:** canonical dependency record
- **Responsibility:** Replace its dependency key with one engine ID and bind the validated
  project/manifest/lockfile mutation authority.

## `ValidateEvidenceExpectationProposalAction`

- **Input:** one plan-stage evidence expectation and plan-known command/file/parser/scenario
  registries
- **Output:** expectation evidence
- **Responsibility:** Validate only plan-known authorities; task IDs and task-bound predicates
  are schema-impossible.

## `BuildEvidenceExpectationAction`

- **Input:** one validated expectation proposal and plan key map
- **Output:** canonical evidence expectation
- **Responsibility:** Resolve scenario/command references without creating a task predicate.

## `BuildCoverageEntryAction`

- **Input:** one validated coverage proposal, canonical expectations, key map, and obligation
  registry
- **Output:** canonical coverage entry
- **Responsibility:** Resolve design-unit/scenario keys and upstream IDs exactly.

## `AssignSourceReferenceAuthorityRegistryStateIdAction`

- **Input:** final plan/file/dependency/contract/passive authority IDs, validated current
  feature `StateIdLedger`, and matching single-use namespace capability
- **Output:** source-reference-authority-registry reservation plus successor ledger
- **Responsibility:** Reserve one plan-local registry ID.

## `BuildSourceReferenceAuthorityRegistryAction`

- **Input:** registry identity, existing dependency facts, planned dependencies, file registry,
  canonical contracts/endpoints/resources/external-endpoint policy, and passive registry
- **Output:** source-reference-authority candidate
- **Responsibility:** Assemble every source-code reference target without resolving source
  occurrences.

## `ValidateSourceReferenceAuthorityRegistryAction`

- **Input:** authority candidate and exact bound registries/policies
- **Output:** source-reference-authority evidence
- **Responsibility:** Prove total/unique IDs and source joins, package grammars, endpoint
  scheme/host/operation rules, resource ownership, and inert-only passive targets.

## `BuildContractViewRegistryAction`

- **Input:** canonical contracts, workflow contract collection root, schema-to-extension table,
  and renderer contract
- **Output:** contract-view registry candidate
- **Responsibility:** Allocate each view path solely from engine contract ID plus registered
  extension.

## `ValidateContractViewRegistryAction`

- **Input:** contract-view registry candidate, canonical contracts, workflow root, and
  portability policy
- **Output:** contract-view evidence
- **Responsibility:** Prove total one-to-one coverage, containment, extension/schema agreement,
  and no host/target collision.

## `AssignPlanReviewUnitRegistryStateIdAction`

- **Input:** plan scope, validated current feature `StateIdLedger`, and matching single-use
  namespace capability
- **Output:** review-unit-registry reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry state ID.

## `AssignPlanReviewUnitIdAction`

- **Input:** one canonically ordered reviewable plan record and current plan ID ledger
- **Output:** identified review-unit selector plus next ledger
- **Responsibility:** Retain fixed selectors or assign one monotonic review-unit ID without
  prose matching.

## `BuildPlanReviewUnitRegistryAction`

- **Input:** registry identity and all identified review-unit selectors
- **Output:** review-unit registry candidate
- **Responsibility:** Assemble the complete registry without assigning IDs.

## `ValidatePlanReviewUnitRegistryAction`

- **Input:** review-unit registry candidate and canonical plan
- **Output:** review-unit evidence
- **Responsibility:** Prove every reviewable record has exactly one stable selector and no
  orphan target.

## `MergePlanUnitAction`

- **Input:** one validated/materialized unit and current plan candidate
- **Output:** next plan candidate
- **Responsibility:** Insert one unit by its closed kind and reject duplicate singleton
  ownership.

## `ValidatePlanCandidateCompletenessAction`

- **Input:** assembled plan candidate and artifact applicability policy
- **Output:** plan-completeness evidence
- **Responsibility:** Prove every required unit and required artifact payload is present exactly
  once.

## `BuildPlanIRAction`

- **Input:** complete validated plan candidate
- **Output:** canonical plan IR
- **Responsibility:** Construct one plan authority without assigning state identity.

## `RenderSpecificationAction`

- **Input:** validated specification IR, exact passive-literal registry state, required bound
  reference snapshot, and renderer contract
- **Output:** Markdown candidate
- **Responsibility:** Render `spec.md`, resolving passive display nodes and exact-copy tokens
  only from bound authorities.

## `RenderPlanArtifactAction`

- **Input:** validated `PlanState`, artifact selector, exact passive-literal registry state,
  required bound reference snapshot, and renderer contract
- **Output:** Markdown/data candidate
- **Responsibility:** Render one plan output while resolving file/source/passive nodes from the
  state's exact registries/snapshot.

## `RenderTasksAction`

- **Input:** task definition state, task runtime revision, input `PlanState` file registry,
  exact passive-literal registry state, required bound reference snapshot, and renderer contract
- **Output:** Markdown candidate
- **Responsibility:** Render definitions, controlled source/path/passive labels, and
  engine-owned checkbox/runtime projection.

## `BuildGeneratedViewAction`

- **Input:** artifact selector, rendered bytes, exact canonical-state binding, workflow artifact
  registry, optional exact `ContractViewRegistry`, and renderer contract version
- **Output:** generated-view candidate
- **Responsibility:** Resolve singleton paths from workflow authority or a contract selector
  from its bound per-contract registry, then construct one complete read-only view without
  writing it.

## `ValidateEditableSpecificationRenderAction`

- **Input:** rendered `spec.md` and specification IR
- **Output:** round-trip evidence
- **Responsibility:** Reparse only the editable specification and compare normalized IR.

## `BuildEditableSpecificationViewAction`

- **Input:** validated rendered bytes, exact
  specification/provenance/acknowledgement/clarification/passive/reference bindings, workflow
  artifact registry, and renderer contract
- **Output:** editable-specification-view candidate plus its exact
  `EditableSpecificationViewAuthorityBinding` projection
- **Responsibility:** Bind the engine-owned `spec.md` path and protected-structure contract, and
  project every non-content field a later edit must echo, without writing or treating later
  edits as canonical.

## `ValidateEditableSpecificationViewAction`

- **Input:** editable-view candidate and every bound canonical authority
- **Output:** editable-view evidence
- **Responsibility:** Prove selector/path/editability, exact state joins, renderer version,
  protected structure, and round-trip IR before output preparation.

## `CaptureReviewSubmissionAction`

- **Input:** raw review event and runner-held submission/authentication-lease table
- **Output:** immutable run-local review-submission handle/candidate
- **Responsibility:** Capture expected workflow revision, exact plan/task target, decision,
  bounded feedback bytes, and target-unit IDs; keep the lease opaque and perform no
  authentication or durable ID assignment.

## `ValidateReviewSubmissionAction`

- **Input:** captured review submission, current
  workflow/plan-or-task/review-unit/review-decision authorities, text policy, and review policy
- **Output:** validated review submission or stale/structural diagnostic
- **Responsibility:** Before authentication, prove exact target/current workflow revision,
  stage-compatible approve/reject shape, complete valid target-unit references, and canonicalize
  bounded feedback into durable `BusinessText`; raw invocation handles cannot survive.

## `BindAuthenticatedReviewSubmissionAction`

- **Input:** validated review submission and validated fresh actor evidence for its exact
  plan/tasks review kind
- **Output:** authenticated review-submission binding
- **Responsibility:** Bind submission ID, target/decision, actor/evidence, and event kind after
  freshness validation; assign no decision ID.

## `AssignReviewDecisionIdAction`

- **Input:** authenticated review-submission binding, unchanged validated review submission, and
  current review-decision registry
- **Output:** reserved review-decision allocation
- **Responsibility:** Reserve the exact next monotonic ID only after authentication is bound,
  and return its input revision/ordinal/next-ordinal delta without building a decision.

## `AssignReviewSubmissionIdAction`

- **Input:** reserved review-decision ID and compiler-locked singleton `review` slot
- **Output:** owner-local review-submission identity
- **Responsibility:** Construct `(reviewDecisionId, review)` after decision allocation; consume
  no second ledger or caller/model scalar.

## `BuildReviewDecisionAction`

- **Input:** decision/submission identities, authenticated review-submission binding, unchanged
  validated review submission with canonical feedback, and exact plan/task-definition target ID
- **Output:** review-decision candidate
- **Responsibility:** Build one actor-bound approve/reject record carrying only durable text and
  the owner-local submission ID.

## `ValidateReviewDecisionAction`

- **Input:** decision candidate, current target/review-unit/actor authorities, and review policy
- **Output:** review-decision evidence
- **Responsibility:** Prove target/revision freshness, actor-evidence equality, allowed targeted
  feedback, and approve/reject shape.

## `AssignReviewDecisionRegistryStateIdAction`

- **Input:** feature ID, optional prior review registry, validated current feature
  `StateIdLedger`, and matching single-use namespace capability
- **Output:** review-registry-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry revision ID.

## `BuildInitialReviewDecisionRegistryAction`

- **Input:** feature ID and revision-zero state identity
- **Output:** empty review-decision registry
- **Responsibility:** Initialize next decision ordinal to one and no active approvals.

## `AppendReviewDecisionAction`

- **Input:** validated prior registry, next state identity, exact reserved allocation, and one
  validated matching decision
- **Output:** next review-decision registry candidate
- **Responsibility:** Compare-and-swap the allocator delta, append immutable history, and
  consume the reservation; approval activity is projected by the same complete review output
  into `WorkflowState.activeApprovalDecisionIds`.

## `RetireReviewDecisionAllocationAction`

- **Input:** validated prior registry, next state identity, exact reserved allocation, and
  terminal construction/validation diagnostic
- **Output:** next review-decision registry candidate with tombstone
- **Responsibility:** Consume one failed reservation by advancing the ordinal and adding its ID
  to `retiredReviewDecisionIds`; never append a decision or reuse the ID.

## `ValidateReviewDecisionRegistryAction`

- **Input:** candidate, optional prior registry, current plan/task definitions, actor registry,
  and invalidation records
- **Output:** review-registry evidence
- **Responsibility:** Prove append-only unique IDs, monotonic allocation, target/actor joins,
  and that every workflow-active or invalidated approval decision ID resolves; rework never
  mutates old decision history.

## `ParseReviewDecisionRegistryAction`

- **Input:** raw canonical review-state bytes
- **Output:** unvalidated review-decision registry
- **Responsibility:** Parse one persisted review-registry revision without treating its
  decisions as active approvals.

## `SerializeReviewDecisionRegistryAction`

- **Input:** validated review-decision registry
- **Output:** canonical review-state bytes
- **Responsibility:** Serialize review history without credentials or free-standing approval
  booleans.

## `ValidateReviewApprovalAction`

- **Input:** plan state ID or task-definition state ID, validated current review-decision
  registry, and workflow active-approval projection
- **Output:** approval authorization
- **Responsibility:** Require one workflow-active approve decision whose registry record exactly
  targets the current immutable definition state and is absent from every applicable
  invalidation record.

## `AssignWorkflowControlEventRegistryStateIdAction`

- **Input:** feature ID, optional prior control registry, validated current feature
  `StateIdLedger`, and matching single-use namespace capability
- **Output:** control-event-registry-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry revision ID.

## `BuildInitialWorkflowControlEventRegistryAction`

- **Input:** feature ID and revision-zero state identity
- **Output:** empty workflow-control-event registry
- **Responsibility:** Initialize final-validation/rework/evidence-invalidation ordinals to one
  and all event/tombstone sets empty.

## `BuildWorkflowControlEventAppendSequenceAction`

- **Input:** one closed `StageTransitionKind`, its versioned control-event-append policy, and
  validated candidate records
- **Output:** ordered control-event append descriptors
- **Responsibility:** Before output construction, derive the exact set/order only: final
  failure/completion appends one final record; localized remediation appends one evidence
  invalidation; reference-revision/rework/reconciliation appends rework invalidation then
  optional/required evidence invalidation; specification-acknowledgement ID retirement and other
  non-control mutations produce the locked empty sequence.

## `AppendWorkflowControlEventAction`

- **Input:** validated prior registry, next state identity, next matching namespace ledger, and
  exactly one validated final-validation/rework/evidence-invalidation record
- **Output:** next workflow-control-event registry candidate
- **Responsibility:** Append one immutable control event and advance only its namespace; build
  or validate no event.

## `ValidateWorkflowControlEventRegistryAction`

- **Input:** candidate, optional prior registry, workflow/task/evidence/review authorities, and
  all referencing output/state records
- **Output:** control-event-registry evidence
- **Responsibility:** Prove append-only histories, unique monotonic IDs/tombstones, every event
  join, and that active workflow final/rework pointers resolve exactly.

## `ParseWorkflowControlEventRegistryAction`

- **Input:** raw canonical control-event bytes
- **Output:** unvalidated control-event registry
- **Responsibility:** Parse one persisted registry revision only.

## `SerializeWorkflowControlEventRegistryAction`

- **Input:** validated control-event registry
- **Output:** canonical control-event bytes
- **Responsibility:** Serialize restart-safe final-validation and invalidation history.

## `MapReviewFeedbackAction`

- **Input:** rejected review feedback and unit registry
- **Output:** targeted feedback records
- **Responsibility:** Resolve feedback to explicit plan/task unit IDs.

## `InvalidateDescendantStateAction`

- **Input:** authorized rework transition and state graph
- **Output:** invalidated-state delta
- **Responsibility:** Invalidate declared descendant states/approvals only.


For a complete workflow output that needs two control events, the orchestrator statically invokes `AppendWorkflowControlEventAction` twice against successive in-memory registry candidates in the sequence above. Only the final validated registry revision is prepared with the complete output set. The intermediate candidate is neither persisted nor externally visible; validators prove both parent links and require the output set's event records to equal the exact appended suffix.
