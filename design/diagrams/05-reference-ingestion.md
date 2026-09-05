```mermaid
flowchart TD
    START[sdd specify --reference &lt;relative-selector&gt;] --> RUNNER[PipelineRunner<br/>sole node invocation and delta application owner]
    RUNNER --> ENGINE[WorkflowEngineOrchestrator<br/>no workflow-name branch;<br/>coordinate only through runner-owned ChildNodeBinding values]
    ENGINE -. bootstrap child binding .-> RUNNER
    RUNNER --> BOOT[Invoke the fixed startup BootstrapOrchestrator through its runner-owned binding;<br/>diagram 08 loads and compiles the variable-size workflow registry without selecting a workflow<br/>and returns without acquiring a project or feature transaction lock]
    BOOT --> CONFIG[Engine startup only: use the invocation working directory as project root;<br/>read/directly decode only its exact .sddtoolkit.json or fail the invocation if missing;<br/>validate seven configured directory roots plus paths.providers and every discovered workflow definition;<br/>do not read provider config or inventory presets/toolchain.yaml/principles yet]
    CONFIG --> WSELECT[Runner invokes ParseWorkflowSelectionAction then ValidateWorkflowIdAction;<br/>extract exactly WorkflowId specify and preserve the remaining arguments]
    WSELECT --> WRESOLVE[Runner invokes ResolveSelectedWorkflowAction;<br/>exactly one match in the validated registry; no default or filename inference]
    WRESOLVE --> CLI[Registered specify invocation-contract node;<br/>runner invokes its ParseSpecifyInvocationAction child]
    CLI --> COK{Runner invokes its ValidateSpecifyArgumentsAction child:<br/>exactly one non-empty --reference value<br/>and no -feature, --feature, --description, positional or unknown input}
    COK -- No --> INPUTERR[Nonzero user-input error<br/>no feature directory, feature log, model call or artifact write]
    COK -- Yes; return validated specify invocation context --> SEL[Normalize required relative selector beneath configured paths.references]
    SEL --> ROOT[Resolve no-follow contained reference root]
    ROOT --> RDIR{Exists, readable directory and regular traversal root}
    RDIR -- No --> INPUTERR
    RDIR -- Yes --> FID[DeriveFeatureIdentityAction<br/>deterministic identity from canonical selector and naming policy]
    FID --> SDDSETUP[Selected specify graph invokes diagram 08 SDD feature-context setup;<br/>resolve the fixed project transaction collection, acquire its lock,<br/>and recover the project WAL and transaction-ID ledger before feature ownership reads]
    SDDSETUP --> FIPATH[ResolveFeatureIdentityRegistryPathAction<br/>sole project-level registry beneath the reserved paths.workflows/features child]
    FIPATH --> FIREAD[ReadFeatureIdentityRegistryAction<br/>bounded no-follow read; absence is valid only before first activation]
    FIREAD --> FIPRESENT{Registry bytes present}
    FIPRESENT -- No --> FIINITIAL[BuildInitialFeatureIdentityRegistryAction<br/>empty revision-zero ownership authority whose identity is exactly<br/>bootstrapRootRegistryId plus revision; consume no project state-ID ordinal]
    FIPRESENT -- Yes --> FIPARSE[ParseFeatureIdentityRegistryAction<br/>all owner and lifecycle pointers remain untrusted]
    FIINITIAL --> FSEMPTY[AssembleFeatureStateInventoryAction<br/>empty ordered inventory for the empty revision-zero ownership registry]
    FIPARSE --> FSPATHS[ResolveFeatureStateInventoryEntryPathsAction<br/>derive exact root/workflow/artifact/ledger header paths per ownership record]
    FSPATHS --> FSCAPTURE[CaptureFeatureStateHeaderObservationAction<br/>one bounded no-follow root or header observation per invocation;<br/>PipelineRunner repeats in canonical feature/path order]
    FSCAPTURE --> FSENTRY[BuildFeatureStateInventoryEntryAction<br/>one live archived or blocking terminal account per ownership record]
    FSENTRY --> FSASSEMBLE[AssembleFeatureStateInventoryAction<br/>complete canonical entry/account set]
    FSEMPTY --> FSVALID{ValidateFeatureStateInventoryAction<br/>exact ownership coverage, root/header identity joins,<br/>containment and hard traversal limits}
    FSASSEMBLE --> FSVALID
    FSVALID -- Invalid --> INPUTERR
    FSVALID -- Valid --> FIVALID{ValidateFeatureIdentityRegistryAction<br/>against the complete current FeatureStateInventory}
    FIVALID -- Invalid --> INPUTERR
    FIVALID -- Valid --> OWNER[ResolveFeatureIdentityTargetAction<br/>new feature or exact existing owner by stored selector and policy version;<br/>reject every other active or archived collision and never suffix]
    OWNER --> TARGET{Exact feature target}
    TARGET -- New --> NFLEDGER[BuildInitialFeatureStateIdLedgerAction then ValidateStateIdLedgerAction<br/>in memory for the exact new feature; persist it only inside activation]
    NFLEDGER --> NEWCTX[Use empty prior preset/principle ID-ledger inputs and buffer<br/>bounded preactivation telemetry; no feature directory or feature log exists]
    TARGET -- Existing owner --> EHEADER[From the validated FeatureStateInventory resolve and validate only<br/>the exact WorkflowArtifactRegistry header and StageTransactionCollection path;<br/>do not trust WorkflowState, BootstrapAuthorityState or any specialized ledger yet]
    EHEADER --> ECAP[LoadActiveFeatureDirectoryCapabilityAction<br/>reissue only for the exact stored owner and fresh no-follow root/header metadata]
    ECAP --> EPRELEASE[ReleaseProjectTransactionCollectionLockAction<br/>immediately after exact ownership and the feature recovery path are resolved;<br/>all later existing-owner work uses only feature-owned storage]
    EPRELEASE --> ERECOVER[Invoke diagram 09 in recovery-only feature mode:<br/>acquire the exact feature collection lock, scan journals, load/initialize and validate<br/>its TransactionIdLedger, build/validate the typed recovery plan, perform every disposition,<br/>commit or retire each ID before cleanup, rescan, then release the feature lock;<br/>assign no new transaction ID and trust no canonical feature authority during recovery]
    ERECOVER --> EFLEDGER[ResolveFeatureStateIdLedgerPathAction, ReadStateIdLedgerAction,<br/>ParseStateIdLedgerAction and ValidateStateIdLedgerAction<br/>against the recovered exact inventory header and feature owner]
    EFLEDGER --> ELOAD[Only after feature-WAL recovery, bounded-load/parse/validate<br/>the exact current WorkflowArtifactRegistry, WorkflowState, BootstrapAuthorityState,<br/>actor/review/control/passive/clarification authorities and prior preset/principle ledgers]
    ELOAD --> ELOG[BuildFeatureLogPolicyIdAction, BuildFeatureLogPolicyAction and<br/>ValidateFeatureLogPolicyAction from the persisted current BootstrapAuthorityState<br/>and its recorded config version; initialize/recover all streams through diagram 06,<br/>acquiring/validating/releasing each exact stream lock]
    ELOG --> ELOGREADY[Historical-policy feature log ready before bootstrap refresh;<br/>record bootstrap failures under that validated current policy and buffer bounded<br/>successor-policy telemetry until a compatible refresh commits]
    ELOGREADY --> SOPEN{Current validated WorkflowState has an open SNN}
    SOPEN -- No --> POSTBOOT
    SOPEN -- Yes --> SRESUME[Invoke diagram 07 before any refreshed authority is referenced:<br/>load current registry/forms; ParseClarificationViewAction; validate static/current submission;<br/>authenticate only a valid submission and commit response through diagram 09]
    SRESUME -- Invalid or stale submission --> INPUTERR
    SRESUME -- Authenticated cancel --> SCANCEL[Return cancelled; no bootstrap/reference/spec generation]
    SRESUME -- Defer or another SNN remains open --> SWAIT[Return spec_clarification_pending;<br/>persisted registry/form/workflow authority is already complete]
    SRESUME -- Final user closure for a conflict-bound SNN --> CRESPONSE
    SRESUME -- Final non-conflict closure --> POSTBOOT
    SRESUME -- No submission --> SREFRESH[Invoke diagram 07 authority refresh/resolver path;<br/>compare direct current authorities, deduplicate the same subject, and commit any<br/>same-open pause or authority resolution before leaving the pending stage]
    SREFRESH -- Still open unchanged or refreshed --> SWAIT
    SREFRESH -- Final authority resolution --> POSTBOOT
    NEWCTX --> POSTBOOT[The selected specify graph invokes the target-context setup portion in diagram 08<br/>using empty prior ledgers for new or validated prior ledgers for existing]
    POSTBOOT --> PRESETS[Validated ToolchainPresetRegistryState, typed project-toolchain layer,<br/>CompiledEnvironmentPolicies and command/parser/resource authorities]
    POSTBOOT --> PREG[Validated separate PrincipleRegistryState<br/>complete opaque Markdown and deterministic transport chunks;<br/>exact paths.principles/toolchain.yaml is excluded from free-text ingestion]
    PREG -. selected only at plan tasks and implement; absent from reference/specify routes .-> LATER[Later-stage bounded complete category-based principle selections]
    PRESETS --> POLICY[Receive the ValidatedBootstrapOperationalCandidate from diagram 08:<br/>validated typed leaf candidates plus identity-free grammar/policy aggregate blueprints;<br/>no generic canonical component or bootstrap-state ID is allocated]
    PREG --> POLICY
    POLICY --> BCASE{Feature target}
    BCASE -- New --> NEWBOOT[Retain the validated candidate in memory only;<br/>assign no bootstrap-state ID or path before the artifact registry exists]
    BCASE -- Existing --> EBOOT[Run the complete diagram 08 direct-equality/change classification:<br/>unchanged and compatible/later-stage rework routes commit through their owning feature transaction;<br/>administrative change blocks; ReferenceIngestion and an owning-stage SpecificationContract change<br/>return only typed identity-free candidate/change evidence/classification handoffs]
    EBOOT --> EBAUTH{Bootstrap classification permits this reference route}
    EBAUTH -- Administrative or incompatible current workflow --> PREBLOCK
    EBAUTH -- Unchanged or prerequisite rework/refresh committed --> PSESSION
    EBAUTH -- ReferenceIngestion typed handoff; no write in diagram 08 --> RBUNDLE[Retain the bounded typed handoff in memory for this run only;<br/>identity-free bootstrap candidate, candidate-change evidence and exact classification]
    RBUNDLE --> PSESSION[BuildReferencePreactivationSessionAction<br/>trusted run, selector and feature seed; run-local source/block counters only;<br/>no canonical reference identity is allocated, persisted, rendered, logged or model-visible]
    EBAUTH -- SpecificationContract handoff while specifying --> SBUNDLE[Retain the bounded typed specification-contract handoff in memory only;<br/>adopt it only in the next owning specification completion or clarification transaction]
    SBUNDLE --> PSESSION
    EBAUTH -- SpecificationContract handoff while spec_clarification_pending --> CLIFE
    NEWBOOT --> PSESSION

    PSESSION --> BUDGET[BuildReferencePreactivationSourceBudgetLedgerAction and<br/>BuildReferencePreactivationDecodedBudgetLedgerAction plus bounded entry, depth,<br/>time and memory capabilities; every identity and budget is provisional]
    BUDGET --> INV[Enumerate bounded unordered entries without following symlinks]
    INV --> COUNT{Entry count and traversal telemetry within hard limits}
    COUNT -- No --> PREBLOCK[Blocking preactivation diagnostic<br/>new target: no feature directory or per-feature log;<br/>existing owner: record failure in its ready feature log and commit no new snapshot/spec]
    COUNT -- Yes --> DEPTH{Every entry within directory-depth limit}
    DEPTH -- No --> PREBLOCK
    DEPTH -- Yes --> PATH[Validate UTF-8, NFC, containment and host/target portable paths]
    PATH --> COLL{No duplicate or portability collision}
    COLL -- No --> PREBLOCK
    COLL -- Yes --> SORT[SortReferenceInventoryAction<br/>normalized Unicode-scalar relative path; assign no identity]
    SORT --> SOURCEID[AssignReferencePreactivationSourceIdAction<br/>one run-local identity per ordered entry; thread the successor session]
    SOURCEID --> CLASS{Classify each entry under explicit hidden and symlink policy}

    CLASS -- Accepted exclusion --> EXCLUDED[Retain accepted provisional exclusion outcome]
    CLASS -- Unaccepted exclusion or unsupported node --> BAD[Retain exact provisional blocking outcome and diagnostic]
    CLASS -- Included regular file --> READ{Open readable bounded no-follow regular-file descriptor}
    READ -- No --> BAD
    READ -- Yes --> SIZE{Descriptor size within per-file source limit}
    SIZE -- No --> BAD
    SIZE -- Yes --> SRES{Reserve source bytes in current ledger revision}
    SRES -- No capacity --> BAD
    SRES -- Reserved --> CAPTURE[Capture immutable source blob through the same descriptor]
    CAPTURE --> STABLE{Identity, type and exact length stable; no overrun}
    STABLE -- No --> SREL[Release reservation]
    SREL --> BAD
    STABLE -- Yes --> SCOMMIT[Commit actual source-byte debit]
    SCOMMIT --> MIME[Sniff captured blob and probe exact-version primary then fallback readers]
    MIME --> READER{Unique eligible highest-ranked reader}
    READER -- No reader or rank tie --> BAD
    READER -- Yes --> DRES{Reserve decoded-byte ceiling and remaining corpus allowance}
    DRES -- No capacity --> BAD
    DRES -- Reserved --> DBUD[Build sandboxed decoder budget]
    DBUD --> DECODE[Decode into bounded block proposals with telemetry]
    DECODE --> DSTAT{Decode outcome and all byte, time, memory, block, page and cell limits valid}
    DSTAT -- Empty --> EMPTY[Release decoded reservation and retain positive-empty decode outcome]
    DSTAT -- Failed, terminated or over limit --> DREL[Release decoded reservation]
    DREL --> BAD
    DSTAT -- Decoded --> DCOMMIT[Commit actual decoded-byte debit then<br/>AssignReferencePreactivationBlockIdAction for every ordered block proposal]
    DCOMMIT --> DOBS[Retain successful nonempty decode observation, identified blocks<br/>and decoder coordinate proposal; do not materialize a source map,<br/>canonical ReferenceEntry or semantic block status yet]

    EXCLUDED --> PBRANCH[BuildReferencePreactivationBranchAction<br/>project one closed provisional inventory/capture/decode outcome per source;<br/>construct no canonical ReferenceEntry or semantic block status]
    EMPTY --> PBRANCH
    BAD --> PBRANCH
    DOBS --> PBRANCH
    PBRANCH --> PBSET[BuildReferencePreactivationBranchSetAction<br/>join exactly one branch to every identified source in source order]
    PBSET --> CLOSE[Close source and decoded ledgers and validate exact totals]
    CLOSE --> PCOVER{ValidateReferencePreactivationCoverageAction<br/>inventory, blobs, reader/decode/identified-block outcomes and both budgets<br/>join exactly once; no source-map/chunk/semantic acceptance yet}
    PCOVER -- Invalid --> PREBLOCK
    PCOVER -- Valid --> PRE{ValidateReferencePreactivationAction<br/>nonempty mandatory corpus; no unsupported failed or blocked source}
    PRE -- No --> PREBLOCK
    PRE -- Yes --> POSTPRE{Feature target}
    POSTPRE -- Existing owner --> EACTIVE[Use the already validated current/successor BootstrapAuthorityState,<br/>WorkflowArtifactRegistry, feature StateIdLedger, authorities and ready feature log]
    POSTPRE -- New --> NALLOC[From the validated initial feature StateIdLedger build purpose keys/capabilities;<br/>call only AssignBootstrapAuthorityStateIdAction and then<br/>AssignWorkflowArtifactRegistryStateIdAction, threading their exact successors;<br/>generic bootstrap-component identities are owner-local and consume no state-ledger ordinal]
    NALLOC --> ART[Build, resolve and validate WorkflowArtifactRegistry<br/>fixed spec.md, plan.md, tasks.md, clarify, state and feature-log paths;<br/>no model-supplied artifact filename]
    ART --> NLEAF[AssignBootstrapComponentIdAction for every generic leaf and compiled-policy slot,<br/>plus AssignPathTokenGrammarStateIdAction for the base grammar;<br/>MaterializeBootstrapCandidateComponentAction only for leaf candidates]
    NLEAF --> NLEAFMAP[BuildBootstrapCandidateDependencyResolutionMapAction for leaf_dependencies then<br/>ValidateBootstrapCandidateDependencyResolutionMapAction; only aggregate handles remain unresolved]
    NLEAFMAP --> NGRAMMAR[BuildSupersetPathTokenGrammarAction, ValidateSupersetPathTokenGrammarAction<br/>and BindDerivedBootstrapCandidateComponentAction using the validated leaf map]
    NGRAMMAR --> NGRAMMARMAP[BuildBootstrapCandidateDependencyResolutionMapAction and<br/>ValidateBootstrapCandidateDependencyResolutionMapAction at base_grammar_resolved;<br/>prove strict extension from leaf_dependencies and only policy remains unresolved]
    NGRAMMARMAP --> NPOLICY[AssembleCompiledEnginePolicyAction, ValidateCompiledEnginePolicyAction<br/>and BindDerivedBootstrapCandidateComponentAction using the grammar-resolved map]
    NPOLICY --> NCOMPLETEMAP[BuildBootstrapCandidateDependencyResolutionMapAction and<br/>ValidateBootstrapCandidateDependencyResolutionMapAction at complete;<br/>prove total one-to-one generic-handle coverage with none unresolved]
    NCOMPLETEMAP --> NMAT[BuildBootstrapAuthorityStateCoreAction and ValidateBootstrapAuthorityStateCoreAction,<br/>then BuildInitialBootstrapAuthorityStateAction and ValidateBootstrapAuthorityStateAction;<br/>resolve/serialize through the exact artifact collection; bytes remain transaction-private]
    NMAT --> PASS0[Assign, build and validate the revision-zero passive-literal registry<br/>under the canonical base grammar; consume the exact artifact-ledger successor<br/>and return the next feature-ledger successor]
    PASS0 --> ACTOR0[Assign, build and validate empty revision-zero ActorEvidenceRegistryState;<br/>consume the exact passive-ledger successor and return the next]
    ACTOR0 --> REVIEW0[AssignReviewDecisionRegistryStateIdAction then<br/>BuildInitialReviewDecisionRegistryAction and ValidateReviewDecisionRegistryAction;<br/>consume the exact actor-ledger successor and return the next]
    REVIEW0 --> CONTROL0[AssignWorkflowControlEventRegistryStateIdAction then<br/>BuildInitialWorkflowControlEventRegistryAction and ValidateWorkflowControlEventRegistryAction;<br/>consume the exact review-ledger successor and return the next]
    CONTROL0 --> CLAR0[Assign, build and validate empty revision-zero clarification registry<br/>and its S/P/T owner-local ID ledger; consume the exact control-ledger successor and return the next]
    CLAR0 --> WF0[Assign and build the pre-snapshot specifying WorkflowState bound to all five<br/>revision-zero registries and exact feature, clarify, log and engine-state entries;<br/>consume the exact clarification-ledger successor; the initial state has no currentReferenceStateId]
    WF0 --> FIOWN[BuildFeatureIdentityOwnershipRecordAction<br/>bind the new target to prospective workflow, artifact and root identities]
    FIOWN --> FINEXT[BuildNextFeatureIdentityRegistryAction<br/>compare-and-swap append exactly one active ownership record]
    FINEXT --> FINVALID{ValidateFeatureIdentityRegistryAction<br/>input and successor revisions, ownership uniqueness and exact pointers}
    FINVALID -- Invalid --> PREBLOCK
    FINVALID -- Valid --> FISERIAL[SerializeFeatureIdentityRegistryAction]
    FISERIAL --> ACT09[Invoke diagram 09 project-storage lifecycle for feature_activation:<br/>recover first; reserve and fsync the collection-local transaction ID;<br/>then BuildFeatureActivationStageTransactionAction and ValidateFeatureActivationStageTransactionAction<br/>with the mandatory DurableTransactionMember, validate project storage, journal/apply/mark,<br/>commit the transaction ID, clean up and ReleaseProjectTransactionCollectionLockAction exactly once]
    ACT09 --> CAP[BuildActiveFeatureDirectoryCapabilityAction<br/>issue only from the durably committed activation]

    CAP --> NLOG[Run the complete feature-log startup protocol in diagram 06;<br/>for each enabled stream acquire and validate its exact lock capability,<br/>inspect or initialize/recover, apply retention, then release every lock]
    NLOG --> LOGREADY[Feature log ready; flush bounded preactivation metadata<br/>without exposing any provisional reference identity]

    EACTIVE --> RRID[AssignReferenceStateIdAction from the exact current validated feature ledger]
    LOGREADY --> RRID
    RRID --> RRESERVE[Invoke diagram 09 feature-storage lifecycle for state_identity_reservation:<br/>acquire the feature collection lock; reserve/fsync the transaction ID; then build/validate<br/>StateIdentityReservationStageTransaction with its DurableTransactionMember;<br/>commit the purpose-bound reference-state reservation and transaction ID,<br/>clean up and ReleaseFeatureTransactionCollectionLockAction exactly once]
    RRESERVE --> RPOSTLEDGER[ResolveFeatureStateIdLedgerPathAction, ReadStateIdLedgerAction,<br/>ParseStateIdLedgerAction and ValidateStateIdLedgerAction after the committed reservation;<br/>all later feature-state allocations consume this current revision or a threaded successor]
    RPOSTLEDGER --> RLEDGER[BuildReferenceIdLedgerAction<br/>initialize or advance the canonical reference-local namespaces]
    RLEDGER --> RCSOURCE[AssignReferenceSourceIdAction for every ordered provisional source;<br/>thread the exact successor reference ledger]
    RCSOURCE --> RBUDID[AssignReferenceBudgetReservationIdAction<br/>construct owner-local referenceStateId/sourceId/source_bytes or decoded_bytes tuples;<br/>consume no ReferenceIdLedger namespace]
    RBUDID --> RCBLOCK[AssignReferenceBlockIdAction for every ordered provisional block;<br/>thread the exact successor reference ledger]
    RCBLOCK --> RCLONE[ClonePreactivationBlobIntoReferenceStateAction<br/>copy every accepted provisional blob into the write-once canonical namespace]
    RCLONE --> RIMAP[BuildReferencePreactivationIdentityMapAction<br/>total provisional-to-canonical source, block, blob and reservation mappings]
    RIMAP --> RBUDCOVER{ValidateReferenceBudgetReservationIdentityCoverageAction<br/>exact applicable source/kind coverage, unique tuples and total provisional mapping}
    RBUDCOVER -- Invalid --> INVALID
    RBUDCOVER -- Valid --> RSBUDGET[MaterializeReferenceSourceBudgetLedgerAction<br/>translate the closed source ledger without changing limits or totals]
    RBUDCOVER -- Valid --> RDBUDGET[MaterializeReferenceDecodedBudgetLedgerAction<br/>translate the closed decoded ledger without changing limits or totals]
    RSBUDGET --> RIMAPVALID{ValidateReferencePreactivationIdentityMapAction<br/>one-to-one order-preserving coverage and no provisional identity survives}
    RDBUDGET --> RIMAPVALID
    RIMAPVALID -- Invalid --> INVALID
    RIMAPVALID -- Valid --> CENTERMINAL[BuildExcludedReferenceEntryAction and BuildEmptyReferenceEntryAction<br/>for the corresponding mapped canonical sources]
    RIMAPVALID -- Valid --> SMAP[Validate and build canonical source maps from the<br/>mapped provisional decode observations; defer manifest completeness]
    DOBS -. in-memory decode and map proposal .-> SMAP
    SMAP --> FACTS[Extract deterministic structured facts and preservation candidates]
    FACTS --> PSCAN[Scan decoded source spans for passive literals]
    PSCAN --> PASS[Assign, build and validate next exact PassiveLiteralRegistry revision]
    SMAP --> CHUNK[Create bounded source-located chunks]
    CHUNK --> ALLOW[Select chunk-local source-token and passive-literal allowlists]
    PASS --> ALLOW
    FACTS --> ALLOW

    ALLOW --> EXTRACT[reference.extract returns only closed claim/citation proposals]
    EXTRACT --> XSCHEMA[Validate runner-bound call association,<br/>compact result schema and positive extraction outcome]
    XSCHEMA --> CITE[Validate every citation against immutable source bytes, source map and chunk]
    CITE --> CID[Assign canonical citation and claim IDs; validate typed claims]
    FACTS --> TOK[Validate one preserve/irrelevant disposition per structured candidate]
    TOK --> TBUILD[Assign token IDs and build source-grounded preservation claims]
    CID --> DISP[Attach exactly one extraction disposition to every expected chunk]
    TBUILD --> DISP
    DISP --> CACCT[Prove all chunks accounted exactly once]
    CACCT --> BLOCKS[DeriveBlockDispositionAction<br/>produce every canonical ContentBlock with its final accountingStatus]
    BLOCKS --> MERGE[Merge identified claims into bounded reconciliation clusters]
    MERGE --> RECON[reference.reconcile returns one closed reconciliation proposal per cluster]
    RECON --> RVALID[Validate supplied IDs, total claim dispositions, signals and conflicts]
    RVALID --> RLOCUS[BuildReferenceAuthorityLocusAction for every conflict citation from its<br/>fresh manifest/source-map/decoder/direct-capture coordinates; include no snapshot-local ID]
    RLOCUS --> RSUBJECT[BuildReferenceConflictSubjectCoordinateAction<br/>structural conflict kind, decision slot and canonically ordered authority loci]
    RSUBJECT --> ROPTION[BuildReferenceConflictOptionContinuityKeyAction for each exact claim option<br/>from typed content, direct captured scalar spans, citations and loci]
    ROPTION --> RCONTINUITY{ValidateReferenceConflictContinuityKeySetAction<br/>complete one-to-one current claim coverage, unique keys and exact source equality}
    RCONTINUITY -- Invalid --> INVALID
    RCONTINUITY -- Valid --> RCONFLICTS[BuildSourceConflictAction for every validated proposal<br/>with its snapshot-independent subject coordinate and option-continuity keys]
    RCONFLICTS --> LEDGERS[Build canonical claim, signal and conflict ledgers]
    BLOCKS --> DENTRY[BuildDecodedReferenceEntryAction<br/>only from a successful decode whose every block has a final status]
    LEDGERS --> DENTRY
    DENTRY --> FACCOUNT[ValidateReferenceEntryAccountingAction<br/>for each canonical entry and its final accounted block set]
    CENTERMINAL --> FACCOUNT
    FACCOUNT --> MANIFEST[BuildReferenceManifestAction then<br/>ValidateReferenceManifestCompletenessAction from exactly one final<br/>entry candidate per ordered source and the closed budget ledgers]

    LEDGERS --> CONTEXT[Build and validate complete ReferenceContext including conflict IDs]
    MANIFEST --> SNAP[Assemble immutable ReferenceSnapshot candidate]
    CONTEXT --> SNAP
    PASS --> SNAP
    LEDGERS --> SNAP
    SNAP --> SVALID[ValidateReferenceSnapshotAction<br/>all manifests, maps, chunks, ledgers, budgets, passive registry and authority joins]
    SVALID -- Invalid --> INVALID[No reference or specification transaction commit]

    SVALID -- Valid --> CSETP[BuildPriorReferenceConflictClarificationSubjectSetAction then<br/>ValidatePriorReferenceConflictClarificationSubjectSetAction;<br/>project the complete canonical prior set P from the latest active clarification revisions,<br/>or the explicit empty P with no prior pointer for initial ingestion]
    CREFRUN -. durable response ID plus the prior registry/reference bindings only;<br/>never retained source bytes .-> CSETP
    CSETP --> CSETC[BuildCurrentUnresolvedReferenceConflictSubjectSetAction then<br/>ValidateCurrentUnresolvedReferenceConflictSubjectSetAction;<br/>project the complete canonical current set C from every unresolved behavior-changing<br/>conflict in this fully validated fresh snapshot]
    CSETC --> CSETREC[ReconcileReferenceConflictSubjectSetsAction then<br/>ValidateReferenceConflictSubjectSetReconciliationAction;<br/>exact full-key merge join into disjoint exhaustive P intersection C, P minus C and C minus P;<br/>no hash, wording, position, cardinality, fuzzy similarity or unequal-key pairing]
    CSETREC --> CEQUAL{Next canonical P intersection C entry}
    CEQUAL -- Usable closed response --> CREFCORR[BuildFreshReferenceConflictCorrespondenceAction then<br/>ValidateFreshReferenceConflictCorrespondenceAction for this exact equal-key entry only,<br/>using freshly captured descriptors, maps, typed claims, ranges and scalar bytes]
    CREFCORR --> CREFCGATE{Correspondence candidate and validation evidence valid}
    CREFCGATE -- Invalid --> INVALID
    CREFCGATE -- Valid --> CREFKIND{FreshReferenceConflictCorrespondence variant}
    CREFKIND -- current with total selected-option mapping --> CREFDECID[AssignReferenceConflictDecisionIdAction from the refreshed candidate ledger;<br/>BuildReferenceConflictDecisionFromClarificationResponseAction against the mapped<br/>current candidate conflict, claims and citations; never against the prior snapshot]
    CREFKIND -- stale_same_subject --> CREFSTALE[RefreshReferenceConflictClarificationAction;<br/>record a same-ID open outcome with current snapshot-local conflict/options<br/>and allocate no decision or clarification ID]
    CEQUAL -- No usable closed response --> CREFUNANSWERED[RefreshReferenceConflictClarificationAction;<br/>record the same-ID open outcome for this directly equal structural key]
    CREFSTALE --> CEQUAL
    CREFUNANSWERED --> CEQUAL
    CREFDECID --> CREFVALID{ValidateReferenceConflictResolutionDecisionAction<br/>subject, conflict and mapped selected claims remain revision-current}
    CREFVALID -- Race or post-allocation validation failure --> CREFRETIRE[RetireReferenceAllocatedIdAction<br/>tombstone the exact conflict-decision ID without rewinding its namespace]
    CREFRETIRE --> CREFLEDGER{ValidateReferenceIdLedgerAction<br/>prove the successor ordinal/tombstone and all current reference allocations}
    CREFLEDGER -- Invalid --> INVALID
    CREFLEDGER -- Valid --> CREFUNDECIDED{Rebuild the undecided conflict/decision ledger and successor snapshot with the<br/>tombstoned ID; rerun ValidateReferenceSnapshotAction and every complete join}
    CREFUNDECIDED -- Invalid --> INVALID
    CREFUNDECIDED -- Valid --> SVALID
    CREFVALID -- Valid --> CREFRESOLVE[BuildResolvedSourceConflictAction<br/>apply only the current-authority decision and retain its authenticated decision ID]
    CREFRESOLVE --> CREFREBUILD[Rebuild conflict/decision and claim-disposition ledgers, ReferenceContext<br/>and successor snapshot candidate; rerun complete accounting, reconciliation,<br/>citation, exact-token, source-map, manifest and full-snapshot validation]
    CREFREBUILD --> SVALID
    CEQUAL -- No entries remain --> COBSOLETE{Next canonical P minus C entry}
    COBSOLETE -- Present --> COBCLOSE[AssignClarificationResolutionIdAction then<br/>BuildObsoleteReferenceConflictAuthorityResolutionAction from the entry's exhaustive<br/>current-set absence correspondence; close only that prior key and name no replacement]
    COBCLOSE --> COBSOLETE
    COBSOLETE -- None remain --> CINTRO{Next canonical C minus P entry}
    CINTRO -- Present --> CINEED[BuildReferenceConflictClarificationNeedAction for that exact current conflict;<br/>FindExistingClarificationBySubjectAction and ValidateClarificationSubjectUniquenessAction<br/>perform the global exact full-key lookup across open and closed history]
    CINEED --> CIIDENT[Reuse and reopen the exact existing identity, or call AssignClarificationIdAction<br/>only after validated global absence; keep a new identity and successor ledger transaction-private<br/>until the complete registry/view/reference/workflow commit, otherwise discard the whole candidate]
    CIIDENT --> CIOPEN[BuildIntroducedReferenceConflictOpeningAction;<br/>bind the current conflict/options without pairing it to any obsolete prior key]
    CIOPEN --> CINTRO
    CINTRO -- None remain --> CSETBUILD[BuildReferenceConflictClarificationSetTransitionAction once from every<br/>same-key decision/reopen outcome, obsolete closure, introduced opening and the fully<br/>threaded successor clarification ID ledger in canonical partition order]
    CSETBUILD --> CSETSTATE[AssignClarificationStateIdAction then call<br/>BuildNextClarificationRegistryAction exactly once with the complete set transition]
    CSETSTATE --> CVIEWS[RenderClarificationViewAction for the complete clarification view set;<br/>ValidateClarificationViewLifecycleAction per view and ValidateClarificationViewSetAction globally;<br/>only expected-open SNN keys expose submittable forms, while closed historical views remain<br/>read-only for audit; also render the current conflict-bearing reference-context view]
    CVIEWS --> CSETVALID[ValidateReferenceConflictClarificationSetTransitionAction then<br/>ValidateClarificationRegistryAction; reprove complete partition/allocator coverage and exact<br/>equality of unresolved current keys, open registry keys and submittable form-view keys]
    CSETVALID -- Invalid --> INVALID
    CSETVALID -- Valid --> CSETOPEN{expectedOpenCurrentSubjectKeys}
    CSETOPEN -- Nonempty --> CBOOT{Staged bootstrap handoff kind}
    CSETOPEN -- Empty --> RBSTAGED{This snapshot was ingested under the staged<br/>ReferenceIngestion bootstrap handoff}
    RBUNDLE -. exact run-local typed handoff .-> RBSTAGED
    RBSTAGED -- No --> SUCCESSOR{Snapshot replaces an existing durable reference<br/>or follows a committed conflict response}
    RBSTAGED -- Yes --> RBTXBEGIN[Enter diagram 09 feature-storage reference_revision lifecycle only now:<br/>acquire/recover the feature collection, reserve and fsync its transaction ID,<br/>then keep the validated feature lock/storage capability through transaction completion]
    RBTXBEGIN --> RBLEDGER[ResolveFeatureStateIdLedgerPathAction, ReadStateIdLedgerAction,<br/>ParseStateIdLedgerAction and ValidateStateIdLedgerAction again after the earlier<br/>state_identity_reservation commit; never allocate from the stale pre-reservation revision]
    RBLEDGER --> RBALLOC[AssignBootstrapAuthorityStateIdAction; assign leaf/policy component IDs with<br/>AssignBootstrapComponentIdAction and the grammar ID with AssignPathTokenGrammarStateIdAction;<br/>MaterializeBootstrapCandidateComponentAction only for leaf candidates,<br/>threading only the exact reloaded feature StateIdLedger successor]
    RBALLOC --> RBLEAFMAP[BuildBootstrapCandidateDependencyResolutionMapAction for leaf_dependencies<br/>then ValidateBootstrapCandidateDependencyResolutionMapAction]
    RBLEAFMAP --> RBGRAMMAR[Build/validate the identified superset grammar and<br/>BindDerivedBootstrapCandidateComponentAction for its aggregate handle]
    RBGRAMMAR --> RBGRAMMARMAP[BuildBootstrapCandidateDependencyResolutionMapAction then<br/>ValidateBootstrapCandidateDependencyResolutionMapAction at base_grammar_resolved<br/>as a strict extension of leaf_dependencies]
    RBGRAMMARMAP --> RBPOLICY[AssembleCompiledEnginePolicyAction and ValidateCompiledEnginePolicyAction,<br/>then BindDerivedBootstrapCandidateComponentAction for the policy aggregate]
    RBPOLICY --> RBCOMPLETEMAP[BuildBootstrapCandidateDependencyResolutionMapAction then<br/>ValidateBootstrapCandidateDependencyResolutionMapAction at complete;<br/>prove all generic handles resolved exactly once]
    RBCOMPLETEMAP --> RBSTATE[BuildBootstrapAuthorityStateCoreAction and<br/>ValidateBootstrapAuthorityStateCoreAction; the unlinked core contains no parent<br/>or change-evidence claim]
    RBSTATE --> RBEVID[BindMaterializedBootstrapChangeEvidenceAction then<br/>ValidateMaterializedBootstrapChangeEvidenceAction;<br/>replace every candidate handle with the exact staged successor identity]
    RBEVID --> RBFINAL[BuildSuccessorBootstrapAuthorityStateAction with the exact current parent/evidence,<br/>ValidateBootstrapAuthorityStateAction, ResolveBootstrapAuthorityStatePathAction<br/>and SerializeBootstrapAuthorityStateAction; bytes remain transaction-private]
    RBFINAL --> RBREVINPUT[Select NoReferenceDescendantMutation, InvalidateUncommittedReferenceDescendants<br/>or ReconcileCommittedReferenceDescendants; both nonempty variants call<br/>AssignReworkInvalidationRecordIdAction, BuildReworkInvalidationRecordAction and<br/>ValidateReworkInvalidationRecordAction; the committed variant additionally calls<br/>BuildReconciledTaskRuntimeStateAction, AssignExecutionEvidenceRegistryStateIdAction,<br/>AssignExecutionEvidenceInvalidationIdAction, BuildNextExecutionEvidenceRegistryWithRetirementsAction,<br/>BuildExecutionEvidenceInvalidationRecordAction and ValidateExecutionEvidenceInvalidationAction;<br/>append rework then evidence-invalidation control events through successive state IDs,<br/>thread every feature-ledger/control successor, render the reference view,<br/>then AssignWorkflowStateIdAction and BuildNextStageStateAction to specifying]
    RBREVINPUT --> RBREV09[Continue the same diagram 09 reference_revision lifecycle:<br/>BuildReferenceRevisionStageTransactionAction and ValidateWorkflowTransitionStageTransactionAction<br/>with the successor snapshot/bootstrap, complete reference-conflict set transition, next clarification<br/>registry, complete view set whose submittable projection is empty, materialized change evidence,<br/>feature-ledger successor and complete descendant mutation; journal/apply/mark, commit the transaction ID,<br/>clean up and release the feature lock]
    RBREV09 --> RBLOG{Adopted changePlan.obligations.transitionFeatureLogging}
    RBLOG -- False --> BRIEF
    RBLOG -- True --> RBLOGTX[Invoke diagram 06 policy transition before any normal log/model/node;<br/>validate old/new bindings, close every historical tail under transition locks,<br/>assemble/validate the successor sink and atomically activate it]
    RBLOGTX --> BRIEF
    RBUNDLE -. ReferenceIngestion .-> CBOOT
    SBUNDLE -. SpecificationContract .-> CBOOT
    CBOOT -- None --> CTX[Assemble complete SpecificationClarificationPause inputs:<br/>validated ReferenceSnapshot, complete reference-conflict set transition, next clarification<br/>registry, retain-current bootstrap mutation, named descendant mutation, authorities,<br/>every required form/reference view and spec_clarification_pending workflow state;<br/>SpecificationIR, PlanState and TaskDefinitionState are forbidden]
    CTX --> CWAL[Invoke diagram 09 feature-storage clarification_pause lifecycle;<br/>after its durable transaction-ID reservation call BuildClarificationPauseStageTransactionAction once<br/>and ValidateClarificationStageTransactionAction with mandatory state/transaction identity members;<br/>atomically commit the snapshot, complete set transition, next registry, all SNN forms/views,<br/>identities and pending state, then commit the transaction ID and release the feature lock]
    CBOOT -- ReferenceIngestion --> RBPAUSEMAT[Enter diagram 09 clarification_pause lifecycle, acquire/recover storage and reserve/fsync<br/>its transaction ID; then assign bootstrap/leaf/grammar/policy IDs and materialize leaves;<br/>build/validate dependency maps at leaf_dependencies, base_grammar_resolved and complete around the<br/>derived grammar then compiled-policy aggregate bindings; BuildBootstrapAuthorityStateCoreAction and<br/>validate the core; BindMaterializedBootstrapChangeEvidenceAction and validate evidence; only then<br/>BuildSuccessorBootstrapAuthorityStateAction, ValidateBootstrapAuthorityStateAction, resolve and serialize;<br/>select the exact no/uncommitted/committed ReferenceRevisionDescendantMutation; both nonempty variants<br/>AssignReworkInvalidationRecordIdAction, BuildReworkInvalidationRecordAction and<br/>ValidateReworkInvalidationRecordAction; the committed variant additionally builds reconciled runtime<br/>and the exact evidence-retirement chain; append rework then evidence-invalidation control events through<br/>successive state IDs, thread all feature-ledger/control successors, then AssignWorkflowStateIdAction<br/>and BuildNextStageStateAction to spec_clarification_pending]
    RBPAUSEMAT --> RBPAUSEWAL[BuildClarificationPauseStageTransactionAction once with extended<br/>SpecificationClarificationPauseEntries: adopt-successor ReferenceRevision bootstrap mutation,<br/>complete reference-conflict set transition, next registry, every required SNN form/reference view,<br/>materialized change evidence, snapshot, named descendant mutation, all feature-ledger successors<br/>and pending workflow; ValidateClarificationStageTransactionAction, journal/apply/mark,<br/>commit transaction ID, clean up and release the feature lock]
    RBPAUSEWAL --> RBPLOG{Adopted changePlan.obligations.transitionFeatureLogging}
    RBPLOG -- False --> CPENDING
    RBPLOG -- True --> RBPLOGTX[Invoke diagram 06 complete policy transition before entering user wait]
    RBPLOGTX --> CPENDING
    CBOOT -- SpecificationContract --> SBPAUSEBEGIN[Enter diagram 09 clarification_pause lifecycle after form construction:<br/>acquire/recover storage, reserve/fsync transaction ID and revalidate workflow/feature ledger;<br/>assign authority/leaf/grammar/policy IDs and materialize leaves; build/validate the dependency map at<br/>leaf_dependencies, bind grammar, extend/validate at base_grammar_resolved, bind policy, then extend/validate<br/>at complete; build/validate core and materialized change evidence; BuildSuccessorBootstrapAuthorityStateAction<br/>and ValidateBootstrapAuthorityStateAction; resolve/serialize transaction-private bytes;<br/>AssignWorkflowStateIdAction then BuildNextStageStateAction to spec_clarification_pending<br/>with the exact remaining-open projection, threading all clarification/workflow successors]
    SBPAUSEBEGIN --> SBPAUSEWAL[BuildClarificationPauseStageTransactionAction once with the closed<br/>adopt-successor SpecificationContract bootstrap mutation, conflict-bearing snapshot, complete<br/>reference-conflict set transition, next registry, every required SNN form/reference view and pending<br/>workflow; ValidateClarificationStageTransactionAction, journal/apply/mark, commit transaction ID,<br/>clean up and release feature lock]
    SBPAUSEWAL --> SBPLOG{Adopted changePlan.obligations.transitionFeatureLogging}
    SBPLOG -- False --> CPENDING
    SBPLOG -- True --> SBPLOGTX[Invoke diagram 06 complete policy transition before entering user wait]
    SBPLOGTX --> CPENDING
    CWAL --> CPENDING[NeedsUser in spec_clarification_pending;<br/>no feature brief or partial specification IR is persisted]
    CPENDING -. a later invocation restarts at START and must pass the SOPEN resume gate .-> START
    CRESPONSE[Committed final closed conflict-bound SNN response from the current-run resume gate]
    CRESPONSE --> CREFRUN[Run the complete current target-context bootstrap and selected-directory flow again:<br/>fresh no-follow inventory, bounded capture/decode, provisional preactivation,<br/>canonical identity reservation/materialization, extraction and reconciliation;<br/>the committed response is authority, but prior blobs/snapshot are not reused]
    CREFRUN --> POSTBOOT
    SUCCESSOR -- No; new feature initial conflict-free ingestion --> BRIEF[Begin or regenerate the complete specification workflow from its first YAML-declared unit<br/>the declared feature-brief operation receives durable bounded reconciled authority]
    SUCCESSOR -- Yes --> RRTX[Assemble complete ReferenceRevision inputs:<br/>successor snapshot, complete reference-conflict set transition, next clarification registry,<br/>complete clarification view set with an empty submittable projection, current actor/passive<br/>authorities, retain-current bootstrap mutation, relevant ledger successors, exact<br/>no/uncommitted/committed descendant mutation, reference view and resumed specifying workflow state]
    RRTX --> RRTWAL[Invoke diagram 09 feature-storage reference_revision lifecycle;<br/>after its transaction-ID reservation call BuildReferenceRevisionStageTransactionAction<br/>and ValidateWorkflowTransitionStageTransactionAction, commit the successor authorities,<br/>then commit the transaction ID and release the feature lock before regeneration]
    RRTWAL --> BRIEF
    BRIEF --> BROUTE{FeatureBriefOperationResult}
    BROUTE -- clarification_needed --> CLIFE[ClarificationLifecycleOrchestrator]
    BROUTE -- content --> BVALID[Validate title, description and goal grounding; no feature ID or path from model]
    BVALID --> REQUEST[AssignFeatureRequestIdAction then BuildFeatureRequestAction<br/>owner-local to the durable ReferenceState; build no generic FeatureRequestState yet]
    REQUEST --> SPEC[Generate bounded F0100 specification units with reference and resolved-answer citations:<br/>Primary User Story, AC, UO, EC, FR, BR, assumptions, non-goals, prohibited behaviors,<br/>and EN only after validated business-data applicability; never generate Markdown or inline clarification]
    SPEC --> SROUTE{Each declared specification-unit operation result}
    SROUTE -- clarification_needed --> CLIFE
    SROUTE -- content --> SUNIT[Validate business boundary, IDs, structure, provenance and passive-literal use]
    SUNIT --> MORE{All specification units accepted}
    MORE -- No --> SPEC

    CLIFE --> CPAUSE[Deduplicate subject key; allocate or reuse SNN; render clarify/SNN.md]
    CPAUSE --> PBOOT{SpecificationContract bootstrap handoff is staged}
    SBUNDLE -. exact run-local handoff .-> PBOOT
    PBOOT -- No --> PTX[Assemble complete SpecificationClarificationPause inputs:<br/>ReferenceSnapshot/current authorities, next registry/forms and pending state;<br/>no incomplete SpecificationIR]
    PTX --> PTX09[Invoke diagram 09 feature-storage clarification_pause lifecycle;<br/>after transaction-ID reservation build and validate the stage transaction<br/>with its complete StateIdentityTransactionMember and DurableTransactionMember]
    PTX09 --> NEEDUSER[NeedsUser; no incomplete spec or downstream artifact]
    PBOOT -- Yes --> SPMAT[Enter diagram 09 clarification_pause lifecycle, reserve/fsync transaction ID<br/>and revalidate workflow/feature ledger; assign authority/leaf/grammar/policy IDs and materialize leaves;<br/>build/validate dependency maps at leaf_dependencies, base_grammar_resolved and complete around the<br/>grammar then policy aggregate bindings; build/validate core and materialized change evidence;<br/>BuildSuccessorBootstrapAuthorityStateAction then ValidateBootstrapAuthorityStateAction;<br/>resolve/serialize transaction-private bytes; AssignWorkflowStateIdAction then<br/>BuildNextStageStateAction to spec_clarification_pending with exact remaining-open projection,<br/>threading all clarification/workflow successors]
    SPMAT --> SPWAL[Build/validate the owning spec ClarificationPause transaction with the closed<br/>SpecificationContract bootstrap adoption, current snapshot, next registry/forms and pending state;<br/>journal/apply/mark, commit transaction ID, clean up and release feature lock]
    SPWAL --> SPLOG{Adopted changePlan.obligations.transitionFeatureLogging}
    SPLOG -- False --> NEEDUSER
    SPLOG -- True --> SPLOGTX[Invoke diagram 06 complete policy transition before entering user wait]
    SPLOGTX --> NEEDUSER

    MORE -- Yes --> SCOMPBEGIN[Enter diagram 09 feature-storage specify_completion lifecycle only after<br/>every model unit is accepted: acquire/recover, reserve/fsync transaction ID,<br/>and revalidate the expected workflow plus current FeatureStateIdLedger]
    SCOMPBEGIN --> REQUESTSTATE[Inside that held transaction lifecycle call AssignFeatureRequestStateIdAction,<br/>BuildFeatureRequestStateAction, ValidateFeatureRequestStateAction and<br/>SerializeFeatureRequestStateAction; thread the exact feature-ledger successor]
    REQUESTSTATE --> FINAL[Build complete SpecificationIR, provenance and acknowledgements;<br/>render F0100's mandatory User Scenarios and Testing plus Requirements hierarchy,<br/>with Key Entities only from validated applicability, and render the reference view]
    FINAL --> FVALID[Reparse spec.md; compare normalized IR; validate exact heading order, paths,<br/>snapshot bindings, no placeholder or inline clarification, and no open SNN]
    FVALID -- Invalid --> SABORT[RetireTransactionIdAction, discard every in-memory state candidate,<br/>clean up and release the feature lock]
    SABORT --> INVALID
    FVALID -- Valid --> FBOOT{SpecificationContract bootstrap handoff is staged}
    SBUNDLE -. exact run-local handoff .-> FBOOT
    FBOOT -- No --> STX[Assemble complete SpecifyCompletion inputs:<br/>snapshot, request, actor-evidence, passive and clarification states, provenance, views,<br/>specified workflow state and every staged canonical state-identity mutation]
    STX --> SWAL[Continue the same diagram 09 specify_completion lifecycle:<br/>call BuildSpecifyCompletionStageTransactionAction and ValidateCoreStageTransactionAction,<br/>validate DurableTransactionMember/storage, journal/apply/mark, commit transaction ID,<br/>clean up and release the feature lock]
    SWAL --> DONE[specified; spec.md is editable and plan gate may run]
    FBOOT -- Yes --> SCMAT[Continue the same diagram 09 specify_completion lifecycle under its held lock;<br/>assign authority/leaf/grammar/policy IDs and materialize leaves; build/validate dependency maps at<br/>leaf_dependencies, base_grammar_resolved and complete around the grammar then policy aggregate bindings;<br/>build/validate core and materialized change evidence; BuildSuccessorBootstrapAuthorityStateAction<br/>then ValidateBootstrapAuthorityStateAction; resolve/serialize transaction-private bytes;<br/>AssignWorkflowStateIdAction then BuildNextStageStateAction to specified and thread all successors]
    SCMAT --> SCWAL[BuildSpecifyCompletionStageTransactionAction with the closed<br/>SpecificationContract bootstrap adoption and complete specification authorities/views;<br/>ValidateCoreStageTransactionAction, journal/apply/mark, commit transaction ID,<br/>clean up and release feature lock]
    SCWAL --> SCLOG{Adopted changePlan.obligations.transitionFeatureLogging}
    SCLOG -- False --> DONE
    SCLOG -- True --> SCLOGTX[Invoke diagram 06 complete policy transition before any plan gate or normal event]
    SCLOGTX --> DONE

    INPUTERR --> ILOCK{Project-transaction lock capability is held}
    ILOCK -- Yes --> IRELEASE[ReleaseProjectTransactionCollectionLockAction<br/>with user-input failure terminal outcome]
    ILOCK -- No; failure occurred before selected SDD setup acquired it --> ISTOP[Return the typed nonzero outcome]
    IRELEASE --> ISTOP
    PREBLOCK --> PLOCK{Project-transaction lock capability is held}
    PLOCK -- Yes --> PRELEASE[ReleaseProjectTransactionCollectionLockAction<br/>with preactivation/ownership block terminal outcome]
    PLOCK -- No; already released after an owning transaction --> PBSTOP[Return the typed blocking outcome]
    PRELEASE --> PBSTOP
    INVALID --> XLOCK{Project-transaction lock capability is held}
    XLOCK -- Yes --> XRELEASE[ReleaseProjectTransactionCollectionLockAction<br/>with reference/specification failure terminal outcome]
    XLOCK -- No; already released after activation or bootstrap transaction --> XSTOP[Return the typed failure outcome]
    XRELEASE --> XSTOP
```
