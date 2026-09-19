# F0006 — LLMProviderInterface

**Status:** Accepted feature design

**Production completion scope:** F0006 includes production provider/model
registration, Bedrock configuration, concrete authorization/count/inference
wiring, native-schema projection and shared fake/real-adapter conformance.
[F0007](F0007-AWSBedrockProvider.md) records the Bedrock implementation using the
existing composition boundary, runner ledgers and pinned Zig HTTP transport.

**Execution amendment:** [ADR 0009](../decisions/0009-atomic-workflow-execution.md)
removes provider-effect persistence, durable handoff and cross-execution
recovery. The whole workflow is atomic; an abandoned execution is never resumed.

**Provider-limit amendment:** [ADR 0011](../decisions/0011-provider-owned-request-limits.md)
removes all additional model-call size ceilings and capacity gates. Provider
APIs report their limits; the runner accounts actual usage against the workflow
token budget. This is accepted, not a pending configuration or approval decision.

**Operation-ID amendment:** [ADR 0005](../decisions/0005-workflow-defined-operations.md#unversioned-operation-ids-accepted-2026-09-06)
removes operation versioning. Runtime operations and names below use one current
unversioned contract per operation; retired suffixes are rejected, not aliased.

**Input-reuse amendment:** [ADR 0013](../decisions/0013-workflow-input-reuse.md)
keeps captured schema source and derives compact expanded transport in the same
compiled owner. Inference and counting use that projection. An originating
`result-selection: input` binds the packet's typed named result view once;
response validation and protocol retries retain it. Full evidence projections
share citation records without changing canonical evidence or usage accounting.

**Implementation:** Provider capture/decoding, registry and repository-slot
validation, conditional bootstrap, retained workflow requests, attempt/operation
accounting, single-use authorization, inference/counting, response validation
and explicit lifecycle closure are connected through native YAML operations.
Production Bedrock uses those same contracts and runner bindings.

**Reading route:** [binding, §6](#6-providermodel-binding-and-workflow-token-accounting)
→ [lifecycle, §7](#7-operation-identity-lifecycle-and-interface)
→ [results, §8](#8-closed-request-observation-and-failure-algebra)
→ [action ownership, §9](#9-action-and-orchestration-ownership).
[ADR 0012](../decisions/0012-workflow-owned-model-request.md) owns request handoff;
the [example](../examples/provider-request.workflow.yaml) shows inference,
validation, closure and pre-call failure handling. It is test/design source,
never a runtime fallback. The [prompt/response diagram](../diagrams/17-model-prompt-response-flow.md)
shows input projection, evidence selection and repair.

**Compatibility:** None. This is a pre-release contract. There is one exact
provider filename and JSON shape, with no alias, migration, dual reader,
implicit provider, cached fallback, source-example fallback, or permissive
configuration map.

**Classification:** Provider-neutral model port and read-only provider registry

**Scope:** SDDE engine development. This document does not authorize an engine
run against a target project, a provider request, credential access, or a
project-content change.

**Governing authority:** [Engine design](../design.md), especially Sections 1,
3-6, 9, 12-13.4, 15, 21-22, and 26-31; [ADR 0001 — Zig native
engine](../decisions/0001-zig-engine.md); [ADR 0004 — conditional
model-provider bootstrap](../decisions/0004-model-provider-bootstrap.md); [F0001 —
SDDToolKitConfigService](F0001-SDDToolKitConfigService.md); [F0002 —
LogService](F0002-LogService.md); [F0008 —
LLMProviderConfigService](F0008-LLMProviderConfigService.md); accepted [ADR
0005 — workflow-defined operations](../decisions/0005-workflow-defined-operations.md);
the [path contract](../paths.md); and
`design/code.md` Sections 21-24. The
[`.sddproviders.json`](../examples/.sddproviders.json) file is source material
for the requested collection pattern. It is not runtime authority, a schema,
a default, or a fallback.

---

## 1. Responsibility

`LLMProviderInterface` is the definitive name for the sole provider-neutral
architectural port. There is no alias or parallel gateway.

- The interface has one responsibility: execute one already selected, validated,
  identified, and accounted provider operation through an immutable provider/model
  binding and return one bounded provider-neutral observation.
- It does not select a workflow operation, slot, or model, read configuration, acquire
  workflow authority, interpret model content, or validate an SDDE candidate.

- The F0006 feature also defines the separate bootstrap path that makes the port usable.
- When the exactly selected compiled workflow requires model binding or provider calls,
  the engine consumes F0008's immutable bytes from the project-owned location selected
  by `.sddtoolkit.json` `paths.providers`, decodes its one closed shape, joins every
  entry to compiler-registered provider/model contracts, and constructs one immutable
  `LLMProviderRegistryService`.
- Providers receive only validated typed bindings; they never locate, read, parse, or
  reinterpret the file.

- `AWSBedrockProvider` is the first implementation.
- A later provider requires a new compiled discriminator, closed configuration variant,
  provider/model contracts, concrete adapter, exhaustive dispatch branch,
  composition-root binding, and positive and negative conformance tests.
- Project data cannot add executable code, dynamically load a provider, or create a
  capability.

## 2. Accepted amendments

These amendments are accepted and implemented. ADR 0009 withdraws their former
provider-effect journal and cross-execution recovery requirements; lifecycle
facts remain local to the abandoned or completed execution.

1. Require `paths.providers`; reserve its exact project-relative `.sddproviders.json`
   capability and prove all configured-location collisions.

   - Only F0008 captures the file, when requested.
   - Contract: [F0004 path
     validation](F0004-BootstrapRootRegistryService.md#4-path-and-existence-contract);
     [conditional capture, §5](#5-conditional-bootstrap-and-change-handling).

2. Place the fixed, capability-free `ModelProviderBootstrapOrchestrator` after
   selected-workflow compilation and before execution, using runner-owned bindings.

   - This explicitly amends fixed startup-graph authority.
   - Contract: [Conditional bootstrap,
     §5](#5-conditional-bootstrap-and-change-handling); [action ownership,
     §9](#9-action-and-orchestration-ownership).

3. Make the closed document, provider-specific configuration union, and
   byte/collection/nesting/identity limits normative.

   - Contract: [Provider document, §3](#3-exact-sddprovidersjson-contract).

4. Add separate provider-file diagnostics without broadening F0001's two reader codes.

   - Contract: [Diagnostics, §10](#10-diagnostics-security-and-cleanup).

5. Capture once on a required branch; retain one immutable per-invocation
   registry/allowlist, with no refresh, cache or last-known fallback.

   - Contract: [Snapshot lifetime, §5](#5-conditional-bootstrap-and-change-handling).

6. Treat the catalogue as configured models and `models.slots` as the repository
   allowlist.

   - Originating YAML requests select a slot; consumers retain that binding under ADR
     0012.
   - ADR 0005 removes built-in routes.
   - Contract: [Binding, §6](#6-providermodel-binding-and-workflow-token-accounting).

7. Amend `AdvanceModelAttemptAccountingAction`, Design §§12.1/13.4 and
   `ModelRequestLifecycle`: reserve the initial attempt once; later attempts require
   explicit operation-local `retry-limit`; close every assigned/uninvoked branch.

   - Count and inference failures consume their attempt.
   - No workflow-global attempt, retry, unit-repair or stage-repair ceiling applies.
   - Contract: [Full-attempt lifecycle,
     §7](#7-operation-identity-lifecycle-and-interface).

8. Use `LLMProviderInterface` as the sole name in design, package and architecture-test
   authority, without aliases.

   - Contract: [Responsibility, §1](#1-responsibility).

9. Require a relocated packaged executable to use target-owned provider configuration
   without source examples.

   - Contract: [Acceptance, §12](#12-acceptance-criteria); [verification,
     §13](#13-verification).

10. Prepare authorization from a preloaded, non-refreshing, no-I/O lease.

    - Only a narrowly defined environment preloader may obtain material; Bedrock uses
      `AWS_BEARER_TOKEN_BEDROCK`.
    - Repository-selected secrets, files, processes, metadata, STS and refresh effects
      are prohibited.
    - Contract: [F0007 credentials and
      transport](F0007-AWSBedrockProvider.md#credentials-and-transport).

11. Expose transport/auth/throttle/timeout outcomes to YAML; only its explicit
    registered retry operation selects a retry.

    - Providers and generation orchestrators cannot hide it.
    - Contract: [Failure algebra,
      §8](#8-closed-request-observation-and-failure-algebra).

12. Use one positive workflow total-token budget.

    - Before a call, reject exhaustion; afterward, charge reported inference
      input/output once, including overshoot.
    - Exact equality permits the current result only; retries share the total and a new
      execution starts at zero.
    - Counting is not charged again.
    - No reservation, estimate or budget-derived output allowance applies.
    - Contract: [Actual-usage accounting,
      §6](#6-providermodel-binding-and-workflow-token-accounting).

The two project inputs have distinct responsibilities:

| File | Responsibility |
| --- | --- |
| `.sddtoolkit.json` | Define the repository's allowed model set through named slots containing exact provider/model references and accepted options. F0001 remains its sole reader and decoder. |
| `.sddproviders.json` | Catalogue the bounded configured provider/model instances and their closed provider-specific deployment configuration. It contains no repository allowlist, workflow-operation assignment, capability claim, executable implementation, or secret. |

- Let `C` be the exact validated catalogue tuple set and `S` the tuple set projected
  from `models.slots`.
- The required relationship is `S ⊆ C`.
- Equality is valid, as is a strict subset; `S` containing any tuple outside `C` rejects
  the repository model configuration.
- No reverse completeness requirement exists, and `C - S` remains configured but
  unauthorized for this repository.
- Distinct slot names may reference the same member of `C`; this does not increase `S`
  or duplicate the catalogue entry.
- F0006 does not replace `models.slots` with a profile or workflow-operation registry.
- Each YAML-declared generic model operation must select a configured slot and produce
  the same `ValidatedProviderModelBinding` before any provider operation.

## 3. Exact `.sddproviders.json` contract

The formal common structural contract is
[`sddproviders.schema.json`](../schemas/sddproviders.schema.json). Constraints
that JSON Schema cannot express—duplicate-key rejection, strict transport,
nesting depth, total model count, global identity uniqueness, compiled-contract
joins, and provider-specific configuration closure—remain normative here and
are enforced by the implementation.

- The runtime source is exactly `<projectRoot>/<paths.providers>`, where `projectRoot`
  is the same canonical invocation root established for F0001 and the normalized
  configured path has the exact `.sddproviders.json` basename.
- F0006 receives only F0008's bounded immutable bytes; it does not resolve or read the
  path.
- The engine never searches a parent, child, home directory, environment-selected path,
  source tree, or packaged asset.
- The repository example is never opened at runtime.

The transport is strict UTF-8 JSON without a BOM, comments, duplicate keys,
non-integer numeric tokens, or trailing content. The root has exactly one
required member. The common shape intentionally matches the example:

```text
LLMProviderDocument {
  providers: ProviderDefinition[]
}

ProviderDefinition {
  provider: LLMProviderId,
  models: ProviderModelDefinition[]
}

ProviderModelDefinition {
  model: ProviderModelId,
  config: RegisteredProviderModelConfig
}
```

- The trust-boundary decoder first produces a bounded `RawLLMProviderDocument` with the
  same exact common member names.
- Provider and model identities remain bounded untrusted strings and each `config`
  remains a bounded untrusted JSON object; no raw configuration field is usable.
- The decoder rejects malformed transport, duplicate keys, wrong common kinds, and
  unknown root/provider/model members as `LLM_PROVIDER_CONFIG_PARSE_ERROR`.

- `BuildLLMProviderRegistryAction` then resolves each provider discriminator and decodes
  its raw `config` through exactly one registered closed variant, producing a validated
  `ProviderModelDefinition`.
- An unregistered provider, unknown provider-specific field, or wrong provider-specific
  value is `LLM_PROVIDER_REGISTRY_INVALID`, not a partial decode.
- This staged raw-to-validated boundary rejects any unsupported sibling before
  publishing the registry.
- The current source example selects the registered Sydney Bedrock model; it is still
  not an automatic runtime configuration or fallback.

- There are no common project-authored `endpoint`, `contextWindow`, `maxOutputTokens`,
  `supportsTemperature`, `structuredOutput`, `tokenizer`, or wire-parameter fields.
- Those are trusted compiler-registered model-contract facts described in Section 4.
- The provider catalogue may declare only a known provider, known model, and the fields
  permitted by that provider's closed `config` variant.
- Catalogue membership alone does not make that model repository-authorized.

`RegisteredProviderModelConfig` is a closed tagged union selected by the
validated enclosing provider. For example, `provider: "aws-bedrock"` requires
the exact F0007 configuration `{ "region": <validated-region> }`.

- Every root, provider, model, and resolved provider-specific configuration object is
  closed at its owning boundary.
- An unknown field, provider, configuration variant, duplicate provider, duplicate
  `(provider, model)` tuple, missing registered contract, or invalid sibling rejects the
  complete document.
- There is no partial registry.

The accepted pre-release resource limits are:

- at most 1,048,576 captured bytes and 16 JSON nesting levels;
- at most 16 provider entries;
- at most 256 models under one provider and 256 models in total;
- `LLMProviderId` of 1-64 ASCII bytes in lower-kebab form; and
- a non-empty provider-validated `ProviderModelId` of at most 512 UTF-8 bytes.

Provider and model matching is exact and case-sensitive. The tuple
`(provider, model)` is globally unique. A model string is an identifier to join
against a compiled contract, not an arbitrary endpoint, URL, resource
capability, library symbol, or dynamically loaded implementation.

- Configuration contains no API key, access key, secret key, session token, bearer
  token, credential material, credential file, environment-variable name, credential
  process, command, role session, secret reference, arbitrary header, retry count,
  proxy, CA override, or unrestricted request map.
- Provider-specific features may add only narrowly typed, explicitly accepted fields.

The provider and [toolkit source example](../examples/.sddtoolkit.json) select
the registered Sydney `openai.gpt-oss-20b-1:0` Bedrock model. Multiple repository
slots may reference it without duplicating its provider configuration. These
files are source examples, never runtime fallbacks.

## 4. Registered contracts and immutable registry

Capabilities come only from immutable contracts compiled into the
native executable. A representative contract is:

```text
ProviderModelContract {
  provider: LLMProviderId,
  model: ProviderModelId,
  providerVariant: RegisteredProviderVariant,
  targetContract: RegisteredProviderTargetContract,
  operationSet: RegisteredProviderOperationSet,
  exactTokenCounter: RegisteredExactTokenCounter,
  structuredResponse: RegisteredStructuredResponseContract,
  supportedControls: RegisteredInferenceControlSet
}
```

- Provider-specific versions may add only closed typed facts.
- Project configuration can select a deployment fact such as a registered source region,
  and may narrow accepted choices where its variant says so.
- It cannot claim model support for an operation, tokenizer, control, structured schema,
  endpoint, region, partition, or data-routing policy.

Registry ownership is separated as follows:

| Owner | Sole responsibility |
| --- | --- |
| `BuildLLMProviderRegistryAction` | Join the decoded document to the fixed provider discriminator registry and compiler-registered model contracts, producing one owned candidate registry. |
| `ValidateLLMProviderRegistryAction` | Prove closed variants, exact joins, uniqueness, resource totals, target policy, model capability, and registered provider discriminator availability for the entire candidate. |
| Pipeline runner | Apply the validated delta and materialize the run-owned immutable `LLMProviderRegistryService`; destroy the candidate on every rejected path. |
| `LLMProviderRegistryService` | Expose borrowed immutable lookup by exact `(provider, model)` tuple; it does not read files, mutate entries, choose a workflow operation or slot, or perform I/O. |
| `ValidateRepositoryModelAllowlistAction` | Join the complete F0001 `models.slots` map to the validated catalogue and produce immutable slot-to-entry references only when every tuple resolves exactly once. |
| `ValidatedRepositoryModelAllowlist` | Be the sole repository model-allowlist authority. It owns slot identity, catalogue-entry identity, and validated slot options; it copies no provider configuration, contract facts, adapter, client, or capability. |
| Composition root | Construct the fixed provider/model contract registry, concrete provider adapters, the private exhaustive dispatcher, and their narrow dependencies; inject the common port only into provider-operation actions. |

- Registry entries and pipeline bindings contain immutable provider/model facts plus a
  closed discriminator only.
- They never contain a provider object, client, function pointer,
  credential/authorization handle, or operation capability.

The infrastructure-private dispatch implementation is an exhaustive closed tagged union,
not `anyopaque`, a service locator, callback map, or project-extensible factory:

```text
LLMProviderDispatch = union(enum) {
  aws_bedrock: AWSBedrockProvider
  // A future compiled provider adds a new exhaustive variant.
}
```

- Production installs the Bedrock contracts in
  `composition/provider_model_contracts.zig` with the closed `aws_bedrock { region }`
  configuration and exhaustive concrete dispatch.
- The exact supported models, regions and modes are listed in F0007.
- The empty-object variant belongs only to private test contracts, not production.
- External catalogue and slot selection remain mandatory; registration supplies support
  facts, never a default or repository authorization.

- The neutral contract carries count/inference support, an exact-count mechanism
  (`unavailable | provider_input_token_count`), response support and temperature
  support.
- These are compiler-supplied capability facts, not configuration fields or
  provider-size policy.
- Canonical/wire capacity fields are absent.
- The catalogue validator proves exact equality with the registered contract; even a
  narrower candidate cannot substitute different contract facts.
- An internally consistent but insufficient contract may remain catalogued, but cannot
  produce a usable model binding.

- Response support admits `unavailable | prompt_only | bedrock_json_schema`.
- Only the registered native profile permits native mode.
- Its projection preserves closed fields, required members, types, enums and disjoint
  tagged alternatives.
- Bedrock receives supported structural constraints; the complete schema, including all
  bounds, remains in guidance and deterministic validation.
- Unsupported modes reject without fallback.
- Provider grammar never establishes candidate validity.

- Every union variant conforms directly to `LLMProviderInterface`; dispatch forwards
  exactly one operation and introduces no second port.
- Adding a provider therefore requires a source change and architecture tests.
- Unused entries do not become callable: only a compiled YAML model operation whose
  originating request slot resolves to a validated fact-only binding can reach the
  composition-injected common port.

## 5. Conditional bootstrap and change handling

- The bootstrap root registry always reserves the exact configured provider path and its
  access class before any project operation.
- The complete bootstrap root validator proves that file role distinct from
  `.sddtoolkit.json` and every configured/derived root under all active host/target
  normalization, case, alias, and containment rules.
- A collision blocks even when provider content loading will be skipped.
- Reservation grants no provider capability and does not probe file existence or
  content.

- After the validated workflow registry has resolved the selected graph,
  `DeriveProviderRequirementAction` derives whether any step has compiled model
  requirements or the exact compiler-owned `model-provider` capability.
- It reads no workflow/node name, parameter, policy allowance alone, configuration,
  slot, or provider content.
- A project workflow cannot manufacture that capability by naming a provider node or
  field; it can receive it only through an accepted registered node contract under an
  allowing workflow policy.

The fixed `ModelProviderBootstrapOrchestrator` then branches only on that typed
outcome through runner-owned child bindings:

- If the selected compiled graph has neither model-binding requirements nor
  the exact `model-provider` capability, file existence probing, opening, reading,
  decoding, and registry construction are unreachable. A missing or malformed
  file is not observed and has no effect on that run.
- If it has either requirement, F0008 must successfully capture the exact configured
  provider file, and the complete document must build and validate before
  `ValidateRepositoryModelAllowlistAction` joins the complete `models.slots` map to that
  catalogue.

  - Both the complete catalogue and complete allowlist must validate before the first
    selected-workflow node runs.
  - Missing, malformed, unsupported, partially valid, or catalogue-missing slot input
    blocks run preparation; no partial allowlist is published.

- The orchestrator performs no filesystem, parsing, registry, state, logging, or
  provider work itself.
- ADR 0004 accepts this fixed run-preparation placement and the narrow expansion beyond
  the startup graph; the runner does not infer or sequence it by convention.
- The implemented runner invokes F0008 once, then applies the decoder, registry builder,
  registry validator, and complete allowlist validator through their existing contracts.

- The engine invocation runner invokes one composition-supplied
  `ModelProviderBootstrapBinding` immediately after exact workflow selection and before
  constructing the selected-workflow runner.
- `not_required` and `ready` continue to workflow execution; `failed` returns the exact
  provider-bootstrap diagnostic; `cancelled` returns cancellation.
- A `ready` result remains owned until selected-workflow execution returns.
- The binding exposes no filesystem port; the composition assembly alone constructs the
  F0008 adapter and both runners.

- F0008's owned capture is the only provider-document read for the engine invocation.
- The validated registry and allowlist derived from it remain authoritative until that
  invocation ends even if the backing filesystem entry later changes; the raw capture
  need not be retained after preparation.
- No identity comparison or refresh is performed after capture; the next invocation
  performs a new conditional capture.
- There is no stale fallback because no prior invocation's bytes, registry, or allowlist
  are retained.

## 6. Provider/model binding and workflow token accounting

- F0001 remains the sole owner of `.sddtoolkit.json` decoding.
- The complete `models.slots` map defines the repository's candidate allowlist.
- Before any workflow model operation is usable, every slot's exact case-sensitive
  `(provider, model)` tuple must resolve once in `LLMProviderRegistryService` and
  produce one entry in `ValidatedRepositoryModelAllowlist`; one missing or ambiguous
  tuple rejects the complete repository model configuration.
- Provider catalogue entries not selected by any slot are retained as configured facts
  but cannot be resolved through repository model authority.
- The allowlist references registry-entry identities rather than copying provider
  configuration or compiled contract facts.
- Decoded strings alone grant no provider authority.

`ResolveProviderModelBindingAction` must prove:

1. the compiled workflow operation's YAML-declared slot resolves in `ValidatedRepositoryModelAllowlist` to
   exactly one immutable registry-entry identity; direct provider/model tuple
   selection bypassing the allowlist is impossible;
2. the entry resolves to exactly one registered provider discriminator and
   compiled model contract, without storing a concrete adapter;
3. its provider-specific configuration, target, source region, destination
   policy and selected operation support are valid; counting support is optional;
4. every selected option, including `reasoningEffort`, is explicitly supported
   and representable rather than silently ignored;
5. the request retains the complete compiled result schema under ADR 0006;
   native generation constraints derive from it through the registered profile.

Request-origin contracts declare one repository slot and explicit `response-mode`
(`prompt-only | native-schema`). Under the user-approved 2026-09-19 amendment
to §12.5, temperature is engine-owned: binding selects `0` when the registered
model supports it, otherwise omission. Workflow `temperature` parameters reject,
including zero; neither request consumers nor retries can override the binding.
Resources and outcomes remain in the existing concise workflow structure.

- The originating step's typed slot and response-control requirements compile into the
  existing model-binding projection.
- Registered request consumers use the prepared request's typed data dependencies and
  cannot select a replacement.
- They grant immutable binding data, not a provider port.
- Provider-call capabilities remain independently derived from narrow ports and
  constrained by the selected policy.
- No capacity field, second flag or registry is needed to derive binding requirements.

**Provider-owned size limits**

- Under ADR 0011, registration, compilation and preparation require no byte ceilings or
  size estimates.
- Retired `input-bytes`, `output-bytes`, `input-tokens` and `output-tokens` parameters
  reject; do not replace them with another size knob.
- The runner checks identity, slot, schema, response mode and supported controls against
  the compiled contract and retains those facts for exact single-use authorization.
- Providers report oversized requests, output stops and context errors through the
  ordinary typed observation path.

**Actual token accounting**

- The selected workflow policy contributes one `totalModelTokenBudget` to each workflow
  execution.
- Its sole accounting authority records actual API-reported input plus output tokens.
- A pre-call check reads the current total without changing it; total usage at or above
  the budget rejects further model calls.
- Reconciliation records each inference operation once, including retries and stopped
  responses.
- Usage above budget remains recorded and returns `WorkflowTokenBudgetExceeded`; exact
  equality allows the current result only.
- No input count, maximum-output estimate, reservation, release or retained worst-case
  charge participates in workflow budgeting.
- Proven non-delivery adds no charge.
- Unavailable usage blocks further model calls with `ProviderTokenUsageUnavailable`,
  never a fabricated zero or estimate.
- The count operation supplies evidence and is not charged again as inference usage.
- Ordinary non-model cleanup is not prohibited by an exhausted budget.

**Transport and response integrity**

- Provider serialization performs the protocol's exact escaping and shape translation
  without an engine-defined body, header, path or response-size cap.
- A provider rejection is an API observation, not a locally fabricated `not_sent` size
  failure.
- Transport, allocation, cancellation and deadline failures remain distinct and retain
  their actual delivery disposition.

- Reported usage must be internally consistent under the registered provider protocol.
- Complete output is validated as UTF-8 and against its exact compiled schema; neither
  serialization nor decoding compares its length against a request/output byte ceiling.
- Invalid or stopped output never becomes a truncated candidate.
- Reported usage remains accounted even when content fails validation.

There is no implicit default, nearest match, first entry, provider-owned
selection, or silent fallback. Only the compiled YAML `on` mapping may choose
an explicit retry or fallback operation from typed outcomes. The runner only
validates and applies the resulting attempt/lifecycle/accounting deltas.

## 7. Operation identity, lifecycle, and interface

One reserved model attempt owns separately identified external operations:

```text
ProviderOperationKind = input_token_count | inference

ProviderOperationId {
  modelRequestId: ModelRequestId,
  modelAttemptOrdinal: PositiveInteger,
  kind: ProviderOperationKind
}
```

One ordinal represents one provider attempt. Inference has no count prerequisite:

1. validate request identity, binding, supported controls and schema;
2. reserve the initial ordinal, or a later ordinal only under the YAML-selected
   operation's explicit compiler-validated `retry-limit`;
3. assign the chosen operation from its exact binding/input identity and prepare
   its single-use authorization;
4. check actual execution token usage, apply the in-memory invoked transitions,
   then perform that one API call under cancellation and deadline guards;
5. record reported input/output usage once, retaining any overshoot before
   returning the budget error; when execution continues, an explicit YAML
   completion step closes the observed operation; and
6. follow explicit YAML transitions for retry or logical-request closure.

A separately selected count operation has its own identity, authorization,
lifecycle and observation. Its value or failure is not an implicit inference
gate. An unfinished operation must close before another operation or attempt.

- `AdvanceProviderOperationLifecycleAction` proposes compare-and-swap deltas for
  `assigned -> invoked -> terminal`; preparation failure or cancellation may use
  `assigned -> terminal`.
- Only the runner validates and applies these deltas.
- No operation may remain assigned when its attempt or request terminates.
- A provider action requires proof that its `invoked` transition is already applied.

**Ledger ownership**

- The implementation retains immutable ledger snapshots under one execution owner.
- Sealed pipeline evidence retains that owner and the canonical request owner until
  destroyed; it does not copy operation authority.
- Every change checks the exact ledger, request, attempt, and operation revisions; count
  and inference reference the existing reserved attempt rather than reserving it again.
- Either assignment owns immutable binding and input-identity facts; inference does not
  join a count record.
- The action emits one declared runner transition, and only the runner publishes the
  successor.
- Request terminalization and a later attempt are rejected while an operation remains
  assigned or invoked.

- The native assignment binding accepts only the two assignment commands.
- The registry/compiler require its closed `kind` parameter and prepared-request/
  applied-attempt dependencies.
- The runner supplies read-only lifecycle authority, checks the proposal against the
  retained request, and publishes the successor and evidence together only after
  envelope validation.
- Removing evidence cannot erase an open operation or reset an attempt.
- Assignment is not invocation or a lease: authorization preparation is a separate
  implemented YAML operation; Logical-request and provider-operation invocation state
  and the explicit `invoke-model` call and observed inference completion are
  YAML-integrated; evidence-derived logical-request closure is YAML-integrated too;
  authorization-derived assigned-operation termination is also YAML-integrated.
- Execution cleanup discards its in-memory records, never resumes or persists them.

The applied invocation record belongs only to the current execution. No
persisted send marker or result-consumption record is required. The runner's
binding, single-use authorization, budget and deadline checks remain required;
an invocation record alone does not grant a provider capability.

**Inference action**

- `InvokeModelAction` forwards the exact prepared request, binding, single-use
  authorization reference and applied invocation record through the existing
  `LLMProviderInterface.invoke` port once.
- The port owns lease consumption and call checks; the action adds no counting, retry,
  fallback, response parsing, validation or accounting.
- Complete/stopped observations and failure facts pass through unchanged, as do
  cancellation and allocation errors.
- The caller owns the returned observation.
- Its `model_call` side-effect classification grants no capability or send authority;
  capability derivation still uses the injected port.
- Fake-provider tests exercise the action through observation validation, decoding and
  payload schema validation.
- Native YAML registration now invokes this same action; provider implementation binding
  remains explicitly required.

**Count action**

- `CountModelInputTokensAction` is implemented and YAML-callable.
- It forwards the exact request, binding, applied count-operation record and single-use
  lease reference through `LLMProviderInterface.countInputTokens` once.
- The existing port owns association/deadline checks, lease consumption and backing
  cleanup.
- Counted observations, failure facts, cancellation and allocation errors pass through
  unchanged; no validation, retry, fallback, inference, token charge or lifecycle
  transition occurs inside the action.
- Count observations borrow their request and binding identities, so those owners
  outlive their use.
- Counting remains optional, not an inference prerequisite or capacity gate.

**Count observation validation**

- `ValidateModelTokenCountObservationAction` is pure and allocation-free.
- The caller supplies the current operation ledger and original request/binding.
- Validation reuses `requireInvoked` and `validateCountInvocation`, compares both
  observation variants with that exact operation ID (including attempt), and reuses
  `ExactInputTokenCountEvidence.fromObservation` for counted request/binding/input
  association.
- After validation, that shared constructor returns canonical request/binding references
  rather than observation-owned identity strings.
- Invalid context or association rejects without rewriting the input; provider failures
  retain their cause, retry class and delivery facts.
- Cancellation remains the provider port's separate `Cancelled` error, never a failure
  or count.
- The result copies scalar facts and borrows the original identity owners, not the
  observation container; it needs no `deinit`.
- Those owners must outlive the result.
- Validation is repeatable and performs no call, lease consumption, clock read, capacity
  check, token charge or lifecycle transition.
- Current-ledger checks reject terminal operations; one-time completion remains the
  existing lifecycle CAS's responsibility, not a second consumption ledger.

**Implemented count YAML integration:** `count-model-input-tokens` consumes the
current request ledger, prepared request, applied attempt, invoked count operation
and prepared authorization result. It calls the existing action once. Its
`provider_token_count_result` owns the raw outcome and retains the original
request/binding owners before calling the port. The shared call binding also owns
inference results; there is no second provider dispatcher.

- `validate-model-token-count-observation` consumes that result and exact invoked
  request/attempt association.
- It publishes `provider_token_count_validation_result`: validated count/failure facts,
  typed association rejection, or cancellation.
- The validation result independently retains the original request/binding owners; it
  need not retain the raw observation container.
- Revalidation makes no API call or token charge.

- `complete-count-operation` consumes the validated result with the current invoked
  operation and applied attempt.
- The existing lifecycle action/runner publishes the canonical terminal record:
  `counted(input_tokens)`, original failure facts, or `cancelled(accepted_or_unknown)`.
- It invalidates invocation evidence and releases unused lease backing through the
  existing table.
- `complete-count-request` consumes the matching terminal operation and validation
  result, reusing request lifecycle closure only for failure or cancellation.
- All associated operations must be terminal.
- Count success cannot accept the logical request; inference still needs its own
  explicit assignment and lease.

- All four operations are parameter-free.
- Missing, foreign, stale, rejected or duplicate completion evidence fails closed.
- No count step alters token usage, adds a capacity gate, retries, renews a deadline,
  persists state or selects its successor.
- Retry and cleanup transitions remain explicit in the compiled YAML.

- Authorization failure before the first provider call leaves the logical request
  `assigned`; a typed terminal outcome uses an amended `assigned ->
  terminal(not_invoked_authorization_failure)` transition, while the already reserved
  attempt remains consumed.
- A failure after logical `assigned -> invoked` leaves the request invoked only while
  explicit YAML selects further permitted work; otherwise a terminal action closes it.
- Cancellation before the first call closes the assigned operation as not sent, then
  closes the request as cancelled.

- Optional count and inference IDs can share an ordinal but have distinct kinds.
- Count evidence does not assign or authorize inference.
- Retry requires the YAML-selected instance's explicit `retry-limit` and a new ordinal;
  no count, inference, fallback or retry is hidden inside an adapter.

- `PrepareProviderOperationAuthorizationAction` depends only on the provider-neutral
  `ProviderOperationAuthorizationPort`.
- The runner first allocates a single-use slot in its private
  `ProviderAuthorizationLeaseTable`.
- The action supplies that slot plus F0006 closed binding/request/operation facts; the
  infrastructure adapter deposits one move-only prepared capability and returns bounded
  observation/evidence.
- The action's `NodeDelta` contains only an opaque
  `ValidatedProviderAuthorizationLeaseRef` bound to the provider, operation ID, binding,
  `ModelVisibleInputId`, and deadline.
- The capability itself never enters the immutable `PipelineEnvelope`.

- At the provider call, the concrete adapter uses a narrow runner-owned
  `ProviderAuthorizationLeasePort` to compare-and-swap consume that exact lease once.
- The capability moves from the private table to the adapter; the adapter destroys it
  after the one call.
- If it is never consumed, the table owns and destroys it on cancellation, failure,
  attempt termination, or runner cleanup.
- A stale, mismatched, reused, or already-finalized reference fails before send.
- The table is one-purpose and operation-keyed, not a service locator or generic
  capability store.
- Provider-specific credential and signing types remain wholly inside infrastructure.

- The implementation separates the adapter's deposit-only slot from the action's
  slot-bound reference publication.
- The YAML binding retains that reference in the closed `provider_authorization_result`;
  the runner validates/applies its normal `NodeDelta`.
- The backing capability never enters a pipeline value.
- Reference tokens contain no payload, retain identity through immutable value copies,
  and remain distinct while any owner retains them.
- Consumption joins the current invoked ledger record, exact binding/input/provider and
  deadline, then transfers ownership once.
- Preparation failure, expiration, cancellation and operation terminalization release
  unused backing; consumed backing is destroyed by the adapter.
- The lifecycle runner destroys its table before its ledger and canonical request
  identities.
- Leases are execution-local and never restored by a later invocation.
- There is no provider-recovery storage contract.

- The minimum v1 authorization path uses already loaded, non-refreshing material and
  performs no filesystem, process, metadata, STS, or refresh I/O.
- If an accepted credential policy later permits any such effect, each effect first
  requires its own closed operation identity, lifecycle, budget, explicit retry policy
  and terminal accounting within the current execution.
- It cannot be hidden inside authorization preparation or a model operation.
- The envelope-visible lease reference contains no credential bytes, provider client, or
  operation capability and is harmless without the runner-private table.

The interface is a narrow behavioral port with compile-time conformance:

```text
port LLMProviderInterface {
  countInputTokens(
    binding: ValidatedProviderModelBinding,
    request: IdentifiedProviderNeutralModelRequest,
    authorization: ValidatedProviderAuthorizationLeaseRef,
    operation: InvokedProviderOperation
  ) -> ProviderTokenCountObservation

  invoke(
    binding: ValidatedProviderModelBinding,
    request: IdentifiedProviderNeutralModelRequest,
    authorization: ValidatedProviderAuthorizationLeaseRef,
    operation: InvokedProviderOperation
  ) -> ProviderInvocationObservation
}
```

- The implementation mechanism exposes no unbounded `anytype`, `anyopaque`, generic
  capability bag, provider-client type, credential material, or unrestricted
  infrastructure capability across the port.
- The authorization argument is only a typed single-use lease reference; concrete
  infrastructure consumes its private backing through the narrow lease port.
- Operation context otherwise contains only typed identity, cancellation and absolute
  deadline.
- It contains no filesystem, process, state, transaction, logger, command, completion,
  child-node, or unrestricted tool capability.

- Each method performs zero or one declared provider API request.
- Zero is allowed only for a typed pre-I/O rejection such as a registered unsupported
  operation.
- Automatic SDK/client retry, backoff, fallback, and failover are disabled.
- An interface call cannot conceal credential acquisition, refresh, token counting, or a
  second inference request; a concrete provider must resolve such effects at separately
  accepted and accounted boundaries.

- `ExactInputTokenCountEvidence` binds a successful count to the exact
  `ProviderOperationId`, binding ID, and `ModelVisibleInputId`.
- That identity binds ordered model-visible content, controls, response-guidance mode,
  and the full response-schema identity shared by counting and inference; it is not a
  provider wire-request digest because count and inference wire shapes differ.
- A different binding, content projection, control, schema mode, schema, or attempt
  invalidates the optional count evidence.
- Unavailable counting rejects only a requested count operation; inference neither
  accepts nor requires count evidence.

## 8. Closed request, observation, and failure algebra

**Protocol correction:** Retain the original task input and latest rejection;
use the owning attempt-accounting step's explicit retry limit. Strict decoding
and schema validation remain mandatory; schema-valid output is only a candidate.

- `IdentifiedProviderNeutralModelRequest` contains only engine-assigned request,
  workflow-operation identity, binding, request-schema, result-schema, and
  `ModelVisibleInputId`; ordered system/guidance and user/evidence content; the exact
  complete `model-envelope/v1` response schema; and supported engine-selected controls.
- It contains no provider URL, arbitrary provider map, credential, path capability,
  command, logger, state writer, transaction, or tool definition.

- Those identities belong to the internal request, not automatic model-visible fields.
- [ADR 0006](../decisions/0006-minimal-model-response.md) defines the complete response
  as the workflow's compact result object: no outer result/payload wrapper, echoed
  identity or version.
- Only a multi-variant result requires a root `kind`.
- The runner carries the exact association from request through validated observation,
  decode and candidate consumption; necessary domain selections and citations remain in
  model content.

- Request preparation consumes existing request-binding evidence, the validated model
  binding, runner-supplied request-schema/input IDs, the selected compiled result-schema
  resource, and explicitly ordered content.
- The builder copies content and transient IDs without adding guidance, duplicating
  schema text, or allocating execution identities.
- Canonical request identity, binding identity and the exact compiled schema remain
  borrowed execution authorities; their owners outlive the prepared request.
- Its arena has one explicit cleanup owner.
- Prepared-request checks reuse the shared identity, binding, control and schema
  validators.
- They grant no send authority or token allowance and enforce no request/response size
  ceiling.
- These pure checks do not reserve attempts, prepare leases or call a provider.
- Native YAML preparation bindings implement this handoff, inference, observation
  validation, JSON decoding and payload-schema validation under ADR 0012.
- The fixed internal content contract is `model-request/v1`: the selected prompt is
  guidance and an optional declared data resource is user content.
- The builder adds no instruction text or metadata echoes.

Provider observations are closed tagged unions:

```text
ProviderTokenCountObservation =
  | counted {
      operationId,
      bindingId,
      modelVisibleInputId,
      inputTokens
    }
  | failed { failure }

ProviderInvocationObservation =
  | completed { operationId, rawResult }
  | failed { failure }

ProviderNonCandidateStopReason =
  output_limit | content_filtered | unsupported_tool_request |
  malformed_output | context_limit

RawProviderModelResult =
  | complete {
      requestId,
      bindingId,
      content: CompleteOwnedUtf8,
      usage,
      providerLatencyMs?
    }
  | stopped {
      requestId,
      bindingId,
      reason: ProviderNonCandidateStopReason,
      usage,
      providerLatencyMs?
    }
  | rejected {
      requestId,
      bindingId,
      reason: invalid_content | missing_final_text,
      usage,
      providerLatencyMs?
    }

ProviderFailureCause =
  authentication_failed | authorization_denied | request_rejected |
  model_unavailable | throttled | timeout | service_unavailable |
  transport_failed | response_invalid |
  exact_token_count_unavailable

ProviderRetryClass = never | policy_eligible

ProviderDeliveryDisposition =
  not_sent | response_received | accepted_or_unknown

ProviderFailure {
  operationId: ProviderOperationId,
  cause: ProviderFailureCause,
  retryClass: ProviderRetryClass,
  delivery: ProviderDeliveryDisposition,
  content?: invalid_content | missing_final_text
}
```

`ProviderInvocationObservation.completed` means the provider operation returned
a complete recognized terminal response; it does not mean candidate or
workflow completion. The nested `RawProviderModelResult` tag decides whether
content exists.

- `ProviderFailure.operationId.kind` is the single operation-kind authority; an
  observation carries no second identity that could disagree.
- `not_sent` is provable only when no request byte left the process.
- A decoded provider response is `response_received`; interruption after transmission
  begins is `accepted_or_unknown` in that execution's observation.
- These classifications support diagnostics and current-execution control, not restart
  recovery.

- The whole workflow execution is atomic under ADR 0009.
- Provider attempts, operations, observations and leases remain in memory for that
  execution.
- Failure, cancellation or interruption abandons it; a later invocation starts at the
  compiled `start` step with fresh lifecycle and token accounting.
- It never restores a provider response, resumes an operation or consults a durable
  send/result marker.
- A full rerun may repeat API calls and incur cost again.

- There is no provider-effect journal service, persisted attempt/operation record
  schema, recovery action, storage-ownership decision or durable-result handoff.
- Do not introduce the same machinery beneath feature transaction storage.
- A model-capable workflow has no active-feature prerequisite solely for provider
  storage.
- Its declared domain gates and provider capabilities still apply.

Every terminal lifecycle fact retains delivery disposition, including
cancellation outside `ProviderFailure`. An API request already sent cannot be
undone; it does not make any candidate workflow output successful.

- All `RawProviderModelResult` variants contain only engine-supplied identities,
  bounded nonnegative usage, and optional bounded latency; none accepts an identity
  from the provider.
- Only `.complete` owns UTF-8 content.
- `.stopped` and `.rejected` contain no content member, so a missing/non-text provider output cannot be
  represented by an empty-string sentinel.

- `.stopped` publishes no candidate to `DecodeModelEnvelopeAction`.
- A `.complete` result is still untrusted candidate data.
- Native structured output is only a transport optimization: the engine validates the
  exact runner-owned observation/request association, then decodes and validates the
  complete compact result, semantic assertions and no-invention requirements.
- It never correlates from echoed IDs or attaches unbound bytes to the latest request.

- The observation validator joins the retained prepared request to its immutable
  invoked-operation ledger record, including binding and input identity.
- The exact input and compiled schema remain request-owned authority, never model
  echoes.
- Shared invocation, usage and UTF-8 validators supply the checks; no size ceiling, JSON
  parsing, size proof or accounting mutation is introduced.
- Identity/usage rejection returns a typed error without evidence.
- Valid usage survives content rejection as `response_invalid`, with `response_received`
  delivery and no candidate.
  Raw `.rejected` preserves independently decoded usage until the shared association
  and usage validator admits it. The resulting failure retains the content diagnostic
  and transport retry class `never`. The user-approved missing-answer amendment
  permits only validated `missing_final_text` with known usage to enter explicit
  workflow protocol correction (§22.6); it creates no candidate or call permission.
  All other rejected content remains terminal. The existing runner allowance,
  authorization lifecycle and total-token budget govern any further call.
  Its declared envelope history retains the same immutable evidence owner through
  transport/current-slot retirement for reports, without another accounting ledger.
- Provider-reported size rejection uses the existing API-failure mapping; a provider
  output/context stop stays a stopped result.
- No local `request_limit_exceeded` or `response_limit_exceeded` cause remains.
- Other provider failures retain their exact cause/retry/delivery facts and have no
  fabricated usage.

- One owned immutable evidence object retains the validated metadata and borrows the
  request and complete response bytes; those owners must outlive it.
- Only its complete branch exposes the sealed decoder input.
- Validation never consumes or frees the raw observation, including on rejection or
  allocation failure.
- Usage is available independently for the existing accounting action; evidence does not
  prove budget reconciliation or candidate schema validity.

- `DecodeModelEnvelopeAction` accepts only that sealed complete branch.
- It reuses the strict JSON syntax boundary with result-schema transport, accepts one
  object with optional JSON whitespace, and rejects duplicate decoded keys at every
  depth, malformed JSON, non-object roots, fences and trailing content.
- Parsing uses the schema profile's 64-level JSON nesting guard, not an output-byte
  ceiling.
- Numeric lexemes remain exact; no rounding, coercion, JSON extraction, wrapper
  insertion or schema validation occurs here.

- The decoded candidate owns one parse tree and exposes only read-only object, array and
  scalar views.
- It borrows the original invocation evidence, whose request/graph/observation owners
  must outlive it; it creates no competing identity or schema authority.
- Rejection and allocation failure free partial trees without consuming that evidence or
  its response bytes.

- `ValidateModelPayloadSchemaAction` validates the complete supported profile against
  that retained compiled schema without reparsing or rechecking call association.
- It checks required/unknown properties, scalar types and bounds, all array items,
  constants, enumerations and the exact declared alternative.
- Optional fields remain absent; no defaults, coercion, field dropping or schema
  selection from model content occurs.
- String lengths count Unicode scalars.
- Following the profile's [JSON Schema numeric
  semantics](https://json-schema.org/understanding-json-schema/reference/numeric),
  integer candidates are checked by exact value, including decimal/exponent spellings
  such as `1.0` and `1e0`; no floating-point rounding or conversion of numeric strings
  is permitted.
- Schema bounds/constants retain their existing signed-64-bit literal contract.

- Validation returns either an opaque, allocation-free view of the same decoded
  candidate or one closed rejection reason.
- One invalid member rejects the whole result; no partial proof is published.
- The proof borrows its existing owners and changes no candidate, usage, lifecycle or
  execution state.
- Schema validity proves neither semantic correctness nor permission to commit.
- The native YAML binding retains the candidate's existing owner and preserves
  non-decoded outcomes without invoking this validator.

- Explicit cancellation remains terminal `cancelled` and is propagated outside the
  failure union.
- Provider failure is never converted to the model-content `invalid` state because
  `invalid` enters schema/semantic repair.
- A provider operation returns the closed `retryClass` and delivery disposition; the
  compiled YAML transition may pass those facts to an explicit retry operation allowed
  by policy.
- Terminal-outcome actions construct the corresponding delta; the runner only
  validates/applies it and never chooses `blocked`, `failed`, `cancelled`, retry, or
  fallback.

## 9. Action and orchestration ownership

| Owner | Sole responsibility |
| --- | --- |
| `DeriveProviderRequirementAction` | Return `required` when the selected compiled graph contains typed model-binding requirements or the exact compiler-owned `model-provider` capability; otherwise return `not_required`. |
| `LocateLLMProviderConfigAction` (F0008) | Open only the exact F0004-authorized no-follow regular file. |
| `ReadLLMProviderConfigAction` (F0008) | Capture that already-opened file completely under its fixed bound. |
| `LLMProviderConfigService` (F0008) | Own the complete capture and expose immutable untrusted bytes without I/O or parsing. |
| `DecodeLLMProviderConfigAction` | Decode strict JSON and the exact common container into bounded untrusted raw identities/config objects; grant no provider authority. |
| `BuildLLMProviderRegistryAction` | Resolve discriminators, decode each closed provider config variant, and join entries to model contracts. |
| `ValidateLLMProviderRegistryAction` | Validate the whole candidate and total resource accounting. |
| `ValidateRepositoryModelAllowlistAction` | Join the entire F0001 `models.slots` map to the validated provider catalogue and emit only immutable slot-to-entry references; reject the whole allowlist if any tuple is absent or ambiguous. |
| `ModelProviderBootstrapRunner` | Invoke the fixed child bindings, apply their pipeline deltas, own every intermediate, and map each rejected boundary to its existing provider-bootstrap diagnostic. It delegates provider-file location/read sequencing to F0008 rather than duplicating it. |
| `ModelProviderBootstrapServices` | Keep the validated registry and repository allowlist alive as one immutable invocation-owned authority and destroy the allowlist before its referenced registry. |
| `ModelProviderBootstrapBinding` | Give the invocation runner one typed post-selection child boundary without exposing filesystem or provider capabilities. |
| Provider-bootstrap composition assembly | Construct the concrete F0008 adapter and config/provider runners, then invoke the fixed orchestrator; perform no selection or branching. |
| Engine invocation runner | Invoke provider preparation after exact selection, preserve its typed outcome, retain `ready` services through workflow execution, and make workflow execution unreachable after failure or cancellation. |
| `ResolveProviderModelBindingAction` | Resolve one compiled workflow operation's YAML-declared slot through `ValidatedRepositoryModelAllowlist` to its registry entry and supported controls; never accept a raw provider/model tuple or hidden route as authority. |
| `BuildImmutableUnitOwnerIdAction` | Validate a generic compiled-step owner or the required closed SDD unit-owner tuple; generic ownership never supplies SDD repair/review/clarification authority. |
| `BuildInitialModelRequestIdentityLedgerAction` | Create a fresh process-local execution epoch and the sole empty immutable request ledger for its closed purpose registry. |
| `AssignModelRequestIdAction` | Allocate one purpose-bound ordinal from the current ledger revision and return an immutable successor; never mutate the current ledger or reassign a protocol retry. |
| `ValidateModelRequestBindingAction` | Prove exact ledger membership and epoch/unit/workflow-operation/purpose/ordinal binding without changing the ledger. |
| `BuildModelRequestAction` | Build one identified provider-neutral request; keep execution identity internal and project only needed guidance/evidence and the exact compact result schema. |
| `AdvanceModelAttemptAccountingAction` | Reserve the initial complete provider-attempt ordinal, or a later ordinal only under the YAML-selected operation instance's explicit compiler-validated `retry-limit`; it applies no workflow-global attempt ceiling. |
| `CheckWorkflowTokenBudgetAction` | Read the execution's actual-usage ledger and reject further provider calls when the total is at or above budget or usage is unavailable; reserve nothing. |
| `ReconcileWorkflowTokenUsageAction` | Propose once-only recording of validated API input/output usage or a proven not-sent/unavailable disposition; the runner retains an overshoot before returning the budget error. |
| `AdvanceModelRequestLifecycleAction` | Propose the amended logical request compare-and-swap transition. |
| `AdvanceProviderOperationLifecycleAction` | Propose one execution-local count/inference lifecycle compare-and-swap transition; perform no I/O. |
| `PrepareProviderOperationAuthorizationAction` | Fill one runner-private operation-bound lease slot through the provider-neutral preparation port and return only validated opaque lease-reference evidence. |
| `CountModelInputTokensAction` | Make exactly one interface count call for an already invoked count operation. |
| `ValidateModelTokenCountObservationAction` | Validate a separately requested count observation against its operation, binding and input; impose no token/context ceiling or inference prerequisite. |
| `InvokeModelAction` | Make exactly one interface inference call for an already invoked inference operation. |
| `ValidateProviderInvocationObservationAction` | Validate the exact runner-bound operation/request/input/schema/model association, delivery, stop, usage, UTF-8 content, and complete-candidate eligibility before decoding. |
| `DecodeModelEnvelopeAction` | Parse one complete compact JSON object and retain its bound schema and validated invocation association; never invoke a provider or recover IDs from model content. |
| `ValidateModelPayloadSchemaAction` | Validate the decoded result against only its bound closed schema; do not repeat parsing or trusted call-association checks. |
| Pipeline runner | Invoke bound children; own the per-execution token ledger, private authorization-lease table; validate/apply deltas, lifecycle compare-and-swap transitions, explicit operation-local retry accounting, actual token-usage reconciliation and pre-call budget guards, deadlines, and cleanup; choose no workflow branch. |

- `ModelProviderBootstrapOrchestrator` coordinates only the requirement and
  provider-file child bindings described in Section 5.
- It is engine preparation, not workflow behavior.
- Provider retry, fallback, and protocol-retry branches must each be visible as YAML
  steps and transitions; their registered generic operations perform one bounded
  responsibility and never select a successor.

No action invokes another action or selects its successor. Every orchestrator
receives only runner-owned child bindings and typed outcomes. It has no
provider, network, credential, tokenizer, registry-mutator, parser, logger,
filesystem, process, state, transaction, or command capability.

## 10. Diagnostics, security, and cleanup

The accepted provider-file diagnostics are:

| Code | Meaning |
| --- | --- |
| `LLM_PROVIDER_CONFIG_READ_ERROR` | The exact required file cannot be safely and completely located or read under the no-follow and size contract. |
| `LLM_PROVIDER_CONFIG_PARSE_ERROR` | Bytes do not decode as strict JSON with the exact closed common container and bounded raw `config` objects. |
| `LLM_PROVIDER_REGISTRY_INVALID` | A registered provider-config variant, model/contract join, capability, target policy, bound, uniqueness, discriminator, or total-accounting proof fails. This includes an unimplemented provider in an otherwise structurally decoded file. |
| `LLM_PROVIDER_MODEL_BINDING_INVALID` | Any repository slot's provider/model/options tuple does not resolve exactly in the complete validated catalogue; the complete allowlist is rejected. |

Runtime failures use only the Section 8 union and bounded public rule evidence.
They contain no raw request/response body, arbitrary provider JSON, header,
credential, environment value, signature, canonical request, unrestricted URL,
or provider error text.

Authorization references and private capabilities are never persisted. Each
execution owns and destroys its lease table; a new execution constructs a new
one. Logs cannot act as send, result or continuation authority.

Only concrete infrastructure adapters import provider clients, networking,
TLS, signing, or credential sources. Application and domain code import only
the common port and typed values. A provider adapter has no filesystem,
command, project-state, workflow, transaction, log-sink, or child-node
capability.

Ordinary metadata logs never contain raw provider bodies. Under
[ADR 0018](../decisions/0018-debug-model-exchange-logging.md), debug/trace captures
complete serialized model-facing requests and available raw provider bodies through
a composition-injected narrow observation port. The common runner owns attribution
and lifetime; the capture runner and active logging lifecycle own redaction, bounded
lossless fragments and persistence. Providers receive no sink, child bindings or
business graph control. A typed body variant distinguishes provider bytes from
engine-authored no-response transport diagnostics. Higher thresholds emit metadata
only. Logs have no retry, validation, provider, or workflow authority.

- Every raw/configured/validated request buffer, response buffer, binding, transport
  handle, authorization table slot/capability, lease reference and observation has
  explicit ownership and deterministic cleanup on success, rejection, timeout,
  cancellation and operational error.
- No failed bootstrap retains a partial or last-known registry; no failed provider
  operation retains a stale successful response.

## 11. Explicit non-responsibilities

F0006 does not:

- define workflow semantics, prompts, guidance, or response payload schemas;
- choose a workflow operation, slot, provider, model, fallback, or retry;
- decode or validate an SDDE model envelope;
- perform semantic review, no-invention routing, or repair;
- expose provider-native tools, agents, browsing, filesystem, or commands;
- define credentials inside either project configuration file;
- permit project-defined provider implementations or dynamic libraries;
- provide a built-in model route, hidden slot assignment, prompt, schema, or workflow branch; or
- select an AWS SDK, HTTP/TLS/signing library, linking mode, credential policy,
  or platform matrix.

## 12. Acceptance criteria

1. Accepted authority names `LLMProviderInterface` as the sole
   provider-neutral model port; no alternate alias remains.
2. The bootstrap root registry reserves the exact `paths.providers` path
   unconditionally; the fixed run-preparation orchestrator conditionally asks F0008 to
   load only that `.sddproviders.json` file, and no provider reads it independently.

   - Full host/target collision proof keeps that file role distinct from engine config
     and every configured/derived root even when loading is skipped.
3. The document has exactly the bounded
   `providers[] -> { provider, models[] -> { model, config } }` shape, and every
   common object and resolved provider variant is closed at its owning boundary.
4. Capabilities, operations, tokenization, structured response, target,
   endpoint, and data-routing facts come only from compiled model contracts.
5. The repository example selects a registered Bedrock model/configuration and
   validates against the production contracts. It is never a runtime default
   or fallback.
6. If the selected compiled graph has neither model-binding requirements nor the exact
   `model-provider` capability, file probing/loading is unreachable; otherwise the
   entire exact file must validate before selected-workflow execution.

   - A required branch captures it once; no active invocation rereads or refreshes that
     snapshot, and no prior invocation supplies a fallback.
   - Provider failure or cancellation makes every selected-workflow child unreachable;
     prepared authority remains alive until workflow execution returns.
7. One invalid or unsupported sibling publishes no partial registry.
8. Every `.sddtoolkit.json` slot tuple and its options resolve exactly to one registry
   entry, compiled model contract, and exhaustive provider discriminator.

   - Slots may reference some or all catalogue entries, never an absent entry; an
     unreferenced catalogue entry is not repository-authorized.
   - The one validated allowlist stores slot-to-entry identities without copying
     provider configuration or contract facts.
   - No adapter/client is stored in registry or pipeline data.
9. Project configuration contains no secret, executable behavior, arbitrary
   endpoint, retry policy, header, wire parameter, or capability claim.
10. Registration and request preparation require no capacity configuration.

    - There are no additional canonical, serialized request/header, response or
      provider-wire byte ceilings, size estimates, token/context preflight or pre-call
      reservations.
    - Reject retired size parameters.
    - Provider APIs own their size limits and the engine propagates their errors/stops.
    - Model-request IDs are engine-assigned from one immutable run-local ledger by exact
      revision; execution, originating compiled step, unit/purpose authority where
      required, and ordinal validate before construction.
    - Generic requests need no SDD owner.
    - Explicit consumer steps retain one immutable request association; they cannot
      rebind its model or resources.
    - The selected workflow policy contributes the only workflow-global limit: one
      positive total model-token budget initialized independently for each workflow
      execution.
11. Inference works without a count operation or count capability.

    - Optional count observations remain bound to their operation, binding and input,
      but do not authorize or prohibit inference.
    - Count-action fake-provider tests prove exact pointer/observation forwarding, zero
      and maximal counts without capacity checks, all closed failure facts, unchanged
      request/attempt/operation ledgers, single-use authorization, foreign/substituted
      evidence rejection, deadline and cancellation behavior, unsupported counting and
      allocation-error propagation with one cleanup owner.
    - Count-validation fake-provider tests prove exact evidence reuse, zero/maximal
      counts, all failure facts, rejection of foreign/copied request IDs, wrong
      attempts/kinds/bindings/inputs, invalid request context and non-invoked or
      terminal operations.
    - Independently allocated observation identities can be freed after either the
      shared constructor or action returns.
    - Validation retains no observation allocation, changes no ledger and works after
      lease consumption/deadline expiry or token exhaustion.
    - Cancellation produces no observation; cleanup remains exactly once.
    - Fake-provider YAML evidence additionally covers raw/validated owner retention
      beyond runner cleanup, count completion and failure/cancellation request closure,
      missing/foreign/stale/duplicate evidence, explicit retry exhaustion, independent
      execution ledgers, cancellation boundaries and allocation failure.
    - A count-then-inference graph uses separate leases on the same attempt and charges
      only actual inference usage.
    - Registry/compiler and clean packaged tests reject hidden operations, parameters
      and missing prerequisites.
12. Request identity, binding, schema and control validation precede one reserved
    full-attempt ordinal.

    - Every later ordinal requires a YAML-selected retry operation with its explicit
      compiler-validated `retry-limit`.
    - Provider size rejection consumes the attempted operation and retains its response
      delivery classification.
    - Count and inference operations each have a distinct execution-local
      identity/lifecycle transition; no hidden retry, size preflight or count
      prerequisite exists.
    - Native YAML accounting is implemented: retained binding, fresh epoch-bound
      ledgers, initial/retry classification, compiler-permitted delta application,
      sealed applied evidence, explicit retry exhaustion, cancellation, allocation
      cleanup, and rejection of forged/stale/cross-execution associations are tested.
    - Native assignment is also implemented for both operation kinds: exact retained
      associations, immutable applied evidence, duplicate/open-operation rejection,
      compiled permission checks, cancellation and allocation cleanup.
    - YAML logical-request invocation retains that association through an exact ledger
      successor, with prepared-lease guards before execution/publication; stale
      snapshots, wrong requests, disguised assignments and skipped revisions reject
      without publishing an invocation state or performing a provider call.
    - YAML provider-operation invocation requires that applied logical-request state and
      the original prepared lease deadline.
    - Only runner application publishes canonical invoked evidence and invalidates
      assignment evidence.
    - Forged transitions, deadline replacement, stale/foreign evidence, duplicate
      invocation, rejected deltas and cancellation cannot publish a successor.
    - Both operation kinds retain the unconsumed lease and zero token usage; allocation
      failures and retained-evidence destruction release owners once.
    - Native YAML inference proves one provider call, no count/fallback/retry, exact
      retained association and lease consumption, preserved complete/stopped/
      failed/cancelled outcomes, token equality/overshoot/unavailable handling,
      post-call cancellation/deadline/delta rejection without lost usage, allocation
      cleanup and fresh execution identity/usage.
    - Budget rejections reach the top-level result without selecting a declared failure
      edge.
    - Native YAML observation validation preserves complete/stopped/failed/cancelled
      facts, rejects foreign associations and unsafe UTF-8, and retains the exact
      request/response owners.
    - Tests prove no decoding or second token charge, validation at exact budget
      exhaustion, missing-input/override rejection, allocation cleanup and evidence
      lifetime after source-value cleanup.
    - Native YAML decoding proves strict object parsing, exact numeric lexemes,
      malformed/duplicate/trailing-content rejection, unchanged non-complete outcomes,
      missing/foreign-evidence rejection, and cleanup of parsed trees and retained
      evidence.
    - Parsing does not validate payload schema, charge tokens again or repeat a provider
      call.
    - Protocol rejection remains `invalid`.
    - Native YAML payload-schema validation proves exact retained-schema selection,
      valid/invalid payloads, unchanged protocol/provider/cancellation outcomes,
      missing/foreign-evidence and override rejection, retained candidate lifetime,
      allocation and rejected-publication cleanup.
    - It remains available at exact token-budget exhaustion without another charge or
      provider call.
    - Native YAML operation completion proves exact canonical terminal evidence,
      retained stop/failure/cancellation facts, content-validity independence,
      missing/foreign/stale/duplicate/rejected-evidence rejection, forged terminal and
      suppressed-outcome rejection, allocation/cancellation cleanup and owner lifetime.
    - Completion at token exhaustion or after the call deadline adds no charge, call,
      retry or logical-request transition.
    - Native YAML logical-request closure proves evidence-derived accepted, failed and
      cancelled reasons while preserving invalid/failed/cancelled outcomes, exact ledger
      replacement, all-operation closure, missing/foreign/ stale/duplicate evidence
      rejection, forged reason/outcome rejection, cancellation and allocation cleanup,
      and retained owner lifetime.
    - It works at token exhaustion without a live lease or provider deadline and grants
      no semantic or workflow-success authority.
    - Native YAML pre-call termination covers both operation kinds, exact failure and
      cancellation facts, prepared/missing/foreign/stale/duplicate rejection, forged
      deltas/outcomes, retained owners, deposited-capability and allocation cleanup, and
      zero provider calls/token charges.
    - Terminal fact consumers need no clock but cannot mix lifecycle phases or bypass
      prepared-lease checks.
    - Runtime cancellation performs no hidden termination or logical-request closure.
    - Native YAML pre-call request closure covers both operation kinds and request
      states, exact failure/cancellation reasons, all-operation terminality,
      prepared/missing/foreign/stale/duplicate/inconsistent evidence rejection, forged
      successors/outcomes, cancellation and allocation cleanup, retained owner lifetime
      and unchanged token usage.
    - Hidden YAML assertions and altered compiled contracts reject; packaged execution
      rejects missing prerequisites.
    - A full fake-provider YAML run closes a previously invoked request after later
      authorization rejection, retaining its earlier response and single usage charge.
13. Each call performs zero or one provider request with no hidden retry,
    fallback, backoff, credential acquisition/refresh, or second operation;
    any permitted credential I/O has separate accepted accounting.
14. Only an opaque validated lease reference enters the pipeline envelope; its
    move-only authorization capability stays in a single-use runner-private
    table with compare-and-swap consume and one cleanup owner.
15. Attempts and operations exist only within their workflow execution.

    - A crash abandons that execution.
    - A subsequent invocation starts at `start` with fresh identities, leases and token
      usage, without a journal read, response restoration or saved-step continuation.
    - A full rerun may repeat API calls; no feature-storage capability is required
      merely to call a model.
16. Only the compiled YAML graph may choose an explicit registered retry
    operation, and every retry-capable operation instance supplies its own
    bounded `retry-limit`; no workflow policy, configuration file, provider, or
    runner supplies a retry default. Every retry uses a new ordinal, and an
    accepted-or-unknown delivery never auto-replays.
17. Provider failures never enter model-content repair or become `invalid`.
18. Only `complete` UTF-8 content reaches envelope decoding, where the complete compact
    result remains untrusted and authoritatively validated under ADR 0006.

    - Execution metadata is runner-owned; unbound observations, undeclared/mixed
      variants, unknown/duplicate fields and the superseded wrapper form reject.
    - No missing citation or target selection is supplied by guessing, and no
      metadata-echo compatibility reader exists.
19. No provider operation receives filesystem, process, state, transaction,
    logger, command, completion, child-node, or unrestricted tool capability.
20. Credentials, signatures, raw bodies, headers, arbitrary provider metadata,
    and environment values never enter canonical state or ordinary logs.
21. The fake provider conforms to the same interface and keeps all model
    workflow increments deterministic without network access or credentials.
22. The packaged native executable needs only accepted target-owned runtime
    inputs, never repository examples, source files, build cache, or Zig.
23. Production composition installs real contracts and authorization/count/
    inference implementations through the sole port. Shared fake/Bedrock tests
    prove association, usage, failure/cancellation, deadlines, single-use leases,
    secret handling and cleanup. YAML tests prove complete lifecycle, execution
    isolation and token-budget enforcement with a deterministic HTTP seam;
    live AWS requests remain separately authorized.

## 13. Verification

Implementation evidence must cover:

**File boundary**

- unconditional configured-path registration
- exact F0004-capability lookup
- graph bypass only with neither binding requirements nor provider-call capability
- pure binding-only graph preparation without a provider port
- provider calls still denied by a capability-free policy
- exactly one capture for a required branch
- immutable registry/allowlist after capture despite a later backing-source change
- no active-run reread, refresh, monitoring, last-known fallback, or cross-invocation
  cache
- missing, parent/child/example fallback, wrong kind, symlink, permissions, short read,
  file growth/shrink, exact/over size, collision with engine config and every
  configured/derived root by exact/case/normalization/alias/ containment equivalence,
  cancellation, and deadline.

**JSON/registry**

- raw common decode versus closed variant-build diagnostics
- reordered fields
- empty, maximum, and over-limit collections
- duplicate keys/identities
- unknown provider/config/field
- malformed UTF-8/JSON
- unimplemented OpenAI entries
- invalid sibling with no partial registry
- exact ownership and cleanup.

**Binding and provider-owned size limits**

- all-catalogue and strict-subset slot selections
- missing or ambiguous tuples
- one invalid slot rejecting the complete allowlist
- unauthorized unreferenced models
- unsupported options, targets, data policy and structured schemas
- registration without capacity fields
- rejected legacy size parameters
- exact serialization and complete valid responses beyond former byte ceilings
- provider-reported oversized-request failures and output/context stops
- no truncation or hidden fallback.

**Request and operation accounting**

- closed request-purpose registries
- malformed unit owners
- duplicate purpose entries
- unregistered or mismatched purposes
- independent monotonic ordinals
- stale ledger revisions
- foreign or altered request IDs
- exact canonical binding evidence
- distinct count/inference IDs and operation records beneath one attempt record,
  lifecycle CAS, request-validation ordering, provider rejection consuming the attempted
  operation, direct inference without counting support, optional count outcomes and
  exact association, every assigned-branch close, abandonment before send, after send
  and after response, and a new execution starting at `start` rather than restoring the
  old operation.
- No provider record, recovery lock or result marker is read or written.
- Every within-run retry receives a new ordinal
- every retry-capable operation instance declares and exhausts its own validated
  `retry-limit`
- missing limits and policy-supplied retry defaults are rejected, cancellation is
  terminal, and the client never auto-retries.
- Per-execution token-ledger evidence covers initial isolation, exact-budget stopping,
  retained actual overshoot before error, safe addition, once-only actual-usage
  reconciliation, no charge for proven non-delivery, unavailable-usage blocking without
  estimates, count-token non-duplication, and independence between two executions of the
  same workflow.

**Port conformance**

- identical golden provider-neutral cases through fake and real adapters
- closed stop/failure mapping
- complete response reads with cancellation/deadline enforcement
- malformed and partial observations
- complete cleanup on every terminal branch.
- Concrete HTTP acceptance uses in-memory connections beneath the same send/read and
  deadline code, proving in-flight interruption, rejected partial bodies, joined cleanup
  and no resend
- F0007 records the implemented evidence.

**Compact response**

- ADR 0006 single-shape and discriminated results, bound-identity swaps, strict
  whole-object parsing, required selections, keyed repair groups and
  clarification/context alternatives.
- Inspect actual model-visible payloads without reattached engine metadata and account
  for API-reported input/output usage
- test identical semantics in prompt-only and supported native mode without silent
  fallback.

**Architecture/security**

- dependency-import tests, fact-only registry, composition-injected common port,
  exhaustive private adapter dispatch, pipeline containing only authorization lease
  references, runner- private capability table one-use/cleanup tests, no operation port
  in an orchestrator or `NodeRuntime`, no provider imports outside adapters,
  secret/body/header canaries absent from state/logs, and F0002 fragment-only capture.

**End to end/packaging**

- fake-provider workflows first
- relocated target files
- clean native executable without source examples or development assets.
- Any live provider test is separately authorized, credential-gated, non-default, and
  excluded from deterministic CI.

## Implementation status

- Provider capture, decoding, registry construction and complete repository-slot
  validation run immediately after exact workflow selection through the fixed
  conditional bootstrap owner.
- The request-identity ledger owns assignment and binding validation without
  provider I/O.
- Production contracts, attempt/operation accounting, authorization and externally
  counted operations use the same execution-local boundaries.
- Native YAML connects retained requests, inference/counting, response validation
  and explicit lifecycle closure. Production Bedrock uses those contracts and
  runner bindings.
- Offline conformance and YAML tests establish mechanical boundary evidence;
  they do not establish live reliability or semantic quality.

## 14. Traceability

| Concern | Authority |
| --- | --- |
| Candidate-only LLM boundary | Design Sections 1, 3-4, 12, and 26.1 |
| Fixed conditional provider bootstrap and derivation | ADR 0004; Design Sections 3-6 and 13.1 |
| Common port, action, runner, and dependency direction | Design Sections 5-6 and 13.4; ADR 0001 |
| Current engine configuration ownership | Design Section 9; F0001; `design/paths.md` |
| Request/invoke/decode separation | Design Sections 12.1-12.4 and 13.4; `design/code.md` Sections 21-24 |
| Compact response and runner-owned correlation | [ADR 0006](../decisions/0006-minimal-model-response.md); Design Sections 12.3 and 22.4 |
| Workflow-operation limits, retry, fallback, and repair authority | ADR 0005; Design Sections 12.5-12.7 and 21-22 |
| Provider-owned size limits and actual workflow token accounting | [ADR 0011](../decisions/0011-provider-owned-request-limits.md); Section 6 |
| Atomic execution and fresh reruns; no provider recovery | ADR 0009; Design Sections 24–25 |
| Secret-safe logging | Design Sections 26.5 and 27; F0002 |
| Fake-first testing and native packaging | Design Sections 28 and 30-31 |
