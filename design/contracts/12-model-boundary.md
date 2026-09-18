# 12. LLM interaction boundary

Part of the [proposed design](../design.md#12-llm-interaction-boundary). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 12.1 Discrete LLM components

LLM interaction is deliberately split across actions:

1. `SelectContextAction` chooses relevant typed facts and bounded source excerpts.
2. `BuildInitialGuidanceAction` converts compiled policy into a concise instruction packet.
3. `BuildModelRequestAction` constructs the internally identified provider-neutral request and compact result schema; it does not serialize engine-only identities into model content.
4. `InvokeModelAction` performs exactly one provider call and returns raw provider output plus usage metadata.
5. `ValidateProviderInvocationObservationAction` proves the exact runner-bound call association and complete-candidate eligibility before decoding.
6. `DecodeModelEnvelopeAction` parses the compact JSON result, retaining the trusted association; `ValidateModelPayloadSchemaAction` checks the bound closed result schema.
7. Stage-specific validation actions validate the candidate.
8. `BuildAtomicRepairGuidanceAction` builds a single-diagnostic repair request when required.
9. `MergeAtomicRepairAction` merges only the authorized replacement into the in-memory candidate.

No one action both invokes and interprets the model. No model action reads or writes the workspace directly.

- Optional `CountModelInputTokensAction` is implemented and fake-provider tested.
- It forwards the exact request, binding, invoked count operation and single-use lease through
  the existing provider port once, preserving counts, failures and cancellation.
- The port owns call checks and cleanup; the action adds no capacity gate, inference
  prerequisite, retry, token charge or lifecycle transition.
- `ValidateModelTokenCountObservationAction` separately validates the current invoked count
  operation and reuses `ExactInputTokenCountEvidence.fromObservation` for request/binding/input
  checks.
- It preserves failures, while cancellation remains outside observations.
- The allocation-free result borrows the original identity owners; validation neither consumes a
  lease nor changes accounting/lifecycle.
- Both actions have parameter-free YAML bindings, `count-model-input-tokens` and
  `validate-model-token-count-observation`.
- Their typed results retain the original request/binding owners.
- `complete-count-operation` reuses the existing lifecycle action/runner to terminalize only the
  exact validated count, failure or cancellation.
- `complete-count-request` closes the logical request only for count failure/cancellation after
  all its operations are terminal.
- Count success cannot accept a request.
- Missing, foreign, stale or duplicate completion evidence rejects; lease cleanup and explicit
  YAML retries use the existing owners.
- Fake-provider YAML tests cover these paths without an inference prerequisite or token charge.

- Native YAML `validate-provider-invocation-observation` implements step 5 through the existing
  validator.
- Its parameter-free binding retains the exact request and response owners and publishes sealed
  evidence or typed rejection/cancellation.
- Only complete evidence exposes decoder input.
- It performs no provider call, token accounting, decoding or lifecycle transition; YAML selects
  those steps.

- Native `decode-model-envelope` separately parses only complete validated content, retaining
  its evidence with the owned tree.
- Malformed JSON returns `invalid`, including through the inference profile's permitted
  `end.invalid`; non-complete observations keep their failure/cancellation outcome without
  parsing.
- This proves syntax only and performs no provider call, accounting or payload-schema check.

Native `validate-model-payload-schema` checks only decoded candidates against
their retained compiled schema and retains the original tree/evidence owner.
Its parameter-free result separates schema rejection from unchanged protocol,
provider and cancellation outcomes. No parsing, accounting or semantic/commit
authority is implicit.

`admit-model-response` is the pure consolidated alternative: reuse both owners
and publish the existing envelope and payload results in one runner-validated
delta. It accepts only the decoder's existing inputs, preserves syntax/schema
diagnostics and non-complete outcomes, and retains the exact observation/tree
association. Detailed operations remain available. This grants no semantic,
provider, retry, lifecycle or accounting authority (ADR 0012).

### 12.2 Initial guidance packet

- Every model request includes the short engine-owned JSON framing instruction defined by [ADR
  0014](../decisions/0014-universal-response-format-guidance.md), once per serialized call.
- It applies to all workflows, response modes and retries.
- Task guidance and the exact result schema remain workflow-selected; the schema alone defines
  the permitted response fields and values.

Each generation request contains only what the current unit needs:

[View the Initial guidance packet sample](../code.md#initial-guidance-packet).

- Raw preset YAML is not sent.
- The engine sends the compiled subset relevant to the requested unit.
- Normal path-intent guidance contains the complete bounded allowed `pathIntentOptionId` and
  `nameSourceId` choices for that unit.
- Normal candidate-selection guidance contains only the complete bounded candidate-ID set,
  engine-rendered display labels, and capability summary; if exactly one candidate exists, an
  action selects it without a model call.
- These packets do not repeat the underlying path-rule language or repository collision
  inventory.

- For every explicitly permitted model-visible raw fallback filename field, the packet instead
  contains a closed `PathGuidance` variant with the declared intent/capabilities,
  naming-enforcement mode, complete applicable root/include/exclude/basename/extension/placement
  rules, full-match glob/RE2 semantics, configured-target plus active-host filename constraints,
  inaccessible/generated-root classes, applicable content rules, and every mechanical rule ID.
- Rules are never truncated or rejected by a local model-call size gate; API size failures
  follow the workflow's explicit outcome transitions.
- Repository collision paths are not bulk-sent; a collision repair identifies only the exact
  conflicting engine record allowed for that unit.
- `applicableRuleIds` is checked against the validator dependency set before the call, and
  atomic repair cites one of those same rule IDs and the exact field pointer, so first-pass
  guidance and repair cannot drift.

- For display prose, the packet also carries `PassiveLiteralGuidance` selected from the exact
  registry and current unit evidence.
- It says explicitly that passive IDs may be selected only at the listed presentation field
  pointers and authorize no read, write, copy, command, import, context request, or URI fetch.
- Operational references use only locally allowed file/source IDs.
- The path-token grammar still scans ordinary literal segments, so a nano model cannot bypass
  the distinction by copying the display bytes inline.

- A dependency-capable plan unit receives `DependencyGuidance` from the exact
  `DependencyPolicyRegistry`: allowed target project/manifest IDs, ecosystems, registry-source
  IDs, scopes, and version/package grammar plus deny-rule IDs.
- It receives no install command and cannot introduce a registry endpoint.
- The same authority and typed rules are used by proposal validation and atomic repair.

Raw whole-repository listings, principle categories not selected by the configured stage/file-kind mapping, and earlier model prose are not sent. Stable identifiers replace repeated text wherever possible.

### 12.3 Provider-neutral response envelope

- [ADR 0006](../decisions/0006-minimal-model-response.md) is the normative `model-envelope/v1`
  standard.
- The model returns the closed workflow result object directly, without execution metadata or a
  universal result/payload wrapper.
- A single-shape result needs no kind tag; multiple allowed variants use one root `kind` plus
  their own fields.
- The runner retains the exact version, request/attempt/operation, unit, input, binding and
  schema association.
- Workflow result-schema resources compile under ADR 0006's closed `model-result-schema/v1`
  profile.
- Its opaque typed authority replaces the raw schema-only compiled resource; the registry
  retains the exact capture and owns the schema through execution.
- Unsupported or unbounded schemas reject before provider preparation.
- Request construction and candidate validation reuse that same compiled contract.

- Native structured output uses a registered structural projection of that same compiled schema
  (ADR 0006's 2026-09-12 amendment).
- The complete schema remains model guidance and the sole acceptance contract;
  provider-unsupported bounds are still enforced by the engine.
- Provider projections retain closed fields, types and disjoint alternatives and cannot be
  supplied by workflows or models.
- The engine validates trusted call association separately from model-data decoding and
  validation.
- Native schema compliance, an echoed ID or a model claim never proves correctness or authority.

- Allowed variants come from the workflow-declared result schema and selected generic operation.
- A generation operation cannot return a patch; a repair operation cannot return a whole
  document; an implementation operation cannot return task status.
- Required citations, selected IDs and keyed multi-target results remain explicit candidate
  data.
- See the [compact response example](../code.md#model-response-envelope).

### 12.4 Context requests

If the current unit cannot be completed with supplied facts, a workflow model operation may declare one typed context request:

[View the Model context request sample](../code.md#model-context-request).

- The model does not provide a raw path.
- The context request must reference an already validated ID or a strictly typed query.
- The orchestrator permits at most the `context-round-limit` declared explicitly for that YAML
  operation instance and validated against its registered contract.
- Unsupported requests become a diagnostic, not an agentic tool call.

- A context request asks only for already-held evidence.
- It cannot stand in for absent business authority.
- When a workflow model operation generates specification content, if the supplied
  reference/clarification authorities do not support a required business fact, the only valid
  semantic alternative is `clarification_needed`; inventing a default, silently omitting the
  affected behavior, or repeatedly asking the model to guess is invalid.

### 12.5 Low-capability model operating rules

- one reference chunk, artifact section, requirement cluster, task cluster, or file operation per call;
- strict JSON schema with enums and `additionalProperties: false`;
- low temperature or provider equivalent, without relying on it for correctness;
- stable IDs for sources, requirements, tokens, projects, files, tasks, commands, and diagnostics;
- complete response-shape guidance from the bound compiled schema, including
  nested alternatives and constraints, without synthetic candidate examples;
- no request to reproduce engine-known filenames, IDs, headings, checkboxes, or status;
- no open-ended “inspect the repo” instruction;
- no unrestricted tool use;
- no invention of an absent business fact; return the workflow operation's typed clarification variant when available;
- no full-document retry for a local validation failure;
- one complete schema-valid result and explicit operation-local retry limits;
- an optional YAML-declared fallback operation only after deterministic retry exhaustion, never as hidden behavior.

### 12.6 Semantic review

- Some current gates—testability, ambiguity, minimality, unsupported behavior, and conflict
  detection—are semantic.
- If desired, a workflow explicitly calls a registered generic model operation over one typed
  unit and declares its semantic-review resources and transitions in YAML.
- Its findings are labeled `model_assisted`, retain source citations, and never masquerade as
  deterministic evidence.

### 12.7 Workflow-defined model operations

- The engine ships no model-route registry.
- The originating model-request step calls a registered generic operation and declares its model
  slot, prompt/guidance resources, result schema, supported controls, allowed context behavior,
  and outcome transitions in the workflow definition.
- Large resources are declared once and referenced by concise local IDs.
- The compiler captures and validates every declared resource before execution; there is no
  packaged route descriptor, prompt, schema, slot assignment, or fallback.
- Under ADR 0012, later YAML operations consume the same immutable request through their typed
  data dependencies.
- Preparation may use detailed operations or the pure `prepare-model-request`
  operation. Both reuse the same identity, binding and construction owners; the
  consolidated form publishes their typed values together through runner validation.
- They retain its slot, resources, controls and identity; they do not declare replacement
  selections for their own step.
- The internal `model-request/v1` content contract is not a YAML resource; the workflow supplies
  prompt content and its closed result-schema resource.

- The workflow-selected slot must resolve through `.sddtoolkit.json` `models.slots`,
  `ValidatedRepositoryModelAllowlist`, the validated `.sddproviders.json` catalogue entry, and
  one compiled provider/model contract.
- The workflow cannot name a provider or model directly, and a catalogue entry not selected by a
  repository slot remains unauthorized.
- Missing operations, resources, slots, outcome mappings, or unsupported controls fail
  compilation or run preparation before provider I/O.
- Provider APIs own request, response and context-size limits under ADR 0011.
- The engine, operation, slot and model contract add no byte/token ceilings, capacity
  intersections or size-fit gates.

- Model-operation identity is the compiled `(workflowId, workflowVersion,
  originatingWorkflowStepId)` tuple retained across consumer steps.
- Request identity, logging and evaluation use that identity; no independent route ID or
  route-registry version exists.
- A resource or model-operation declaration change changes the compiled workflow authority.
- ADR 0005 governs the concise YAML representation and prohibits any hidden workflow-specific
  behavior.

- Inference requires no size estimate, token count or static-capacity preflight; the provider
  reports its own size errors or stops.
- The runner accounts API-reported input plus output usage against the execution's total token
  budget.
- Optional count operations provide observations only and never authorize inference or replace
  actual-usage accounting.

- Native `advance-model-attempt-accounting` consumes the retained prepared request through an
  explicit YAML step and requires `retry-limit` (`0` means initial execution only).
- Its accounting permission is compiled from the registered contract, never authored in YAML.
- The runner binds the attempt and provider-operation ledgers to the request's fresh execution
  identity, applies the proposed accounting transition, and publishes sealed
  `accounted_model_attempt` evidence from that canonical record together with the envelope
  delta.
- Rejection publishes neither.
- Later visits use the accounting step's compiled authority and runner-owned counts.
  Atomic repairs and their required dependent requests use the native defect key
  under [§22.7](22-repair.md#227-repair-retry-limit-and-escalation); other requests
  retain operation counts. Request ordinals never reset either.
- A consumer must invalidate used attempt evidence before retry; foreign/stale evidence and
  another initial attempt cannot reset accounting.
- This operation prepares no lease, advances no provider operation, performs no provider call
  and charges no tokens.
- All its owners are destroyed with execution.

- Native `assign-provider-operation` consumes that prepared request and applied attempt with one
  explicit `kind` (`inference` or `input-token-count`).
- The existing provider-operation lifecycle action proposes assignment; the runner validates its
  exact request/attempt/binding/input association and current revisions, then publishes the
  immutable ledger successor and sealed `assigned_provider_operation` view together.
- Consuming evidence cannot erase an unfinished operation or permit a retry.
- This step neither invokes a provider nor prepares authorization, counts tokens or persists
  records.
- Those operations remain explicit separate YAML work.

- Native `prepare-provider-operation-authorization` now consumes that same request, attempt and
  assignment through a separate YAML step with required positive `timeout-ms`.
- The runner derives one absolute monotonic deadline, allocates the existing private lease slot
  and validates exact result correlation before publication.
- The action holds only the policy-permitted preloaded `provider-authorization` port: no I/O,
  refresh or provider call is allowed.
- Its sealed result contains a lease reference or closed failure/cancellation facts, never a
  backing capability.
- Rejected/expired preparation and execution cleanup release unused leases.
- Invocation and observed completion are separately selected YAML operations; no token charge or
  persistent record is added here.

- Native `advance-model-request-lifecycle` with `transition: invoked` now exposes the existing
  logical-request `assigned -> invoked` action.
- The runner requires the exact prepared authorization and validates one direct immutable
  successor before replacing the request ledger.
- It retains that published snapshot and rejects stale, foreign, duplicate, skipped or
  assignment-disguised updates.
- Authorization is rechecked before publication; rejection preserves the prior ledger.
- The prepared request, attempt and lease are unchanged and the provider operation remains
  assigned.
- This step performs no API call or token accounting; actual API calls and request closure use
  separate YAML operations.

- Native `advance-provider-operation-lifecycle` with `transition: invoked` advances the assigned
  operation under that invoked request.
- The runner binds the existing prepared lease's original deadline and validates the lifecycle
  proposal before publishing canonical invoked-operation evidence and invalidating assignment
  evidence together.
- Stale/foreign/duplicate evidence, altered deadlines, cancellation and rejected deltas cannot
  publish a successor.
- The lease remains unconsumed; no API call, token charge, new timeout or persistence occurs.

- Observed inference completion is exposed by `complete-provider-operation`.
- It consumes the validated observation and exact invoked-operation association; the existing
  lifecycle action and runner publish a sealed terminal-record view while removing invocation
  evidence.
- Provider facts, response ownership and actual-token usage stay unchanged.
- Stops/failures and cancellation retain their outcomes; a completed provider response proves no
  payload or workflow success.
- There are no parameters, API calls, renewed deadlines or hidden completion steps on
  abandonment.

- Pre-call `terminate-provider-operation` consumes the exact assigned operation and retained
  authorization result.
- The same lifecycle action and runner terminal publication path apply `assigned -> terminal`,
  publishing terminal evidence and removing assignment evidence together.
- Authorization failure becomes `preparation_failed`; cancellation becomes
  `cancelled(not_sent)`, preserving `failed`/`cancelled` outcomes.
- Prepared, missing, foreign, stale or duplicate evidence cannot authorize termination.
- Authorization-result consumers require exactly one current assigned/invoked/terminal
  association; non-prepared facts need no clock, while prepared leases retain their deadline
  checks.
- Existing lease cleanup remains the sole backing owner.
- No provider call, token charge, retry, persistence or logical-request transition is added by
  this operation.
- Runtime abandonment never inserts this YAML step.

- Pre-call logical-request closure is the explicit parameter-free `terminate-model-request`
  step.
- It consumes the current request ledger, prepared request, applied attempt, terminal operation
  and retained authorization result.
- The shared authorization validator requires exactly matching identity and terminal
  failure/cancellation facts.
- Authorization failure closes an assigned request as `not_invoked_authorization_failure` or an
  invoked request as `failed`; cancellation closes either as `cancelled`.
- Outcomes remain `failed`/`cancelled`.
- The existing request lifecycle action and runner replacement validator require every
  associated operation to be terminal and publish one direct ledger successor.
- Prepared, missing, foreign, stale, duplicate, inconsistent or forged evidence rejects.
- Original evidence ownership, lease cleanup and token usage remain unchanged; no
  response-validation evidence, live lease, clock, provider call, retry, persistence or hidden
  closure is introduced.

- Logical-request closure is an explicit parameter-free `complete-model-request` step using the
  same lifecycle action and request ledger.
- It requires the retained payload-validation result, exact current attempt and terminal
  provider-operation evidence; every operation associated with the request must be terminal.
- Schema-valid candidate evidence permits request `accepted`/`ok` only, granting no semantic,
  approval, commit or workflow-success authority.
- Protocol/schema rejection closes as request `failed` while retaining the `invalid` outcome;
  provider stops/failures remain `failed` and cancellation remains `cancelled`.
- No retry exhaustion or user approval is inferred.
- The runner validates the evidence-derived reason/outcome and one direct ledger successor
  before publication; missing, foreign, stale, duplicate or unfinished operation evidence
  rejects.
- Response ownership and token usage are unchanged; no call, renewed lease, deadline,
  persistence or hidden completion is added.

- Each workflow-declared result schema defines the entire compact response; there is no generic
  open payload or repeated engine metadata.
- Repair operations do not recursively repair semantic failures: malformed responses may receive
  only the YAML-declared bounded protocol-retry transition, while a schema-valid but invalid
  repair consumes the existing authorization attempt.

- In particular, `result.reference-claims/v1` contains a bounded ordered collection of
  `ReferenceClaimProposal` values, exactly one `PreservedTokenClassificationProposal` for every
  engine-supplied structured-token candidate, and a closed claims/positive-`no_feature_claim`
  outcome.
- A preserve classification deterministically creates a canonical token and preserved-token
  claim, so `no_feature_claim` is valid only when no model or preserved-token claim remains.
- Each model claim contains typed content plus one or more `SourceCitationProposal` values;
  neither proposal admits reference-state, chunk, citation, claim, token, obligation,
  reconciliation-disposition, or related-claim IDs.
- The request envelope binds the exact state/chunk and allowed sources/candidates.
- Completeness validators reject omitted/duplicate token classifications; then distinct
  validation/ID/build actions create canonical citations, tokens, and identified claims.

- The reference-reconciliation result schema selected by the workflow is discriminated.
- A bounded lower-level partition returns a `ReferenceReconciliationSummaryProposal`.
  The engine derives its enclosing member IDs from the supplied partition; model-authored
  statements select supporting claims, and validators require complete partition coverage.
- The final global partition returns one `ReferenceReconciliationProposal`: total
  claim-disposition proposals plus bounded signal and conflict proposals over the complete
  represented claim set.
- Neither variant can redefine claim/token content or mint canonical
  summary/statement/signal/conflict/decision IDs.
- Dedicated coverage, join, ID, and build operations materialize summaries, the final claim
  ledger, `ReferenceSignal` records, and `SourceConflict` records.

- The feature-brief result schema selected by the workflow yields a `FeatureBriefProposal`
  grounded only in the completed reference claim/citation registries, or a typed specification
  clarification need.
- The model supplies a business title, description, and primary goal plus existing
  claim/citation or resolved clarification-response IDs; it cannot supply the `featureId`, any
  workflow or project path, or a reference selector.
- Before the call, the engine binds `featureId` to the validated supplied directory's lossless
  `paths.specs`-relative key under [ADR 0010](../decisions/0010-explicit-feature-directory.md).
  The independent reference selector and model output cannot name or rename the feature.
- An unsupported fact takes the YAML-declared clarification branch; a path-shaped or
  structurally invalid value follows the normal passive-literal/atomic protocol.

- Specification-section, plan-unit, and task-cluster workflows declare discriminated result
  schemas that return either stage content or one `ClarificationNeedProposal`.
- A clarification carries a bounded user-answer schema and engine-known subject authorities
  explaining the gap.
- It is a successful semantic pause, consumes no operation-local retry, and is never sent
  through repair to manufacture content.
- A malformed need is an ordinary invalid model candidate; content that asserts an unsupported
  fact is a semantic no-invention finding and must be replaced by the clarification variant
  under one atomic authorization.
- The engine validates/deduplicates the need, assigns an `SNN`, `PNN`, or `TNN` ID when
  necessary, persists its form under `clarify/`, and enters the matching clarification-pending
  state.

**Shared clarification preparation:** the existing need builders prepare a concise
question and reason naming the affected structural requirement, established facts
and current evidence, exact unresolved decision and permitted answer. Reuse the
registered requirement descriptors and existing `question`/`why_required` fields.
Admitted model explanations remain attributed evidence; diagnostic prose is not
automatically a question. Both generation needs and authority-gap needs follow this
contract. Preparation performs no semantic reassessment, model call, publication or
state transition; rendering formats its result through the existing controlled form.

Consolidate only the same engine-built subject under existing identity rules.
Equal wording or shared citations across subjects do not establish equivalent
decisions or let one answer resolve multiple requirements. A related-needs display
is a projection only. Broader answer sharing requires an explicitly approved
membership/applicability contract. Preserve current bindings, earliest ownership,
authenticated answer acceptance and protected history (§23.2).

- The workflow-declared clarification-resolution result schema may only select one existing open
  clarification and existing current-authority IDs.
- It is used on a subsequent stage run when exact deterministic lookup cannot decide semantic
  sufficiency.
- The engine—not the model—checks the subject key, authority provenance, non-conflict, current
  revisions, and required-field coverage before closing the record.
- Failure to establish support leaves the same record open; it never creates an answer.

- A reference-extraction workflow step additionally declares its partition-contract resource.
- `ReferenceSnapshot.extractionContract` stores the exact compiled workflow ID/version/node
  identity, internal request-contract identity, selected result-schema resource identity, and
  partition contract.
- Revalidation of a persisted snapshot must resolve that closed compiled authority and blocks with
  `REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE` rather than silently using a newer schema,
  resource, or chunk boundary contract.
- A fresh extraction starts at the selected workflow's `start`; it never resumes a saved request
  or candidate from that snapshot.

### 12.8 Closed authority-reconciliation boundary

[View the authority-reconciliation contract sample](../code.md#authority-reconciliation-contract).

- Authority completeness is a shared engine contract, not behavior duplicated in prompts or
  implemented separately for particular domains.
- Before generation and again before stage commit, the engine deterministically builds an
  `AuthorityRequirementLedger` from every required field, decision slot, obligation, policy
  predicate, and accepted upstream authority applicable to that stage.
- Requiredness is closed: it comes only from a versioned schema, compiler-locked
  ownership/reconciliation policy, accepted canonical record, or explicit obligation.
- The engine does not ask about every fact that could exist, and the model cannot remove a
  required entry or create a new requiredness rule.

- Each ledger entry has a structural `AuthorityRequirementId`, earliest owning stage, required
  slot, exact input-authority set, reconciliation-policy ID, and downstream obligation IDs.
- Domain-specific extractors or resolvers may contribute candidate authorities and typed
  evidence, but they cannot choose a terminal outcome.
- The common reconciliation actions produce exactly one closed result:

- `resolved_exactly_one`, naming either one current existing authority or one candidate resolution supported by current authority, together with its evidence IDs;
- `resolved_explicit_not_applicable`, naming either the deterministic rule or one authority-supported candidate disposition that proves why the required slot does not apply;
- `resolved_explicit_exception`, naming a current authenticated exception whose scope exactly covers the requirement;
- `clarification_required`, with a closed reason and the earliest owning `spec | plan | tasks` stage;
- `upstream_rework_required`, when a downstream stage encounters a gap owned by an earlier stage; or
- `administrative_block`, when the kind/slot has no registered ownership/reconciliation policy or requires authority that the workflow is not authorized to create.

- There is no unresolved-success, warning-only, inferred-default, closest-match,
  conventional-choice, model-memory, or current-stage-fallback variant.
- Exact equality and equivalence use the registered policy for that requirement kind.
- If deterministic comparison cannot prove equivalence, a bounded YAML-declared semantic
  operation may classify only the supplied candidates with citations; uncertainty remains a
  clarification and is never promoted to proof.
- Multiple directly equivalent candidates may collapse only when the policy defines canonical
  equivalence and records total member evidence; multiple non-equivalent candidates require
  clarification.

- `ClarificationOwnershipRegistry` maps every registered `(requirementKind, requiredSlotId)` to
  its earliest owner and allowed resolution policies.
- It is compiler-locked and exhaustive.
- Specification ownership covers feature intent and reference meaning; planning ownership covers
  design, architecture, project policy, repository/capability, and verification-strategy
  decisions; task ownership covers executable decomposition, dependency, authorized work, and
  evidence binding.
- Unknown ownership blocks administratively rather than falling back to the stage that noticed
  it.

- Detection time does not change resolution ownership. Spec's early principle
  assessment (§17.3.1) must completely account for its assigned evidence and findings;
  project-policy findings enter the existing mandatory Plan-obligation projection.
  They are not inserted as policy-resolution requirements into the Spec ledger or
  relabelled resolved. Plan's ledger consumes and resolves them under current authority.
  Genuine business-intent gaps remain Spec-owned; missing/invalid assessment evidence
  follows the ordinary rejection path and cannot be deferred as a policy obligation.

- The ledger is a deterministic projection over current canonical authorities, not a competing
  persisted truth or fingerprint.
- It is rebuilt after authority refresh, clarification resolution, repair, and immediately
  before commit.
- Accepted canonical IR retains the authority, provenance, decision, obligation, and exception
  IDs needed to reproduce every successful entry.
- An open clarification retains its structural requirement/subject identity.
- Successful workflow publication is invalid unless the projection is exhaustive and every
  required entry is successfully resolved; any clarification/rework/block result instead follows
  its typed lifecycle with no partial stage IR.

This contract is deliberately domain-neutral. Adding a new requirement kind requires its schema, ownership entry, reconciliation policy, accepted and rejected fixtures, and stage-gate tests. It never authorizes a caller-specific workaround or a special continuation for one example.

- The native H-008 implementation is `src/domain/required_authority.zig`, with Specify's
  schema/reference projection in `specification_authority.zig` and five generic YAML bindings
  documented in [F0100
  §3.10](../features/F0100-SpecWorkflow.md#310-shared-required-authority-boundary).
- The runner checks both direct authority generations and their source lineage; replacing a
  source requires rebuilding its affected projection and gate.
- Native data schemas distinguish current authorities from captured immutable evidence.
- A captured value carries its complete current-authority frontier into every successor;
  retiring or replacing its transport slot does not invalidate that evidence.
- Conflicting source generations remain stale.
- Gate authorities must use current schemas.
- YAML and model output cannot change this classification.
- Runner-validated execution-control records (such as the request identity ledger) are not
  domain authorities and cannot be gate authorities.
- They retain their canonical lifecycle/accounting checks rather than making every later request
  depend on the business inputs of every historical request.
- Request/result validators still prove the exact current association before capture, and
  successors own their data; capture never grants semantic support.
- This handoff is in memory only, with no snapshot files or recovery subsystem.
- Production generation, support review and registered publication use this boundary.
  [F0100](../features/F0100-SpecWorkflow.md#implementation-status) tracks remaining
  clarification and workflow acceptance work; the shared gate alone does not establish it.
