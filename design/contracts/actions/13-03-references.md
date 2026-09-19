# 13.3 Reference actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


## `AssignReferenceStateIdAction`

- **Input:** feature ID, optional parent state ID, validated current feature `StateIdLedger`,
  and matching single-use namespace capability
- **Output:** prospective reference-state reservation plus successor ledger
- **Responsibility:** Allocate the candidate state ID before any local ID/citation/blob binding.
  Retain its successor ledger in the execution; publication follows §25 or the clarification
  persistence exception, never a write-before-call prerequisite.

## `BuildReferenceIdLedgerAction`

- **Input:** prospective state identity and optional prior snapshot for correction
- **Output:** reference-ID ledger candidate
- **Responsibility:** Initialize or advance monotonic
  source/block/chunk/citation/claim/signal/conflict/feedback/conflict-decision/token/reconciliation-partition/reconciliation-summary/reconciliation-statement
  allocators and the shared tombstone set.

## `RetireReferenceAllocatedIdAction`

- **Input:** one failed allocated reference ID, its namespace, and current successor ledger
- **Output:** next reference ID ledger
- **Responsibility:** Add the exact failed ID to the shared tombstone set without rewinding any
  namespace ordinal.

## `ValidateReferenceIdLedgerAction`

- **Input:** initial/final ledgers and every canonical/intermediate allocation or retirement in
  the prospective snapshot
- **Output:** reference-ID-ledger evidence
- **Responsibility:** Prove each assigner advanced exactly its namespace, monotonic uniqueness,
  no reuse, total tombstone accounting, and that the final ledger resolves every persisted
  reference identity.

## Extraction-contract readback

The existing snapshot writer and canonical-state validation actions use the shared
[§12.7 extraction binding](../12-model-boundary.md#127-workflow-defined-model-operations).
They derive comparison evidence from compiled metadata and resolve it against the
current registry. No separate resolver action or historical-schema registry is needed.

## `ResolveReferenceRootAction`

- **Input:** canonical configured reference root and required non-empty relative descendant
  selector
- **Output:** lexical reference-root candidate
- **Responsibility:** Join the required selector without treating it as an alternate root.

## `ValidateReferenceRootContainmentAction`

- **Input:** lexical candidate, canonical configured reference root, and workspace
- **Output:** contained reference root
- **Responsibility:** Prove containment beneath both authorities and apply no-follow root
  policy.

## `ValidateReferenceRootDirectoryAction`

- **Input:** one contained reference root
- **Output:** directory evidence
- **Responsibility:** Prove it exists, is a readable directory, and is not a special file.

## `BuildReferencePreactivationSessionAction`

- **Input:** trusted run ID, canonical selector, validated supplied feature directory, and
  run-local session ordinal
- **Output:** noncanonical reference-preactivation session
- **Responsibility:** Create provisional source/block counters that may identify bounded
  reader/decoder observations only; emit no canonical state ID and persist nothing.

## `BuildReferenceTraversalBudgetAction`

- **Input:** validated reference limits
- **Output:** traversal budget capability
- **Responsibility:** Bind entry, depth, and enumeration time/memory ceilings for one traversal.

## `EnumerateReferenceFilesAction`

- **Input:** contained root and traversal budget capability
- **Output:** bounded unordered raw inventory and traversal telemetry
- **Responsibility:** Enumerate without decoding/ordering and terminate before a hard traversal
  bound is exceeded.

## `ValidateReferenceEntryCountAction`

- **Input:** bounded raw inventory telemetry and entry limit
- **Output:** entry-count evidence
- **Responsibility:** Apply the corpus entry ceiling once.

## `BuildReferencePreactivationBranchAction`

- **Input:** one identified source and exactly one accepted exclusion, successful empty/nonempty
  decode, unsupported, failed, or blocked deterministic outcome with its budget/reader/resource
  bindings
- **Output:** one provisional preactivation branch
- **Responsibility:** Project the closed outcome without constructing a canonical
  `ReferenceEntry` or semantic block status.

## `BuildReferencePreactivationBranchSetAction`

- **Input:** preactivation-session ID, sorted provisionally identified sources, and all
  provisional branches
- **Output:** ordered preactivation branch-set candidate
- **Responsibility:** Join one branch to every provisional source in source order; perform no
  acceptance decision.

## `ValidateReferencePreactivationCoverageAction`

- **Input:** branch-set candidate, sorted inventory, source blobs, both closed budget ledgers,
  reader selections, identified nonempty blocks, and decoder telemetry
- **Output:** branch-set evidence
- **Responsibility:** Prove exact one-to-one source coverage and every branch's complete
  identity/budget/read/decode joins before policy acceptance.

## `ValidateReferencePreactivationAction`

- **Input:** validated provisional branch set, complete deterministic inventory, provisional
  source/decoded budget ledgers, and mandatory-reference policy
- **Output:** preactivation authorization
- **Responsibility:** Require a nonempty corpus, one accepted deterministic branch per source,
  closed budgets, and no unsupported/failed/blocked branch; all IDs remain run-local and
  noncanonical, and source-map materialization, chunks, canonical entries, and semantic
  dispositions are intentionally later.

## `ValidateReferenceDirectoryDepthAction`

- **Input:** one raw inventory entry and depth limit
- **Output:** depth evidence
- **Responsibility:** Apply one traversal-depth ceiling.

## `ValidateReferenceInventoryPathAction`

- **Input:** one raw directory entry and reference policy
- **Output:** canonical inventory path
- **Responsibility:** Validate UTF-8, NFC form, containment, and platform names.

## `DetectReferenceInventoryCollisionAction`

- **Input:** canonical inventory paths and compiled portability-policy set
- **Output:** collision evidence
- **Responsibility:** Reject one NFC/case-fold-equivalent entry set under host or target rules.

## `SortReferenceInventoryAction`

- **Input:** collision-free canonical inventory
- **Output:** ordered inventory
- **Responsibility:** Sort once by normalized Unicode-scalar relative path.

## `AssignReferencePreactivationSourceIdAction`

- **Input:** one ordered inventory entry and current preactivation session
- **Output:** provisional source identity plus successor session
- **Responsibility:** Allocate one run-local source ordinal for bounded capture/decoder joins
  only; never persist, render, log as canonical, or send it to a model.

## `AssignReferenceSourceIdAction`

- **Input:** one ordered provisional source, the execution-local candidate reference-state
  identity, and current reference ID ledger
- **Output:** canonical source mapping plus successor ledger
- **Responsibility:** Allocate one monotonic source ID and return the exact ledger with
  `nextSourceOrdinal` advanced.

## `ClassifyReferenceEntryPolicyAction`

- **Input:** one identified inventory entry and hidden/symlink policy
- **Output:** include/exclude decision candidate
- **Responsibility:** Apply one entry-class policy without accepting it.

## `ValidateReferenceExclusionAcceptanceAction`

- **Input:** one exclusion candidate and exact compiled configuration-policy rule
- **Output:** exclusion-acceptance evidence
- **Responsibility:** In v1, accept only a durable preconfigured policy decision and bind its
  rule/evidence ID; preactivation cannot use a not-yet-existing feature actor registry, so a
  user-authored exclusion is unrepresentable and requires policy update plus rerun.

## `BuildReferencePreactivationSourceBudgetLedgerAction`

- **Input:** preactivation-session identity and validated source-corpus limit
- **Output:** empty provisional source-byte ledger
- **Responsibility:** Create the run-local reservation/debit authority used during bounded
  capture.

## `ValidateReferenceEntryReadabilityAction`

- **Input:** one included regular-file entry and no-follow adapter
- **Output:** descriptor-bound readability evidence
- **Responsibility:** Open one regular file without following links and retain the exact bounded
  descriptor capability; do not reopen it by path.

## `ValidateReferenceFileSizeAction`

- **Input:** descriptor-bound readability evidence and per-file limit
- **Output:** file-size evidence
- **Responsibility:** Apply one per-file byte ceiling to the descriptor metadata.

## `ReserveReferenceSourceBytesAction`

- **Input:** current provisional source-byte ledger, preactivation-session ID, provisional
  source ID, source/file-size evidence, and ledger revision
- **Output:** tuple-identified source-byte reservation and next ledger revision
- **Responsibility:** Construct the closed `(sessionId, source_bytes, provisionalSourceId)`
  run-local identity, prove it is unique in the ledger, and reserve the descriptor-reported
  bytes before capture or fail without reading.

## `CaptureReferenceSourceBlobAction`

- **Input:** exact no-follow descriptor, provisional source-byte reservation, and
  preactivation-session identity
- **Output:** immutable provisional blob handle and capture telemetry
- **Responsibility:** Read that descriptor once into a private run-local store, reject
  length/identity mutation or a reservation overrun, and never reopen by path.

## `CommitReferenceSourceBudgetDebitAction`

- **Input:** matching source-byte reservation, immutable blob length, and current ledger
  revision
- **Output:** committed debit and next ledger revision
- **Responsibility:** Convert one reservation to actual source-byte use exactly once.

## `ReleaseReferenceSourceBudgetReservationAction`

- **Input:** failed/abandoned capture and matching current reservation
- **Output:** released reservation and next ledger revision
- **Responsibility:** Release one uncommitted source-byte reservation exactly once.

## `AccumulateReferenceCorpusSizeAction`

- **Input:** ordered captured source blobs, final source-byte ledger, and total limit
- **Output:** corpus-size evidence
- **Responsibility:** Verify blob lengths equal committed debits and the total ceiling was never
  exceeded.

## `BuildReferencePreactivationDecodedBudgetLedgerAction`

- **Input:** preactivation-session identity and validated decoded-corpus limit
- **Output:** empty provisional decoded-byte ledger
- **Responsibility:** Create the run-local reservation/debit authority for decoded output bytes.

## `ReserveReferenceDecodedBytesAction`

- **Input:** current provisional decoded-byte ledger, preactivation-session ID, provisional
  source/reader IDs, per-file decoded limit, and ledger revision
- **Output:** tuple-identified decoded-byte reservation and next ledger revision
- **Responsibility:** Construct the closed `(sessionId, decoded_bytes, provisionalSourceId,
  readerId)` run-local identity, prove it is unique in the ledger, and reserve at most the
  lesser of the per-file ceiling and remaining corpus allowance before decode.

## `BuildReferenceDecoderBudgetAction`

- **Input:** validated config, exact reader descriptor, and decoded-byte reservation
- **Output:** decoder budget capability
- **Responsibility:** Bind the reservation plus time, memory, block, page, cell, archive, and
  expansion ceilings for one decode.

## `BuildExcludedReferenceEntryAction`

- **Input:** one accepted exclusion and identified entry
- **Output:** excluded-entry candidate
- **Responsibility:** Build one union variant without a decoder/blocks.

## `SniffReferenceMediaTypeAction`

- **Input:** one immutable source blob
- **Output:** media-type result
- **Responsibility:** Determine content type using registered sniffers without reopening the
  inventory path.

## `ProbeReferenceReaderAction`

- **Input:** one immutable source blob and exact reader descriptor
- **Output:** bounded integer probe score
- **Responsibility:** Probe one reader only against the captured bytes.

## `FilterReferenceReaderThresholdAction`

- **Input:** one reader/score/media tuple
- **Output:** eligible or rejected candidate
- **Responsibility:** Apply one descriptor's threshold only.

## `SelectReferenceReaderTierAction`

- **Input:** eligible primary and fallback sets
- **Output:** one candidate tier
- **Responsibility:** Choose primaries when nonempty, otherwise fallbacks.

## `BuildReferenceReaderRankAction`

- **Input:** one eligible candidate and detected media type
- **Output:** rank tuple
- **Responsibility:** Build one integer `(score, media-rank, priority)` tuple.

## `SelectReferenceReaderAction`

- **Input:** one-tier candidate/rank set
- **Output:** reader selection
- **Responsibility:** Select the unique maximum or diagnose a tie.

## `DecodeReferenceAction`

- **Input:** one immutable source blob, exact reader, and decoder budget capability
- **Output:** bounded decode result and resource telemetry
- **Responsibility:** Decode one captured file only; the sandboxed reader must terminate before
  a bound is exceeded and cannot reopen its path.

## `ValidateReferenceDecodedFileSizeAction`

- **Input:** one decode result and per-file decoded-byte limit
- **Output:** decoded-size evidence
- **Responsibility:** Apply one decoded-output ceiling.

## `CommitReferenceDecodedBudgetDebitAction`

- **Input:** matching decoded-byte reservation, validated decoded length, and current ledger
  revision
- **Output:** committed debit and next ledger revision
- **Responsibility:** Convert one reservation to actual decoded-byte use exactly once.

## `ReleaseReferenceDecodedBudgetReservationAction`

- **Input:** failed/empty/abandoned decode and matching current reservation
- **Output:** released reservation and next ledger revision
- **Responsibility:** Release one uncommitted decoded-byte reservation exactly once.

## `AccumulateReferenceDecodedCorpusSizeAction`

- **Input:** ordered successful decoded lengths, final decoded-byte ledger, and total limit
- **Output:** decoded-corpus evidence
- **Responsibility:** Verify output lengths equal committed debits and the total ceiling was
  never exceeded.

## `ValidateReferenceBlockCountAction`

- **Input:** one decode result and block limit
- **Output:** block-count evidence
- **Responsibility:** Apply one decoded-block ceiling.

## `ValidateReferencePageCountAction`

- **Input:** one document decode and page limit
- **Output:** page-count evidence
- **Responsibility:** Apply one document-page ceiling.

## `ValidateReferenceCellCountAction`

- **Input:** one tabular decode and cell limit
- **Output:** cell-count evidence
- **Responsibility:** Apply one table-cell ceiling.

## `ValidateReferenceDecoderResourceUseAction`

- **Input:** one decoder telemetry record and time/memory limits
- **Output:** resource-use evidence
- **Responsibility:** Prove the sandbox terminated within its time and memory envelope.

## `BuildUnsupportedReferenceEntryAction`

- **Input:** one no-reader result and identified entry
- **Output:** unsupported-entry candidate
- **Responsibility:** Build one unsupported union variant.

## `BuildFailedReferenceEntryAction`

- **Input:** one decode failure and attempted reader IDs
- **Output:** failed-entry candidate
- **Responsibility:** Build one failed union variant.

## `BuildBlockedReferenceEntryAction`

- **Input:** one readability/source-size/source-capture/reader-selection/decode-budget failure
  and identified entry
- **Output:** blocked-entry candidate
- **Responsibility:** Build one phase-exact blocking union variant without fabricating captured
  or decoded content.

## `BuildEmptyReferenceEntryAction`

- **Input:** one successful empty decode and decoder identity
- **Output:** empty-entry candidate
- **Responsibility:** Build one empty union variant.

## `BuildDecodedReferenceEntryAction`

- **Input:** one successful nonempty decode and accounted content blocks
- **Output:** decoded-entry candidate
- **Responsibility:** Build one decoded union variant only after every block has a final status.

## `AssignReferencePreactivationBlockIdAction`

- **Input:** one decoder block proposal and current preactivation session
- **Output:** provisional block observation plus successor session
- **Responsibility:** Allocate one run-local block ordinal for decoder/source-map joins only and
  claim no canonical identity.

## `AssignReferenceBlockIdAction`

- **Input:** one ordered provisional block, the execution-local candidate reference-state
  identity, and current reference ID ledger
- **Output:** canonical block mapping plus successor ledger
- **Responsibility:** Allocate one reference-state-global block ID, advance only
  `nextBlockOrdinal`, and claim no accounting.

## `AssignReferenceBudgetReservationIdAction`

- **Input:** canonical reference-state ID, one mapped canonical source ID, and closed budget
  kind `source_bytes | decoded_bytes`
- **Output:** owner-local canonical budget-reservation identity
- **Responsibility:** Construct `(referenceStateId, sourceId, budgetKind)`; require at most one
  terminal reservation per source/kind and consume no `ReferenceIdLedger` namespace.

## `ValidateReferenceBudgetReservationIdentityCoverageAction`

- **Input:** canonical source set, complete source/decoded reservation sets, and preactivation
  identity-map candidate
- **Output:** reservation-identity coverage evidence
- **Responsibility:** Require exactly one unique source-byte and one decoded-byte terminal
  identity for every applicable source, no duplicate tuple, and total provisional mapping.

## `ClonePreactivationBlobIntoReferenceStateAction`

- **Input:** one validated provisional blob handle, canonical reference-state ID, and exact
  provisional source/canonical-source mapping
- **Output:** reference-state-owned immutable blob plus one blob mapping
- **Responsibility:** Copy exact bytes into the write-once canonical namespace without reopening
  the reference path.

## `BuildReferencePreactivationIdentityMapAction`

- **Input:** preactivation session, canonical reference-state ID, complete ordered
  source/block/blob/reservation mappings
- **Output:** reference-preactivation identity map candidate
- **Responsibility:** Assemble the total provisional-to-canonical translation without assigning
  or copying anything.

## `ValidateReferencePreactivationIdentityMapAction`

- **Input:** map candidate, validated branch set, canonical reference-ID ledger, cloned blobs,
  and both provisional/canonical budget ledgers
- **Output:** identity-map evidence
- **Responsibility:** Prove total one-to-one source/block/blob/reservation coverage, order
  preservation, no provisional ID survives in canonical state, and every canonical ID belongs
  to the current candidate state and its validated ledger. The candidate state ID must be
  allocated before any canonical local ID, citation or blob binding; no durable write is required.

## `MaterializeReferenceSourceBudgetLedgerAction`

- **Input:** closed provisional source budget, identity-map candidate, exact source/reservation
  mappings, and canonical reference-state ID
- **Output:** canonical source-budget ledger candidate
- **Responsibility:** Translate every reservation/debit/release exactly once without changing
  limits or totals; validation occurs only after both ledgers exist.

## `MaterializeReferenceDecodedBudgetLedgerAction`

- **Input:** closed provisional decoded budget, identity-map candidate, exact source/reservation
  mappings, and canonical reference-state ID
- **Output:** canonical decoded-budget ledger candidate
- **Responsibility:** Translate every reservation/debit/release exactly once without changing
  limits or totals; validation occurs only after both ledgers exist.

## `ValidateReferenceSourceMapProposalAction`

- **Input:** decoder source-map proposal, source bytes/metadata, and identified block set
- **Output:** source-map evidence
- **Responsibility:** Validate coordinate ordering/bounds, handle containment, media-specific
  required mappings, and source/block joins.

## `BuildReferenceSourceMapAction`

- **Input:** source-map evidence and exact decoder identity
- **Output:** canonical reference source map
- **Responsibility:** Materialize one source-keyed map without changing coordinates.

## `ValidateReferenceSourceMapCompletenessAction`

- **Input:** manifest decoded entries, block set, and canonical source maps
- **Output:** source-map completeness evidence
- **Responsibility:** Prove exactly one sufficient map per decoded source and every mapped block
  resolves once.

## `ExtractStructuredFactsAction`

- **Input:** decoded structured content
- **Output:** exact machine facts/tokens
- **Responsibility:** Parse values mechanically where supported.

## `AssignStructuredTokenCandidateIdAction`

- **Input:** one source-ordered deterministic fact whose typed extractor marks it
  preservation-eligible, its extractor ID, source ID, and source-local ordinal
- **Output:** owner-local structured-token candidate identity
- **Responsibility:** Construct `(sourceId, extractorId, ordinal)` before model classification;
  this transient candidate consumes no canonical reference-ID namespace.

## `ValidatePreservedTokenClassificationProposalAction`

- **Input:** one model classification, allowed candidate IDs, closed token kinds, and current
  source map
- **Output:** token-classification evidence
- **Responsibility:** Resolve one engine candidate, require the preserve/irrelevant shape, and
  forbid model-authored bytes/citations/IDs.

## `ValidateStructuredTokenClassificationCompletenessAction`

- **Input:** exact chunk-local candidate set and all validated classifications
- **Output:** token-accounting evidence
- **Responsibility:** Prove every candidate has exactly one preserve/irrelevant disposition and
  no unknown/duplicate candidate appears.

## `AssignPreservedTokenIdAction`

- **Input:** one preserve-valid structured-token candidate and current reference ID ledger
- **Output:** token identity plus successor ledger
- **Responsibility:** Allocate one reference-state-local token ID and advance only
  `nextTokenOrdinal`.

## `BuildPreservedTokenAction`

- **Input:** token identity, structured-token candidate, canonical citation, and deterministic
  obligation namespace
- **Output:** canonical preserved token
- **Responsibility:** Copy exact captured bytes and derive the downstream obligation ID from the
  token identity.

## `BuildPreservedTokenClaimAction`

- **Input:** canonical preserved token, its canonical citation, and current block/chunk
- **Output:** preserved-token claim candidate
- **Responsibility:** Construct one citation-bound deterministic claim candidate for normal
  claim-ID assignment/accounting.

## `ChunkReferenceAction`

- **Input:** one identified content block and workflow-declared chunking contract
- **Output:** ordered bounded chunk proposals
- **Responsibility:** Partition one block while preserving exact source ranges.

## `AssignReferenceChunkIdAction`

- **Input:** one ordered chunk proposal and current reference ID ledger
- **Output:** identified reference chunk plus successor ledger
- **Responsibility:** Allocate one reference-state-global chunk ID and advance only
  `nextChunkOrdinal`.

## `RecordChunkDispositionAction`

- **Input:** one identified chunk and validated extraction result
- **Output:** accounted reference chunk
- **Responsibility:** Attach exactly one claims, positive no-feature-claim, or blocked outcome.

## `ValidateChunkAccountingAction`

- **Input:** one block's expected chunks and accounted chunk set
- **Output:** chunk-accounting evidence
- **Responsibility:** Prove every chunk appears exactly once and every referenced claim
  resolves.

## `DeriveBlockDispositionAction`

- **Input:** one identified block and complete chunk-accounting evidence
- **Output:** canonical accounted content block
- **Responsibility:** Derive blocked if any chunk blocked, no-feature-claim if all are
  positive-empty, otherwise extracted.

## `ValidateSourceCitationAction`

- **Input:** one `SourceCitationProposal`, current `ReferenceChunk`, captured source blob, and
  validated source map
- **Output:** validated citation proposal
- **Responsibility:** Prove the source/block/location/verbatim tuple exists and lies inside the
  exact chunk range supplied to this unit; accept no model-owned canonical ID.

## `AssignSourceCitationIdAction`

- **Input:** one validated citation proposal and current reference ID ledger
- **Output:** citation identity plus successor ledger
- **Responsibility:** Allocate one reference-state-local citation ID, advance only
  `nextCitationOrdinal`, and leave the proposal unchanged.

## `BuildSourceCitationAction`

- **Input:** citation identity, prospective reference-state identity, and validated citation
  proposal
- **Output:** canonical source citation
- **Responsibility:** Bind engine identity/state to the unchanged validated location and
  optional exact scalar.

## `ValidateReferenceClaimProposalAction`

- **Input:** one `ReferenceClaimProposal`, current chunk, canonical citations, passive-literal
  registry, and closed claim schema
- **Output:** validated claim proposal
- **Responsibility:** Validate kind/content and require every citation to be canonical, unique,
  and chunk-local; accept no disposition or model-owned ID.

## `AssignReferenceClaimIdAction`

- **Input:** one validated model claim proposal or deterministic preserved-token claim candidate
  and current reference ID ledger
- **Output:** claim identity plus successor ledger
- **Responsibility:** Allocate one reference-state-local claim ID, advance only
  `nextClaimOrdinal`, and choose no disposition.

## `BuildIdentifiedReferenceClaimAction`

- **Input:** claim identity, validated model/token claim candidate, canonical citations, and
  current chunk
- **Output:** identified reference claim
- **Responsibility:** Derive source/block/chunk/citation joins and bind the unchanged validated
  content.

## `AssignReferenceReconciliationStateIdAction`

- **Input:** prospective reference-state identity and reconciliation contract version
- **Output:** owner-local reconciliation-state identity
- **Responsibility:** Construct the closed tuple `(referenceStateId,
  reconciliationContractVersion)`; consume no hidden allocator.

## `BuildReferenceReconciliationItemAction`

- **Input:** one identified claim, canonical citations, and source ordering
- **Output:** compact reconciliation item
- **Responsibility:** Project the bounded content/IDs needed for conflict/disposition decisions
  without losing claim meaning.

## `PartitionReferenceReconciliationItemsAction`

- **Input:** reconciliation items, level, workflow-declared partition contract, and stable
  source/claim ordering
- **Output:** bounded reconciliation partitions
- **Responsibility:** Deterministically partition within source, across sources, or globally
  under the declared contract; infer no API-size ceiling.

## `AssignReferenceReconciliationPartitionIdsAction`

- **Input:** ordered unidentified partitions and current reference ID ledger
- **Output:** identified partitions plus successor ledger
- **Responsibility:** Allocate one partition ID per canonical order and advance only
  `nextReconciliationPartitionOrdinal`.

## `ValidateReferenceReconciliationPartitionCoverageAction`

- **Input:** partitions and exact input item/summary set
- **Output:** partition-coverage evidence
- **Responsibility:** Prove every input member appears exactly once at that level and IDs/order
  are unique; perform no model-request size estimation.

## `ValidateReferenceReconciliationSummaryProposalAction`

- **Input:** one summary proposal, exact partition, and claim/summary allowlists
- **Output:** summary-proposal evidence
- **Responsibility:** Require exact member-ID echo, total represented-claim coverage, closed
  content variants, and no canonical IDs.

## `AssignReferenceReconciliationSummaryIdsAction`

- **Input:** one validated summary proposal and current reference ID ledger
- **Output:** summary/statement ID map plus successor ledger
- **Responsibility:** Allocate summary and statement IDs in canonical local-key order and
  advance only their two reconciliation ordinals.

## `BuildReferenceReconciliationSummaryAction`

- **Input:** validated proposal and ID map
- **Output:** canonical summary
- **Responsibility:** Replace local keys with IDs while preserving represented claims/content.

## `BuildCrossSourceReconciliationInputAction`

- **Input:** validated lower-level summaries and exact represented-claim evidence
- **Output:** next-level item set
- **Responsibility:** Project the next bounded level and preserve a total claim-membership map.

## `ValidateGlobalReferenceReconciliationProposalAction`

- **Input:** final global proposal, global partition, all summaries/identified claims, and
  registries
- **Output:** global reconciliation evidence
- **Responsibility:** Prove exactly one disposition per original claim, complete signal/conflict
  joins, and no summary/member loss.

## `BuildHierarchicalReferenceReconciliationStateAction`

- **Input:** state identity, all validated partitions/summaries, operation/partition contract,
  and final proposal
- **Output:** hierarchical reconciliation state
- **Responsibility:** Assemble the complete reconciliation authority without assigning IDs.

## `ValidateHierarchicalReferenceReconciliationCompletenessAction`

- **Input:** hierarchical state and complete identified-claim registry
- **Output:** reconciliation-completeness evidence
- **Responsibility:** Prove level lineage, one-to-one membership at every level, total final
  claim coverage, and no dropped/duplicated claim.

## `ValidateClaimDispositionProposalAction`

- **Input:** one `ClaimDispositionProposal` and current identified-claim set
- **Output:** disposition evidence
- **Responsibility:** Validate closed disposition shape, allowed related IDs, and self/cycle
  constraints without changing a claim.

## `ValidateReferenceSignalProposalAction`

- **Input:** one `ReferenceSignalProposal` and current claim/citation/token registries
- **Output:** signal-projection evidence
- **Responsibility:** Validate the kind-to-content variant and every claim/citation/token join
  without accepting a signal ID.

## `AssignReferenceSignalIdAction`

- **Input:** one validated signal proposal and current reference ID ledger
- **Output:** signal identity plus successor ledger
- **Responsibility:** Allocate one reference-state-local signal ID and advance only
  `nextSignalOrdinal`.

## `BuildReferenceSignalAction`

- **Input:** signal identity and validated signal proposal
- **Output:** canonical reference signal
- **Responsibility:** Bind identity to the unchanged validated projection.

## `ValidateSourceConflictCandidateAction`

- **Input:** one `SourceConflictProposal`, current claim/citation/source/block/chunk registries,
  and compiled precedence rules
- **Output:** conflict-candidate evidence
- **Responsibility:** Validate kind, mutually relevant claim set, citations, typed summary, and
  any selected precedence rule without accepting an ID or user decision.

## `BuildReferenceAuthorityLocusAction`

- **Input:** one current citation, manifest entry, source map, decoder contract, and directly
  captured source location
- **Output:** snapshot-independent authority locus
- **Responsibility:** Project normalized relative path plus versioned structural decoder
  selector; omit every reference-state/source/block/chunk/citation ID and perform no fuzzy
  matching.

## `BuildReferenceConflictSubjectCoordinateAction`

- **Input:** validated conflict kind, required decision slot, and complete canonically ordered
  authority loci
- **Output:** structural conflict-subject coordinate
- **Responsibility:** Build a non-hash tuple whose equality is decidable across independently
  captured snapshots.

## `BuildReferenceConflictOptionContinuityKeyAction`

- **Input:** conflict-subject coordinate, one exact identified claim, its canonical typed
  content, citations, authority loci, and captured scalar spans
- **Output:** structural option-continuity key
- **Responsibility:** Bind claim meaning and direct source coordinates without including a
  snapshot-local claim/citation ID.

## `ValidateReferenceConflictContinuityKeySetAction`

- **Input:** conflict proposal, subject coordinate, option-continuity keys, current
  claims/citations/source maps, and direct capture evidence
- **Output:** continuity-key evidence
- **Responsibility:** Prove complete one-to-one claim coverage, unique keys, canonical ordering,
  exact content/location equality, and no hash/prose/fuzzy correspondence.

## `AssignReferenceConflictIdAction`

- **Input:** one validated conflict proposal and current reference ID ledger
- **Output:** conflict identity plus successor ledger
- **Responsibility:** Allocate one reference-state-local conflict ID and advance only
  `nextConflictOrdinal`.

## `BuildSourceConflictAction`

- **Input:** conflict identity, validated conflict proposal, subject coordinate, and complete
  continuity-key set
- **Output:** canonical source conflict
- **Responsibility:** Bind identity and materialize only an unresolved or validated
  source-precedence resolution while retaining restart-safe subject/option continuity.

## `DeriveReferencedSourceIdsAction`

- **Input:** validated signals/conflicts/open questions and citation ledger
- **Output:** ordered referenced source IDs
- **Responsibility:** Derive the exact manifest-source projection once.

## `BuildReferenceContextIRAction`

- **Input:** referenced source IDs and validated identified signals/conflicts/open questions
- **Output:** reference-context candidate
- **Responsibility:** Place each typed record into exactly one closed context collection.

## `ValidateReferenceContextCompletenessAction`

- **Input:** reference-context candidate and claim/citation/token/conflict registries
- **Output:** context evidence
- **Responsibility:** Prove unique IDs, complete joins, collection-kind correctness, and no
  orphan context record.

## `BuildPriorReferenceConflictClarificationSubjectSetAction`

- **Input:** validated prior clarification registry and optional prior reference-state identity
- **Output:** prior subject-set candidate `P`
- **Responsibility:** Project the latest active revision of every clarification binding owned by
  the prior reference state, including its exact structural key, ID, binding, and
  usable-response disposition, in canonical complete-key order; for initial ingestion build the
  explicitly empty set with no prior pointer, and make no current-subject comparison.

## `ValidatePriorReferenceConflictClarificationSubjectSetAction`

- **Input:** prior subject-set candidate, prior clarification registry, and optional prior
  reference state
- **Output:** prior-set evidence
- **Responsibility:** Prove complete latest-record coverage, exact binding/reference ownership,
  valid response disposition, canonical order, and unique full structural keys; permit an absent
  prior pointer only for initial ingestion and then require zero subjects.

## `BuildCurrentUnresolvedReferenceConflictSubjectSetAction`

- **Input:** fully validated freshly recaptured snapshot and complete current conflict registry
- **Output:** current subject-set candidate `C`
- **Responsibility:** Project every unresolved behavior-changing current conflict to its exact
  structural clarification key and binding in canonical complete-key order; make no
  prior-subject comparison.

## `ValidateCurrentUnresolvedReferenceConflictSubjectSetAction`

- **Input:** current subject-set candidate, fully validated fresh snapshot, complete conflict
  registry, and continuity contract
- **Output:** current-set evidence
- **Responsibility:** Prove complete unresolved behavior-conflict coverage, exact
  conflict/binding joins, canonical order, and one unique full structural key per current
  conflict.

## `ReconcileReferenceConflictSubjectSetsAction`

- **Input:** complete canonical `P` and `C`
- **Output:** structural subject-set reconciliation candidate
- **Responsibility:** Deterministically merge-join the full keys into `P ∩ C`, `P ∖ C`, and `C ∖
  P`; retain each intersection entry's prior answer disposition and produce exhaustive
  current-set absence evidence for each obsolete prior key without relating it to an introduced
  key.

## `ValidateReferenceConflictSubjectSetReconciliationAction`

- **Input:** reconciliation candidate, prior clarification registry, fresh snapshot, and
  complete conflict registry
- **Output:** set-reconciliation evidence
- **Responsibility:** Prove the three partitions are pairwise disjoint and exhaustive: every `P`
  key occurs exactly once in the intersection or `P ∖ C`, every `C` key exactly once in the
  intersection or `C ∖ P`, intersection keys are directly equal, and difference keys have no
  equal counterpart.
- No cardinality, ordering proximity, wording, hash, or semantic similarity may pair subjects.

## `BuildFreshReferenceConflictCorrespondenceAction`

- **Input:** one validated `P ∩ C` entry with a usable closed response, its exact equal-key
  prior/current bindings, current continuity-key registry, and direct typed fresh-capture
  comparisons
- **Output:** `current` or `stale_same_subject` correspondence candidate
- **Responsibility:** Compare options only inside the already established equal-key pair.
- Return `current` for a total unique selected-option map or `stale_same_subject` for a nonempty
  exact-mapping failure.
- There is no absent or unequal-subject variant, and the action may not search for a nearest,
  first, or unrelated current conflict.
- Read no retained parent blob as refresh input.

## `ValidateFreshReferenceConflictCorrespondenceAction`

- **Input:** correspondence candidate, exact intersection entry/prior response, fresh
  manifest/source blobs/source maps/claims, equal-key current conflict, and direct fresh-capture
  descriptor/range/scalar evidence
- **Output:** variant-specific correspondence evidence
- **Responsibility:** Prove the prior, intersection, and current subject keys are directly
  equal.
- For `current`, require a total one-to-one mapping of every selected option by structural
  coordinates, typed content, and directly recaptured bytes.
- For `stale_same_subject`, require at least one selected prior option with a typed
  missing-or-mismatched exact mapping.
- Reject unequal-key pairing, ID equality as continuity, hashes, summaries, old blobs, model
  prose, and fuzzy similarity.

## `AssignReferenceConflictDecisionIdAction`

- **Input:** validated `current` fresh-reference correspondence, authenticated response binding,
  and current refreshed reference ID ledger's conflict-decision allocator
- **Output:** conflict-decision identity and successor ledger
- **Responsibility:** Advance only `nextConflictDecisionOrdinal` after exact correspondence is
  proven; perform no decision build or retirement.

## `BuildReferenceConflictResolutionDecisionAction`

- **Input:** decision identity, authenticated user event or validated current correspondence,
  target state/conflict, selected current claims, and rationale
- **Output:** conflict-decision candidate
- **Responsibility:** Bind trusted actor/time metadata and only revision-current selected claim
  IDs without minting identity.

## `ValidateReferenceConflictResolutionDecisionAction`

- **Input:** one authenticated decision and current unresolved conflict
- **Output:** conflict-decision evidence
- **Responsibility:** Resolve the target state/conflict/claims and validate the selected subset.

## `BuildResolvedSourceConflictAction`

- **Input:** one decision-valid conflict
- **Output:** resolved conflict candidate
- **Responsibility:** Apply one user decision while retaining its decision ID.

## `ValidateCitationLedgerAction`

- **Input:** citation ledger, claims, signals, provenance, and manifest
- **Output:** citation-join evidence
- **Responsibility:** Prove unique IDs and resolve every citation/source join.

## `ValidateSpecificationClaimJoinAction`

- **Input:** one specification record's claim/citation IDs and claim ledger
- **Output:** claim-to-spec evidence
- **Responsibility:** Resolve claims and prove citation consistency for one record.

## `BuildReferenceClaimLedgerAction`

- **Input:** identified claims and validated reconciliation disposition proposals
- **Output:** claim-ledger candidate
- **Responsibility:** Join one engine-owned claim record to exactly one disposition and
  related-claim set without minting IDs.

## `ValidateReferenceClaimLedgerAction`

- **Input:** claim-ledger candidate and identified-claim registry
- **Output:** extraction-ledger evidence
- **Responsibility:** Prove every extracted claim has one valid
  retained/superseded/duplicate/conflicting disposition and all related claim IDs resolve.

## `ValidateReferenceEntryAccountingAction`

- **Input:** one inventory entry and block ledger
- **Output:** entry accounting evidence
- **Responsibility:** Prove one file and all of its blocks have dispositions.

## `BuildReferenceManifestAction`

- **Input:** identified inventory, exactly one final entry candidate per source, accepted
  exclusions, and blocking diagnostics
- **Output:** reference manifest candidate
- **Responsibility:** Join the ordered inventory to final entry variants without inventing or
  dropping a source.

## `ValidateReferenceManifestCompletenessAction`

- **Input:** manifest candidate, ordered inventory, source/decode budget ledgers, and blocking
  policy
- **Output:** manifest evidence
- **Responsibility:** Prove one-to-one source accounting, ledger closure, and the derived
  `allEntriesAccountedFor` value.

## `CaptureReferenceFeedbackSubmissionAction`

- **Input:** raw feedback event and runner-held submission/authentication-lease table
- **Output:** immutable run-local feedback handle/candidate
- **Responsibility:** Capture expected reference revision, closed change proposal, and bounded
  feedback bytes without authenticating or assigning a durable ID.

## `ValidateReferenceFeedbackSubmissionAction`

- **Input:** captured feedback candidate, current reference state, target schema, and
  business-text policy
- **Output:** validated reference-feedback submission or stale/structural diagnostic
- **Responsibility:** Before authentication, prove closed intent/target shape, exact current
  revision, target existence/kind compatibility, and canonicalize feedback bytes to durable
  `BusinessText`.

## `BindAuthenticatedReferenceFeedbackSubmissionAction`

- **Input:** validated feedback submission and validated fresh actor evidence for
  `reference_feedback`
- **Output:** authenticated feedback binding
- **Responsibility:** Bind the exact run-local submission handle/change/text to actor evidence
  after static freshness validation; assign no reference ID.

## `AssignReferenceFeedbackIdAction`

- **Input:** authenticated feedback binding and current reference ID ledger's feedback allocator
- **Output:** feedback identity and next ledger
- **Responsibility:** Assign one monotonic engine-owned feedback ID and retire failed
  allocations.

## `BuildReferenceFeedbackAction`

- **Input:** feedback identity, authenticated binding, validated submission with durable
  `BusinessText`, unchanged target/change, and trusted clock
- **Output:** canonical reference-feedback event
- **Responsibility:** Bind public actor/time/evidence metadata and canonical text without
  credentials or invocation-owned handles and without performing correction.

## `ValidateReferenceFeedbackTargetAction`

- **Input:** one canonical feedback event and current snapshot
- **Output:** target evidence
- **Responsibility:** Validate its exactly-one target and intent-compatible block/chunk, claim,
  classification, token, and replacement-citation join.

## `CloneReferenceBlobIntoRevisionAction`

- **Input:** one current snapshot-owned immutable blob and newly assigned prospective
  reference-state identity
- **Output:** new state-owned immutable blob handle
- **Responsibility:** Copy exact stored bytes into the successor's write-once namespace without
  reopening an original reference path or hashing.

## `BuildSuccessorReferenceIdLedgerAction`

- **Input:** validated prior ID ledger, prospective reference-state identity, and one typed
  feedback/decision allocation delta
- **Output:** successor ID-ledger candidate
- **Responsibility:** Preserve monotonic allocators/tombstones and apply only the explicitly
  authorized identity transition.

## `RebindRetainedReferenceManifestEntryAction`

- **Input:** one retained manifest entry, prospective state identity, and exact
  cloned-blob/source mapping
- **Output:** successor manifest entry
- **Responsibility:** Rebind one unchanged entry without rebuilding a manifest or reading its
  path.

## `RebindRetainedReferenceChunkAction`

- **Input:** one retained accounted chunk, prospective state identity, and exact
  cloned-blob/block mapping
- **Output:** successor accounted chunk
- **Responsibility:** Rebind one unchanged chunk and disposition without extracting or
  reconciling it.

## `RebindRetainedReferenceSourceMapAction`

- **Input:** one retained source map and exact successor source/block/blob mapping
- **Output:** successor source map
- **Responsibility:** Rebind one source map while preserving all source ranges.

## `RebindRetainedReferenceBudgetEntryAction`

- **Input:** one closed source/decoded budget entry and prospective ledger identity
- **Output:** successor budget entry
- **Responsibility:** Copy one immutable reservation/debit/release outcome without changing its
  byte accounting.

## `RebindRetainedSourceCitationAction`

- **Input:** one retained citation and exact successor state/source/block/chunk mapping
- **Output:** successor citation
- **Responsibility:** Rebind one citation while preserving its validated location/content.

## `RebindRetainedReferenceClaimAction`

- **Input:** one retained identified claim and successor citation/token mappings
- **Output:** successor identified claim
- **Responsibility:** Rebind one unchanged claim; it assigns no disposition or identity.

## `RebindRetainedConflictDecisionAction`

- **Input:** one retained authenticated decision and successor state/conflict mapping
- **Output:** successor conflict decision
- **Responsibility:** Rebind one decision only after its selected claim IDs remain valid.

## `ValidateReferenceRevisionProjectionAction`

- **Input:** prior snapshot, typed feedback/decision, and complete per-record retained/changed
  projections
- **Output:** revision-projection evidence
- **Responsibility:** Prove every prior record is retained, explicitly replaced, or tombstoned
  exactly once before normal manifest/reconciliation/context assembly.

## `AssembleReferenceSnapshotAction`

- **Input:** prospective state identity, exact extraction-operation contract, final ID ledger,
  validated passive-literal registry, manifest/budget ledgers/entries/chunks/source
  maps/citations/reconciliation/claims/feedback events/conflict-resolution
  decisions/context/blobs
- **Output:** reference-snapshot candidate
- **Responsibility:** Copy the exact passive-registry/reconciliation state IDs and assemble one
  complete snapshot without assigning identity or hashing content.

## `ValidateReferenceSnapshotAction`

- **Input:** reference-snapshot candidate and every bound ledger/registry/route/blob authority
- **Output:** whole-snapshot evidence
- **Responsibility:** Prove state-ID ownership, ledger closure,
  citation/chunk/source/context/reconciliation/claim/conflict joins, total accounting, immutable
  blob ownership, and no orphan or duplicate record.

## `SerializeCanonicalReferenceStateAction`

- **Input:** validated reference snapshot
- **Output:** canonical reference-state bytes
- **Responsibility:** Serialize one authoritative reference snapshot.

## `RenderReferenceContextAction`

- **Input:** validated reference snapshot, its exact passive-literal registry state, and
  renderer contract
- **Output:** Markdown candidate
- **Responsibility:** Render the sidecar using snapshot-owned source labels/locations and inert
  registered display literals only.


Semantic extraction and reconciliation use the common LLM actions; there is no special reader that also calls a model.
