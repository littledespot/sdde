# 13.4 Model actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


## `SelectContextAction`

- **Input:** unit plus indexed facts
- **Output:** bounded context set
- **Responsibility:** Select relevant known context.

## `BuildInitialGuidanceAction`

- **Input:** unit, context, compiled policy
- **Output:** guidance packet
- **Responsibility:** Generate deterministic initial guidance.

## `BuildImmutableUnitOwnerIdAction`

- **Input:** one compiled-step descriptor or required SDD canonical owner tuple
- **Output:** immutable unit-owner tuple
- **Responsibility:** Validate the generic workflow-step owner or matching canonical SDD owner
  variant; reject missing/extra fields.
- Generic ownership supplies no SDD repair/review/clarification authority.

## `BuildInitialModelRequestIdentityLedgerAction`

- **Input:** closed request-purpose registry
- **Output:** empty run-local `model.request_identity_ledger/v1` DataKey
- **Responsibility:** Create a fresh process-local execution epoch and initialize its
  ordinal/accounting state without assigning a request; it is the sole producer of this
  compiler-owned key.

## `AssignModelRequestIdAction`

- **Input:** immutable unit owner, exact compiled model-operation identity, one closed
  discriminated purpose binding, and current model-request identity-ledger DataKey revision
- **Output:** one typed model-request ID plus successor-ledger DataKey replacement
- **Responsibility:** Allocate one logical request ordinal and enforce the purpose variant's
  required owner fields; protocol retries do not invoke this action, and runner CAS is the only
  mutation.

## `AdvanceModelRequestLifecycleAction`

- **Input:** exact request ID, expected status, typed invocation/terminal fact, and current
  model-request identity-ledger DataKey revision
- **Output:** successor-ledger DataKey replacement
- **Responsibility:** Apply one runner-enforced compare-and-swap `assigned -> invoked`, `invoked
  -> terminal`, or the approved `assigned -> terminal` not-invoked transition for authorization
  failure; protocol retries remain invoked and never reassign identity.

## `ValidateModelRequestBindingAction`

- **Input:** request ID, immutable unit, compiled workflow model-operation declaration,
  discriminated purpose authority, and current request ledger
- **Output:** model-request binding evidence
- **Responsibility:** Prove epoch/unit/workflow-operation/purpose/ordinal and ledger membership,
  including required/forbidden purpose-owner fields.

## `BuildModelRequestAction`

- **Input:** validated request binding, guidance and exact YAML-declared result schema
- **Output:** internally identified provider-neutral request
- **Responsibility:** Project only needed guidance, evidence and compact result schema into
  model content; retain engine-only identity in the bound request.

## `PrepareModelRequestAction`

- **Input:** current request ledger/revision, compiled model binding and selected
  prompt/schema/input resources or native input packet.
- **Output:** one successor ledger and its assigned, validated and prepared request
  values, published atomically by the runner.
- **Responsibility:** Prepare one request using the existing identity, binding and
  request-construction owners. This pure consolidated entrypoint performs no
  authorization, model call, retry, accounting or continuation. Detailed preparation
  operations remain available under ADR 0012.

## `InvokeModelAction`

- **Input:** identified provider-neutral request, binding evidence, already-applied runner
  attempt transition, and a non-exhausted workflow-execution actual-usage ledger
- **Output:** raw provider result
- **Responsibility:** Make one model call only after identity, operation-local retry accounting,
  and workflow actual-usage budget checks succeed; count evidence is not required.

## `AdmitModelResponseAction`

- **Input:** complete validated provider evidence with its retained selected schema.
- **Output:** one decoded candidate and its schema-validation result. The binding
  retains the existing envelope/payload owners and forwards non-complete outcomes.
- **Responsibility:** Admit response syntax and shape through the existing decoder
  and validator. Detailed operations remain available; no action invokes another
  action. No semantic review, provider call, retry or accounting occurs.

## `BuildPromptBodyFragmentManifestAction`

- **Input:** typed request/result assembly, exact workflow-declared schemas, and
  fragment-classification registry
- **Output:** complete prompt-body fragment manifest
- **Responsibility:** Before provider serialization, bind every loggable typed body field to one
  `ordinary`, `reference_body`, or `code_body` fragment and prove complete pointer coverage;
  never reclassify opaque whole serialized bytes.

## `BuildPromptLogCandidateAction`

- **Input:** complete fragment manifest, provider metadata, exact model operation/slot, and
  enabled feature-log policy
- **Output:** prompt-exchange candidate
- **Responsibility:** Select request fragments only when request capture is enabled, response
  fragments only when response capture is enabled, and additionally require the matching
  reference/code opt-in for those classes; an unclassified or multiply classified fragment
  blocks capture.
- Do not redact, truncate, or emit.

## `RedactPromptLogContentAction`

- **Input:** one prompt candidate, structured secret-field registry, mandatory credential
  detectors, and configured bounded RE2 detectors
- **Output:** redacted prompt candidate and evidence
- **Responsibility:** Remove secrets before any size truncation and never retain an original
  value/length in the replacement.

## `TruncatePromptLogContentAction`

- **Input:** redacted prompt candidate and compiler-fixed 5,000-byte UTF-8 content ceiling
- **Output:** bounded redacted prompt candidate and evidence
- **Responsibility:** Truncate only at a UTF-8 scalar boundary after redaction.

## `ValidatePromptLogContentAction`

- **Input:** bounded redacted prompt candidate, feature-log policy, fragment manifest,
  event/field registry, and record-byte ceiling
- **Output:** transient logging-internal `SanitizedPromptExchangeLogRecord`
- **Responsibility:** Prove complete fragment accounting, all direction/class opt-ins, field
  schemas, redaction-before-truncation evidence, per-fragment/final byte limits, and canonical
  `promptBodyFragmentId` order.
- Retain scalar sanitized fragments and internal evidence separately; no metadata/evidence
  vector is a delimited cell.
- Return it only through a compiler-locked transient logging `DataKey`; it is never added to the
  business envelope or model context.

## `ValidateProviderInvocationObservationAction`

- **Input:** provider observation and exact runner-owned invoked-operation binding
- **Output:** validated observation or provider diagnostic
- **Responsibility:** Prove call association, delivery, stop, usage and UTF-8 safety before any
  candidate decode.

## `DecodeModelEnvelopeAction`

- **Input:** validated complete provider observation with exact request/schema binding
- **Output:** parsed compact result or protocol diagnostic
- **Responsibility:** Parse the complete JSON object only, preserving its trusted association.

## `BuildProtocolRetryGuidanceAction`

- **Input:** decoder/schema diagnostic and original workflow-declared result schema
- **Output:** protocol-retry guidance
- **Responsibility:** Build decoder-only retry guidance without semantic instructions.

## `AdvanceModelAttemptAccountingAction`

- **Input:** exact stage-run epoch/request/unit identity, current runner model-attempt
  accounting, initial-or-retry classification, and the compiler-validated explicit `retry-limit`
  of the YAML-selected retry-capable operation instance
- **Output:** request-keyed compare-and-swap model-attempt transition
- **Responsibility:** Reserve the initial attempt once.
- Reserve a later attempt only after an explicit YAML retry transition and while the
  runner's operation/defect count remains within its declared limit under
  [§22.7](../22-repair.md#227-repair-retry-limit-and-escalation).
- Assign monotonic ordinals for execution-local identity; impose no workflow-global attempt
  ceiling.

## `CheckWorkflowTokenBudgetAction`

- **Input:** current workflow-execution actual-usage ledger
- **Output:** read-only budget check
- **Responsibility:** Reject a subsequent provider call when actual usage is at or above the
  selected policy budget; reserve no tokens and derive no output allowance.

## `ReconcileWorkflowTokenUsageAction`

- **Input:** current execution token ledger, exact inference operation ID, validated reported
  input/output usage or delivery disposition
- **Output:** actual-usage compare-and-swap transition
- **Responsibility:** Account the operation once.
- Retain all reported usage before returning an overshoot error; exact equality blocks later
  calls.
- Unknown usage blocks without an estimate.

## `ValidateModelPayloadSchemaAction`

- **Input:** parsed compact result and its bound workflow-declared result schema
- **Output:** schema-valid candidate result
- **Responsibility:** Apply only the bound closed result schema; do not repeat parsing or
  call-association validation.

## `ValidateSemanticReviewResultAction`

- **Input:** schema-valid payload from the workflow-declared semantic-review operation, exact
  request/unit binding, and closed finding-kind/confidence/disposition policy
- **Output:** validated semantic-finding proposals
- **Responsibility:** Prove result cardinality and allowed kinds without treating a model
  assertion as deterministic evidence.

## `AssignSemanticFindingIdAction`

- **Input:** exact semantic-review request ID and stable finding ordinal
- **Output:** owner-local semantic-finding identity
- **Responsibility:** Construct `{modelRequestId, findingOrdinal}`; accept no model-provided
  identity.

## `ResolveSemanticFindingCitationsAction`

- **Input:** one finding proposal and the request's current authority/span allowlist
- **Output:** exact citation bindings or diagnostic
- **Responsibility:** Resolve every cited record/span against its state revision and reject
  missing, stale, out-of-unit, or uncited findings.

## `BuildSemanticFindingAction`

- **Input:** assigned identity, validated proposal, exact
  `SemanticReviewOwner`/request/model-operation/slot metadata, citation bindings, confidence
  policy, and configured disposition
- **Output:** canonical `SemanticFinding`
- **Responsibility:** Label the finding `model_assisted`, retain the typed semantic-review
  owner, and copy provenance without promoting it to validator evidence.

## `ValidateSemanticFindingAction`

- **Input:** canonical finding, semantic-review request, parent content-unit owner, and current
  workflow-operation/unit/authority/policy registries
- **Output:** semantic-finding evidence
- **Responsibility:** Reprove identity/request/result/schema/citations/confidence/disposition
  and require `finding.immutableUnitOwnerId.parentUnitOwnerId` to equal the reviewed
  content-unit owner.

## `ProjectSemanticFindingDiagnosticAction`

- **Input:** validated semantic finding and exact unit pointer
- **Output:** model-assisted diagnostic
- **Responsibility:** Embed the complete finding as the diagnostic's evidence class; never
  attach a mechanical rule claim.

## `ValidateContextRequestSchemaAction`

- **Input:** one context request and compiled workflow model-operation declaration
- **Output:** schema evidence
- **Responsibility:** Apply the one context-request schema explicitly selected by the workflow
  operation.

## `ValidateContextRequestScopeAction`

- **Input:** schema-valid context request and current unit allowlists
- **Output:** context-scope evidence
- **Responsibility:** Validate one requested ID/query against local scope.

## `ResolveContextRequestAction`

- **Input:** scope-valid request and immutable fact/content registries
- **Output:** bounded context result
- **Responsibility:** Resolve one authorized context request only.

## `OrderRepairDiagnosticsAction`

- **Input:** repairable diagnostics
- **Output:** ordered diagnostic IDs
- **Responsibility:** Sort repair diagnostics deterministically.

## `SelectNextRepairDiagnosticAction`

- **Input:** ordered diagnostics and attempt state
- **Output:** selected diagnostic
- **Responsibility:** Select one next diagnostic only.

## `ClassifyRepairAuthorizationPurposeAction`

- **Input:** selected diagnostic, optional validated embedded semantic finding, exact
  content-unit owner, operation-result kind, and closed purpose table
- **Output:** ordinary atomic or no-invention-replacement purpose
- **Responsibility:** Select the dedicated no-invention branch only for `unsupported_behavior`
  and exact semantic-review-parent/content-owner equality against a content-kind operation
  result; otherwise select the ordinary builder or reject nonrepairable evidence.

## `CreateRepairAuthorizationAction`

- **Input:** selected diagnostic, candidate handle/revision, repair-unit descriptor, schema
  registry, exact compiled-engine-policy identity, and complete cited rule bindings
- **Output:** repair authorization
- **Responsibility:** Bind one closed operation, current values, preconditions, and
  self-contained versioned rules used by the diagnostic.

## `CreateNoInventionClarificationReplacementAuthorizationAction`

- **Input:** one validated unsupported-content semantic finding, content-kind operation result,
  exact parent content `ImmutableUnitOwnerId`, exact candidate revision, clarification-result
  schema, and runner repair accounting
- **Output:** one-shot no-invention replacement authorization
- **Responsibility:** Require the finding's `SemanticReviewOwner.parentUnitOwnerId` to equal the
  authorization/accounting owner; authorize only whole-result replacement from `content` to
  schema-valid `clarification_needed` and reject a consumed unit one-shot.

## `BuildAtomicRepairGuidanceAction`

- **Input:** immutable repair authorization, matching diagnostic, and authorization-bound
  semantic guidance/finding
- **Output:** repair guidance
- **Responsibility:** Explain exactly the authorized change from bound rule values and reproduce
  every bound principle raw span/citation as context; never use semantic guidance as mechanical
  authority or perform ambient lookup.

## `ValidateRepairEnvelopeAction`

- **Input:** decoded repair candidate, bound repair authorization and current candidate
- **Output:** authorization-valid repair payload
- **Responsibility:** Check the retained authorization, diagnostic and current revision; do not
  require model echoes or repeat generic call-association checks.

## `ValidateRepairScopeAction`

- **Input:** repair payload, authorization, source semantic finding, and runner repair
  accounting
- **Output:** scope-valid repair operation plus next accounting
- **Responsibility:** Prove only authorized pointers/keys are present; for no-invention
  replacement reprove semantic-review parent = authorization content owner = one-shot accounting
  owner, require exactly `kind=clarification_needed`, consume that owner's flag, and do not
  increment the ordinary counter.

## `MergeAtomicRepairAction`

- **Input:** candidate, repair authorization, scope-valid operation
- **Output:** repaired in-memory candidate
- **Responsibility:** Compare-and-swap one authorized operation.
