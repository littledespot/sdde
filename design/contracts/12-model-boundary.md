# 12. LLM interaction boundary

Part of the [proposed design](../design.md#12-llm-interaction-boundary), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

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

Under [ADR 0030](../decisions/0030-engine-owned-model-request.md) (not yet implemented), the
request-lifecycle actions run as fixed stages of one `request-model` step. A capability-free
kernel orchestrator coordinates them through runner-owned child bindings. The split above is
unchanged: each stage is still a separate action with its own narrow ports.

Independently valid usage survives invalid answer content through the shared
provider observation contract, including missing final text. Only complete content
reaches decoding. The envelope retains declared observation history for reporting;
storage does not change retry eligibility or the execution-wide token ledger.

Under [ADR 0030](../decisions/0030-engine-owned-model-request.md) as amended on
23 October 2026 (not yet implemented), provider token counting is removed; the count
actions and bindings below go with it.

- Optional `CountModelInputTokensAction` forwards the exact request, binding, invoked count operation and single-use lease through
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
  its evidence with the owned tree. The sole approved prefix-normalization exception
  and its logging are defined in [§22.6](22-repair.md#226-unparseable-output).
- JSON still malformed after that exception returns `invalid`, including through the inference profile's permitted
  `end.invalid`; non-complete observations keep their failure/cancellation outcome without
  parsing.
- The [composition contract](text-field-composition.md#composition-defects-are-corrected-as-a-unit)
  also checks each native-bound text field at this shared admission boundary.
  A rejection retains every violating field's concrete pointer and typed reason
  for the existing bounded protocol correction. Pure syntax parsing stays separate
  for diagnostic inspection. These checks prove syntax and mechanical field
  composition; they perform no semantic assessment, provider call, accounting or
  payload-schema check.

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
- Source-document names remain citation metadata. Only captured source-body occurrences
  make filenames available as passive content choices; semantic relevance still requires review.
- Native availability facts may exclude unavailable tagged alternatives from the selected
  compiled schema. The existing schema owner derives a narrower
  view; it never adds fields, values or semantic decisions. A source-review
  assignment excludes each positive verdict to which no claim set can be bound for
  its subjects ([ADR 0023](../decisions/0023-advisory-post-generation-review.md#unresolvable-positive-verdicts-at-response-admission-20-october-2026)). Initial reference/specification
  requests and their repairs omit `passive` when their evidence permits no passive references.
  Under [ADR 0020](../decisions/0020-derived-exact-reference-lineage.md#native-exact-value-recognition),
  all model-response wire contracts and schemas omit `exact_copy`. The model types required
  values verbatim; the native packet retains current snapshot-bound eligible
  occurrences and exact bytes separately from model-visible guidance. Fixed repair
  scopes cannot borrow eligibility outside their fixed owning-unit `S+E` bound. That scope and the
  native field-role metadata govern raw-byte recognition before normalization;
  matching text or a projected catalogue cannot create the scope.
- Integer-choice restriction narrows scalar and collection ID selectors to their native owner's eligible set. Typed atoms use their declared
  tag/field; other selectors use an exact property/items path bound to a compiled
  response definition. Request preparation validates locations, definition/part
  association and canonical integer bounds, then derives one schema for provider
  and local validation. The one exception is `exact_members` uniqueness (below):
  provider schema syntax cannot express it, so local admission, request
  descriptions and replay apply it natively from the same restriction. Unknown locations or definitions reject; a carried sibling
  restriction may be unused only after validation against its compiled definition
  or the composition part's complete parent. Unused typed text atoms retain their
  existing behavior. No field-name search crosses unrelated ID namespaces.
- Empty eligible sets admit only an empty collection where the canonical shape
  permits it (including an optional enclosing record collection). Scalar or
  required collection choices reject. Nonempty restrictions preserve canonical
  cardinality unless the native owner declares a unique-subset selector: its maximum
  is the smaller of the canonical maximum and eligible-ID count. This fact applies
  only to integer collections, never scalar choices, and introduces no token limit.
  An `exact_members` selector instead names an integer property of array items:
  - the array must contain exactly one item for each allowed value;
  - its item count is fixed to the member count, which the guidance schema states
    (a provider structural projection may keep only its own array floor);
  - a repeated member rejects natively as `duplicate_member`;
  - it applies only to a path ending in array items and one property, with a
    nonempty member set that fits the canonical item bounds;
  - the key must be a required, non-nullable scalar integer in every item variant;
  - it must constrain the selected schema itself, through required properties, one
    array step and every alternative along its path, never through a projection
    parent or another definition;
  - after every choice applies, the key must still enumerate exactly the member
    set, so no later choice, path or tagged, may narrow it.
  Duplicate-target detection for every integer choice treats a choice naming the
  selected definition as the same target as one naming none.
  Sets above ADR 0006's 1,024-choice bound reject before invocation.
  Source review and its selection repairs use actual source IDs; reference
  authoring and repairs use their current native claim, signal or group scope.
  Visible display catalogues use the same scope. Refreshing text choices preserves
  other owners' restrictions. Membership enums do not prove correlation,
  provenance, uniqueness, source support or semantic correctness; native admission
  and canonical readback remain mandatory.
  The closed schema profile does not support `uniqueItems`; subset cardinality does
  not enforce uniqueness. The complete guidance and local schema retain the bound;
  provider structural projections retain their existing supported-keyword profile.
- Packet context/repair projections retain these facts out of band. Request preparation binds
  the derived schema once; provider serialization, payload validation and protocol corrections
  use that same view. Composition accepts only its exact part schema or a restriction derived
  from that schema, then validates the complete assembled candidate. No alternate schema
  configuration, retry owner or persisted policy is introduced.
- It says explicitly that passive IDs may be selected only at the listed presentation field
  pointers and authorize no read, write, copy, command, import, context request, or URI fetch.
- Operational references use only locally allowed file/source IDs.
- Prose and references follow the shared typed-content contract in §7.1. Literal
  punctuation does not select a resource or grant operational authority.

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
- ADR 0006's enum cardinality guard applies to both workflow resources and captured
  selected schemas through the shared compiler.
- Its opaque typed authority replaces the raw schema-only compiled resource; the registry
  retains the exact capture and owns the schema through execution.
- Unsupported or unbounded schemas reject before provider preparation.
- Request construction and candidate validation reuse that same compiled contract.

- Native structured output uses a registered structural projection of that same compiled schema
  (ADR 0006).
- The complete schema remains model guidance and the sole acceptance contract;
  provider-unsupported bounds are still enforced by the engine.
- Provider projections retain closed fields, types and disjoint alternatives and cannot be
  supplied by workflows or models.
- The engine validates trusted call association separately from model-data decoding and
  validation.
- Native schema compliance, an echoed ID or a model claim never proves correctness or authority.

- ADR 0006 permits nested alternatives proven disjoint by JSON type. Same-type object alternatives retain distinct `kind` tags;
  repeated primitive types and overlapping alternatives reject before invocation.
- The shared candidate codec maps declared ordinal wrappers to integers, ordinary
  prose to strings and explicit typed composition to closed `fragments` objects. Explicit
  passive/source references remain typed candidates. Exact-copy occurrences are
  derived natively under ADR 0020, never accepted as model-authored selections.
  A selected scalar/array repair stays inside a closed `value` object envelope.
  This lossless representation is shared by initial output, evidence and repairs;
  canonical segment storage remains separate from the model-facing codec.

- Allowed variants come from the workflow-declared result schema and selected generic operation.
- A generation operation cannot return a patch; a repair operation cannot return a whole
  document; an implementation operation cannot return task status.
- Required citations, selected IDs and keyed multi-target results remain explicit candidate
  data.
- See the [compact response example](../code.md#model-response-envelope).

#### 12.3.1 Bedrock Converse

All Bedrock consumers use one canonical
[Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html)
request/response codec, including production invocation, diagnostic replay and the
development harness. Common `system`, `messages`, `inferenceConfig` and
`outputConfig` fields replace provider-specific chat envelopes. Native structured
output projects the existing compiled schema into `outputConfig.textFormat`;
`structure.jsonSchema.schema` is a JSON string. Prompt-only models still receive
the exact closed schema as guidance and pass the same native candidate validators.

The compiled provider/model contract owns the typed additional-control policy:
no additional fields, GPT-OSS reasoning effort, or Luna strict native JSON. The external
catalogue can select a supported tuple but cannot supply a serializer or control
policy. Unknown models, regions, controls and unsupported schema modes reject at
the existing binding boundary. Model switching therefore requires a registered
contract and explicit configuration, rather than a model-name branch or fallback.

Only an `end_turn` response with valid assistant text is candidate-eligible. Join
text fragments in order without inserting characters. Provider-supplied reasoning
is retained as owned, ordered typed diagnostic data on complete, stopped and
rejected raw provider results, including optional signatures and opaque redacted
blocks, and is available in debugger extraction. The existing observation owner
controls its lifetime and cleanup independently of final answer content. It is excluded
from answer content and has no semantic-validation or workflow authority.
Absent reasoning stays absent; encrypted/redacted data is not invented as prose.
Stopped or missing-answer responses can expose supplied reasoning without
becoming candidates. Tool-use, truncation, filtering, guardrail and other
noncandidate stops preserve their typed outcomes and independently valid usage.
Normalize cached token usage under
[ADR 0011](../decisions/0011-provider-owned-request-limits.md#workflow-token-accounting).
Optional CountTokens uses its `input.converse` shape, without inference-only
configuration or an encoded legacy chat body. Models without registered count support do
not acquire it merely because the API exists.
[ADR 0030](../decisions/0030-engine-owned-model-request.md) (amended 23 October 2026,
not yet implemented) removes CountTokens and all provider token counting.

The user-selected small-model test binding is `openai.gpt-oss-20b-1:0` from
`ap-southeast-2`, using native JSON Schema, low reasoning for Spec generation,
repair and grading, registered temperature `0.1`, and its documented maximum of
16,384 output tokens sent on every inference request
([ADR 0011](../decisions/0011-provider-owned-request-limits.md#model-maximum-output)). The separately registered Luna profile retains its strict-output field, omitted
temperature/reasoning controls and unavailable CountTokens capability.
This is mechanical support, not a live compatibility or semantic-quality claim.
The test cost policy is development-only; it cannot change production authority.
Historical captures follow the immutable inspection/replay boundary in
[ADR 0019](../decisions/0019-single-request-debugger.md#replay).

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
- A required business fact genuinely absent from the supplied authorities may produce
  `clarification_needed` only under §12.8.1. Failure to interpret available evidence
  is a candidate/review failure. Neither route permits invented defaults, silent
  omission or repeated guessing.

### 12.5 Low-capability model operating rules

- one reference chunk, artifact section, requirement cluster, task cluster, or file operation per call;
- strict JSON schema with enums and `additionalProperties: false`;
- temperature `0.1` whenever the selected registered model supports temperature; omit
  the control only when unsupported, without relying on it for correctness (workflow
  definitions cannot select or override it; prepared requests, retries and provider
  authorization retain and validate it; Bedrock rubric evaluation uses the same policy,
  OpenAI evaluation does not);
- stable IDs for sources, requirements, tokens, projects, files, tasks, commands, and diagnostics;
- complete response-shape guidance from the bound compiled schema, including
  nested alternatives and constraints, without synthetic candidate examples;
- no request to reproduce engine-known filenames, IDs, headings, checkboxes, or status;
- no open-ended “inspect the repo” instruction;
- no unrestricted tool use;
- no invention of an absent business fact; admit a typed clarification only under §12.8.1;
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
- Under [ADR 0023](../decisions/0023-advisory-post-generation-review.md),
  every post-generation source/principle finding remains advice unless an
  independent owning deterministic validator establishes the corresponding
  defect. Complete current assessment is a native fact; semantic support is not.
  Whole-unit, record-family and collection assignments retain one finding per native member, with
  exact association, per-member origins and narrow correction. Pre-generation
  source-readiness/preservation policy remains separate and mandatory.

**Review retention:** an explicit pure native transition may re-admit an execution-local source-review assignment when its
complete assessment dependencies are unchanged. The original terminal accepted
request, epoch and actual inference origin remain the witness; reuse creates no
request, attempt, provider receipt or token charge. Compare the native unit and
purpose, full packet and restrictions, selected schema, compiled guidance/context
and provider/model/slot/settings. The pure admission step may have a different
workflow-step ID; workflow identity/version and the original producing request
association remain fixed. No other binding difference is equivalent by implication.
Current native subject, requiredness, applicability and evidence admission still
apply. Eligibility and conservative exclusions are defined once in
[§22.4](22-repair.md#224-repair-request-and-response); resource-only requests and
JSON-composition parts have no review-retention contract. This is assessment
reuse, not provider caching or deterministic semantic proof.

### 12.7 Workflow-defined model operations

> **ADR 0030 amendment (22 October 2026, amended 23 October 2026, not yet implemented).**
> One [`request-model`](../decisions/0030-engine-owned-model-request.md) step replaces the
> preparation step and every explicit lifecycle step below. A fixed kernel orchestrator runs
> them as the stages ADR 0030 lists, through runner-owned child bindings. Where a bullet below
> says a step is "explicit", "separate YAML work" or "YAML-selected", read it as that stage of
> the one step. Each stage's rules are otherwise unchanged. `retry-limit` moves to the
> `request-model` step. Retry counting keeps its scopes, with the compiled operation now
> being that step. ADR 0030's "What stays in YAML" list names the steps that remain.
> The 23 October amendment also:
> - removes provider token counting: read every count operation below as removed; actual
>   inference usage still feeds the one workflow token budget;
> - takes the provider-operation deadline from the bound catalogue entry's required
>   `requestTimeoutMs`, not a YAML `timeout-ms`;
> - lets only a step declared `role: advisory` map `more` and `blocked`.

- The engine ships no model-route registry.
- The originating model-request step calls a registered generic operation and declares its model
  slot, prompt/guidance resources, result schema, allowed context behavior,
  and outcome transitions in the workflow definition.
- Response mode comes only from the selected catalogue model’s required `json` boolean
  (§9; ADR 0012). Bindings derive it from their immutable catalogue entry rather than
  retaining another selector. Workflow response-mode overrides reject; schemas remain workflow-owned.
- Large resources are declared once and referenced by concise local IDs.
- Request preparation may select an optional `context` prompt resource, including
  JSON field guidance. It precedes task guidance in static developer content;
  current sources and repair evidence remain dynamic user content. Both initial
  preparation paths, protocol corrections and diagnostic source capture retain
  that exact selection. It adds no caching behavior or schema authority.
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

**Focused semantic reviews.** For a review whose required subjects are known
natively, the review owner selects one complete native assignment from its ordered
ledger (a whole unit, record family or collection, or one selected principle set;
ADR 0023) and
binds its ordered members, purpose, parent and current dependencies to the request.
The response returns exactly one finding per assigned member, keyed by its
assignment ordinal, under the selected canonical finding schema; it returns no
expected count or completion flag. Source-preservation, candidate-support and
principle reviews use this shared contract. The review packet owner derives a
bounded slot from the purpose prefix and SHA-256 of the existing canonical
typed-subject snapshot, and binds that same slot as unit owner and semantic-review
purpose. Request identity excludes attempt, mutable text and revision; the exact
dependency binding rejects stale responses. The runner retires each completed
request before another assignment is selected. Native review progress retains
admitted findings and their origins; pending assignments are work, not missing
findings. Only complete native collection validation permits authority advancement.

- The workflow-selected slot must resolve through `.sddtoolkit.json` `models.slots`,
  `ValidatedRepositoryModelAllowlist`, the validated `.sddproviders.json` catalogue entry, and
  one compiled provider/model contract.
- The workflow cannot name a provider or model directly, and a catalogue entry not selected by a
  repository slot remains unauthorized.
- Missing operations, resources, slots, outcome mappings, or unsupported controls fail
  compilation or run preparation before provider I/O.
- Provider APIs own request, response and context-size limits under ADR 0011.
- The engine, operation, slot and model contract add no engine-enforced byte/token
  capacity ceilings, intersections or size-fit gates, and no request carries an
  output allowance below the model's own maximum: Bedrock requests send the
  catalogue's documented maximum. A provider-applied stop is logged with its reason
  under [ADR 0011](../decisions/0011-provider-owned-request-limits.md#model-maximum-output).

- Model-operation identity is the compiled `(workflowId, workflowVersion,
  originatingWorkflowStepId)` tuple retained across consumer steps.
- Request identity, logging and evaluation use that identity; no independent route ID or
  route-registry version exists.
- A resource or model-operation declaration change changes the compiled workflow authority.
- ADR 0005 governs the concise YAML representation and prohibits any hidden workflow-specific
  behavior.

- Inference requires no size estimate, token count or static-capacity preflight; the provider
  reports its own size errors or stops.
- The runner accounts API-reported input plus output usage exactly once against
  the execution's single `totalModelTokenBudget`, currently 100,000 tokens, across
  all inference calls. Advice has no separate allowance or usage subtotal
  (ADR 0011). Global exhaustion, overshoot or unavailable usage prohibits later
  model calls. Native advisory classification controls eligible non-budget
  incomplete-failure semantics only, survives correction and cannot be chosen by a
  workflow, slot or model response. A global budget rejection remains fatal during
  advice and required work; it cannot become incomplete advice.
- Optional count operations provide observations only and never authorize inference or replace
  actual-usage accounting. [ADR 0030](../decisions/0030-engine-owned-model-request.md) (amended
  23 October 2026, not yet implemented) removes them; actual-usage accounting is unchanged.

- Native `advance-model-attempt-accounting` consumes the retained prepared request through an
  explicit YAML step and requires `retry-limit` (`0` means initial execution only).
- Its accounting permission is compiled from the registered contract, never authored in YAML.
- The runner binds the attempt and provider-operation ledgers to the request's fresh execution
  identity, applies the proposed accounting transition, and publishes sealed
  `accounted_model_attempt` evidence from that canonical record together with the envelope
  delta.
- Rejection publishes neither. An advisory protocol-correction exhaustion instead
  publishes a sealed stop receipt naming the existing request and exact exhaustion,
  without allocating an attempt or provider operation. An explicit lifecycle step
  closes that request failed; the native advice owner may record incomplete advice
  only for that same current projection (ADR 0023).
- Later visits use the accounting step's compiled authority and runner-owned counts.
  Atomic repairs use native defect keys; ordinary requests use immutable assignment
  keys, and required dependent requests additionally bind their native repair parent
  under [§22.7](22-repair.md#227-repair-retry-limit-and-escalation). Request ordinals
  never reset history. Other retry-capable operations retain invocation-wide counts.
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

- Native `prepare-provider-operation-authorization` consumes that same request, attempt and
  assignment through a separate YAML step with required positive `timeout-ms`. Under
  [ADR 0030](../decisions/0030-engine-owned-model-request.md) as amended on 23 October 2026
  (not yet implemented), the deadline is the bound catalogue entry's required
  `requestTimeoutMs` instead.
- The runner derives one absolute monotonic deadline, allocates the existing private lease slot
  and validates exact result correlation before publication.
- The action holds only the policy-permitted preloaded `provider-authorization` port: no I/O,
  refresh or provider call is allowed.
- Its sealed result contains a lease reference or closed failure/cancellation facts, never a
  backing capability.
- Rejected/expired preparation and execution cleanup release unused leases.
- Invocation and observed completion are separately selected YAML operations; no token charge or
  persistent record is added here.

- Native `advance-model-request-lifecycle` with `transition: invoked` exposes the existing
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
- Protocol/schema rejection closes as request `failed` while retaining the `invalid` outcome.
  The approved missing-final-answer case also admits as `invalid`, with no candidate:
  sealed observation evidence must establish `missing_final_text`, valid association
  and known usage. It may enter the same explicit protocol correction and attempt
  retirement path, or close as failed. Other provider stops/failures remain `failed`
  and cancellation remains `cancelled`.
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
- [ADR 0016](../decisions/0016-configured-json-response-composition.md) permits this
  complete candidate to be assembled from separately admitted configured responses;
  it is no longer required to originate in one model call. Initial extraction uses
  that path. Assembly retains every contributing origin and does not invent provider
  evidence.
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
- The final global partition assembles one `ReferenceReconciliationProposal` from
  separate disposition, signal-grouping and conflict responses (ADR 0022).
  Conflict resolution is `unresolved` until a separate authorized decision exists, so
  model conflict proposals omit that fixed status and the engine constructs it.
- Neither variant can redefine claim/token content or mint canonical
  summary/statement/signal/conflict/decision IDs.
- Dedicated coverage, join, ID, and build operations materialize summaries, the final claim
  ledger, `ReferenceSignal` records, and `SourceConflict` records.

- The feature-brief result schema selected by the workflow yields a `FeatureBriefProposal`
  grounded only in the completed reference claim/citation registries, or a typed specification
  clarification need, or the approved `inconclusive` diagnostic result.
- The model supplies a business title, description, and primary goal plus selected
  source-group handles (`signal_ids`, ADR 0020) or resolved clarification-response IDs;
  it cannot supply the `featureId`, any
  workflow or project path, or a reference selector.
- Before the call, the engine binds `featureId` to the validated supplied directory's lossless
  `paths.specs`-relative key under [ADR 0010](../decisions/0010-explicit-feature-directory.md).
  The independent reference selector and model output cannot name or rename the feature.
- An admitted authority gap takes the YAML-declared clarification branch under
  §12.8.1; candidate defects follow their existing validation/repair boundary.

- Specification-section, plan-unit, and task-cluster workflows declare discriminated result
  schemas for stage content or a `ClarificationNeedProposal`. Specification generation
  also permits `inconclusive` with diagnostic `detail`; it terminates through the
  existing invalid-result path and cannot authorize a user question.
- A clarification carries a bounded user-answer schema and engine-known subject authorities
  explaining the gap.
- An admitted need is a normal semantic pause, consumes no operation-local retry,
  and is never sent through repair to manufacture content. Returning the model's
  clarification variant alone does not admit the need.
- A malformed need is an invalid model candidate. The existing one-use no-invention
  replacement may yield a clarification only for an identifiable authority gap;
  it cannot turn an interpretation failure into a request for user information.
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
Preparation uses precise claim/citation bindings when supplied; source-only gaps
and generation needs retain their producer's validated captured-source/subject
evidence. It does not include every citation merely because its source matches. It quotes
captured text with source/line attribution and avoids repeating contained excerpts
when the full relevant text and every binding remain represented; citation IDs and
source records remain unchanged. Distinct evidence must not be merged by similar
wording. This is presentation deduplication, not multi-subject answer consolidation.
When full excerpts exceed the existing form fields, preparation references the complete
`reference-context.md` view instead of clipping or inventing a summary. Keep the
review concern in `why_required` and the subject-specific requested answer in
`question`. Evidence presentation does not certify a semantic finding.

Ask for the missing decision in ordinary user terms, not a restatement of the
reviewer's rejection. Identify what is already known and its source, then exactly
what the answer must add or choose. Explain why that decision is needed for this
subject; a generic absence message and a byte limit are insufficient. Do not ask
the user to reproduce known requirements in internal specification categories.
If admitted evidence does not identify the semantic gap, return to the existing
review/validation boundary under §12.8.1; formatting must not invent a question or
change a finding. A missing semantic decision cannot be filled by a generic
requirement-descriptor question or a copied diagnostic. Descriptor-based questions
remain valid for mechanically established gaps with a known required decision.
For a claimed conflict, the evidence must identify the incompatible meanings, why
they cannot both hold and the precise choice the answer must resolve. A conflict ID,
an unresolved status, copied rejection prose or an answer byte limit does not supply
that decision. Correct malformed/incomplete review data through existing bounded
review handling; substantive uncertainty remains a clarification only when an
actual user decision is identified. Formatting must not perform a second semantic
review. Source-review findings and canonical review evidence carry an optional
`question`. It is required for genuine negative source
findings and absent for supported/applicability/candidate-defect findings. Existing
`detail` carries the facts/reason. Initial admission, insertion, selected detail
correction and persisted validation share this contract; detail correction retains
the verdict/provenance. Its selected schema requires both `detail` and `question`
for a retained negative finding, and permits only `detail` otherwise. Diagnostics
identify missing, invalid or forbidden questions separately from invalid detail;
they retain one repair unit and retry family. Initial reviews and insertion use
closed `kind`-discriminated source findings:
`ambiguous`, `conflicting` and `unsupported` require `detail` and `question`;
`supported`, `not_applicable`, `candidate_omission` and `inconclusive` forbid
`question`. Shared fields remain schema references; `kind` is the sole source
decision field. Principle findings retain their separate `decision` contract.
The existing codec decodes source candidates with `kind`; native candidates retain
optional question data for diagnostics and the same decision-dependent checks.
Persisted evidence retains its existing finding/resolution representation.
Missing/forbidden questions reject at schema admission, before native collection.
So do missing, repeated or foreign assignment members: the packet's `exact_members`
ordinal choice fixes the item count and rejects a repeat as `duplicate_member`
([ADR 0023](../decisions/0023-advisory-post-generation-review.md#assignment-membership-at-response-admission-18-october-2026)).
So does a positive verdict the assignment withholds because no claim set can be
bound to it: it rejects as `unknown_variant`.
Existing protocol correction resubmits the whole assigned review under its original
assignment allowance, including otherwise correct siblings; insertion still corrects
only its selected finding. No partial-response merge, new counter or verdict
reassessment is introduced. Selected native text repairs retain their narrow scope.
There is no source `decision` wire format or compatibility reader. Generation uses its existing question shape. Presence and association checks are structural,
not deterministic proof of actionability.

**User-facing output:** reuse the current controlled form and fields:

| Information | Existing owner/field |
| --- | --- |
| Known facts/preconditions, current evidence and why a choice is required | Review `detail` → `why_required`; generation's existing attributed `question` carries its context; cited excerpts shown once |
| Exact missing decision and expected answer format | `question`; the workflow supplies the format and leaves the answer blank |
| Permitted input and lifecycle controls | Native `answer_schema`, existing Allowed answer and editable Answer regions |

Illustrative genuine gap, not a prompt example or hard-coded fixture:

- **Preconditions:** customers may cancel paid bookings; the supplied source gives
  no rule for the payment after cancellation.
- **Question:** What should happen to the payment when a customer cancels a paid booking?
- **Expected answer:** one sentence stating the payment outcome and any condition.
- **User answer:** empty until supplied by the user.

If the source already states the payment rule, asking this question fails semantic
conformance. A byte limit alone is not an expected answer. No additional form field,
summary call, answer-sharing rule or renderer-owned semantic check is introduced.
Generation's reason enum remains a reason code; a generic enum description alone
does not explain its missing decision. Do not parse free text into a second set of
authority fields to force the two producers into identical internal shapes.

Evidence-selection repair selects its response shape from the retained native
evidence minimum. A `claim_required` rule selects the canonical named shape with
nonempty `claim_ids`; optional and claim-or-source rules retain the generic shape.
Initial and inserted `supported`/`not_applicable` findings reference that same
nonempty provenance shape. Conformance tests compare configured shapes with the
native evidence minimum; schemas do not create a separate evidence policy.
The same evidence owner supplies concise guidance to initial review, insertion
and repair: `not_applicable` still needs supporting claims. Native validation and
persisted readback retain eligibility, exact-set and current-provenance checks;
schema cardinality never establishes semantic support or selects citations.
Review insertion and replacement reuse the initial guidance for the **same
assessment purpose**, returning only the authorized replacement and retaining
any existing verdict. Shared orchestration does not require source and principle
assessment to share semantic instructions; §17.3.1 owns the policy boundary. A
`missing_finding` diagnostic identifies an absent assessment, not missing source
information or candidate content. Insertion must assess the supplied content;
it must not infer a candidate omission from the mechanical diagnostic.
For entity applicability, the shared requirement description asks whether required
business behavior needs entities. An entity heading or explicit declaration of
absence is unnecessary; displayed values alone do not establish business entities.
A genuine missing data decision must state its behavioral effect and request the
details needed to resolve it, rather than a bare yes/no about entities. This guidance
does not authorize native inference from question prose or verdict reassessment.

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

- Persisted extraction-contract metadata is derived from the current compiled workflow,
  complete result schema, composition and part-operation bindings, plus the native
  `source_blocks_v1` partition identity. No separate partition resource is configured.
- `ReferenceSnapshot.extraction_contract` records the workflow ID/version, extraction
  and assembly nodes, `model-request/v1`, exact schema/composition resource IDs and
  bytes, and part-operation IDs/parameters. Derived part schemas remain owned by the
  canonical schema and composition; they are not copied into a second authority.
- The runner supplies immutable selected-graph metadata to the snapshot writer. The
  existing graph data-flow owner resolves the applicable extraction bindings. The
  state reader and publication validator resolve them through the current validated
  workflow registry and compare exact content as well as identity.
- Missing, unavailable or changed bindings reject with the terminal typed
  `REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE` diagnostic. The snapshot supplies
  comparison evidence, never a schema fallback, executable graph or saved request.
  Existing source, claim, token, relationship and review validation still applies.
- Fresh invocations start at the selected workflow's `start`; snapshots do not resume
  requests or parts. Readback must work after the original execution has been released.

### 12.8 Closed authority-reconciliation boundary

[View the authority-reconciliation contract sample](../code.md#authority-reconciliation-contract).

- Authority completeness is a shared engine contract, not behavior duplicated in prompts or
  implemented separately for particular domains.
- Required upstream authority is validated before generation. Execution-local
  drafting need not establish semantic support for output fields before they exist:
  [§17.3](17-specify.md#173-llm-work) defines Specify's draft-first sequence.
  Before stage commit, the engine builds and resolves the complete
  `AuthorityRequirementLedger` from every required field, decision slot, obligation,
  policy predicate and accepted upstream authority applicable to that stage.
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
- `assessment_complete`, naming the exact current subject/revision binding of
  complete admitted advisory review; it neither asserts semantic support nor
  discharges native authority/coverage defects;
- `assessment_incomplete`, naming the exact current advisory projection, revision,
  authority/member set, missing assignment suffix, native stop reason and origin
  when sent. Only ADR 0023's bound non-budget provider/protocol stop or eligible
  missing usage can produce it;
  native requirements remain mandatory and absent findings are not evidence;
- `clarification_required`, with a closed reason and the earliest owning `spec | plan | tasks` stage;
- `upstream_rework_required`, when a downstream stage encounters a gap owned by an earlier stage; or
- `administrative_block`, when the kind/slot has no registered ownership/reconciliation policy or requires authority that the workflow is not authorized to create.

- There is no unresolved native-authority success, warning-only authority resolution, inferred-default, closest-match,
  conventional-choice, model-memory, or current-stage-fallback variant.
- Exact equality and equivalence use the registered policy for that requirement kind.
- If deterministic comparison cannot prove equivalence, a bounded YAML-declared semantic
  operation may classify only supplied candidates with citations. An identifiable
  user choice follows §12.8.1; inconclusive interpretation remains a review failure.
- Multiple directly equivalent candidates may collapse only when the policy defines canonical
  equivalence and records total member evidence. Non-equivalence requires clarification
  only when current evidence establishes an actual unresolved authority choice.

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
  assessment (§17.3.1) must completely account for its assigned evidence and findings,
  or retain the exact missing assignment suffix under ADR 0023's native
  incomplete-advice contract.
  Under ADR 0023, semantic policy findings remain cited advice and alone create
  no mandatory Plan obligation. They are not inserted as policy-resolution
  requirements into the Spec ledger or relabelled supported. Plan validates its
  current native required policy decisions independently.
  Genuine business-intent gaps remain Spec-owned; invalid assessment evidence or
  missing evidence without that native stop follows the ordinary rejection path
  and cannot be deferred as a policy obligation.

- The ledger is a deterministic projection over current canonical authorities, not a competing
  persisted truth or fingerprint.
- It is rebuilt after authority refresh, clarification resolution, repair, and immediately
  before commit.
- Accepted canonical IR retains the authority, provenance, decision, obligation, and exception
  IDs needed to reproduce every successful entry.
- An open clarification retains its structural requirement/subject identity.
- Successful workflow publication is invalid unless the projection is exhaustive and every
  required entry is accounted under its native registered authority/assessment
  policy; assessment completion is never semantic proof. Any clarification/rework/block result instead follows
  its typed lifecycle with no partial stage IR.

This contract is deliberately domain-neutral. Adding a new requirement kind requires its schema, ownership entry, reconciliation policy, accepted and rejected fixtures, and stage-gate tests. It never authorizes a caller-specific workaround or a special continuation for one example.

- The shared authority owner is `src/domain/required_authority.zig`, with Specify's
  schema/reference projection in `specification_authority.zig` and five generic YAML bindings
  documented in [F0100
  §3.10](../features/F0100-SpecWorkflow.md#310-shared-required-authority-boundary).
- The runner checks both direct authority generations and their source lineage; replacing a
  source requires rebuilding its affected projection and gate.
- Only a directly consumed prior revision is a replacement's self-input. Reusing
  an output key cannot turn an inherited stale dependency into that exception.
- Native data schemas distinguish current authorities from captured immutable evidence.
- A captured value carries its complete current-authority frontier into every successor;
  retiring or replacing its transport slot does not invalidate that evidence.
- Conflicting source generations remain stale.
- Renewal distinguishes repair evidence from current dependencies. After exact native authorization/revision/old-value checks,
  a merge requiring dependent review renews only its declared replacements. Its
  native invalidation set and replaced generations become historical inputs;
  every other source/policy dependency must still be current and conflict-free.
  The envelope applies renewal and declared invalidation atomically. Original
  input generations and retained evidence remain available as history. No gate
  passes until all dependent projections and validation evidence are rebuilt.
  YAML/model data cannot select renewal keys; ordinary replacement cannot renew
  dependencies. Retry history and semantic-subject identity are not reset.
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

#### 12.8.1 Clarification admission and candidate-failure precedence

This section governs every unsupported/uncertain → clarification decision in
§§12, 17 and 21. It does not authorize verdict reassessment (§22.1).

**Admission:** `needs_user` requires a current required subject and an identifiable
decision the user can supply. Existing review/generation evidence must establish
known facts, the precise missing choice, why it affects the required subject and
the expected answer. Conflicts require the incompatible source meanings and their
exact subject/claim/source joins. A negative enum, conflict label, copied diagnostic,
nonempty question or absence of prewritten specification headings is insufficient.

Engine execution failures are never clarification evidence or question text in
generated Markdown. Preserve their typed rejection in operational reports/logs;
do not convert them into `needs_user`, missing business information or a fallback
question. Existing open clarifications do not permit continuation after failure.

The existing admission owner checks requiredness, permitted applicability, complete
assignment coverage, evidence identity/freshness, decision-dependent shape and
candidate-defect disposition. Existing semantic review assesses whether the decision
is actually absent. Text/citation checks cannot prove that semantic conclusion;
record it as model-assisted. Do not add keyword heuristics, a second reviewer by
default, or a parallel gap certificate/store. A known inconclusive review cannot
enter clarification just because the wire shape has no uncertainty alternative:
its owner must expose a closed rejection through the existing invalid-result path.
Source-review decisions and native findings include `inconclusive`: nonempty `detail`, no `question`, no localized loss or repair
authority. Specification generation has a corresponding `inconclusive` result with
`detail`. Existing invalid-result handling retains diagnostics and terminates if no
eligible producer repair can cause a dependent reassessment. Source schema variants
follow §12.7; verdict reassessment is not approved.

**Pre-generation diagnostic evidence:** the existing evidence owner must admit source-backed loss
against the selected producer even when its claims are ineligible for positive
content. The loss owner validates the exact producer/claim/source combination;
packet guidance, selected schemas, collection and readback project those same rules.
Source-only evidence is valid only for loss locations that permit it. A selected
signal/conflict requires its exact producer claims; disposition loss may use its
claim or source-only evidence. A `candidate` attribution means the fixed omission
belongs to the generated subject while its meaning survived upstream; it requires
a current candidate and nonempty subject-bound claim evidence. `unlocalized`
means no reliable attribution was established. Both retain ordinary eligibility.
Native source-review evidence retains the bound preservation assignment and complete
assessment response under [§22.1](22-repair.md). The derived location must agree
with re-admission against current canonical facts. Non-omission and principle
findings carry no comparison. The response supplies judgments, original-source
spans and explanations; its comparison ID binds the entire native collection.
The current specification-state contract in [§24.1](24-workflow-state.md#241-workflow-state)
retains authorized pre-generation comparisons and authored associations. Generated
source and principle findings instead retain advisory assessment bindings under
ADR 0023 and reject attached loss-comparison authority. Earlier snapshot contracts
reject without supplying missing bindings. ADR 0020 governs exact lineage.
Diagnostic eligibility never grants positive support or automatically selects citations.

**Source-review response contract:** the model chooses a semantic finding, detail,
and any genuinely selectable source. [§22.1](22-repair.md) also requires
`missing_obligation` for a source candidate omission, distinct from its diagnostic
detail and bound to its selected sources. No other finding or principle review
may supply it. Before generation, the separate loss call assesses native-bound preservation
views against that unchanged obligation without revising the finding or inferring
its requirement from diagnostic prose. It returns complete evidenced comparisons,
not a location; the same schema and immutable assignment govern protocol correction.
Resolved business values, numbered sources and producer context support those
comparisons. Native code derives attribution under §22.1;
every selected generation, source-review and repair schema rejects `provenance`.
The engine constructs the canonical claim selection from the current bound
source group, candidate evidence or natively derived diagnostic producer. A selected
extraction or token loss has an empty diagnostic claim set; signal or conflict
loss uses the named producer's exact set. Source-only negative findings may
carry empty canonical support where the rule permits it. An eligible catalogue,
including a singleton, cannot establish positive support. Source IDs remain
model-selected where the rule permits them; invariant empty clarification IDs
and an unlocalized default loss are constructed by code. Readback validates
stored evidence against its bound authority before accepting any projection.

**Readiness evidence:** under
[ADR 0023](../decisions/0023-advisory-post-generation-review.md), a positive finding
for a native `source_readiness` source-purpose subject before any authored candidate
exists requires explicitly selected, nonempty current original source IDs. Native
code constructs an empty canonical claim, citation and clarification-response
selection, independently of the eligible catalogue's cardinality. The packet,
wire decoder, admission and stored validation use the same role. The method remains
model-assisted and existing authority/applicability rules apply; this creates no
supported-candidate resolution or authored `S`/`E`/`L`. Empty, duplicate, foreign or
stale source selections and forged nonempty canonical provenance reject. Model
wire provenance/group fields remain forbidden. Candidate-bound/generated evidence
and source-preservation/reference exact claim sets retain their existing rules.

Reconciliation supplies validated source-obligation groups. The engine binds each record authoring task to one active group before
dispatch and resolves its claims through the existing ledger. A task may author
several records; overlapping or multi-claim groups preserve many-to-many links.
Unbound or stale units block as engine defects. Semantic verdicts and ADR 0020's
generation evidence bounds remain independently enforced.

A reconciliation conflict starts as an unresolved candidate assertion. Only current
review evidence for that exact subject establishing incompatible original meanings
and a concrete user choice can classify it as a genuine source conflict. An unrelated
negative finding, generic `unsupported`, or a positive verdict cannot discharge it.
Native joins establish association; the incompatibility judgment remains semantic.

Disagreement between model findings is not itself a source contradiction. If current
evidence already resolves the same registered decision against the same authorities,
a contrary need must account for that evidence. Unresolved assessment disagreement
stays at the review boundary; it does not ask the user to repeat known facts. Match
exact subject/purpose/dependency bindings, never similar wording or shared citations.
Changed source or a different decision still requires its own current assessment.

The shared authority owner combines the complete findings using this precedence;
the source-loss owner selects targets and the runner executes declared operations:

| Current state | Required continuation |
| --- | --- |
| Terminal validation/runner/provider failure, exhausted applicable retry, or token budget preventing required work | Terminal error; no new specification or clarification publication |
| Administrative block or required upstream rework | Preserve that typed outcome; no caller-local repair or clarification bypass |
| Repairable malformed review/need | Existing bounded correction and full admission; no authority gate on the partial result |
| One or more uniquely authorized localized candidate repairs, with current dependencies and allowance | Select deterministically from eligible targets; repair, rebuild affected dependents and reassess the complete ledger before choosing another outcome |
| No eligible repair remains, but candidate loss or interpretation failure remains unresolved | Terminal invalid/error with the native reason; no generic question, new forms or incomplete specification |
| No unresolved candidate/review defect and one or more admitted user decisions | `needs_user`; validate the complete clarification output under the owning workflow policy |
| All required authorities resolved and candidate validation passes | Continue the declared workflow; completion still requires all later gates |

An earlier unlocalized finding must not hide a later authorized repair. Retain it
for reassessment; never discard it. A genuine gap alongside a candidate defect cannot
mask the defect or cause early publication. A missing external authority that makes
the proposed repair unsafe prevents its authorization. Stable native ordering,
old-value/revision checks, independent defect identities, recurrence history and the
global actual-token limit remain with existing owners; selection cannot reset them.

Need construction and formatting occur after this gate. Text/evidence repair never
reclassifies a semantic verdict. If existing authority cannot safely correct an
inconclusive finding, reject it; optional reassessment requires its separate decision.
Apply this boundary to source review, generated needs, candidate review, selected
repairs and rerun/output validation. No special Spec YAML exception owns the policy.

For an admitted Spec pause, publish the validated incomplete `spec.md` and linked
forms under ADR 0017; report `awaiting_clarification`, IDs/paths and actual publication
status, with completed-spec grading `not_run`. Errors grant no new publication;
preserve prior artifacts/protected forms and retain diagnostics/logs. Pending forms
remain questions/answers, not semantic proof: readback checks current bindings and
fresh invocations rebuild the review/gate rather than trusting stored question prose.

This contract closes the specified unsafe transitions. It cannot
guarantee that every model judgment is true. False-gap recognition requires the
offline and separately approved live evidence in §28.9; documentation alone is not
an implementation or a reliability result.

### 12.9 Configured JSON response composition

[ADR 0016](../decisions/0016-configured-json-response-composition.md) owns the
user-directed decomposition contract: configured shapes and partitions, derived
part schemas, explicit independent request bindings, deterministic prompt-free
assembly and complete validation, and sets the 1,024-step workflow ceiling. The closed `json-composition/v1` resource is compiled through the existing
resource boundary and selects parts through ordinary request preparation.
The optional composition `definition` selects an existing named definition in its
`result` resource; otherwise the resource root is selected. Compilation rejects
unresolved selections. Projections, requests and complete validation retain this
same binding, and registry transfer rebinds to its destination schema owner.

A part's optional `input-context` selects a native immutable assignment context
into `assignment` through the shared request preparation owner. The complete
evidence packet and declared prerequisites remain available; missing contexts
reject before inference. Corrections retain the selected presentation. Contexts
carry applicable guidance, not independent validation, repair or gap policy
(ADR 0016).

The mechanism is shared across supported JSON shapes. Domain owners contribute
facts and semantic validators; they do not gain separate assembly, retry, storage
or continuation policies. An assembled candidate retains every real producer
association and never becomes a fabricated provider response.
A parent subtree has one producer only when all present selected descendants share
that exact origin. Absent fields contribute none; an empty structural container or
subtree with mixed origins has no single producer. Finer required-object selectors
therefore preserve native consumer provenance without assigning a synthetic origin.


[ADR 0022](../decisions/0022-native-reference-phase-handoffs.md) adds native part
placement through a registered producer's `native-composition-part` parameter.
The compiler verifies its configured part and prerequisites; YAML still chooses
execution. The composition owner admits the projected value through that part's
schema and binds exact prerequisite snapshots. Native values carry no provider
origin; mixed assembly retains the actual model origins per selected subtree.
Full candidate validation remains required. Reconciliation uses explicit native
phase handoffs rather than composition to establish semantic prerequisites.
Their current-phase assignment projections follow ADR 0022: complete evidence
remains available, while semantic authoring receives only eligible claim IDs.
Protocol corrections retain the same projection and acceptance rules.

### Source invalid-content finding

One source-only `candidate_invalid` finding covers invented additions and
contradictions that retain the original obligation. Its closed response contains `source_ids`,
`detail` and required nullable `authority_gap`. A non-null gap retains the existing
`unsupported`, `ambiguous` or `conflicting` kind, its own source IDs, explanation
and actionable question. Native admission validates both evidence selections
against the same current subject; neither part supplies authority for the other.
The top-level finding carries no question, `missing_obligation`, localized loss
or preservation comparison. A contradiction that removes original meaning still
uses `candidate_omission`. Per-source preservation permits only a null gap;
principle review retains its separate finding vocabulary.

The shared authority owner retains an `invalid_content` candidate defect without
omission-repair support, and evaluates a nested gap through its existing gap
rules. Candidate failure continues to prevent clarification and completion.
Structural detail, source-selection and question correction preserves both verdict
kinds. It cannot erase the defect, invent an omission or reassess the finding.
It grants no new semantic repair or verdict-reassessment permission.
The finding, explanation, original evidence and native repair denial together
describe an actionable failure; structural admission is not semantic proof.

The typed-text wire contract in §7.1 applies: ordinary prose is a string, and explicit composition is
`{"fragments":[text, typed-reference, ...]}`. Native conversion preserves declared
fragments, whitespace and exact occurrence identity. Initial input/output,
protocol correction and authorized content repair use that one conversion.
Canonical arrays remain native data; bare model arrays reject.

Under ADR 0020 the same model-wire conversion applies to generation,
clarification and repair, and `exact_copy` is absent from both shared
response-codec directions and every selected response schema. Explicit native-evidence
encoding may retain sealed identities as read-only facts, never response alternatives. Current native `exact_scope`
metadata binds the reference snapshot and eligible occurrence bytes, while field
bindings retain their canonical roles. Protocol correction retains these exact
facts and its original schema; it cannot acquire a fresh occurrence scope from
its rejected body. Admission recognizes raw prose before NFC and validates the
derived composition through the shared owner. Ambiguous eligible spans reject the
complete field through existing bounded correction, not a new retry route.
`model-request-debug/v9` retains native scope for diagnostic replay; request logs
never become workflow or persistence authority. Missing historical native scope
stays unavailable rather than reconstructed from a visible token catalogue.
