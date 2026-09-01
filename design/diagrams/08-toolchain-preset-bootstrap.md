```mermaid
flowchart TD
    START[Invocation working directory] --> RUNNER[PipelineRunner executes BootstrapOrchestrator's<br/>bound actions/orchestrators through ChildNodeBinding]
    RUNNER --> LOCATE[LocateExactEngineConfigAction<br/>invocation working directory is the canonical project root;<br/>resolve only its exact .sddtoolkit.json; never search parents/children]
    LOCATE -- Cannot resolve safe file --> READFAIL[ENGINE_CONFIG_READ_ERROR<br/>terminal failed outcome and nonzero exit;<br/>no workflow/model/log/write starts]
    LOCATE --> READ[ReadEngineConfigAction<br/>compiler-owned maximum 1 MiB / 1,048,576 bytes]
    READ -- Cannot read or over guard --> READFAIL
    READ --> SCHEMACFG[DecodeSDDToolKitConfigAction<br/>parse directly to the closed reader-facing shape and supported version;<br/>immutable config value; no generic JSON tree or domain-policy compilation]
    SCHEMACFG -- Invalid JSON, version or shape --> PARSEFAIL[ENGINE_CONFIG_PARSE_ERROR<br/>terminal failed outcome and nonzero exit;<br/>no workflow/model/log/write starts]
    LOCATE --> HOST[DetectWorkspaceFilesystemPolicyAction]
    SCHEMACFG --> BASES[For each required directory key exactly once:<br/>specs, references, specsArchive, workflows, toolchainPreset,<br/>principles and templates]
    SCHEMACFG --> PROVIDERPATH[Validate and resolve paths.providers exactly once;<br/>project-relative file with basename .sddproviders.json;<br/>reserve only, do not read]
    HOST --> BASES
    BASES --> RESOLVEBASE[ResolveConfiguredBaseRootAction<br/>join one configured relative base to the exact project root]
    RESOLVEBASE --> VALIDBASE[ValidateConfiguredBaseRootAction<br/>containment, normalization, access and portability capability]
    PROVIDERPATH --> ROOTID
    VALIDBASE --> ROOTID[BuildBootstrapRootRegistryIdAction<br/>self-validating canonical project-root and contract-version tuple;<br/>consume no state ledger and inspect no content]
    ROOTID --> BUILDROOTS[BuildBootstrapRootRegistryAction<br/>identity, exact config/project descriptors plus complete configured-root capabilities]
    BUILDROOTS --> VALIDROOTS{ValidateBootstrapRootRegistryAction<br/>all seven directory roots plus provider file exactly once; no escape, alias, duplicate or illegal overlap;<br/>only specsArchive may nest beneath specs}
    VALIDROOTS -- Invalid --> FAIL[Bootstrap fails with typed diagnostic<br/>no model call and no partial registry or compiled policy]
    VALIDROOTS -- Valid --> WLAYOUT[BuildWorkflowAuthorityLayoutAction then<br/>ValidateWorkflowAuthorityLayoutAction;<br/>include features/ and transactions/ root entries for ownership accounting<br/>but exclude every descendant in both reserved subtrees]
    WLAYOUT --> WINVENTORY[Enumerate and normalize every in-scope entry;<br/>validate the complete portability collision set, sort by Unicode-scalar path,<br/>then bind contiguous one-based inventory ordinals]
    WINVENTORY --> WCLASSIFY[Classify every ordinal-bound entry as directory, exact reserved child,<br/>definition candidate or blocking; capture/parse/schema-validate each definition candidate;<br/>accept WorkflowId only from validated content, never filename inference]
    WCLASSIFY --> WACCOUNT[Build exactly one terminal entry account then<br/>BuildWorkflowAuthorityInventoryAction and<br/>ValidateWorkflowAuthorityInventoryAction;<br/>no blocking/unaccounted entry or reserved-child definition is legal]
    WACCOUNT --> WCOMPILE[CompileWorkflowGraphAction then ValidateCompiledWorkflowGraphAction<br/>for every schema-valid definition; resolve only registered invocation-contract and graph PipelineNodes,<br/>outcome, gate and workflow-policy contracts; invoke no node]
    WCOMPILE --> WVALID{BuildWorkflowDefinitionRegistryAction then<br/>ValidateWorkflowDefinitionRegistryAction;<br/>arbitrary bounded definition count; unique WorkflowIds, logging shortcodes and source ordinals;<br/>complete graph/outcome closure; no executable payload, infrastructure selection,<br/>capability addition, gate weakening or runner bypass}
    WVALID -- Invalid --> FAIL
    WVALID -- Valid --> PREFLIGHT[Return validated roots/config/portability and the complete workflow registry;<br/>acquire no project or feature transaction lock; workflow selection remains outside bootstrap]
    PREFLIGHT -. only after a selected SDD invocation-contract node produces valid typed context;<br/>unrelated workflows and selection/invocation failures do not enter this branch .-> PTXPATH[ResolveProjectTransactionCollectionAction<br/>fixed reserved paths.workflows/transactions collection<br/>for SDD preownership recovery and activation]
    PTXPATH --> PTXLOCK[AcquireProjectTransactionCollectionLockAction<br/>runner retains the opaque capability while project TransactionIdLedger recovery<br/>and FeatureIdentityRegistry ownership resolution are performed]
    PTXLOCK --> PTXSCAN[ScanTransactionJournalInventoryAction<br/>bounded raw journal/header/marker and transaction-ledger inventory<br/>before any FeatureIdentityRegistry read]
    PTXSCAN --> TLPATH[ResolveTransactionIdLedgerPathAction then ReadTransactionIdLedgerAction]
    TLPATH --> TLCASE{Transaction-ID-ledger bytes present}
    TLCASE -- No --> TLINIT[BuildInitialTransactionIdLedgerAction]
    TLCASE -- Yes --> TLPARSE[ParseTransactionIdLedgerAction]
    TLINIT --> TLVALID{ValidateTransactionJournalInventoryAction then<br/>ValidateTransactionIdLedgerAction over the same owner/inventory pair}
    TLPARSE --> TLVALID
    TLVALID -- Invalid --> FAIL
    TLVALID -- Valid --> TLPLAN[BuildTransactionIdentityRecoveryPlanAction then<br/>ValidateTransactionIdentityRecoveryPlanAction]
    TLPLAN --> TLDISP{Next typed disposition}
    TLDISP -- block --> FAIL
    TLDISP -- retire_orphan, rollback_and_retire,<br/>recover_commit_id or verify_committed --> PTXRECOVER[Invoke the matching recovery portion of diagram 09<br/>under the same held project lock and validated storage capability]
    PTXRECOVER --> TLRECHECK{Revalidate transaction ledger/inventory and recovery plan}
    TLRECHECK -- More --> TLDISP
    TLRECHECK -- Stable --> FEATUREPREP
    TLDISP -- Complete clean plan --> FEATUREPREP[Return the recovered project TransactionIdLedger<br/>and held project-transaction capability to the selected SDD graph for exact feature ownership resolution]
    FEATUREPREP -. after diagram 05 validates FeatureStateInventory and resolves the exact feature target;<br/>the selected SDD graph alone continues this setup .-> TARGETCTX{Post-feature-selector exact target}
    TARGETCTX --> TROOT[ResolveConfiguredToolchainPresetRootAction<br/>sole runtime root paths.toolchainPreset]
    TARGETCTX --> PROOT[ResolveConfiguredPrinciplesRootAction<br/>sole runtime root paths.principles]
    VALIDROOTS -. validate the directory capability only;<br/>normal bootstrap never inventories, reads or copies template content .-> TEMPLATEINERT[paths.templates/*.template.md<br/>inert throughout v1; reserved for a future sdd init boundary]
    TARGETCTX -- New target --> NOPRIOR[Receive the validated initial in-memory feature StateIdLedger from diagram 05;<br/>use absent optional prior specialized registries and ledgers;<br/>all bootstrap-local namespaces begin at ordinal one and generic authority-state IDs<br/>remain unallocated until post-preactivation activation; retain the project lock]
    TARGETCTX -- Existing exact owner --> EHEADER[Require the exact owner plus only the validated WorkflowArtifactRegistry header<br/>and StageTransactionCollection recovery binding from FeatureStateInventory;<br/>trust no feature authority or specialized ledger yet]
    EHEADER --> EPRELEASE[ReleaseProjectTransactionCollectionLockAction<br/>immediately after ownership and feature recovery-path resolution]
    EPRELEASE --> ERECOVER[Invoke diagram 09 in recovery-only feature mode:<br/>acquire/recover/validate the feature transaction collection and TransactionIdLedger,<br/>commit or retire each recovered transaction ID before cleanup, rescan,<br/>release the feature lock and allocate no new transaction ID]
    ERECOVER --> EAUTHORITIES[Only after recovery, load/parse/validate the feature StateIdLedger,<br/>WorkflowArtifactRegistry, WorkflowState, current BootstrapAuthorityState<br/>and every actor/review/control/passive/clarification authority]
    EAUTHORITIES --> PRIORPATH[ResolveBootstrapAuthorityStatePathAction<br/>from that recovered and validated current WorkflowArtifactRegistry collection]
    PRIORPATH --> PRIORREAD[Bounded no-follow read through the registered<br/>engine-state reader action and validated FeatureStateInventory entry]
    PRIORREAD --> PRIORPARSE[ParseBootstrapAuthorityStateAction<br/>all nested component values and IDs remain untrusted]
    PRIORPARSE --> TPARSELEDGER[ParseToolchainPresetIdLedgerAction]
    TPARSELEDGER --> TPRIORVALID{ValidateToolchainPresetIdLedgerAction plus<br/>ValidateToolchainPresetRegistryStateAction prove the closed prior component}
    TPRIORVALID -- Invalid --> FAIL
    TPRIORVALID -- Valid --> TPRIOR[Validated optional prior preset registry and ledger]
    PRIORPARSE --> PPARSELEDGER[ParsePrincipleIdLedgerAction]
    PPARSELEDGER --> PPRIORVALID{ValidatePrincipleIdLedgerAction plus<br/>ValidatePrincipleRegistryStateAction prove the closed prior component}
    PPRIORVALID -- Invalid --> FAIL
    PPRIORVALID -- Valid --> PPRIOR[Validated optional prior principle registry and ledger]
    NOPRIOR --> TPRIOR
    NOPRIOR --> PPRIOR

    PROOT --> LAYERREAD[Resolve and bounded-capture the exact root child toolchain.yaml;<br/>it is a typed project principle, never free-text or model authority]
    LAYERREAD --> LAYERPARSE[ParseProjectToolchainLayerAction then<br/>ValidateProjectToolchainLayerSchemaAction;<br/>closed inheritance and project-layer data only]
    PROOT --> PRINCIPLES[PipelineRunner continues BootstrapOrchestrator<br/>with free-text Markdown principle-ingestion actions;<br/>the exact toolchain.yaml child is excluded]
    PRINCIPLES --> PJOIN[Join the validated root capability with the optional<br/>validated prior registry and PrincipleIdLedger]
    PPRIOR --> PJOIN
    PJOIN --> PLEDGER[BuildPrincipleIdLedgerAction<br/>retain prior ordinals and tombstones or initialize every namespace]
    PLEDGER --> PLEDGER0{ValidatePrincipleIdLedgerAction<br/>current ledger ownership and prior join valid}
    PLEDGER0 -- Invalid --> FAIL
    PLEDGER0 -- Valid --> PENUM[EnumeratePrincipleSourcesAction accounts for every directory, regular file, link and special node;<br/>ClassifyPrinciplesRootEntryAction separates exact toolchain.yaml, normalized Markdown candidates,<br/>directories and blocking entries; validate collisions and sort the complete inventory]
    PENUM --> PENTRYID[AssignPrincipleInventoryEntryIdAction then<br/>BuildPrincipleInventoryEntryAction for every ordered node;<br/>each assignment consumes the exact current ledger and returns its successor]
    PENTRYID --> PSESSION[BuildPrincipleCaptureBudgetSessionAction<br/>run-local entry, semantic-source-byte, time, memory and chunk ceilings;<br/>the provisional session is never persisted]
    PSESSION --> PCAPTURE[For each validated semantic-Markdown candidate only:<br/>ReservePrincipleSourceBytesAction, CapturePrincipleSourceAction and<br/>CommitPrincipleSourceDebitAction or ReleasePrincipleSourceReservationAction;<br/>never capture toolchain.yaml through this lane]
    PCAPTURE --> PSESSIONVALID{ValidatePrincipleCaptureBudgetSessionAction<br/>one terminal reservation per semantic-Markdown candidate;<br/>none for toolchain.yaml, directories or blocking entries;<br/>exact totals and no unaccounted semantic-source read}
    PSESSIONVALID -- Invalid --> FAIL
    PSESSIONVALID -- Valid --> PBID[AssignPrincipleBudgetLedgerStateIdAction<br/>after the complete session and captured owner/byte set are known;<br/>direct-equal retain or monotonic allocate; current ledger to successor]
    PBID --> PRESIDS[AssignPrincipleReservationIdAction<br/>retain or allocate one stable ID per provisional reservation<br/>in canonical inventory order]
    PRESIDS --> PRETIRE[RetireRemovedPrincipleReservationAction<br/>once per unmatched prior reservation; IDs are never reused]
    PRETIRE --> PBUDGET[BuildPrincipleSourceBudgetLedgerAction<br/>assemble the complete provisional-to-stable map, next ordinal,<br/>tombstones and exact totals; perform no allocation itself]
    PBUDGET --> PALLOC[For each stable captured source in order: AssignPrincipleSourceIdAction,<br/>BuildPrincipleCapturedSourceAction, DecodePrincipleFreeTextAction,<br/>AssignPrincipleSourceMapIdAction, BuildPrincipleSourceMapAction,<br/>ClassifyPrincipleCategoryFromFilenameAction, AssignPrincipleModuleIdAction,<br/>BuildPrincipleModuleAction, PartitionPrincipleTextAction,<br/>AssignPrincipleChunkIdAction and BuildPrincipleChunkAction;<br/>each ID action consumes the exact current ledger and returns the successor]
    PALLOC --> PACCOUNT[BuildPrincipleEntryAccountAction<br/>exactly one directory_accounted, mechanical_toolchain_layer_excluded,<br/>blocking or captured_source disposition per encountered entry]
    PACCOUNT --> PINVID[AssignPrincipleInventoryStateIdAction<br/>direct-equal retain or allocate from the current ledger; return successor]
    PINVID --> PINVLEDGER{ValidatePrincipleIdLedgerAction<br/>inventory-bound successor, stable retained IDs and retired allocations}
    PINVLEDGER -- Invalid --> FAIL
    PINVLEDGER -- Valid --> PINVSTATE[BuildPrincipleInventoryStateAction then<br/>ValidatePrincipleInventoryStateAction with that exact successor ledger;<br/>prove toolchain.yaml has one mechanical exclusion and no semantic reservation/source/source map]
    PINVSTATE --> PREGID[AssignPrincipleRegistryStateIdAction<br/>direct-equal retain or allocate; inventory successor to final successor]
    PREGID --> PFINALLEDGER{ValidatePrincipleIdLedgerAction<br/>complete final successor through registry_state}
    PFINALLEDGER -- Invalid --> FAIL
    PFINALLEDGER -- Valid --> PSERIAL[SerializePrincipleIdLedgerAction<br/>canonical ownership, next ordinals and tombstones]
    PSERIAL --> PREG[BuildPrincipleRegistryStateAction then<br/>ValidatePrincipleRegistryStateAction with the same final ledger;<br/>prove no semantic source/module/chunk references toolchain.yaml;<br/>filename supplies only a configured category hint and body remains free text]

    TROOT --> RVALID{Readable no-follow directory, contained by its capability,<br/>not aliased and not equal to another protected root}
    RVALID -- No --> FAIL
    RVALID -- Yes --> TJOIN[Join the validated root capability with the optional<br/>validated prior registry and ToolchainPresetIdLedger]
    TPRIOR --> TJOIN
    TJOIN --> TLEDGER[BuildToolchainPresetIdLedgerAction<br/>retain prior ordinals and tombstones or initialize every namespace]
    TLEDGER --> TLEDGER0{ValidateToolchainPresetIdLedgerAction<br/>current ledger ownership and prior join valid}
    TLEDGER0 -- Invalid --> FAIL
    TLEDGER0 -- Valid --> ENUM[EnumerateToolchainPresetResourcesAction<br/>bounded full unordered inventory without following links]
    ENUM --> COUNT{Entry count, depth, traversal time and memory within hard limits}
    COUNT -- No --> FAIL
    COUNT -- Yes --> PATH[ValidateToolchainPresetResourcePathAction<br/>every directory, regular file, link, special node and locked metadata candidate]
    PATH --> COLLISION[ValidateToolchainPresetInventoryCollisionAction<br/>complete-inventory duplicate, case-fold, normalization and portable-name checks]
    COLLISION --> SORT[SortToolchainPresetInventoryAction<br/>one Unicode-scalar ordering]
    SORT --> IID[AssignToolchainPresetInventoryEntryIdAction<br/>direct-equal retain or allocate for each stable ordered node;<br/>thread each successor ledger to BuildToolchainPresetInventoryEntryAction<br/>and the next entry allocation]
    IID --> SESSION[BuildToolchainPresetCaptureBudgetSessionAction<br/>run-local entry, depth, source-byte, time and memory ceilings;<br/>the provisional session is never persisted]

    SESSION --> ENTRY{Observed no-follow node kind}
    ENTRY -- Directory --> DREC[Directory-accounted disposition]
    ENTRY -- Engine-locked metadata --> XREC[Locked-metadata-excluded disposition]
    ENTRY -- Symlink, alias, special or unsupported --> RAWBAD[Terminal blocking inventory/capture outcome]
    ENTRY -- Regular file --> RESERVE[ReserveToolchainPresetSourceBytesAction]
    RESERVE -- No capacity --> RAWBAD
    RESERVE -- Reserved --> CAPTURE[CaptureToolchainPresetResourceAction<br/>one raw immutable-byte observation through the same descriptor;<br/>no resource or source-map identity yet]
    CAPTURE --> STABLE{Identity, node type, complete length and reservation still exact}
    STABLE -- No --> RELEASE[ReleaseToolchainPresetSourceReservationAction]
    RELEASE --> RAWBAD
    STABLE -- Yes --> DEBIT[CommitToolchainPresetSourceDebitAction<br/>exact actual-byte debit in the provisional session]
    DEBIT --> CAPTUREDSET[Stable raw capture observation and terminal debit;<br/>no durable budget, resource or source-map identity yet]
    DREC --> SESSIONCLOSE[Close the complete provisional capture session<br/>with one terminal outcome per ordered inventory entry]
    XREC --> SESSIONCLOSE
    RAWBAD --> SESSIONCLOSE
    RAWBAD --> BADREC[Blocking disposition; never silently filtered]
    CAPTUREDSET --> SESSIONCLOSE
    SESSIONCLOSE --> SESSIONVALID{ValidateToolchainPresetCaptureBudgetSessionAction<br/>one terminal reservation per regular file, none for other nodes,<br/>exact totals and no unaccounted read}
    SESSIONVALID -- Invalid --> FAIL
    SESSIONVALID -- Valid --> BUDGETID[AssignToolchainPresetBudgetLedgerStateIdAction<br/>after the complete session and captured owner/byte set are known;<br/>direct-equal retain or monotonic allocate; current ledger to successor]
    BUDGETID --> RESIDS[AssignToolchainPresetReservationIdAction<br/>retain or allocate one stable ID per provisional reservation<br/>in canonical inventory order]
    RESIDS --> RETIRE[RetireRemovedToolchainPresetReservationAction<br/>once per unmatched prior reservation; IDs are never reused]
    RETIRE --> BUDGET[BuildToolchainPresetSourceBudgetLedgerAction<br/>assemble the complete provisional-to-stable map, next ordinal,<br/>tombstones and exact totals; perform no allocation itself]
    BUDGET --> RID[AssignToolchainPresetResourceIdAction<br/>for each stable capture; consume current ledger and return successor;<br/>identity is independent of filename and document metadata]
    CAPTUREDSET --> RID
    RID --> SMID[AssignToolchainPresetSourceMapIdAction<br/>consume that successor and return the next; identity is independent of bytes]
    SMID --> BLOB[BuildToolchainPresetCapturedBlobAction<br/>bind resource/source-map identities to the stable capture and debit]
    BLOB --> RMAP[BuildToolchainPresetSourceMapAction<br/>bind only the immutable whole-resource byte span]
    RMAP --> ROLE[ClassifyToolchainPresetResourceRoleAction<br/>locked inventory media/extension evidence; later declarations may only<br/>confirm a compatible asset role, never supply package identity from filename]

    ROLE --> RCLASS{Transport role}
    RCLASS -- package_document with YAML or JSON media --> VERSION[ClassifyPresetDocumentVersionAction<br/>only package documents enter the document decoder]
    RCLASS -- parser_query, grammar, adapter_descriptor or schema --> ASSETC[Typed resource-asset candidate<br/>captured bytes are never parsed as a preset package]
    RCLASS -- Unsupported or ambiguous --> BADREC

    VERSION --> DOCCLASS{Document version class}
    DOCCLASS -- Legacy or unknown --> LEGACY[RejectLegacyPresetDocumentAction<br/>PRESET_LEGACY_SCHEMA_UNSUPPORTED]
    LEGACY --> BADREC
    DOCCLASS -- Candidate v1 --> READPRESET[ReadPresetAction<br/>decode only the captured immutable blob]
    READPRESET --> PARSEPRESET[ParsePresetAction<br/>fixed safe YAML/JSON semantics; no duplicate keys, aliases,<br/>custom tags or multi-document input]
    PARSEPRESET --> SCHEMA[ValidatePresetSchemaAction<br/>closed v1 schema: apiVersion, kind, exact ID/version and layer]
    SCHEMA --> PLACEHOLDER[RejectPresetPlaceholderAction<br/>no unresolved placeholder or undeclared interpolation]
    PLACEHOLDER --> DOCGATE{Decode, schema and placeholder evidence all valid}
    DOCGATE -- No --> BADREC
    DOCGATE -- Yes --> DOCREADY[Placeholder-free schema-valid package document<br/>retain exact declared resource references and source evidence]
    DOCREADY --> PDREC[Captured-package-document disposition]
    DOCREADY --> DECLS[BuildPresetResourceDeclarationIndexAction then<br/>ValidatePresetResourceDeclarationIndexAction over the complete package set;<br/>one contained locator owns declared stable ID, exact version, role, media,<br/>format and package; locator locates bytes but never becomes identity]
    ASSETC --> ASSETJOIN[JoinToolchainPresetAssetDeclarationAction<br/>join each captured typed asset to exactly one compatible declaration<br/>by its validated locator and copy the locked declaration fields]
    DECLS --> ASSETJOIN
    ASSETJOIN --> AJGATE{Exactly one compatible declaration and format descriptor}
    AJGATE -- No --> BADREC
    AJGATE -- Yes --> ASSETID[AssignToolchainPresetAssetIdAction<br/>consume current ledger and return successor; direct-equal retention or<br/>monotonic identity independent of filename and declaration]
    ASSETID --> ASSET[BuildToolchainPresetAssetRecordAction<br/>bind presetAssetId, capturedResourceId, role, media,<br/>format descriptor, declared stable ID and exact version]
    ASSET --> AVALID[ValidateToolchainPresetAssetAction<br/>bounded syntax, dialect/version, required captures or exports,<br/>and no undeclared include or path escape]
    AVALID --> AGATE{Asset declaration join and bounded format evidence valid}
    AGATE -- No --> BADREC
    AGATE -- Yes --> ASSETEVIDENCE[Validated typed asset registry]
    AGATE -- Yes --> ADREC[Captured-asset disposition with exact presetAssetId]
    DECLS --> REFJOIN[ResolvePresetResourceReferenceAction<br/>every declared package reference resolves exactly once]
    ASSETEVIDENCE --> REFJOIN
    REFJOIN --> REFGATE{Every required reference resolved exactly once,<br/>with no undeclared or incompatible asset}
    REFGATE -- No --> FAIL
    REFGATE -- Yes --> PKG[BuildToolchainPresetPackageRecordAction<br/>bind declared preset ID, exact version and layer to its document<br/>and the exact resolved asset IDs]
    PKG --> PKGVALID[ValidateToolchainPresetPackageRecordAction<br/>unique identity/version, exact metadata and resource closure]
    PKGVALID --> PKGGATE{All package-record evidence valid}
    PKGGATE -- No --> FAIL
    PKGGATE -- Yes --> PACKAGESET[Validated exact package records plus package-to-asset joins]

    DREC --> ACCOUNT[BuildToolchainPresetEntryAccountAction<br/>one terminal disposition per encountered inventory entry]
    XREC --> ACCOUNT
    BADREC --> ACCOUNT
    PDREC --> ACCOUNT
    ADREC --> ACCOUNT
    ACCOUNT --> INVID[AssignToolchainPresetInventoryStateIdAction<br/>direct-equal retain or allocate from the current ledger; return successor]
    INVID --> INVLEDGER{ValidateToolchainPresetIdLedgerAction<br/>inventory-bound successor, stable retained IDs and retired allocations}
    INVLEDGER -- Invalid --> FAIL
    INVLEDGER -- Valid --> INVSTATE[BuildToolchainPresetInventoryStateAction<br/>stable entries, closed budget ledger, captured-resource records,<br/>complete accounting and the exact inventory-bound successor ledger]
    INVSTATE --> IVALID{ValidateToolchainPresetInventoryStateAction<br/>all entries accounted, reservations closed, exact debit/blob joins,<br/>and no blocking or unclassified captured resource}
    IVALID -- Invalid --> FAIL
    IVALID -- Valid --> REGCONTENT[Complete validated inventory plus package, asset,<br/>declaration-index and exact reference-join candidate content]
    PACKAGESET --> REGCONTENT
    ASSETEVIDENCE --> REGCONTENT
    DECLS --> REGCONTENT
    REGCONTENT --> REGID[AssignToolchainPresetRegistryStateIdAction<br/>compare every complete typed field and raw byte with the optional prior registry;<br/>direct-equal retain or allocate; inventory successor to final successor]
    REGID --> FINALLEDGER{ValidateToolchainPresetIdLedgerAction<br/>complete final successor through registry_state}
    FINALLEDGER -- Invalid --> FAIL
    FINALLEDGER -- Valid --> SERIALLEDGER[SerializeToolchainPresetIdLedgerAction<br/>canonical ownership, next ordinals and tombstones]
    SERIALLEDGER --> REG[BuildToolchainPresetRegistryStateAction<br/>validated inventory, same final successor ledger and every<br/>package, asset, declaration and reference join]
    REGCONTENT --> REG
    REG --> REGVALID{ValidateToolchainPresetRegistryStateAction<br/>complete inventory/budget coverage, unique packages/assets,<br/>no orphan or multiply owned asset and closure of every package-declared reference;<br/>consult no project environment or project-toolchain selection}
    REGVALID -- Invalid --> FAIL

    REGVALID -- Valid --> LAYERJOIN{ResolveProjectToolchainInheritanceAction then<br/>BuildProjectToolchainLayerAction and ValidateProjectToolchainLayerAction<br/>against the complete preset registry;<br/>resolve exact direct inheritance and schema-typed overrides without merging<br/>or claiming that the eventual result preserves compiler locks}
    LAYERPARSE --> LAYERJOIN
    LAYERJOIN -- Invalid --> FAIL
    LAYERJOIN -- Valid --> GRAPH[Build exact package ID/version composition graph<br/>language, runtime, package-manager, framework, build-tool,<br/>test-runner, environment and the typed project-toolchain layer]
    GRAPH --> GVALID{ValidatePresetVersionPinAction, ValidatePresetLayerEdgeAction,<br/>ValidatePresetDuplicateIdentityAction and DetectPresetCompositionCycleAction}
    GVALID -- Invalid --> FAIL
    GVALID -- Valid --> ORDER[TopologicallyOrderPresetCompositionAction<br/>dependency first with closed layer and ID/version tie-break]
    ORDER --> COMPOSE[CompilePresetSetAction<br/>explicit merge operators only; preserve field-level source evidence]
    COMPOSE --> MERGEDVALID{ValidateCompiledPresetSetSafetyAction<br/>the effective merged result preserves every compiler lock and uses only<br/>declared precedence/operators without conflicting assignments or weakened<br/>path, command, capability, sandbox, network, resource or effect limits}
    MERGEDVALID -- Invalid --> FAIL
    MERGEDVALID -- Valid --> PATTERN[Compile and validate project-independent path patterns,<br/>file kinds, templates, rule IDs and placement contracts]
    PATTERN --> CAPABILITY[Resolve and validate create, update, replace, copy and delete<br/>file-intent capability ceilings]
    CAPABILITY --> COMMAND[Compile and validate structured command descriptors<br/>executable plus argv, cwd, environment, network, quotas,<br/>sandbox and persistent/ephemeral effects]
    COMMAND --> CSAFE{No shell scalar, redirect, glob expansion, mutable version,<br/>unresolved placeholder or unproven effect}
    CSAFE -- No --> FAIL
    CSAFE -- Yes --> PARSER[Bind exact parser/query/grammar/adapter asset IDs and versions;<br/>compile required captures, resolvers and conservative fallbacks]
    PARSER --> COVER{Every model-writable content surface has deterministic<br/>or conservative blocking coverage}
    COVER -- No --> DISABLE[Disable unsupported create, update, replace or copy capability]
    COVER -- Yes --> DEP[Compile dependency trust, package/version grammar,<br/>scope and manifest/lockfile transition policy]
    DISABLE --> DEP

    DEP --> DISCOVER[Run registered project-discovery adapters over bounded repository facts]
    DISCOVER --> BIND[Bind manifests, project ownership, source roots, file kinds,<br/>commands and project-toolchain environment bindings without model input]
    BIND --> MATERIALIZE[Resolve source-root selectors and materialize bound patterns]
    MATERIALIZE --> PROBE[Probe exact executable, script, parser, sandbox and quota capabilities]
    PROBE --> EVALID{Selected project/environment bindings are complete,<br/>contained, portable and unambiguous}
    EVALID -- No --> FAIL
    EVALID -- Yes --> EPOLICY[BuildCompiledEnvironmentPolicyAction then<br/>ValidateCompiledEnvironmentPolicyAction for every noncanonical leaf candidate;<br/>retain run-local handles and specialized preset identities only]
    EPOLICY --> BLUEPRINTS[BuildIdentityFreeSupersetPathTokenGrammarCandidateAction then<br/>ValidateIdentityFreeSupersetPathTokenGrammarCandidateAction; next call<br/>BuildIdentityFreeCompiledEnginePolicyCandidateAction then<br/>ValidateIdentityFreeCompiledEnginePolicyCandidateAction;<br/>both aggregate blueprints carry only typed run-local references to leaf candidates<br/>and contain no generic canonical component ID]
    WVALID -. validated identity-free workflow-definition leaf .-> BLUEPRINTS
    LAYERJOIN -. validated identity-free project-toolchain leaf .-> BLUEPRINTS
    PREG --> BLUEPRINTS
    BLUEPRINTS --> ENGINEPOLICY[BuildBootstrapOperationalCandidateAction<br/>bind every independently validated config/root/preset/leaf candidate plus the<br/>validated grammar and compiled-policy aggregate blueprints, route/reader/parser metadata<br/>and hard limits; allocate no generic project or feature authority-state ID]
    ENGINEPOLICY --> ENGINEVALID{ValidateBootstrapOperationalCandidateAction<br/>all specialized IDs, versions and run-local handle/DataKey/schema joins resolve once,<br/>identity domains are disjoint and every selected environment is complete}
    ENGINEVALID -- Invalid --> FAIL
    ENGINEVALID -- Valid --> CANDIDATE[ValidatedBootstrapOperationalCandidate<br/>generic project/feature component IDs unallocated; candidate is unserialized,<br/>unpersisted and held only by bounded non-loggable run-local handles]
    CANDIDATE --> HANDOFF[Return candidate to the selected compiled workflow execution;<br/>no model-bearing workflow node may run yet]

    HANDOFF --> HCASE{Exact feature target}
    HCASE -- New target --> NHANDOFF[Return the validated identity-free candidate to diagram 05 only;<br/>retain the project lock; after reference preactivation that diagram allocates the feature-local<br/>bootstrap/artifact/initial states and commits the sole feature_activation transaction]
    HCASE -- Existing owner after recovery --> BCOMPARE{CompareBootstrapAuthorityStateAction<br/>use the validated current feature StateIdLedger, artifact/workflow/bootstrap authorities<br/>and released project lock; directly compare every candidate component with current state}
    BCOMPARE -- Equal --> BREUSE[Reuse exact current BootstrapAuthorityState and component IDs/path/bytes;<br/>perform no authority or StateIdLedger write]
    BCOMPARE -- Changed --> BPLAN[ClassifyBootstrapAuthorityChangeAction<br/>produce one complete BootstrapAuthorityChangePlan with total coordinate assignments,<br/>dominant earliest owner, all secondary impacts and unioned obligations]
    BPLAN --> BPVALID{ValidateBootstrapAuthorityChangePlanAction}
    BPVALID -- Invalid --> FAIL
    BPVALID -- Valid --> BRACTION[RouteBootstrapAuthorityChangeAction<br/>use exact current stage, open-clarification projection, descendants and watermark]
    BRACTION --> BRVALID{ValidateBootstrapAuthorityChangeRouteAction<br/>prove every change-plan obligation is preserved and no gate is bypassed}
    BRVALID -- Invalid --> FAIL
    BRVALID -- Valid --> BRTYPE{BootstrapAuthorityChangeRoutePlan variant}
    BRTYPE -- DeferredPlanningBootstrapRoute before specified --> PDEFER[Retain the current bootstrap authority and adopt nothing in the specification route;<br/>carry only the validated run-local planning change plan and closed recheck obligation;<br/>discard candidate handles at user pause or run end, then deterministically rebuild,<br/>compare, classify, validate and route at the first PlanInput gate after specified]
    PDEFER --> READY[Bootstrap routing complete under the exact durable current or adopted authority;<br/>all required secondary obligations are discharged before the next normal node]
    BRTYPE -- AdministrativeBootstrapBlockRoute --> FAIL
    BRTYPE -- CompatibleBootstrapRefreshRoute --> DIRECT[Select bootstrap_authority_refresh;<br/>legal from every stable nonterminal stage and changes no semantic-stage field]
    DIRECT --> BTXBEGIN
    BRTYPE -- ReferenceIngestionBootstrapRoute --> RHANDOFF[Return exactly one typed handoff to diagram 05:<br/>validated identity-free bootstrap candidate, candidate-change evidence,<br/>validated change plan and route evidence; allocate, serialize and commit nothing here]
    BRTYPE -- OwningSpecificationBootstrapRoute specify_completion --> SHANDOFF[Return only a specification-owning plan whose dominant impact is specification_contract,<br/>plus the typed identity-free successor/change-plan/route evidence, to SpecifyCompletion;<br/>allocate/persist no standalone state]
    BRTYPE -- OwningSpecificationBootstrapRoute clarification pause or resolution --> SCHANDOFF[Return only a specification-owning plan whose dominant impact is specification_contract,<br/>plus typed successor/change-plan/route evidence, to the owning spec pause/resolution transaction]
    BRTYPE -- OwningPlanningBootstrapRoute plan_input_authority --> PIROUTE[Select initial specified-to-planning or successor planning-to-planning<br/>PlanInputAuthority transaction exactly as encoded by the validated route]
    BRTYPE -- OwningPlanningBootstrapRoute clarification pause or resolution --> PICLAR[Select the owning PlanClarificationPause or AuthorityResolution transaction;<br/>bind its exact prospective clarification revision and remain pending when required]
    BRTYPE -- BootstrapReworkInvalidationRoute --> RWROUTE{Earliest owner and runtime mutation}
    RWROUTE -- specify and no_committed_runtime --> SREWORK[Select rework_invalidation to specifying;<br/>at specified the validated descendant arrays are empty]
    RWROUTE -- specify and reconcile_committed_runtime --> SRECON[Select rework_invalidation to implementation_reconciliation_spec]
    RWROUTE -- plan and no_committed_runtime --> PREWORK[Select rework_invalidation to planning with exact affected descendants]
    RWROUTE -- plan and reconcile_committed_runtime --> PRECON[Select rework_invalidation to implementation_reconciliation_plan]
    PIROUTE --> BTXBEGIN
    PICLAR --> BTXBEGIN
    SREWORK --> BTXBEGIN
    SRECON --> BTXBEGIN
    PREWORK --> BTXBEGIN
    PRECON --> BTXBEGIN
    BTXBEGIN[Enter diagram 09 feature-storage lifecycle with the selected exact DurableTransactionKind:<br/>acquire/recover the feature collection, AssignTransactionIdAction,<br/>PersistTransactionIdReservationAction and build storage capability before sealing] --> BRELOAD[Under that feature lock, resolve/read/parse/validate the current FeatureStateIdLedger,<br/>ReadWorkflowStateAction, ParseWorkflowStateAction and ValidateWorkflowStateAction,<br/>and reload/validate the expected current BootstrapAuthorityState;<br/>if any expected revision changed, retire this transaction ID and restart comparison/classification]
    BRELOAD --> BAID[AssignBootstrapAuthorityStateIdAction<br/>reserve the exact feature-scoped authority ID from the reloaded current feature ledger]
    BAID --> BCOMP[AssignBootstrapComponentIdAction for every generic leaf and the compiled-policy slot,<br/>plus AssignPathTokenGrammarStateIdAction for the base grammar; then call<br/>MaterializeBootstrapCandidateComponentAction only for typed leaf candidates in canonical order;<br/>preset/principle specialized identities remain exact and owner-local IDs consume no state ledger]
    BCOMP --> BLEAFMAP[BuildBootstrapCandidateDependencyResolutionMapAction for leaf_dependencies then<br/>ValidateBootstrapCandidateDependencyResolutionMapAction; prove exact leaf-only bindings<br/>and leave only base-grammar/policy aggregate handles unresolved]
    BLEAFMAP --> BGRAMMAR[BuildSupersetPathTokenGrammarAction then ValidateSupersetPathTokenGrammarAction<br/>from the assigned grammar ID, validated blueprint and leaf-dependency map;<br/>BindDerivedBootstrapCandidateComponentAction binds its aggregate handle]
    BGRAMMAR --> BGRAMMARMAP[BuildBootstrapCandidateDependencyResolutionMapAction for base_grammar_resolved<br/>then ValidateBootstrapCandidateDependencyResolutionMapAction against leaf_dependencies;<br/>prove strict extension and leave only the compiled-policy handle unresolved]
    BGRAMMARMAP --> BCOMPILE[AssembleCompiledEnginePolicyAction then ValidateCompiledEnginePolicyAction<br/>from its assigned ID, validated blueprint and grammar-resolved map;<br/>BindDerivedBootstrapCandidateComponentAction binds the policy aggregate handle]
    BCOMPILE --> BCOMPLETEMAP[BuildBootstrapCandidateDependencyResolutionMapAction for complete then<br/>ValidateBootstrapCandidateDependencyResolutionMapAction against base_grammar_resolved;<br/>prove total one-to-one generic-handle coverage with none unresolved]
    BCOMPLETEMAP --> BACORE[BuildBootstrapAuthorityStateCoreAction then<br/>ValidateBootstrapAuthorityStateCoreAction;<br/>the unlinked successor core contains no fabricated parent/change evidence]
    BACORE --> BCHANGEEVIDENCE[BindMaterializedBootstrapChangeEvidenceAction then<br/>ValidateMaterializedBootstrapChangeEvidenceAction for the existing classified change;<br/>replace every run-local handle with the exact staged successor identity and retain<br/>the validated change plan plus total direct comparison evidence]
    BCHANGEEVIDENCE --> BASUCCESSOR[BuildSuccessorBootstrapAuthorityStateAction with the exact current parent<br/>and materialized evidence, then ValidateBootstrapAuthorityStateAction;<br/>only this closed lineage wrapper is a canonical successor authority]
    BASUCCESSOR --> BAPATH[ResolveBootstrapAuthorityStatePathAction then SerializeBootstrapAuthorityStateAction<br/>produce transaction-private candidate bytes only; write nothing independently]
    BAPATH --> BOWNER{Validated change plan and closed route-plan variant}
    BOWNER -- CompatibleRuntimeOnly --> EREFRESHINPUT[AssignWorkflowStateIdAction then BuildNextStageStateAction;<br/>the successor differs only in workflow identity/revision/bootstrap pointer,<br/>and carries the exact staged authority, materialized change evidence and feature-ledger successor]
    EREFRESHINPUT --> EREFRESH[Invoke diagram 09 feature-storage bootstrap_authority_refresh lifecycle;<br/>after transaction-ID reservation BuildBootstrapAuthorityRefreshStageTransactionAction then<br/>ValidateBootstrapAuthorityRefreshStageTransactionAction; commit before using any refreshed identity]
    BOWNER -- BootstrapReworkInvalidationRoute earliest specify --> SPECINPUT[AssignReworkInvalidationRecordIdAction, BuildReworkInvalidationRecordAction and<br/>ValidateReworkInvalidationRecordAction for the specification earliest owner;<br/>BuildWorkflowControlEventAppendSequenceAction; assign successive control-state IDs and call<br/>AppendWorkflowControlEventAction once for rework and, iff committed runtime, once for evidence<br/>invalidation in fixed order; ValidateWorkflowControlEventRegistryAction on only the final revision;<br/>use empty descendants at specified and exact affected descendants later; committed runtime also calls<br/>BuildReconciledTaskRuntimeStateAction, AssignExecutionEvidenceRegistryStateIdAction,<br/>AssignExecutionEvidenceInvalidationIdAction, BuildNextExecutionEvidenceRegistryWithRetirementsAction,<br/>BuildExecutionEvidenceInvalidationRecordAction and ValidateExecutionEvidenceInvalidationAction;<br/>thread every feature-ledger/control successor, regenerate views, then AssignWorkflowStateIdAction<br/>and BuildNextStageStateAction to specifying or implementation_reconciliation_spec]
    SPECINPUT --> SPECINV[Invoke diagram 09 feature-storage rework_invalidation lifecycle;<br/>after transaction-ID reservation BuildReworkInvalidationStageTransactionAction and<br/>ValidateWorkflowTransitionStageTransactionAction with exact staged bootstrap/change evidence,<br/>feature-ledger successor, control/runtime/evidence mutation and regenerated views]
    BOWNER -- OwningPlanningBootstrapRoute plan_input_authority --> PIINPUT[Refresh normalized specification, repository facts, baseline files, research and<br/>the complete category-based raw principle selection; AssignPlanInputAuthorityStateIdAction,<br/>BuildPlanInputAuthorityStateAction and ValidatePlanInputAuthorityStateAction;<br/>AssignWorkflowStateIdAction and BuildNextStageStateAction to planning]
    PIINPUT --> PITX[Continue diagram 09 plan_input_authority lifecycle:<br/>BuildPlanInputAuthorityStageTransactionAction and ValidateCoreStageTransactionAction;<br/>commit the exact initial/successor PlanInputAuthority, staged bootstrap/change evidence,<br/>feature-ledger successor and planning workflow]
    BOWNER -- OwningPlanningBootstrapRoute clarification pause or resolution --> PCINPUT[Build the exact next same-ID open or authority-resolved clarification registry first,<br/>then AssignPlanInputAuthorityStateIdAction, BuildPlanInputAuthorityStateAction and<br/>ValidatePlanInputAuthorityStateAction bound to that exact clarification revision;<br/>AssignWorkflowStateIdAction and BuildNextStageStateAction to pending or planning<br/>according to the remaining-open set]
    PCINPUT --> PCTX[Continue diagram 09 using the route's clarification_pause or<br/>clarification_authority_resolution DurableTransactionKind;<br/>BuildClarificationPauseStageTransactionAction or<br/>BuildClarificationAuthorityResolutionStageTransactionAction, validate and commit the staged<br/>bootstrap/change evidence, successor PlanInput, clarification registry/forms and ledger successors]
    BOWNER -- BootstrapReworkInvalidationRoute earliest plan --> PLANINPUT[AssignReworkInvalidationRecordIdAction, BuildReworkInvalidationRecordAction and<br/>ValidateReworkInvalidationRecordAction for the deterministic plan owner;<br/>BuildWorkflowControlEventAppendSequenceAction; assign successive control-state IDs and call<br/>AppendWorkflowControlEventAction once for rework and, iff committed runtime, once for evidence<br/>invalidation in fixed order; ValidateWorkflowControlEventRegistryAction on only the final revision;<br/>committed runtime also calls BuildReconciledTaskRuntimeStateAction,<br/>AssignExecutionEvidenceRegistryStateIdAction, AssignExecutionEvidenceInvalidationIdAction,<br/>BuildNextExecutionEvidenceRegistryWithRetirementsAction,<br/>BuildExecutionEvidenceInvalidationRecordAction and ValidateExecutionEvidenceInvalidationAction;<br/>thread every feature-ledger/control successor, regenerate plan/tasks views, then<br/>AssignWorkflowStateIdAction and BuildNextStageStateAction to planning or reconciliation_plan]
    PLANINPUT --> PLANINV[Continue diagram 09 rework_invalidation lifecycle;<br/>BuildReworkInvalidationStageTransactionAction and ValidateWorkflowTransitionStageTransactionAction<br/>with exact staged bootstrap/change evidence, feature-ledger successor,<br/>runtime/evidence variant, views and next workflow state]
    EREFRESH --> EREFRESHEND[Complete diagram 09: write marker last, CommitTransactionIdAction or<br/>rollback plus RetireTransactionIdAction, clean up and<br/>ReleaseFeatureTransactionCollectionLockAction exactly once]
    EREFRESHEND --> LCHANGE{changePlan.obligations.transitionFeatureLogging}
    LCHANGE -- False --> READY
    LCHANGE -- Yes --> LREBIND[Build/validate the successor policy and binding, then invoke diagram 06:<br/>BuildFeatureLogPolicyTransitionAction and ValidateFeatureLogPolicyTransitionAction;<br/>for each locked stream recover the old tail, CloseFeatureLogStreamForPolicyTransitionAction,<br/>initialize/recover the new-binding tail and ValidateFeatureLogPolicyTransitionStreamAction;<br/>release every stream lock, then ActivateFeatureLogPolicyTransitionAction and flush<br/>bounded buffered telemetry through the successor policy]
    LREBIND --> READY
    SPECINV --> FTXEND[Complete diagram 09: write marker last, CommitTransactionIdAction or<br/>rollback plus RetireTransactionIdAction, clean up and<br/>ReleaseFeatureTransactionCollectionLockAction exactly once]
    PITX --> FTXEND
    PCTX --> FTXEND
    PLANINV --> FTXEND
    FTXEND --> LCHANGE
    BREUSE --> READY

    FAIL --> FLOCK{Project-transaction lock capability is currently held}
    FLOCK -- Yes --> FRELEASE[ReleaseProjectTransactionCollectionLockAction<br/>exactly once with the typed failure/cancel terminal outcome]
    FLOCK -- No --> FAILEND[Return the typed bootstrap failure]
    FRELEASE --> FAILEND

    EXAMPLES[design/examples/.sddtoolkit.json<br/>current reader-facing schema example] -. never searched, installed or used as runtime fallback .-> EXCLUDED[Excluded from runtime bootstrap]
    MIGRATE[Offline curated migration and human review] -. never invoked by bootstrap, specify, plan, tasks,<br/>implement or recovery .-> EXCLUDED
    MIGRATE -. separate administrative workflow only .-> INSTALL[Atomically install a fully validated v1 package-and-asset set<br/>under paths.toolchainPreset]
    INSTALL -. a later independent bootstrap inventories every installed byte from the beginning .-> TROOT
    TEMPLATEINERT -. reserved future contract only .-> FUTUREINIT[Future sdd init template-to-principles boundary;<br/>not a current v1 action or transaction and never model authority]
    FUTUREINIT -. a later bootstrap could ingest future materialized Markdown .-> PROOT
```
