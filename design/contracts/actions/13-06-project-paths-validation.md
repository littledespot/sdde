# 13.6 Project path and static-validation actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


## `BuildRepositoryTraversalBudgetAction`

- **Input:** validated project-discovery limits, compiled exclusion rules, and root-access
  registry
- **Output:** repository traversal capability
- **Responsibility:** Bind file-count/depth/time/memory ceilings and immutable pre-descent prune
  rules for one project scan.

## `EnumerateProjectFilesAction`

- **Input:** one contained project root and repository traversal capability
- **Output:** bounded unordered inventory plus prune records
- **Responsibility:** Discover entries without classifying/minting IDs; record and do not
  descend into an excluded or inaccessible subtree.

## `ValidateProjectInventoryEntryAction`

- **Input:** one raw OS directory entry and owning project
- **Output:** canonical existing-file entry
- **Responsibility:** Require UTF-8/NFC relative path, no-follow containment, allowed
  regular-file type, and valid owner.

## `ClassifyProjectInventoryAccessAction`

- **Input:** one canonical entry and compiled root/generated policy
- **Output:** ordinary, generated-read-only, or inaccessible classification
- **Responsibility:** Apply root access before file-kind inference and record the exact rule ID.

## `ValidateProjectInventoryAccountingAction`

- **Input:** raw entries, prune records, and classified canonical entries
- **Output:** inventory-accounting evidence
- **Responsibility:** Prove every encountered entry is registered, rejected, or covered by an
  authorized pre-descent prune record.

## `DetectProjectInventoryCollisionAction`

- **Input:** canonical existing-file entries and compiled portability-policy set
- **Output:** inventory-collision evidence
- **Responsibility:** Reject duplicate or host/target-equivalent existing paths before ordering.

## `SortProjectFileInventoryAction`

- **Input:** collision-free normalized existing paths
- **Output:** ordered existing-file inventory
- **Responsibility:** Sort once by project ID then normalized Unicode-scalar path.

## `BuildPathNameSourceRegistryAction`

- **Input:** validated specification/entity/plan-role records and naming-source policy
- **Output:** path-name-source registry
- **Responsibility:** Assign engine IDs to the exact allowed semantic name sources without
  creating paths.

## `BuildPathIntentOptionRegistryAction`

- **Input:** compiled environment/project/file-kind/semantic-role/template policy and plan-unit
  scope
- **Output:** bounded path-intent-option registry
- **Responsibility:** Bind each allowed project/kind/role/template/capability tuple to one
  stable option ID without choosing an intent.

## `ValidatePathIntentOptionRegistryAction`

- **Input:** option-registry candidate, compiled policy, bound project/source-root registries,
  plan-unit scope, and option ceiling
- **Output:** path-intent-option evidence
- **Responsibility:** Prove complete unique in-scope option coverage, exact typed-tuple IDs,
  valid bindings/capability ceilings, and the hard count limit before any option reaches a
  model.

## `ValidatePathIntentProposalAction`

- **Input:** one ID-only path intent, exact option/name-source/anchor registries, and plan unit
  scope
- **Output:** path-intent evidence
- **Responsibility:** Resolve the selected option as one indivisible authorized tuple, validate
  the name source/anchor and capability subset, allow only create/copy-destination requests, and
  accept no filename.

## `SelectPresetPathTemplateAction`

- **Input:** one valid path intent with its resolved option and compiled preset templates
- **Output:** ordered applicable templates
- **Responsibility:** Select only the option-bound templates in stable template-ID order.

## `EnumerateProjectPathCandidateAction`

- **Input:** one valid intent, one selected template, exact name-source text, registered
  versioned name transform, and bound roots/placement anchor
- **Output:** raw engine path candidate
- **Responsibility:** Apply the complete registered name transform and directory strategy once;
  do not validate, invent a collision suffix, or assign identity.

## `AssignPathCandidateIdAction`

- **Input:** one fully path-valid ordered candidate and current plan ID ledger
- **Output:** identified path candidate plus next ledger
- **Responsibility:** Assign one monotonic engine-owned candidate ID without deriving it from
  path bytes; retire failed allocations and never reuse them.

## `AssignPathCandidateRegistryStateIdAction`

- **Input:** plan scope, input file-registry identity, validated current feature
  `StateIdLedger`, and matching single-use namespace capability
- **Output:** path-candidate-registry reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry state ID.

## `BuildPathCandidateRegistryAction`

- **Input:** registry identity, exact option/file/name-source states, and all identified valid
  candidates
- **Output:** path-candidate registry candidate
- **Responsibility:** Assemble the complete finite ordered selection set without choosing a
  file.

## `ValidatePathCandidateRegistryAction`

- **Input:** registry candidate, option registry, path intents/templates/transforms, file
  registry, candidate ceiling, and all path-rule evidence
- **Output:** path-candidate evidence
- **Responsibility:** Prove total intent coverage, exact derivation/order, bound compliance,
  uniqueness, and no existing/cross-platform collision; return the typed zero/over-limit outcome
  instead of a partial registry.

## `ValidatePathCandidateSelectionAction`

- **Input:** one model-selected candidate ID, exact path-candidate registry, and current plan
  unit
- **Output:** selected candidate evidence
- **Responsibility:** Resolve one current unit-allowed candidate without accepting a path
  string.

## `ValidateRawPathFallbackPolicyAction`

- **Input:** one raw fallback selection, explicit engine flag/preset support, and path intent
- **Output:** fallback authorization
- **Responsibility:** Reject by default; when explicitly enabled, require the full raw candidate
  to match the same intent before normal path validation/atomic repair.

## `NormalizeProjectPathAction`

- **Input:** raw model path field
- **Output:** normalized lexical path
- **Responsibility:** Validate UTF-8, normalize Unicode to NFC, canonicalize literal separators,
  and remove literal dot segments without percent decoding.

## `ValidateLexicalPathSafetyAction`

- **Input:** normalized path
- **Output:** lexical path evidence
- **Responsibility:** Reject absolute, traversal, control, URI, drive/UNC, and direct/repeated
  percent-encoded dot or separator forms.

## `ValidatePathContainmentAction`

- **Input:** lexically safe path and workspace
- **Output:** contained path
- **Responsibility:** Enforce root and existing-ancestor containment.

## `ValidateRootAccessClassAction`

- **Input:** contained path, intent/capability, file provenance, and compiled root registry
- **Output:** root-access evidence
- **Responsibility:** Apply one access class; only an engine-issued `generated_existing` read
  may pass `generated_read_only`.

## `RegisterGeneratedReadInputAction`

- **Input:** discovered existing generated file and preset read policy
- **Output:** read-only generated `FileRecord`
- **Responsibility:** Mint one engine-issued generated input ID without model path authority.

## `ValidateDeclaredProjectOwnershipAction`

- **Input:** declared project ID, contained path, and project/environment registry
- **Output:** matching ownership evidence
- **Responsibility:** Prove the path belongs to the declared project; never substitute another
  owner.

## `InferExistingFileKindAction`

- **Input:** one ownership-valid existing path and compiled kind languages
- **Output:** unique inferred kind
- **Responsibility:** Select the unique highest-priority compatible existing kind or diagnose
  ambiguity.

## `AssignFileIdAction`

- **Input:** one ordered existing file or accepted planned path and file-ID ledger
- **Output:** identified file candidate
- **Responsibility:** Allocate one monotonic file ID without path hashing.

## `BuildExistingFileRecordAction`

- **Input:** identified existing path, ownership, inferred kind, and compiled policy-capability
  ceiling
- **Output:** existing file record
- **Responsibility:** Construct one `repository_existing` record with `present` state and no
  plan grant.

## `BuildPlannedFileRecordAction`

- **Input:** identified accepted absent create-path candidate, ownership, kind, and compiled
  policy-capability ceiling
- **Output:** planned file record
- **Responsibility:** Construct one `plan_declared` record with engine-derived `absent` state
  and no embedded grant.

## `ValidateFileRegistryCollisionAction`

- **Input:** one file record and current registry
- **Output:** registry uniqueness evidence
- **Responsibility:** Reject duplicate IDs, canonical paths, or cross-platform-equivalent paths.

## `AssignBootstrapDiscoveryFileRegistryStateIdAction`

- **Input:** prospective bootstrap-authority-state ID and singleton discovery-file component
  descriptor
- **Output:** owner-local discovery-file-registry identity
- **Responsibility:** Construct the registered bootstrap-component tuple without consuming a
  generic state ledger.

## `AssignFileRegistryStateIdAction`

- **Input:** plan scope, optional prior plan file registry, validated current feature
  `StateIdLedger`, and matching single-use namespace capability
- **Output:** plan file-registry-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable plan-owned registry state ID.

## `BuildFileRegistryStateAction`

- **Input:** registry identity, ordered validated file records, next file-ID
  allocator/tombstones, and prior registry revision if any
- **Output:** file-registry-state candidate
- **Responsibility:** Assemble one complete versioned file registry.

## `ValidateFileRegistryStateAction`

- **Input:** registry candidate, prior revision, project/environment/kind/root/portability
  authorities
- **Output:** file-registry evidence
- **Responsibility:** Prove ID/path uniqueness, monotonic allocation, immutable retained
  records, ownership, expected existence, capability ceilings, and host/target collision
  freedom.

## `ValidateDeclaredFileKindAction`

- **Input:** project path, resolved path-intent option or authorized raw-fallback kind, and
  preset
- **Output:** kind evidence
- **Responsibility:** Bind the path to the exact option-authorized kind in the normal flow; for
  raw fallback, validate the declared kind without substituting a more permissive sibling kind.

## `ValidatePathOperationAction`

- **Input:** declared kind and planning intent
- **Output:** operation evidence
- **Responsibility:** Validate one read/create/update/delete planning permission.

## `ValidatePathRootAction`

- **Input:** project path and kind roots
- **Output:** root evidence
- **Responsibility:** Validate one segment-aware root policy.

## `ValidatePathIncludeExcludeAction`

- **Input:** project path and one typed include/exclude rule
- **Output:** filter evidence
- **Responsibility:** Apply one kind-policy filter.

## `EvaluatePathIncludeExcludeSetAction`

- **Input:** complete include/exclude match evidence for one containing policy
- **Output:** filter-set authorization
- **Responsibility:** Apply empty-include/any-include/exclude-wins semantics once.

## `ValidateBasenameAction`

- **Input:** basename and kind
- **Output:** basename evidence
- **Responsibility:** Apply exact/glob/regex name rules.

## `ValidateExtensionAction`

- **Input:** basename and kind
- **Output:** extension evidence
- **Responsibility:** Apply longest compound-extension rules.

## `ValidateFilenamePortabilityAction`

- **Input:** normalized relative path, canonical workspace/project root, and compiled
  portability-policy set
- **Output:** portability evidence
- **Responsibility:** Apply target relative limits and host joined absolute-path
  Unicode/name/case/length rules.

## `ValidateCaseFoldCollisionAction`

- **Input:** normalized path, compiled portability-policy set, and file registry
- **Output:** collision evidence
- **Responsibility:** Detect one host or target path collision.

## `ValidateExpectedTargetStateAction`

- **Input:** file record, plan grant, canonical operation, current runtime-file-state
  record/revision, and no-follow target metadata
- **Output:** target-state evidence
- **Responsibility:** Validate the operation-specific current presence/absence, regular-file
  type, and descriptor revision without trusting the immutable plan baseline after execution
  starts.

## `AssignFileStateTransitionIdAction`

- **Input:** operation record and exact current `TaskExecutionIdLedger` revision
- **Output:** file-state-transition identity plus allocation delta
- **Responsibility:** Select one engine-owned transition ordinal before construction.

## `BuildFileStateTransitionAction`

- **Input:** transition identity, operation record, target-state evidence, and current
  runtime-file-state revision
- **Output:** file-state-transition candidate
- **Responsibility:** Derive the exact before/after lifecycle transition without applying it.

## `ApplyFileStateTransitionAction`

- **Input:** promoted operation evidence, transition candidate, and matching runtime-file-state
  revision
- **Output:** next runtime-file-state revision
- **Responsibility:** Compare-and-swap one file's existence/descriptor state and record the
  operation ID.

## `ValidateFileAuthorizationAction`

- **Input:** file ID, operation, and plan/task authorization registry
- **Output:** authorization evidence
- **Responsibility:** Validate one downstream file permission.

## `ValidateTestPlacementAction`

- **Input:** test path, source mapping, resolved source-root IDs, and preset
- **Output:** placement evidence
- **Responsibility:** Enforce co-located/mirrored/module-root rules without nearest-root
  guessing.

## `ValidateProjectSemanticNameAction`

- **Input:** path and parsed source
- **Output:** semantic filename evidence
- **Responsibility:** Apply Java/C# or configured language rules.

## `OpenValidatedCommitTargetAction`

- **Input:** prepared target descriptor and current ancestors
- **Output:** descriptor-bound no-follow target token
- **Responsibility:** Revalidate and open one race-safe target immediately before apply.

## `ValidateFileReferenceNodeAction`

- **Input:** one typed file-reference node, file registry, and current workflow-operation/unit
  allowlist
- **Output:** reference evidence
- **Responsibility:** Resolve one known and locally authorized `fileId`.

## `ValidateSourceReferenceNodeAction`

- **Input:** one typed source-reference node, reference state, and current
  workflow-operation/unit allowlist
- **Output:** reference evidence
- **Responsibility:** Resolve one known and locally authorized `sourceId`.

## `RejectUnboundPathTokenAction`

- **Input:** one model-authored `LiteralText` or `BusinessLiteralText` segment and version-bound
  superset path-token grammar
- **Output:** prose-path evidence
- **Responsibility:** Reject one inline path/URI/filename lexeme without resolving or
  authorizing it.

## `ParseSourceAction`

- **Input:** source bytes and parser ID
- **Output:** AST/parse diagnostics
- **Responsibility:** Parse one source file.

## `ExtractImportsAction`

- **Input:** AST and query ID
- **Output:** import records
- **Responsibility:** Execute one import query.

## `ResolveImportsAction`

- **Input:** import records and resolver
- **Output:** resolution evidence
- **Responsibility:** Resolve referenced modules.

## `ExtractStaticPathReferenceAction`

- **Input:** containing file ID, AST, parser ID, and one registered
  import/path/resource/endpoint/display query
- **Output:** static-reference occurrence proposal
- **Responsibility:** Extract one exact source range/scalar/context without assigning target or
  identity.

## `AssignStaticReferenceOccurrenceIdAction`

- **Input:** one source-ordered occurrence proposal and file-operation-local allocator
- **Output:** static-reference occurrence
- **Responsibility:** Assign one engine ID while preserving parser/query/range/context/raw
  scalar.

## `ResolveStaticPathReferenceAction`

- **Input:** one occurrence, exact `SourceReferenceAuthorityRegistry`, containing file/project
  aliases, and preset resolver
- **Output:** static-reference resolution or diagnostic
- **Responsibility:** Resolve exactly one project file, existing/planned package,
  contract/runtime/external endpoint, or inert display target.

## `ValidateStaticReferenceContextCompatibilityAction`

- **Input:** occurrence, resolution, and exact authority record
- **Output:** context evidence
- **Responsibility:** Permit package only for module syntax, files/resources only in compatible
  contexts, endpoint schemes/hosts/operations exactly, and passive literals only in
  parser-proven display-only contexts.

## `ScanConservativeContentPathTokenAction`

- **Input:** one model-authored text body and registered fallback grammar
- **Output:** unresolved path-token candidates
- **Responsibility:** Scan text surfaces not claimed by a registered parser/extractor.

## `BuildContentReferenceCoverageAction`

- **Input:** containing file ID, parser-covered/fallback-covered ranges, occurrences,
  resolutions, and rejected fallback candidates
- **Output:** content-reference-coverage candidate
- **Responsibility:** Assemble one file-operation-local coverage record without declaring
  validity.

## `ValidateContentReferenceCoverageAction`

- **Input:** coverage candidate, model-authored byte ranges, exact source-reference authority,
  parser/query/fallback policy
- **Output:** coverage evidence
- **Responsibility:** Prove every byte is claimed by a registered extractor or conservative
  scanner and every path-like occurrence has exactly one context-compatible resolution or
  explicit rejection; unknown/dynamic operational references block.
