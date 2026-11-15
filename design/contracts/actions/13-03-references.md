# 13.3 Reference actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

One entry per registered reference operation, in workflow order: owner, data keys, side
effect, responsibility and typed rejections. Entries marked "Proposed, no code" are
responsibilities another document names and no code implements yet; §16 owns the
reference contract.

The reference selector's normalization, validation and directory inspection are steps 4 to 6 of
`prepare-inputs` ([13.2](13-02-invocation-stage-gates.md#prepareinputsaction-prepare-inputs)).

[ADR 0031](../../decisions/0031-stage-actions.md) made the fourteen former preparation
operations the internal steps of two stage actions, with `compile-naming-policy`
([13.1](13-01-bootstrap-configuration.md)) staying a separate step between them. The Specify
workflow runs `prepare-reference-evidence`, `compile-naming-policy`, then
`prepare-reference-tokens`.

## `PrepareReferenceEvidenceAction` (`prepare-reference-evidence`)

- **Owner:** [`src/actions/reference/prepare_reference_evidence.zig`](../../../src/actions/reference/prepare_reference_evidence.zig)
  (binding [`reference_evidence_preparation_workflow.zig`](../../../src/application/reference_evidence_preparation_workflow.zig))
- **Reads:** `reference_directory`, `feature_directory` · **Writes:** `citable_reference_inputs` · **Side effect:** `filesystem_read`
- **Ports:** the corpus enumerator and capturer, the Markdown decoder, the reference-state identity
  source and the Unicode text services (normalizer and case folder, one port family); the binding
  derives `reference-content-read`, `reference-decode` and `reference-identity` only.
- **Outcomes:** `ok`, `failed`. Each internal step's success continues to the next and every
  failure ends the stage with the step's own error, recorded as `step_id` in the failed action's
  event ([§27](../27-observability.md)). It checks the runtime between steps.
- **Does:** Runs these functions in order. Each keeps its former action's responsibility, input,
  output and rejection rules; intermediates are function-local values.
  1. `inventorySources`: enumerates the selected directory. Rejects errors of
     `reference_corpus_source.Error`.
  2. `validateInventory`: checks the raw entries against the entry-count, depth and duration
     limits, with Unicode normalization and case folding; any failure is
     `InvalidReferenceInventory`.
  3. `captureSources`: captures each inventoried entry. Rejects errors of
     `reference_corpus_source.Error`.
  4. `decodeMarkdown`: decodes each captured entry, recording directories, blocked entries and
     decoder failures per entry, and totals the decoded bytes. Rejects only allocation failure: an
     unsupported, malformed or over-budget entry is recorded as that entry's `blocked` result
     (`unsupported_media`, `malformed_text`, `decoded_budget`), and the step still succeeds.
  5. `validateAccounting`: requires the decoded and captured entries to match the inventory one for
     one within the entry limit, then totals source and decoded bytes into the accepted
     documents. Rejects `InvalidReferenceAccounting`.
  6. `assignIdentities`: numbers sources in document order and maps each provisional source and
     block to its canonical ID under a fresh reference-state ID. It is the only step that draws
     system entropy, through its own port. Rejects errors of `reference_evidence.Error` and
     `reference_state_identity.Error`.
  7. `buildChunks`: makes one chunk per source block, numbered in source and block order, under the
     `source_blocks_v1` partition. Rejects errors of `reference_evidence.Error`.
  8. `validateChunks`: checks the chunks against the corpus: the same feature and state, one
     source and mapping per document, and one chunk per block mapping. Rejects
     `InvalidReferenceChunks`.

## `PrepareReferenceTokensAction` (`prepare-reference-tokens`)

- **Owner:** [`src/actions/reference/prepare_reference_tokens.zig`](../../../src/actions/reference/prepare_reference_tokens.zig)
  (binding [`reference_token_preparation_workflow.zig`](../../../src/application/reference_token_preparation_workflow.zig))
- **Reads:** `compiled_naming_policy`, `valid_toolchain`, `citable_reference_inputs` · **Writes:**
  `path_token_grammar`, `reference_passive_literals`, `structured_token_candidates` · **Side effect:** `none`
- **Ports:** the Unicode text services (normalizer, case folder and lexical classifier, one port
  family) only; the binding is capability free.
- **Outcomes:** `ok`, `failed`, as above; it checks the runtime between steps.
- **Does:** Runs these functions in order. Each keeps its former action's responsibility, input,
  output and rejection rules; intermediates are function-local values.
  1. `buildGrammar`: builds the superset path-token grammar from the compiled naming policy, the
     toolchain and the inputs. Rejects errors of `path_token_grammar.Error`, including
     `StaleNamingPolicy` for a policy compiled from another toolchain.
  2. `scanLiterals`: collects passive-literal candidates from source bodies in source, block and
     byte order; source names stay citation metadata. Rejects errors of `passive_literals.Error`.
  3. `assignLiterals`: assigns the candidates their identities. Rejects errors of
     `passive_literals.Error`.
  4. `validateLiterals`: re-scans the captured inputs through the same detector, so candidate
     bytes or supplied IDs can neither add an occurrence nor drop source coverage. Rejects errors
     of `passive_literals.Error`.
  5. `extractFacts`: runs the registered extractors over the captured inputs; only an extractor
     decides eligibility, with no filesystem access or model-authored value. Rejects errors of
     `structured_tokens.Error`.
  6. `assignCandidates`: assigns the extracted facts their candidate identities. Rejects errors of
     `structured_tokens.Error`.

## `InitializeReferenceExtractionAction` (`initialize-reference-extraction`)

- **Owner:** [`src/actions/reference/initialize_reference_extraction.zig`](../../../src/actions/reference/initialize_reference_extraction.zig)
- **Reads:** `citable_reference_inputs` · **Writes:** `reference_extraction_progress` · **Side effect:** `none`
- **Rejects:** errors of `reference_extraction.Error`

## `CheckReferenceExtractionProgressAction` (`check-reference-extraction-progress`)

- **Owner:** [`src/actions/reference/check_reference_extraction_progress.zig`](../../../src/actions/reference/check_reference_extraction_progress.zig)
- **Reads:** `reference_extraction_progress` · **Writes:** nothing · **Side effect:** `none`
- **Does:** Returns `more` while a chunk remains to extract, otherwise `ok`.
- **Rejects:** none; returns a workflow outcome

## `BuildReferenceExtractionModelInputAction` (`build-reference-extraction-model-input`)

- **Owner:** [`src/actions/reference/build_reference_extraction_model_input.zig`](../../../src/actions/reference/build_reference_extraction_model_input.zig)
- **Reads:** `citable_reference_inputs`, `reference_passive_literals`, `structured_token_candidates`, `reference_extraction_progress` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Builds the extraction request for the current chunk from the shared evidence, passive literals and token candidates, with the claim-citation bound.
- **Rejects:** `InvalidReferenceExtraction` and the rest of `reference_model_input.Error`

## `ConstructForcedTokenClassificationsAction` (`construct-forced-token-classifications`)

- **Owner:** [`src/actions/reference/construct_forced_token_classifications.zig`](../../../src/actions/reference/construct_forced_token_classifications.zig)
- **Parameters:** required `source-part` and `native-composition-part` (the composition parts it reads and fills).
- **Reads:** `json_composition`, `structured_token_candidates`, `citable_reference_inputs` · **Writes:** replaces `json_composition` · **Side effect:** `none`
- **Does:** Construct only decisions forced by the admitted extraction outcome.
- **Rejects:** `InvalidReferenceExtraction` and the rest of `json_composition_runtime.Error`, `reference_extraction.Error`

## `BuildReferenceExtractionResultsAction` (`build-reference-extraction-results`)

- **Owner:** [`src/actions/reference/build_reference_extraction_results.zig`](../../../src/actions/reference/build_reference_extraction_results.zig)
- **Reads:** `reference_extraction_progress` · **Writes:** `raw_reference_extraction` · **Side effect:** `none`
- **Does:** Closes the per-chunk iteration into the raw extraction result.
- **Rejects:** errors of `reference_extraction.Error`

## `ParseReferenceExtractionResultsAction` (`parse-reference-extraction-results`)

- **Owner:** [`src/actions/reference/parse_reference_extraction_results.zig`](../../../src/actions/reference/parse_reference_extraction_results.zig)
- **Reads:** `raw_reference_extraction` · **Writes:** `parsed_reference_extraction` · **Side effect:** `none`
- **Rejects:** errors of `reference_extraction.Error`

## `ValidateReferenceExtractionTextAction` (`validate-reference-extraction-text`)

- **Owner:** [`src/actions/reference/validate_reference_extraction_text.zig`](../../../src/actions/reference/validate_reference_extraction_text.zig)
- **Reads:** `parsed_reference_extraction`, `reference_passive_literals`, `valid_toolchain`, `citable_reference_inputs` · **Writes:** `text_validated_reference_extraction` · **Side effect:** `none`
- **Does:** Validates each parsed claim's text against the toolchain, the passive-literal registry and the captured inputs.
- **Rejects:** errors of `reference_extraction.Error`

## Repair operations

The repair operations of this area (reference text, reference extraction, reference summary,
dispositions, signals and conflicts, reference reconciliation, and source omission with its two
merges) are variants of the generic repair operations, specified once in
[13-04](13-04-model.md#generic-repair-operations).

## `CollectReferenceExtractionResultAction` (`collect-reference-extraction-result`)

- **Owner:** [`src/actions/reference/collect_reference_extraction_result.zig`](../../../src/actions/reference/collect_reference_extraction_result.zig)
- **Reads:** `reference_extraction_progress`, `assembled_json`, `validated_assembled_json` · **Writes:** replaces `reference_extraction_progress`; invalidates `assembled_json`, `validated_assembled_json` · **Side effect:** `none`
- **Does:** Appends one chunk's response to the extraction progress, rejecting a packet whose unit isn't a reference chunk or whose purpose isn't initial generation.
- **Rejects:** `InvalidReferenceExtraction` and the rest of `reference_extraction.Error`

## `ValidateReferenceSelectionsAction` (`validate-reference-selections`)

- **Owner:** [`src/actions/reference/validate_reference_selections.zig`](../../../src/actions/reference/validate_reference_selections.zig)
- **Reads:** `citable_reference_inputs`, `structured_token_candidates`, `text_validated_reference_extraction` · **Writes:** `validated_reference_selections` · **Side effect:** `none`
- **Does:** Validates the token classifications against the structured token candidates.
- **Rejects:** errors of `reference_extraction.Error`

## `AssignPreservedTokenIdentitiesAction` (`assign-preserved-token-identities`)

- **Owner:** [`src/actions/reference/assign_preserved_token_identities.zig`](../../../src/actions/reference/assign_preserved_token_identities.zig)
- **Reads:** `validated_reference_selections` · **Writes:** `preserved_token_identities` · **Side effect:** `none`
- **Does:** Numbers each `preserve` selection in order; `irrelevant` and `blocked` selections get no ID.
- **Rejects:** `InvalidStructuredTokens` and the rest of `reference_extraction.Error`

## `BuildPreservedTokenClaimsAction` (`build-preserved-token-claims`)

- **Owner:** [`src/actions/reference/build_preserved_token_claims.zig`](../../../src/actions/reference/build_preserved_token_claims.zig)
- **Reads:** `preserved_token_identities` · **Writes:** `prepared_reference_claims` · **Side effect:** `none`
- **Does:** Turns each preserved token into a claim in source-candidate order, independent of the model's classification order, so token and model claims share one citation and identity path.
- **Rejects:** `InvalidStructuredTokens` and the rest of `reference_extraction.Error`

## `ValidateReferenceClaimsAction` (`validate-reference-claims`)

- **Owner:** [`src/actions/reference/validate_reference_claims.zig`](../../../src/actions/reference/validate_reference_claims.zig)
- **Reads:** `citable_reference_inputs`, `prepared_reference_claims` · **Writes:** `validated_reference_claims` · **Side effect:** `none`
- **Does:** Requires one parsed result per chunk, each scoped to the current state and its own chunk, then checks its claims.
- **Rejects:** `InvalidReferenceExtraction` and the rest of `reference_extraction.Error`

## `AssignReferenceClaimIdentitiesAction` (`assign-reference-claim-identities`)

- **Owner:** [`src/actions/reference/assign_reference_claim_identities.zig`](../../../src/actions/reference/assign_reference_claim_identities.zig)
- **Reads:** `validated_reference_claims` · **Writes:** `reference_claim_identities` · **Side effect:** `none`
- **Does:** Numbers claims and their citations in chunk order.
- **Rejects:** `InvalidReferenceExtraction` and the rest of `reference_extraction.Error`

## `BuildReferenceExtractionLedgerAction` (`build-reference-extraction-ledger`)

- **Owner:** [`src/actions/reference/build_reference_extraction_ledger.zig`](../../../src/actions/reference/build_reference_extraction_ledger.zig)
- **Reads:** `reference_claim_identities` · **Writes:** `reference_extraction_ledger` · **Side effect:** `none`
- **Does:** Assembles each chunk's outcome, token classifications, claims and citations into one extraction ledger.
- **Rejects:** `InvalidReferenceExtraction` and the rest of `reference_extraction.Error`

## `ValidateReferenceExtractionAccountingAction` (`validate-reference-extraction-accounting`)

- **Owner:** [`src/actions/reference/validate_reference_extraction_accounting.zig`](../../../src/actions/reference/validate_reference_extraction_accounting.zig)
- **Reads:** `citable_reference_inputs`, `preserved_token_identities`, `reference_extraction_ledger` · **Writes:** `accounted_reference_extraction` · **Side effect:** `none`
- **Does:** Checks that the ledger covers every chunk of the current state once, with its claims, citations, tokens and selections accounted for.
- **Rejects:** `InvalidReferenceExtraction`, `InvalidStructuredTokens` and the rest of `reference_extraction.Error`

## `BuildReferenceReconciliationItemsAction` (`build-reference-reconciliation-items`)

- **Owner:** [`src/actions/reference/build_reference_reconciliation_items.zig`](../../../src/actions/reference/build_reference_reconciliation_items.zig)
- **Reads:** `citable_reference_inputs`, `accounted_reference_extraction` · **Writes:** `reference_reconciliation_items` · **Side effect:** `none`
- **Does:** Requires a complete extraction ledger of the current state, then builds the reconciliation items from its claims.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `PartitionReferenceReconciliationItemsAction` (`partition-reference-reconciliation-items`)

- **Owner:** [`src/actions/reference/partition_reference_reconciliation_items.zig`](../../../src/actions/reference/partition_reference_reconciliation_items.zig)
- **Parameters:** required integer `group-size`, at least 2.
- **Reads:** `reference_reconciliation_items` · **Writes:** `reference_reconciliation_layout` · **Side effect:** `none`
- **Does:** Deterministically partition within source, across sources, or globally under the declared contract.
- **Rejects:** errors of `reference_reconciliation.Error`

## `AssignReferenceReconciliationPartitionsAction` (`assign-reference-reconciliation-partitions`)

- **Owner:** [`src/actions/reference/assign_reference_reconciliation_partitions.zig`](../../../src/actions/reference/assign_reference_reconciliation_partitions.zig)
- **Reads:** `reference_reconciliation_layout` · **Writes:** `reference_reconciliation_plan` · **Side effect:** `none`
- **Does:** Numbers the layout's groups as partitions, requiring every child to come before its parent.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `ValidateReferenceReconciliationPartitionsAction` (`validate-reference-reconciliation-partitions`)

- **Owner:** [`src/actions/reference/validate_reference_reconciliation_partitions.zig`](../../../src/actions/reference/validate_reference_reconciliation_partitions.zig)
- **Reads:** `reference_reconciliation_plan` · **Writes:** `reference_reconciliation_progress` · **Side effect:** `none`
- **Does:** Validates the partition plan and starts reconciliation progress at the first summary.
- **Rejects:** errors of `reference_reconciliation.Error`

## `BuildReferenceReconciliationInputAction` (`build-reference-reconciliation-input`)

- **Owner:** [`src/actions/reference/build_reference_reconciliation_input.zig`](../../../src/actions/reference/build_reference_reconciliation_input.zig)
- **Reads:** `reference_reconciliation_progress` · **Writes:** `reference_reconciliation_input` · **Side effect:** `none`
- **Does:** Builds the next partition's input: its claim items and its children's summaries.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `BuildReferenceReconciliationModelInputAction` (`build-reference-reconciliation-model-input`)

- **Owner:** [`src/actions/reference/build_reference_reconciliation_model_input.zig`](../../../src/actions/reference/build_reference_reconciliation_model_input.zig)
- **Reads:** `reference_reconciliation_input`, `citable_reference_inputs`, `reference_passive_literals`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Builds the reconciliation request packet, adding the workflow's summary purpose.
- **Rejects:** errors of `reference_model_input.ReconciliationError`

## `CheckReferenceReconciliationPurposeAction` (`check-reference-reconciliation-purpose`)

- **Owner:** [`src/actions/reference/check_reference_reconciliation_purpose.zig`](../../../src/actions/reference/check_reference_reconciliation_purpose.zig)
- **Reads:** `reference_reconciliation_input` · **Writes:** nothing · **Side effect:** `none`
- **Does:** Returns `more` for a summary input and `ok` for the global one.
- **Rejects:** none; returns a workflow outcome

## `CheckReferenceSummaryReuseAction` (`check-reference-summary-reuse`)

- **Owner:** [`src/actions/reference/check_reference_summary_reuse.zig`](../../../src/actions/reference/check_reference_summary_reuse.zig)
- **Reads:** `reference_reconciliation_input`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain` · **Writes:** nothing · **Side effect:** `none`
- **Does:** Prove that a non-final, nonempty partition contains exactly one current validated child with unchanged membership and dependencies under §16.4.
- **Rejects:** errors of `reference_reconciliation.Error`

## `ReuseReferenceReconciliationSummaryAction` (`reuse-reference-reconciliation-summary`)

- **Owner:** [`src/actions/reference/reuse_reference_reconciliation_summary.zig`](../../../src/actions/reference/reuse_reference_reconciliation_summary.zig)
- **Reads:** `reference_reconciliation_input`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `parsed_reference_reconciliation` · **Side effect:** `none`
- **Does:** Recheck reuse eligibility and carry the child's ordered content into the existing summary validation path.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `BuildReferenceDispositionsAssignmentAction` (`build-reference-dispositions-assignment`)

- **Owner:** [`src/actions/reference/build_reference_dispositions_assignment.zig`](../../../src/actions/reference/build_reference_dispositions_assignment.zig)
- **Reads:** `reference_reconciliation_input`, `citable_reference_inputs`, `reference_passive_literals` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Builds the dispositions request packet; a prior phase other than dispositions is `InvalidReferenceReconciliation`.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_model_input.ReconciliationError`

## `CollectReferenceReconciliationResultAction` (`collect-reference-reconciliation-result`)

- **Owner:** [`src/actions/reference/collect_reference_reconciliation_result.zig`](../../../src/actions/reference/collect_reference_reconciliation_result.zig)
- **Reads:** `reference_reconciliation_input`, `assembled_json`, `validated_assembled_json` · **Writes:** `raw_reference_reconciliation`; invalidates `assembled_json`, `validated_assembled_json` · **Side effect:** `none`
- **Does:** Takes a summary partition's initial-generation response, checking that it belongs to the current reference state.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `ParseReferenceReconciliationResultAction` (`parse-reference-reconciliation-result`)

- **Owner:** [`src/actions/reference/parse_reference_reconciliation_result.zig`](../../../src/actions/reference/parse_reference_reconciliation_result.zig)
- **Reads:** `raw_reference_reconciliation` · **Writes:** `parsed_reference_reconciliation`; invalidates `raw_reference_reconciliation` · **Side effect:** `none`
- **Does:** Decodes the response and projects it into a summary or global proposal according to the input's purpose.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `RenderReferenceContextAction` (`render-reference-context`)

- **Owner:** [`src/actions/reference/render_reference_context.zig`](../../../src/actions/reference/render_reference_context.zig)
- **Reads:** `specification_publication_state` · **Writes:** `rendered_reference_context` · **Side effect:** `none`
- **Does:** Render the sidecar using snapshot-owned source labels/locations and inert registered display literals only.
- **Rejects:** errors of `reference_context.Error`, `specification_projection.Error`

## `ScanPathTokensAction` (`scan-path-tokens`)

- **Owner:** [`src/actions/reference/scan_path_tokens.zig`](../../../src/actions/reference/scan_path_tokens.zig)
- **Parameters:** required `text` ([`path_token_workflow.zig`](../../../src/application/path_token_workflow.zig)).
- **Reads:** `path_token_grammar`, `valid_toolchain`, `citable_reference_inputs` · **Writes:** `path_token_scan` · **Side effect:** `none`
- **Does:** Checks the grammar is still bound to the current policy and toolchain, then lexes path tokens over the raw bytes, never NFC offsets.
- **Rejects:** errors of `path_token_scan.Error`

## `ValidateSourceCitationsAction` (`validate-source-citations`)

- **Owner:** [`src/actions/reference/validate_source_citations.zig`](../../../src/actions/reference/validate_source_citations.zig)
- **Reads:** `citable_reference_inputs`, `reference_citation_proposals` · **Writes:** `validated_source_citations` · **Side effect:** `none`
- **Does:** Checks each proposed citation against the captured sources: structural support only, not semantic proof.
- **Rejects:** errors of `reference_evidence.Error`

## `ValidateReferenceReconciliationCompletenessAction` (`validate-reference-reconciliation-completeness`)

- **Owner:** [`src/actions/reference/validate_reference_reconciliation_completeness.zig`](../../../src/actions/reference/validate_reference_reconciliation_completeness.zig)
- **Reads:** `reference_reconciliation_records` · **Writes:** `accounted_reference_reconciliation` · **Side effect:** `none`
- **Does:** Revalidates the partition history and requires the global result to follow the last partition with one disposition per item.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `BuildReferenceSnapshotAction` (`build-reference-snapshot`)

- **Owner:** [`src/actions/reference/build_reference_snapshot.zig`](../../../src/actions/reference/build_reference_snapshot.zig)
- **Reads:** `reference_directory`, `citable_reference_inputs`, `accounted_reference_extraction`, `accounted_reference_reconciliation`, `reference_passive_literals` · **Writes:** `reference_snapshot` · **Side effect:** `none`
- **Does:** Captures the extraction-contract binding and assembles the snapshot from the accepted extraction and reconciliation records, keeping every source.
- **Rejects:** errors of `reference_extraction_contract.Error`, `reference_snapshot.Error`

## `CollectReferenceDispositionsCandidateAction` (`collect-reference-dispositions-candidate`)

- **Owner:** [`src/actions/reference/collect_reference_dispositions_candidate.zig`](../../../src/actions/reference/collect_reference_dispositions_candidate.zig)
- **Reads:** `reference_reconciliation_input`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** `parsed_reference_reconciliation` · **Side effect:** `none`
- **Does:** Collects the dispositions response; a prior phase other than dispositions is `InvalidReferenceReconciliation`.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `ValidateReferenceReconciliationSummaryAction` (`validate-reference-reconciliation-summary`)

- **Owner:** [`src/actions/reference/validate_reference_reconciliation_summary.zig`](../../../src/actions/reference/validate_reference_reconciliation_summary.zig)
- **Reads:** `parsed_reference_reconciliation`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `validated_reference_summary` · **Side effect:** `none`
- **Does:** Checks the summary; an invalid result records the defect's relations and dependency snapshot for the repair authorizer.
- **Rejects:** errors of `reference_reconciliation.Error`

## `AssignReferenceSummaryIdentitiesAction` (`assign-reference-summary-identities`)

- **Owner:** [`src/actions/reference/assign_reference_summary_identities.zig`](../../../src/actions/reference/assign_reference_summary_identities.zig)
- **Reads:** `validated_reference_summary` · **Writes:** `reference_summary_identities` · **Side effect:** `none`
- **Does:** Numbers the summary after its partition, and its statements from the next statement ordinal.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `BuildReferenceReconciliationSummaryAction` (`build-reference-reconciliation-summary`)

- **Owner:** [`src/actions/reference/build_reference_reconciliation_summary.zig`](../../../src/actions/reference/build_reference_reconciliation_summary.zig)
- **Reads:** `reference_summary_identities`, `reference_reconciliation_plan`, `reference_reconciliation_progress` · **Writes:** replaces `reference_reconciliation_progress`; invalidates `reference_reconciliation_input`, `parsed_reference_reconciliation`, `validated_reference_summary`, `reference_summary_identities` · **Side effect:** `none`
- **Does:** Attach native IDs while preserving normalized statements, complete partition membership, validated child-summary lineage and validation proof.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `ValidateReferenceClaimDispositionsAction` (`validate-reference-claim-dispositions`)

- **Owner:** [`src/actions/reference/validate_reference_claim_dispositions.zig`](../../../src/actions/reference/validate_reference_claim_dispositions.zig)
- **Reads:** `parsed_reference_reconciliation` · **Writes:** `validated_reference_dispositions` · **Side effect:** `none`
- **Does:** Requires a global input and proposal, revalidates the partition history, then validates the dispositions; an invalid result keeps its dependency snapshot.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `CheckReferenceReconciliationPhaseAction` (`check-reference-reconciliation-phase`)

- **Owner:** [`src/actions/reference/check_reference_reconciliation_phase.zig`](../../../src/actions/reference/check_reference_reconciliation_phase.zig)
- **Parameters:** required `phase`: `dispositions`, `signals` or `complete`.
- **Reads:** `parsed_reference_reconciliation` · **Writes:** nothing · **Side effect:** `none`
- **Does:** Returns `ok` when the parsed result is in the expected phase, otherwise `more`.
- **Rejects:** none; returns a workflow outcome

## `BuildReferenceSignalsAssignmentAction` (`build-reference-signals-assignment`)

- **Owner:** [`src/actions/reference/build_reference_signals_assignment.zig`](../../../src/actions/reference/build_reference_signals_assignment.zig)
- **Reads:** `validated_reference_dispositions`, `citable_reference_inputs`, `reference_passive_literals` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Builds the signals request packet; a prior phase other than signals is `InvalidReferenceReconciliation`.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_model_input.ReconciliationError`

## `ValidateReferenceSignalProposalsAction` (`validate-reference-signal-proposals`)

- **Owner:** [`src/actions/reference/validate_reference_signal_proposals.zig`](../../../src/actions/reference/validate_reference_signal_proposals.zig)
- **Reads:** `validated_reference_dispositions`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `validated_reference_signals` · **Side effect:** `none`
- **Does:** Checks the signals; an invalid result records the defect's relations and dependency snapshot.
- **Rejects:** errors of `reference_reconciliation.Error`

## `BuildReferenceConflictsAssignmentAction` (`build-reference-conflicts-assignment`)

- **Owner:** [`src/actions/reference/build_reference_conflicts_assignment.zig`](../../../src/actions/reference/build_reference_conflicts_assignment.zig)
- **Reads:** `validated_reference_signals`, `citable_reference_inputs`, `reference_passive_literals` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Builds the conflicts request packet; a prior phase other than conflicts is `InvalidReferenceReconciliation`.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_model_input.ReconciliationError`

## `ValidateReferenceConflictProposalsAction` (`validate-reference-conflict-proposals`)

- **Owner:** [`src/actions/reference/validate_reference_conflict_proposals.zig`](../../../src/actions/reference/validate_reference_conflict_proposals.zig)
- **Reads:** `validated_reference_signals`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `validated_reference_conflicts` · **Side effect:** `none`
- **Does:** Requires a complete prior phase, checks the conflicts, and records relations and dependencies for an invalid result.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `AssignReferenceReconciliationIdentitiesAction` (`assign-reference-reconciliation-identities`)

- **Owner:** [`src/actions/reference/assign_reference_reconciliation_identities.zig`](../../../src/actions/reference/assign_reference_reconciliation_identities.zig)
- **Reads:** `validated_reference_conflicts` · **Writes:** `reference_reconciliation_identities` · **Side effect:** `none`
- **Does:** Numbers the checked signals and conflicts.
- **Rejects:** errors of `reference_reconciliation.Error`

## `BuildReferenceReconciliationRecordsAction` (`build-reference-reconciliation-records`)

- **Owner:** [`src/actions/reference/build_reference_reconciliation_records.zig`](../../../src/actions/reference/build_reference_reconciliation_records.zig)
- **Reads:** `reference_reconciliation_identities` · **Writes:** `reference_reconciliation_records` · **Side effect:** `none`
- **Does:** Pairs each signal and conflict with its ID into the reconciliation records, rejecting a count mismatch.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `CollectReferenceSignalsCandidateAction` (`collect-reference-signals-candidate`)

- **Owner:** [`src/actions/reference/collect_reference_signals_candidate.zig`](../../../src/actions/reference/collect_reference_signals_candidate.zig)
- **Reads:** `validated_reference_dispositions`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** replaces `parsed_reference_reconciliation`; invalidates `validated_reference_dispositions` · **Side effect:** `none`
- **Does:** Collects the signals response; a prior phase other than signals is `InvalidReferenceReconciliation`.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## `CollectReferenceConflictsCandidateAction` (`collect-reference-conflicts-candidate`)

- **Owner:** [`src/actions/reference/collect_reference_conflicts_candidate.zig`](../../../src/actions/reference/collect_reference_conflicts_candidate.zig)
- **Reads:** `validated_reference_signals`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** replaces `parsed_reference_reconciliation`; invalidates `validated_reference_dispositions`, `validated_reference_signals` · **Side effect:** `none`
- **Does:** Collects the conflicts response; a prior phase other than conflicts is `InvalidReferenceReconciliation`.
- **Rejects:** `InvalidReferenceReconciliation` and the rest of `reference_reconciliation.Error`

## Proposed, no code

Named by [§16](../16-reference-ingestion.md); no operation implements them yet.

## `ReconcileReferenceConflictSubjectSetsAction`

Proposed, no code: Deterministically merge-join the full keys into `P ∩ C`, `P ∖ C`, and `C ∖ P`. ([§16](../16-reference-ingestion.md)).

## `BuildFreshReferenceConflictCorrespondenceAction`

Proposed, no code: Compare options only inside the already established equal-key pair. ([§16](../16-reference-ingestion.md)).

## `BuildResolvedSourceConflictAction`

Proposed, no code: Apply one user decision while retaining its decision ID. ([§16](../16-reference-ingestion.md)).

## `ValidateReferenceFeedbackTargetAction`

Proposed, no code: Validate its exactly-one target and intent-compatible block/chunk, claim, classification, token, and replacement-citation join. ([§16](../16-reference-ingestion.md)).
