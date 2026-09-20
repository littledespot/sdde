# 16. Reference ingestion and normalization

Part of the [proposed design](../design.md#16-reference-ingestion-and-normalization). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

“Reference requirements in any format” is implemented as an extensible reader system, not as a promise to interpret arbitrary bytes. The invariant is that no reference is silently ignored.

### 16.1 Reader contract

[View the Reference reader contract sample](../code.md#reference-reader-contract).

Initial readers should cover:

- plain text and Markdown;
- JSON, YAML, XML, CSV, and other tabular data;
- source code and stylesheet formats;
- PDF;
- common office documents;
- raster images through deterministic OCR/layout decoders where installed;
- a declared opaque-binary adapter only when a purpose-built extractor exists.

- Encrypted, corrupted, unsupported, oversized, unreadable, or budget-terminated inputs produce
  explicit diagnostics.
- Traversal is capability-bounded by entry count, depth, time, and memory before decoding;
  readers are sandbox-bounded by source and decoded bytes, time, memory, blocks, pages, cells,
  and archive depth/count/expansion when an archive reader is enabled.
- Source and decoded byte totals also have corpus ceilings.
- The engine enforces each corpus ceiling with a revisioned reservation/debit ledger, so
  parallel readers cannot each observe the same remaining allowance.
- A decoder receives at most the lesser of its per-file limit and its committed ledger
  reservation and must terminate at that boundary.
- Adapters must terminate before a hard bound is exceeded; post-run telemetry validators are
  defense in depth, not the primary resource boundary.

- Enumeration records every encountered regular file, hidden entry, and symlink before policy
  filtering.
- In v1 `references.followSymlinks` is schema-constant `false`: a symlink receives an explicit
  non-followed classification and its target is never traversed.
- For an included regular file, the engine opens one no-follow descriptor, validates its
  metadata, reserves its reported length, and captures the bytes into a write-once state blob
  through that same descriptor.
- A changed identity/length, short/long read, special-file transition, or reservation overrun
  blocks the entry and requires fresh inventory; MIME sniffing, reader probing, decoding, source
  mapping, and citation validation consume only that immutable blob.
- They never reopen the reference path.
- This closes the inventory/read time-of-check-to-time-of-use boundary without hashes.

- `ReferenceEntry` is a status-discriminated union: decoded/empty entries require media type,
  exact decoder version, blocks, and diagnostics; a decoded entry has at least one fully
  accounted block and an empty entry has none plus positive empty-file evidence.
- Excluded entries have no blocks, require an exclusion record, and forbid a fabricated decoder;
  unsupported and failed entries likewise have no decoded blocks and record only what was
  actually detected/attempted.
- Readability/source-size/source-capture/reader-selection/decode-budget rejection creates a
  `blocked` entry with the exact phase; a reader-rank tie is therefore representable and cannot
  vanish into manifest diagnostics alone.
- Corpus/traversal failures create manifest blocking diagnostics and prevent snapshot commit.
- In v1, an exclusion record contains only an exact compiled configuration-policy
  rule/reason/evidence binding with `actor: policy`; a preactivation user-acceptance event is
  not representable because no feature actor registry exists yet.
- The user must update reviewed project policy and rerun.
- Any exclusion without that durable policy acceptance blocks `allEntriesAccountedFor`;
  blocked/unsupported/failed entries block under the default hardened policy.
- “Best effort and silently continue” is prohibited.

- Reader selection is deterministic and version-pinned.
- Configuration names exact `readerId@version` descriptors.
- Each descriptor declares a per-media-type integer rank, an integer probe threshold in
  `0..1000`, a bounded stable priority, and role `primary` or `fallback`; probe adapters must
  return an integer in the same domain.
- For the sniffed media type, below-threshold primary candidates are removed and the unique
  highest `(probeScore, mediaTypeRankForDetectedType, priority)` tuple wins.
- Fallback readers are considered only when no primary candidate qualifies, then use the same
  selection rule.
- A tie is `REF_READER_AMBIGUOUS`, not an ID-based arbitrary selection.
- Deterministic OCR may produce text and regions.
- Any multimodal or vision-model interpretation is not a reader: it must pass through the normal
  context/guidance/request/`InvokeModelAction`/closed-schema/citation/repair chain, with
  citations bound to image regions.

### 16.2 Stable ordering and provenance

- Enumeration retains no durable authority to later reopen a raw entry and does not claim an
  order.
- A reference path must decode as valid UTF-8 and normalize to an NFC workspace-relative path.
- Before sorting, the engine rejects any two entries whose normalized paths are identical or
  equivalent under the compiled active-host-plus-target portability policy; host enumeration
  order never resolves a collision.
- Collision-free files are sorted once by normalized Unicode-scalar relative path, then receive
  only run-local `ReferencePreactivationSession` source IDs for bounded capture/decoder joins.
- Decoded block proposals likewise receive provisional block IDs.
- These values are noncanonical, never model-visible, and never persisted.

- After preflight succeeds for the validated feature directory, the engine allocates the
  execution-local candidate `referenceStateId`, builds the canonical `ReferenceIdLedger`, assigns state-global
  source/block IDs in the same stable order, clones provisional blobs into the reference state's
  write-once namespace, materializes canonical source/decoded budget ledgers, and validates the
  total one-to-one `ReferencePreactivationIdentityMap`.
- These identities, blobs and ledgers remain private candidates until complete workflow
  publication or the explicit clarification persistence exception. No durable reservation
  precedes a model call ([ADR 0009](../decisions/0009-atomic-workflow-execution.md)).
- Only canonicalized blocks then receive chunks and source maps and may enter a model request.
- Each extracted claim must cite one or more real source locations.
- The citation validator resolves `(referenceStateId, sourceId, blockId, location)`, requires
  the location to lie inside the exact `ReferenceChunk` supplied to the call, and validates any
  returned verbatim scalar against the canonical captured blob and source map.

- The complete manifest, closed source/decoded budget ledgers, captured source blobs,
  decoded/accounted block bytes, identified chunks, source maps, unique `SourceCitation` ledger,
  typed extraction/reconciliation claim ledger, conflict-resolution decision events, and
  `ReferenceContextIR` are persisted as one feature-scoped `ReferenceSnapshot` before
  `specified`.
- The snapshot records only reference-derived facts: every claim has one
  retained/superseded/duplicate/conflicting extraction disposition, with valid
  block/chunk/related-claim joins.
- It never stores a mapping to the current editable specification.

- Every citation ID must resolve uniquely to the same `referenceStateId` and a manifest
  source/location; every claim, signal, token, conflict, and provenance citation join is
  validated before commit and again on load.
- Every rendered context item is a `ReferenceSignal<T>` carrying its `signalId`, exact claim
  IDs, citation IDs, and typed content; open questions and preserved tokens use the same join.
- An unresolved conflict additionally stores a snapshot-independent structural subject
  coordinate and one continuity key per option.
- Those tuples use normalized relative source paths, the versioned decoder's structural
  selectors, canonical typed claim content, and exact citation coordinates/scalars—not hashes,
  model summaries, or snapshot-local IDs.
- Thus restart validation and targeted correction never rely on a global source list, digest, or
  prose matching.

- Specification attribution is a separate versioned `SpecificationProvenanceState
  {provenanceStateId, revision, featureRequestStateId, referenceStateId, acknowledgementStateId,
  entries, claimDispositions}` because every specification is reference-backed and editable
  records can change without mutating the immutable snapshot.
- `entries` bind current specification record keys and canonical content identities to their
  origin.
- Reference-derived origins resolve against the required snapshot and derived feature-brief
  origins against the exact persisted `FeatureRequestState`; user-authored origins resolve an
  authenticated `SpecificationAcknowledgement` in the bound acknowledgement-state revision whose
  feature, record key, and canonical content identity all match.
- `claimDispositions` is a total current-specification projection: it contains exactly one entry
  for every claim in the referenced snapshot, and a `mapped_to_spec` entry may name only record
  keys present in the same provenance revision.
- A spec edit rebuilds this projection in the next provenance revision, so deleted or re-keyed
  records cannot leave stale mappings.
- Complete Specify and Plan outputs persist the normalized specification, reference-derived
  feature request, ID ledger, acknowledgement state, provenance state, and relevant
  reference/plan state together.
- Every `ImmutableContentHandle` is a capability to a write-once, snapshot-owned blob in engine
  state; restart validation reads that blob rather than mutable original reference files.
- Immutability comes from owned canonical state and access control, not a content hash.
- This provenance is not fingerprinting.
- No content hash is stored or compared across stages.

### 16.3 Structured facts and exact tokens

- Source citations in model extraction select engine-issued source-line IDs using an inclusive
  `first`/`last` range; separate ranges express discontiguous support.
- IDs are local to the immutable request's source/chunk scope.
- Each selectable unit preserves one original line, including its line ending, or the remaining
  line fragment at a chunk boundary.
- The engine derives exact bytes and all coordinates from captured source data; models supply
  neither quotations nor coordinates.
- Exact-token citations retain their finer extractor-owned spans.
- Canonical citation IDs are still assigned only after validation.
- This shared source-selection contract applies to every workflow using reference evidence; it
  grants no semantic approval, file permission, or execution authority.

Where a parser can decide mechanically, the engine extracts facts before involving the LLM:

- JSON/YAML/XML key/value leaves;
- CSV headers/cells;
- CSS selectors/declarations and exact values;
- manifest dependencies/scripts;
- code declarations/imports;
- document headings/tables;
- explicit numeric values, units, and color literals where a format adapter defines them.

- Ordinary structured facts are supplied as evidence to the chunk's typed claim proposals,
  through which the LLM may classify their meaning as business, design, technical, validation,
  assumption, scope, open question, or irrelevant-to-feature.
- Separately, only extractor facts whose closed descriptor marks them preservation-eligible
  exact values become `StructuredTokenCandidate`s.
- For those candidates the model returns exactly one `preserve | irrelevant` decision and, only
  for preserve, one `PreservedTokenKind`; it never returns the bytes, citation, token ID, or
  obligation ID.
- Exact source values stay as tagged raw-source scalars.
- Dedicated actions assign/build a preserved token and deterministic preserved-token claim.
- Downstream coverage validators require its derived obligation ID in planning and task records,
  and renderers emit the exact scalar sequence through deterministic Markdown escaping without
  Unicode normalization.

- The approved Markdown eligibility rule is `markdown_inline_code_v1`: parsed inline-code spans
  are preservation-eligible candidates; ordinary prose, quoted text and fenced code blocks are
  not candidates through this extractor.
- The candidate retains the exact source bytes between matching backtick delimiters, including
  whitespace and line endings, rather than Markdown-rendered or Unicode-normalized text.
- Eligibility is not relevance, semantic approval or an operational capability.
- The model still classifies every supplied candidate.
- Source partitioning must keep each exact span citable within its chunk or fail explicitly; it
  must never silently omit or truncate an eligible value.

### 16.4 Semantic extraction flow

[View the reference-ingestion diagram](../diagrams/05-reference-ingestion.md).

The linked diagram and this sequence are normative; an orchestrator must require the typed evidence from every named phase before advancing:

1. Resolve/contain the root and prove it is a readable directory. Build one noncanonical `ReferencePreactivationSession`, provisional source/decoded byte ledgers, and traversal capability; enumerate a bounded unordered inventory without following symlinks. No canonical reference, feature-request, source, block, blob, budget-reservation, or citation identity exists yet.
2. Validate entry count/depth/time/memory telemetry; validate every raw path as UTF-8/NFC/no-follow contained; reject host/target collisions; sort the collision-free set; then assign provisional source IDs from the session.
3. Classify every entry. Accept only configuration-backed exclusion candidates; for each included regular file open one no-follow descriptor, validate metadata/per-file size, reserve provisional source-corpus bytes, capture exactly once into a private immutable provisional blob, and commit the actual debit. A capture failure releases the reservation and creates a provisional blocked branch; only captured blobs proceed. Verify the closed provisional source ledger and aggregate ceiling.
4. Sniff and probe each provisional blob, select one exact reader, reserve the lesser of per-file decoded ceiling and provisional corpus remainder, bind that reservation into the sandbox budget, and decode to block proposals. Assign provisional block IDs and validate time/memory/decoded-byte/block/page/cell limits. Close every success/empty/failed/unsupported/blocked branch and the provisional decoded ledger, then validate total branch coverage and mandatory-corpus policy. No provisional identity is serialized, logged as canonical, or sent to a model.
5. Validate the selected target and keep the complete reference candidate inside the current execution. No reference-ID transaction, journal scan or recovered-feature prerequisite precedes canonicalization.
6. For each `ReferenceChunk`, use the configured [ADR 0016 composition](../decisions/0016-configured-json-response-composition.md#5-first-use-extraction): claims/outcome with citations, then dependent token classifications, then prompt-free native assembly. Keep source/token evidence in both requests where required. Validate the complete extraction proposal, every captured-blob/source-map/chunk-bounded citation, and exactly one preserve/irrelevant classification per supplied token candidate. The engine assigns/builds canonical citation/token/claim records only after validation; a preserved token deterministically produces a claim. Repair only the invalid proposal/classification unit.
7. Record exactly one claims/positive-`no_feature_claim`/blocked outcome for every identified chunk. Positive empty is forbidden when any model or preserved-token claim exists. Validate the expected chunk set is complete, then derive each block's final status from all chunks; neither one successful chunk nor a file-level status can hide an unprocessed range. Only then build a decoded-entry candidate.
8. Merge identified claims into a per-document claim set. A compact reconciliation item retains the existing typed claim payload, claim ID, block/chunk IDs, canonical source citations and preserved-token references—not an ID without meaning. Reconciliation does not invent modality or subject/object identities absent from the extraction contract (approved 2026-09-06).
9. Reconcile bounded groups hierarchically: within document, across the documents in the selected reference directory, then across compact group summaries. The selected directory is the related-document set; no inferred affinity or filename priority applies (approved 2026-09-06). The workflow explicitly supplies `group-size` (at least two). Group in stable source/claim order, then in preceding-summary order; recursively group global summaries until one global partition remains. The bound counts immediate claims/summaries, not model bytes or tokens. Every summary retains total original claim membership, payloads needed to decide conflict, and citations. Empty accounted corpora have an explicit empty global partition, not fabricated claims.
10. Validate the closed `ReferenceReconciliationProposal`: every returned ID is supplied/authorized, each input claim has exactly one retained/superseded/duplicate/conflicting disposition, signal variants match their content, and conflict/precedence joins resolve.
11. Build/validate the canonical claim ledger; assign engine conflict/signal IDs; and build canonical `SourceConflict`/`ReferenceSignal` records. Current-spec claim dispositions refer to open-question signals by `signalId`.
12. Build the manifest from the ordered inventory and exactly one final entry variant per source; validate that every inventory entry and decoded block has a final accounting state, both budget ledgers are closed, every source map is complete, and every passive/claim/context join resolves. Assemble and fully validate the immutable `ReferenceSnapshot` candidate before deciding its next branch.
13. If source review establishes genuine behavior-changing source conflicts that remain unresolved, deterministically create or reuse exactly one conflict-bound `SNN` for every unique structural subject coordinate, render their engine-owned current claim-ID choices, and use one `SpecificationClarificationPauseEntries` variant to validate and publish under §§23.2 and 25 the conflict-bearing snapshot, current authorities, complete clarification-set transition, complete controlled-form set, reference view, and `spec_clarification_pending` state. Snapshot-local conflict/claim/citation IDs are binding data, not clarification subject identity. No completed feature brief or specification authority is persisted; ADR 0017 additionally publishes the validated incomplete `spec.md` projection alongside the pending state. A closed authenticated response is first committed through the complete clarification-response publication, then checked against a fully and independently recaptured successor snapshot. Only a validated total old-option-to-current-claim correspondence for the exact same structural subject may feed the decision-ID allocator and decision builder; full accounting, set reconciliation, and snapshot validation run again. Otherwise generate/validate the specification, rebuild the current `SpecificationProvenanceState.claimDispositions`, and persist bootstrap-authority/request/passive-literal-registry/acknowledgement/reference/provenance/spec/views/workflow state with the complete successful Specify output.

`README.md` is flagged as an organizer for presentation, but its claims remain peer authoritative. A conflict with a sibling is treated like any other authoritative conflict.

Conflict classification must distinguish incompatible source requirements from
compatible overlap, repetition, or different business/technical classifications.
Its existing summary must explain the incompatible meanings and cite their claims;
concatenating the claims is not an explanation. Reciprocal IDs, coverage and valid
JSON prove structural consistency, not semantic incompatibility. Source review must
check the classification against captured evidence before treating it as a missing
user decision; it must not assume the earlier model's conflict label is correct.

Source-preservation review may identify an established-source candidate omission.
Under the user-approved chunk 14 amendment (18 September 2026), §22 permits repair
only when captured evidence identifies a unique defective producer and minimal safe
target. Repair extraction loss in extraction; repair reconciliation loss in
reconciliation. Preserve unrelated raw units, rebuild all dependent identities and
projections, and repeat full validation and support review. Unlocalized omissions
remain candidate defects; genuinely missing source decisions remain clarifications.

#### False-conflict repair boundary — approved extension

**Approved by the user on 20 September 2026:** the existing omission-repair owner
may replace one native-bound conflict group: the selected conflict's claims,
their disposition entries and associated conflict records. This amends §22.1/§22.3's
single-record boundary. Reconciliation labels are candidate assertions, so authority
projection records them as candidate defects. Source review establishes a genuine
gap or attributes lost meaning with `reconciliation_conflict`; a positive finding
alone cannot clear an unresolved conflict record.

Authorization requires exact claim/citation/source joins, current old values,
producing origins, candidate revision and source/policy dependencies. Reject a group
whose relationships cross the selected membership; never widen it to the whole
result. Replacement retains that membership and cannot introduce external links.
Reusing existing mutation owners preserves unrelated records and their provenance.
The existing runner invalidates and rebuilds dependent signals, conflicts,
identities, coverage and support before publication; missing signals use ordinary
coverage repair. No new model call type, continuation policy or retry budget applies.

The original claim set supplies a stable retry identity across conflict-ID renewal.
Retain that native witness with the candidate and review, not as persisted authority.
Only complete rebuilt validation and current positive evidence for those claims can
establish progress; unchanged false conflicts remain recurring failures. Genuine
source conflicts remain actionable clarifications. Unsafe attribution fails as a
candidate defect; repair cannot invent source precedence or force a positive verdict.

### 16.5 Human correction without editing generated views

`reference-context.md` remains read-only, but its semantic extraction is correctable. A user submits discriminated `ReferenceFeedback` through the API/CLI against the current `referenceStateId`; each intent admits exactly one compatible block, chunk, claim, or token target. `ValidateReferenceFeedbackTargetAction` proves the complete discriminated join before any change.

- `reextract_block` loads the snapshot-owned block bytes, reproduces its chunking under the recorded workflow-operation/chunker contract (or diagnoses an unavailable version), assigns the new snapshot's chunk IDs, and uses the same configured extraction composition per reproduced chunk with bounded feedback. It requires exactly one complete assembled outcome per chunk and rederives the block status; no block-shaped model call exists.
- `add_claim` uses the existing selected-unit request/merge boundary only for the named chunk. Its output is exactly one `ReferenceClaimProposal` with chunk-bounded citations; it does not invoke whole-chunk composition or replace unrelated claims/classifications. Normal citation/claim validation, ID assignment, canonical build, reconciliation, and accounting apply. Generic feedback is never parsed into a canonical claim by an action.
- `correct_claim_classification` copies the existing canonical claim content/citations into the user-selected closed `newClaimKind`; `remove_claim` tombstones only the named existing claim. Neither intent invokes a model or accepts replacement prose.
- `correct_token` takes no model-authored replacement value: its required `replacementCitationId` must resolve to one exact scalar in the current snapshot, and the builder copies those captured bytes.

These feedback operations remain design requirements, not implemented features.
ADR 0016 defines their composition compatibility but does not add the feedback API
to Chunk 18. Persisted re-extraction must reject unavailable exact extraction
contracts under §12.7; its missing metadata/readback implementation remains explicit.

- A later correction conflict resolution may use the authenticated reference-feedback API; an
  initial behavior-changing conflict always uses its controlled `SNN` form.
- A form response is committed before refresh.
- The engine then reruns the selected workflow's target-context bootstrap, full no-follow
  preactivation/canonical ingestion of the compulsory selected directory, extraction, and
  reconciliation; it never resolves from retained old blobs alone.
- It builds the complete prior conflict-clarification subject set `P` from latest active
  registry revisions bound to the prior reference state and the complete current unresolved
  behavior-conflict subject set `C` from the fully validated fresh snapshot; on initial
  ingestion, `P` is the validated explicit empty set with an absent prior-state pointer.
- Both sets use the same full, non-hash structural `ReferenceConflictClarificationSubjectKey`,
  are canonically sorted, and reject duplicate keys before reconciliation.

- `ReconcileReferenceConflictSubjectSetsAction` performs an exact merge join and nothing else.
- Equal keys form `P ∩ C`; unmatched prior keys form `P ∖ C`; unmatched current keys form `C ∖
  P`.
- A prior key is never paired with an unequal current key, even when each difference set has one
  member.
- For a usable response in `P ∩ C`, `BuildFreshReferenceConflictCorrespondenceAction` compares
  the prior binding's structural option tuples only with that equal-key current conflict, and
  its validator requires direct fresh-capture descriptor, decoder-coordinate, range,
  typed-content, and exact-scalar evidence for a unique mapping of every selected prior claim.
- A `current` equal-key result is the only branch allowed to assign a decision ID; the builder
  binds the already validated actor/time and mapped current claim IDs, and
  `BuildResolvedSourceConflictAction` can act only after those selections rejoin the current
  conflict authority.
- An unprotected unanswered/stale equal-key entry refreshes the same `SNN`.
- If the required subject's protected user answer is stale, the shared Section 23.2 protection
  gate blocks before the set transition; it neither reopens the form nor allocates a second ID.

- Every `P ∖ C` entry has exhaustive absence proof: retain an existing user closure unchanged,
  or build the deterministic obsolete-subject authority resolution for an unprotected record.
- Neither branch names a replacement subject.
- Every `C ∖ P` entry independently performs the global exact-key clarification lookup: an
  unprotected historical key reuses that ID, a protected user closure invokes the Section 23.2
  blocking rule, and exact absence permits a new `SNN` allocation.
- Allocation and resolution IDs are threaded in canonical key order through one prospective
  ledger that remains execution-private until the complete set transition, registry, views,
  reference snapshot, and workflow revision commit.
- If any builder or validator fails first, the whole candidate and prospective ledger are
  discarded; because no ID/path/form/log/diagnostic/model/adapter boundary observed the
  candidate, the unchanged durable ledger may deterministically reselect the same next ordinal.
- `BuildReferenceConflictClarificationSetTransitionAction` then assembles the complete
  intersection continuations, all obsolete closures, and all introduced openings.
- Its validator proves the partition coverage again and proves that, after applying validated
  equal-key decisions, the open subject-key set and open/submittable form-view key projection
  are each exactly the still-unresolved current conflict-key set.
- Closed historical views remain available for audit but are discriminated read-only views with
  `editableRegions: []`.

- When the expected open-key set is nonempty, prepare the complete clarification registry,
  controlled forms, current supporting reference authority and pending state under §23.2.
- Validate exact subject coverage and all protected-input preconditions before writing.
- An empty open-key set exposes no submittable form; retain historical closed forms and continue
  regenerating Specify in memory.
- Neither branch publishes an intermediate reference revision as a stage checkpoint.

- Direct typed structural-key equality is the only continuity rule.
- Hashes, wording similarity, list position, first match, singleton set cardinality or old blobs
  cannot reconcile different subjects.
- A race or stale authority invalidates the candidate; do not apply its decision or rewrite a
  protected form.
- No separate durable decision-ID retirement or recovery transaction is introduced.

- A correction builds a new immutable reference candidate with owned captured bytes and valid
  provenance, never dangling prior handles or a reopened original path.
- Revalidate claim dispositions, citations, exact tokens, chunk/block/source accounting,
  conflicts, source maps and the complete snapshot.
- Clear or invalidate affected downstream authority through §24.5 and regenerate the feature
  brief, specification and provenance from the new snapshot.
- Keep these candidates private until complete Specify publication (§25), unless a genuine
  knowledge gap requires the explicit clarification output.
- Previously published project code is preserved.

Bootstrap changes with `earliestOwner: specify` and
`dominantImpact: reference_ingestion` use the same flow. Retain all classified
invalidation and logging-transition obligations; no candidate bootstrap handle
is persisted as a continuation. A failed write may leave already-replaced files,
but cannot establish new successful completion or bypass protection.

- Initial content grounded through the engine-held feature brief receives `origin:
  reference_derived_feature_brief`, the engine-assigned request ID, and the exact claim/citation
  union from the mandatory snapshot; it never pretends to be an independent user request.
- A later user-authored spec record that lacks reference support requires an authenticated
  acknowledgement event.
- The engine assigns the acknowledgement ID and persists the actor/authentication context,
  feature ID, fixed/allocated record key, exact `BusinessContentIdentity`, intent, and time in
  the next `SpecificationAcknowledgementState`.
- Only after its validator resolves that event may `BuildUserAuthoredProvenanceAction` record
  `origin: user_authored`; a caller cannot fabricate an acknowledgement scalar, claim, or
  citation.
- Project policy decides whether such records are allowed or whether re-attribution to a real
  snapshot claim/citation is mandatory.
