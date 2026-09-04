# F0006 — LLMProviderInterface

**Status:** Accepted feature design

**Implementation readiness:** The configured provider-document path and
read-only byte service are accepted and implemented by F0001/F0004/F0008. The
strict common decoder, compiler-contract registry join, immutable
`LLMProviderRegistryService`, repository-slot allowlist, and YAML-declared typed
slot binding are accepted and implemented. The fixed conditional bootstrap owner
and exact provider-requirement derivation, immutable per-invocation provider
snapshot, orchestrator, runner bindings, and ordinary post-selection invocation
composition are accepted and implemented. Immutable unit-owner validation,
run-local model-request ledger initialization, purpose-bound request assignment,
and exact binding validation are also implemented. Amendments 7-11 were accepted
by explicit user direction on 2026-09-04, with authorization preparation
restricted to a preloaded, non-refreshing, no-I/O lease. The closed
provider-operation values, sole provider-neutral operation port, deterministic
fake provider, immutable model-request lifecycle advancement, and bounded
runner-owned model-attempt ordinal accounting are implemented. The legacy
global attempt ceiling has been removed: initial execution is accounted
separately and later attempts require compiler-proven operation-local retry
authority. The selected policy's positive total-token budget is compiled into
the graph, and each execution owns a fresh reservation/reconciliation ledger.
`AdvanceProviderOperationLifecycleAction`, its immutable execution-owned ledger,
runner application, and non-content journal intents are implemented. Request
finalization and attempt advancement reject unfinished provider operations.
Durable effect-journal integration, authorization storage, provider-call actions,
and production provider contracts remain implementation work.

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

The interface has one responsibility: execute one already selected, validated,
identified, and accounted provider operation through an immutable
provider/model binding and return one bounded provider-neutral observation. It
does not select a workflow operation, slot, or model, read configuration, acquire workflow
authority, interpret model content, or validate an SDDE candidate.

The F0006 feature also defines the separate bootstrap path that makes the port
usable. When the exactly selected compiled workflow requires model capability,
the engine consumes F0008's immutable bytes from the project-owned location
selected by `.sddtoolkit.json` `paths.providers`, decodes its one closed shape,
joins every entry to compiler-registered provider/model contracts, and
constructs one immutable `LLMProviderRegistryService`. Providers receive only
validated typed bindings; they never locate, read, parse, or reinterpret the
file.

`AWSBedrockProvider` is the first implementation. A later provider requires a
new compiled discriminator, closed configuration variant, provider/model
contracts, concrete adapter, exhaustive dispatch branch, composition-root
binding, and positive and negative conformance tests. Project data cannot add
executable code, dynamically load a provider, or create a capability.

## 2. Accepted amendments

Current authority now defines the exact project-root `.sddtoolkit.json`, its
required `paths.providers` member, F0004's opaque provider-document path
capability, F0008's bounded read-only byte service, the strict provider
catalogue, its immutable registry service, and the repository model allowlist.
It also accepts the fixed conditional run-preparation owner and exact
selected-graph requirement derivation. The runner bindings and immutable
per-invocation provider snapshot are implemented and invoked immediately after
exact workflow selection. The request-identity ledger now owns assignment and
binding validation without provider I/O. Production provider contracts,
attempt/operation accounting, and externally counted operations remain
undefined or incomplete.

The following amendments are accepted. Items marked implemented already have
runtime evidence; the remaining items define subsequent implementation work:

1. **Accepted by F0001/F0004/F0008:** require `paths.providers`, validate its
   normalized project-relative path and exact `.sddproviders.json` basename,
   reserve its opaque read-only capability unconditionally, and include it in
   the complete collision proof against `.sddtoolkit.json` and every configured
   root. F0008 alone locates and captures the file when the F0006 branch requests
   it;
2. **Accepted and implemented:** adds a fixed engine-owned,
   capability-free `ModelProviderBootstrapOrchestrator` after selected-workflow
   compilation and before selected-workflow execution. It coordinates
   runner-owned bindings for the conditional
   existence/read/decode/build/validate sequence in Sections 3-5 and 9; this
   explicitly amends the current fixed startup-graph authority rather than
   relying on runner convention;
3. **Accepted and implemented:** makes the closed document and registered
   provider-specific configuration union in Section 3 normative, including
   byte, collection, nesting, and identity limits;
4. **Accepted and implemented:** extends the public diagnostic vocabulary with
   the separately owned provider-file codes in Section 10 without reusing or
   broadening F0001's two reader codes;
5. **Accepted and implemented:** a required branch captures the provider file
   exactly once. The validated registry/allowlist derived from that capture are
   immutable for the remainder of the engine invocation; the untrusted bytes
   may be destroyed after preparation. The engine does not stat, reopen,
   reread, refresh, hot-reload, monitor, retain a last-known registry, or use a
   cross-invocation provider-registry cache. A later file change is visible
   only to a new invocation;
6. **Accepted and implemented configuration relationship:** `.sddproviders.json` is the
   configured provider/model catalogue, while current `.sddtoolkit.json`
   `models.slots` is the repository allowlist. Every slot's exact
   `(provider, model)` tuple must resolve to exactly one validated catalogue
   entry. Slots may select some or all catalogue entries, never an additional
   model; unused catalogue entries gain no repository authority. ADR 0005
   removes built-in routes: each YAML-declared generic model operation names
   one repository slot explicitly;
7. **Accepted, partially implemented:** amends
   `AdvanceModelAttemptAccountingAction`, design Sections 12.1 and 13.4, and
   `ModelRequestLifecycle` for the Section 7 full-attempt semantics:
   reserve the initial attempt once before the first external provider
   operation; reserve a later attempt only through a YAML-selected retry
   operation carrying its own compiler-validated explicit `retry-limit`; define
   count and inference operation lifecycles under that attempt; make
   preparation/count failure terminal and attempt-consuming; relate request
   `assigned`, `invoked`, and terminal transitions to those operations; and
   close every assigned/uninvoked branch. There is no workflow-global attempt,
   retry, unit-repair, or stage-repair ceiling. It also amends Sections 24-25 with the
   engine-owned provider-attempt/operation effect journal in Section 8: exact
   safe location, schema/version, split attempt/operation records, locking/CAS,
   write-before-send durability, terminal-observation/result-consumption
   handoff, retention/redaction, recovery scan, and cleanup;
8. **Accepted:** establishes `LLMProviderInterface` as the sole governing name
   in design, package, and architecture-test authority, without an alias; and
9. **Accepted:** updates packaged-executable acceptance criteria so a relocated executable
   can consume a target-owned provider file without a source-tree example; and
10. **Accepted choice:** provider authorization preparation is restricted to a
    preloaded, non-refreshing, no-I/O lease. A provider feature may define one
    narrow environment-only preloader outside authorization preparation. F0007
    fixes the Bedrock source to `AWS_BEARER_TOKEN_BEDROCK`; no repository input
    can name or contain the key. Credential file, process, metadata, STS, and
    refresh effects are not permitted; and
11. **Accepted:** exposes provider transport/auth/throttle/timeout outcomes to the compiled
   YAML graph, which alone may select an explicit registered retry operation;
   no provider or generation orchestrator hides that branch; and
12. **Accepted and implemented:** the selected workflow policy supplies the only
   workflow-global consumption limit: one positive total model-token budget
   initialized for each workflow execution. Before inference, the runner
   reserves exact input tokens plus the effective maximum output; terminal
   accounting commits exact validated usage, releases only a provably not-sent
   reservation, and otherwise retains the full reservation. Count-token
   evidence is not double-counted as inference usage.

The two project inputs have distinct responsibilities:

| File | Responsibility |
| --- | --- |
| `.sddtoolkit.json` | Define the repository's allowed model set through named slots containing exact provider/model references and accepted options. F0001 remains its sole reader and decoder. |
| `.sddproviders.json` | Catalogue the bounded configured provider/model instances and their closed provider-specific deployment configuration. It contains no repository allowlist, workflow-operation assignment, capability claim, executable implementation, or secret. |

Let `C` be the exact validated catalogue tuple set and `S` the tuple set
projected from `models.slots`. The required relationship is `S ⊆ C`. Equality
is valid, as is a strict subset; `S` containing any tuple outside `C` rejects
the repository model configuration. No reverse completeness requirement exists,
and `C - S` remains configured but unauthorized for this repository. Distinct
slot names may reference the same member of `C`; this does not increase `S` or
duplicate the catalogue entry. F0006 does not replace `models.slots` with a
profile or workflow-operation registry. Each YAML-declared generic model
operation must select a configured slot and produce the same
`ValidatedProviderModelBinding` before any provider operation.

## 3. Exact `.sddproviders.json` contract

The formal common structural contract is
[`sddproviders.schema.json`](../schemas/sddproviders.schema.json). Constraints
that JSON Schema cannot express—duplicate-key rejection, strict transport,
nesting depth, total model count, global identity uniqueness, compiled-contract
joins, and provider-specific configuration closure—remain normative here and
are enforced by the implementation.

The runtime source is exactly `<projectRoot>/<paths.providers>`, where
`projectRoot` is the same canonical invocation root established for F0001 and
the normalized configured path has the exact `.sddproviders.json` basename.
F0006 receives only F0008's bounded immutable bytes; it does not resolve or
read the path. The engine never searches a parent, child, home directory,
environment-selected path, source tree, or packaged asset. The repository
example is never opened at runtime.

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

The trust-boundary decoder first produces a bounded
`RawLLMProviderDocument` with the same exact common member names. Provider and
model identities remain bounded untrusted strings and each `config` remains a
bounded untrusted JSON object; no raw configuration field is usable. The
decoder rejects malformed transport, duplicate keys, wrong common kinds, and
unknown root/provider/model members as `LLM_PROVIDER_CONFIG_PARSE_ERROR`.

`BuildLLMProviderRegistryAction` then resolves each provider discriminator and
decodes its raw `config` through exactly one registered closed variant,
producing a validated `ProviderModelDefinition`. An unregistered provider, unknown
provider-specific field, or wrong provider-specific value is
`LLM_PROVIDER_REGISTRY_INVALID`, not a partial decode. This staged
raw-to-validated boundary permits the current example's common collection
shape to decode, but its unimplemented OpenAI entries make whole-registry build
fail.

There are no common project-authored `endpoint`, `contextWindow`,
`maxOutputTokens`, `supportsTemperature`, `structuredOutput`, `tokenizer`, or
wire-parameter fields. Those are trusted compiler-registered model-contract
facts described in Section 4. The provider catalogue may declare only a known
provider, known model, and the fields permitted by that provider's closed
`config` variant. Catalogue membership alone does not make that model
repository-authorized.

`RegisteredProviderModelConfig` is a closed tagged union selected by the
validated enclosing provider. For example, `provider: "aws-bedrock"` requires
the exact F0007 configuration `{ "region": <validated-region> }`. A future
OpenAI feature would have to accept, reject, or replace `baseUrl` in its own
governing design; F0006 does not treat the current example's OpenAI entries as
implemented or callable.

Every root, provider, model, and resolved provider-specific configuration
object is closed at its owning boundary. An unknown field, provider,
configuration variant, duplicate provider, duplicate `(provider, model)` tuple,
missing registered contract, or invalid sibling rejects the complete document.
There is no partial registry.

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

Configuration contains no API key, access key, secret key, session token,
bearer token, credential material, credential file, environment-variable name,
credential process, command, role session, secret reference, arbitrary header,
retry count, proxy, CA override, or unrestricted request map. Provider-specific
features may add only narrowly typed, explicitly accepted fields.

The current provider source example includes one Bedrock entry and
unimplemented OpenAI entries, while the current [toolkit source
example](../examples/.sddtoolkit.json) selects only OpenAI catalogue models and
leaves the Bedrock entry unreferenced. It therefore demonstrates a valid strict
slot-to-catalogue subset, including multiple slots referencing `gpt-5-nano`.
It is still not a conforming runtime fixture because no accepted OpenAI provider
implementation exists; it does not enable an adapter or provide a fallback.

## 4. Registered contracts and immutable registry

Capabilities and limits come only from immutable contracts compiled into the
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
  supportedControls: RegisteredInferenceControlSet,
  contextWindowTokens: PositiveInteger,
  maximumOutputTokens: PositiveInteger,
  providerWireBudgets: RegisteredProviderWireBudgets
}
```

Provider-specific versions may add only closed typed facts. Project
configuration can select a deployment fact such as a registered source region,
and may narrow accepted choices where its variant says so. It cannot increase a
limit or claim model support for an operation, tokenizer, control, structured
schema, endpoint, region, partition, or data-routing policy.

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

Registry entries and pipeline bindings contain immutable provider/model facts
plus a closed discriminator only. They never contain a provider object, client,
function pointer, credential/authorization handle, or operation capability.
The infrastructure-private dispatch implementation is an exhaustive closed
tagged union, not `anyopaque`, a service locator, callback map, or
project-extensible factory:

```text
LLMProviderDispatch = union(enum) {
  aws_bedrock: AWSBedrockProvider
  // A future compiled provider adds a new exhaustive variant.
}
```

The current production contract registry is empty. The generic registry and
allowlist boundary is exercised with private compiler-supplied test contracts
whose configuration schema is the closed empty object; those contracts are not
installed by production composition and cannot activate a project provider.
F0007 or another accepted provider feature must add a production contract,
configuration variant, implementation discriminator, and later dispatch branch
together.

Every union variant conforms directly to `LLMProviderInterface`; dispatch
forwards exactly one operation and introduces no second port. Adding a provider
therefore requires a source change and architecture tests. Unused entries do
not become callable: only a compiled YAML model operation whose declared slot
resolves to a validated fact-only binding can reach the composition-injected
common port.

## 5. Conditional bootstrap and change handling

The bootstrap root registry always reserves the exact configured provider path and its
access class before any project operation. The complete bootstrap root
validator proves that file role distinct from `.sddtoolkit.json` and every
configured/derived root under all active host/target normalization, case,
alias, and containment rules. A collision blocks even when provider content
loading will be skipped. Reservation grants no provider capability and does not
probe file existence or content.

After the validated workflow registry has resolved the selected graph,
`DeriveProviderRequirementAction` derives whether its effective capability set
contains the exact compiler-owned `model-provider` capability. It reads no
workflow/node name, parameter, policy allowance alone, configuration, slot, or
provider content. A project workflow cannot manufacture that capability by
naming a provider node or field; it can receive it only through an accepted
registered node contract under an allowing workflow policy.

The fixed `ModelProviderBootstrapOrchestrator` then branches only on that typed
outcome through runner-owned child bindings:

- If the selected compiled graph's effective capability set contains no
  exact `model-provider` capability, file existence probing, opening, reading,
  decoding, and registry construction are unreachable. A missing or malformed
  file is not observed and has no effect on that run.
- If it contains the exact `model-provider` capability, F0008 must successfully
  capture the exact configured provider file, and the complete document must
  build and validate before `ValidateRepositoryModelAllowlistAction` joins the
  complete `models.slots` map to that catalogue. Both the complete catalogue and complete
  allowlist must validate before the first selected-workflow node runs.
  Missing, malformed, unsupported, partially valid, or catalogue-missing slot
  input blocks run preparation; no partial allowlist is published.

The orchestrator performs no filesystem, parsing, registry, state, logging, or
provider work itself. ADR 0004 accepts this fixed run-preparation placement and
the narrow expansion beyond the startup graph; the runner does not infer or
sequence it by convention. The implemented runner invokes F0008 once, then
applies the decoder, registry builder, registry validator, and complete
allowlist validator through their existing contracts.

The engine invocation runner invokes one composition-supplied
`ModelProviderBootstrapBinding` immediately after exact workflow selection and
before constructing the selected-workflow runner. `not_required` and `ready`
continue to workflow execution; `failed` returns the exact provider-bootstrap
diagnostic; `cancelled` returns cancellation. A `ready` result remains owned
until selected-workflow execution returns. The binding exposes no filesystem
port; the composition assembly alone constructs the F0008 adapter and both
runners.

F0008's owned capture is the only provider-document read for the engine
invocation. The validated registry and allowlist derived from it remain
authoritative until that invocation ends even if the backing filesystem entry
later changes; the raw capture need not be retained after preparation. No
identity comparison or refresh is performed after capture; the next invocation
performs a new conditional capture. There is no stale fallback because no
prior invocation's bytes, registry, or allowlist are retained.

## 6. Provider/model binding and limits

F0001 remains the sole owner of `.sddtoolkit.json` decoding. The complete
`models.slots` map defines the repository's candidate allowlist. Before any
workflow model operation is usable, every slot's exact case-sensitive `(provider, model)`
tuple must resolve once in `LLMProviderRegistryService` and produce one entry in
`ValidatedRepositoryModelAllowlist`; one missing or ambiguous tuple rejects the
complete repository model configuration. Provider catalogue entries not
selected by any slot are retained as configured facts but cannot be resolved
through repository model authority. The allowlist references registry-entry
identities rather than copying provider configuration or compiled contract
facts. Decoded strings alone grant no provider authority.

`ResolveProviderModelBindingAction` must prove:

1. the compiled workflow operation's YAML-declared slot resolves in `ValidatedRepositoryModelAllowlist` to
   exactly one immutable registry-entry identity; direct provider/model tuple
   selection bypassing the allowlist is impossible;
2. the entry resolves to exactly one registered provider discriminator and
   compiled model contract, without storing a concrete adapter;
3. its provider-specific configuration, target, source region, destination
   policy, operation set, and exact token-count mechanism are valid;
4. every selected option, including `reasoningEffort`, is explicitly supported
   and representable rather than silently ignored;
5. the complete `model-envelope/v1` response schema and YAML-declared result schema are
   representable by the registered response mode; and
6. effective limits are the strict minimum of engine, compiled workflow operation, and registered
   model-contract limits.

The following checks use checked integer arithmetic:

```text
canonicalInputBytes <= effectiveOperationInputBytes
exactInputTokens <= effectiveOperationInputTokens
exactInputTokens + effectiveMaximumOutputTokens <= modelContextWindowTokens
```

These per-operation capacity checks are not workflow-global usage limits. The
selected workflow policy contributes one `totalModelTokenBudget` to each
workflow execution. After exact counting and before inference, the runner must
reserve `exactInputTokens + effectiveMaximumOutputTokens` from that execution's
single immutable-ledger lineage. A reservation that would exceed the remaining
budget prevents the call. A validated terminal inference observation commits
exact reported usage; a provably `not_sent` operation releases its reservation;
`accepted_or_unknown` or unavailable exact usage retains the full reservation.
The count operation supplies evidence and is not charged again as inference
usage.

Before signing or network I/O, the provider serializer also proves the exact
serialized CountTokens/inference request body, path, and bounded headers fit
the separate registered request-wire budgets. These budgets account for fixed
wrappers, URI/JSON escaping, and any schema encoded inside a provider string;
`canonicalInputBytes` is not used as a wire-size approximation.

This provider-specific serialization proof runs inside the already invoked
provider operation. Failure returns `request_limit_exceeded` with delivery
`not_sent`; the previously reserved full attempt remains consumed. There is no
implementation choice to move the failure outside accounting.

After a response, before envelope decoding:

```text
canonicalModelEnvelopeBytes <= effectiveOperationOutputBytes
reportedOutputTokens <= effectiveOperationOutputTokens
reportedTotalTokens >= reportedInputTokens
reportedTotalTokens >= reportedOutputTokens
```

Any stronger usage relation declared by the registered provider/model contract
must also hold. The provider's wire-response ceiling is distinct from the
canonical model-envelope content ceiling. Its registered wire-budget proof
must account for bounded header count/bytes, the fixed protocol wrapper,
content-encoding policy, and worst-case encoding overhead; crossing any ceiling
aborts without truncation.

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

The accepted contract treats one ordinal as one complete provider attempt,
not only one inference call. Its sequence is closed:

1. validate provider/model binding, controls, schema representability,
   canonical input bytes, output reservation, and every other provider-neutral
   deterministic preflight before authorization or attempt reservation; the
   exact provider wire serialization and its body/path/header caps are
   deliberately excluded from this step;
2. invoke `AdvanceModelAttemptAccountingAction` once to reserve the initial
   ordinal, or for a later attempt only after the compiled YAML selects a retry
   operation with its own explicit validated `retry-limit`;
3. assign its `input_token_count` operation and prepare authorization;
4. before the first provider call, apply logical request
   `assigned -> invoked`, operation `assigned -> invoked`, and the durable
   `send_may_occur` effect-journal phase;
5. inside that already invoked operation, serialize the exact CountTokens wire
   request and enforce its body/path/header caps before signing or sending; a
   cap failure terminally returns `request_limit_exceeded`/`not_sent` and
   consumes this attempt;
6. terminally account the count observation, validate its identity/value and
   exact capacity, and build count evidence;
7. only after successful evidence, reserve worst-case tokens against the one
   workflow-execution budget, assign and authorize the inference operation,
   apply the same invoked/journal transition, perform its exact
   serialization/cap checks, invoke it, and terminally reconcile the token
   reservation and operation outcome; and
8. keep the logical request `invoked` across any separately authorized provider
   or protocol retry, then apply exactly one final terminal transition.

`AdvanceProviderOperationLifecycleAction` proposes compare-and-swap deltas for
`assigned -> invoked -> terminal`; preparation failure or cancellation may use
`assigned -> terminal`. Only the runner validates and applies these deltas. No
operation may remain assigned when its attempt or request terminates. A provider
action requires proof that its `invoked` transition is already applied.

The implementation retains immutable ledger snapshots under one execution
owner. The request runner owns that lifetime and destroys it before canonical
request identities. Every change checks the exact ledger, request, attempt, and
operation revisions; count and inference reference the existing reserved
attempt rather than reserving it again. Inference assignment joins successful
terminal count evidence by operation, binding, input identity, and count value.
The action emits one declared runner transition, and only the runner publishes
the successor. Request terminalization and a later attempt are rejected while
an operation remains assigned or invoked.

The transition projects only `assigned`, `send_may_occur`, or
`terminal_observed` journal intents. Those projections omit count values and
model content and do not prove persistence or outcome consumption. Durable
commit/handoff and recovery remain separate implementation increments; the
in-memory `requireInvoked` lookup alone does not authorize production I/O.

Authorization failure before the first provider call leaves the logical request
`assigned`; a typed terminal outcome uses an amended
`assigned -> terminal(not_invoked_authorization_failure)` transition, while the
already reserved attempt remains consumed. Count failure occurs after logical
`assigned -> invoked`; the request remains `invoked` only while an accepted
orchestrator chooses a new attempt, otherwise a terminal-outcome action proposes
`invoked -> terminal`. An inference operation is not assigned until exact count
evidence exists. These cases, cancellation, and recovery exhaust the legal
branches; no implicit status or dangling operation exists.
Cancellation before the first call uses `assigned -> terminal(cancelled)` after
the assigned operation is closed as not sent; it is not an authorization failure.

The two operation IDs share the attempt ordinal but have distinct kinds. Count
or authorization failure consumes the reserved attempt and makes that
attempt's inference operation unreachable. Only the compiled YAML may choose a
registered retry operation. That exact operation instance must carry an
explicit compiler-validated `retry-limit`; a selected workflow policy cannot
supply it. Each permitted retry receives a new ordinal, both new operation IDs,
and a new count. No count or inference retry is hidden inside an adapter or
client, and no workflow-global attempt ceiling exists.

`PrepareProviderOperationAuthorizationAction` depends only on the
provider-neutral `ProviderOperationAuthorizationPort`. The runner first
allocates a single-use slot in its private
`ProviderAuthorizationLeaseTable`. The action supplies that slot plus F0006
closed binding/request/operation facts; the infrastructure adapter deposits one
move-only prepared capability and returns bounded observation/evidence. The
action's `NodeDelta` contains only an opaque
`ValidatedProviderAuthorizationLeaseRef` bound to the provider, operation ID,
binding, `ModelVisibleInputId`, and deadline. The capability itself never enters
the immutable `PipelineEnvelope`.

At the provider call, the concrete adapter uses a narrow runner-owned
`ProviderAuthorizationLeasePort` to compare-and-swap consume that exact lease
once. The capability moves from the private table to the adapter; the adapter
destroys it after the one call. If it is never consumed, the table owns and
destroys it on cancellation, failure, attempt termination, or runner cleanup.
A stale, mismatched, reused, or already-finalized reference fails before send.
The table is one-purpose and operation-keyed, not a service locator or generic
capability store. Provider-specific credential and signing types remain wholly
inside infrastructure.

The minimum v1 authorization path uses already loaded, non-refreshing material
and performs no filesystem, process, metadata, STS, or refresh I/O. If an
accepted credential policy later permits any such effect, each effect first
requires its own closed operation identity, lifecycle, budget, retry, recovery,
and terminal accounting. It cannot be hidden inside authorization preparation
or a model operation. The envelope-visible lease reference contains no
credential bytes, provider client, or operation capability and is harmless
without the runner-private table.

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
    countEvidence: ExactInputTokenCountEvidence,
    authorization: ValidatedProviderAuthorizationLeaseRef,
    operation: InvokedProviderOperation
  ) -> ProviderInvocationObservation
}
```

The implementation mechanism exposes no unbounded `anytype`, `anyopaque`,
generic capability bag, provider-client type, credential material, or
unrestricted infrastructure capability across the port. The authorization
argument is only a typed single-use lease reference; concrete infrastructure
consumes its private backing through the narrow lease port. Operation context
otherwise contains only typed identity, cancellation, absolute deadline, and
registered receive budgets. It contains no filesystem, process, state,
transaction, logger, command, completion, child-node, or unrestricted tool
capability.

Each method performs zero or one declared provider API request. Zero is allowed
only for a typed pre-I/O rejection such as a registered unsupported operation.
Automatic SDK/client retry, backoff, fallback, and failover are disabled. An
interface call cannot conceal credential acquisition, refresh, token counting,
or a second inference request; a concrete provider must resolve such effects at
separately accepted and accounted boundaries.

`ExactInputTokenCountEvidence` binds a successful count to the exact
`ProviderOperationId`, binding ID, and `ModelVisibleInputId`. That identity
binds ordered model-visible content, controls, response-guidance mode, and the
full response-schema identity shared by counting and inference; it is not a
provider wire-request digest because count and inference wire shapes differ. A
different binding, content projection, control, schema mode, schema, or attempt
invalidates the evidence. An estimate is never an exact count; when no accepted
exact mechanism exists, inference blocks.

## 8. Closed request, observation, and failure algebra

`IdentifiedProviderNeutralModelRequest` contains only engine-assigned request,
workflow-operation identity, binding, request-schema, result-schema, and `ModelVisibleInputId`;
ordered bounded system/guidance and user/evidence content; the exact complete
`model-envelope/v1` response schema; supported engine-selected controls; and
effective limits. It contains no provider URL, arbitrary provider map,
credential, path capability, command, logger, state writer, transaction, or
tool definition.

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
      content: CompleteBoundedOwnedUtf8,
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

ProviderFailureCause =
  authentication_failed | authorization_denied | request_rejected |
  model_unavailable | throttled | timeout | service_unavailable |
  transport_failed | request_limit_exceeded | response_invalid |
  response_limit_exceeded |
  exact_token_count_unavailable

ProviderRetryClass = never | policy_eligible

ProviderDeliveryDisposition =
  not_sent | response_received | accepted_or_unknown

ProviderFailure {
  operationId: ProviderOperationId,
  cause: ProviderFailureCause,
  retryClass: ProviderRetryClass,
  delivery: ProviderDeliveryDisposition
}
```

`ProviderInvocationObservation.completed` means the provider operation returned
a complete recognized terminal response; it does not mean candidate or
workflow completion. The nested `RawProviderModelResult` tag decides whether
content exists.

`ProviderFailure.operationId.kind` is the single operation-kind authority; an
observation carries no second identity that could disagree. `not_sent` is
provable only when no request byte left the process. A decoded provider response
is `response_received`. Any interruption after transmission begins, or any
restart that finds `invoked` without a durable terminal observation, is
`accepted_or_unknown` because the provider may have accepted and charged the
request.

Cross-process recovery depends on an engine-owned
`ProviderOperationEffectJournal`; the run-local pipeline ledger is
insufficient. The accepted schema has two distinct record types:

```text
ProviderAttemptEffectRecord.phase = reserved | terminal

ProviderOperationEffectRecord.phase =
  assigned | send_may_occur | terminal_observed | outcome_consumed
```

An attempt record is created exactly once when its ordinal is reserved. Each
count or inference record has its own operation ID and compare-and-swap
revision, references that one attempt record, and never repeats attempt
reservation. A successfully consumed count operation may therefore remain
terminal while a distinct inference operation is assigned beneath the same
still-reserved attempt. The attempt becomes terminal after a count-side
terminal outcome that makes inference unreachable, or after the inference
outcome is consumed.

The closed records contain only run/request/attempt/operation, binding,
`ModelVisibleInputId`, lifecycle revision, and delivery/terminal/handoff facts—
never prompt/response content, headers, credentials, or provider error text.
The runner must commit an operation's `send_may_occur` and the matching logical
request/operation `invoked` facts before any request byte can leave. A crash
after that commit is conservatively ambiguous even if transport had not yet
sent. A crash at attempt `reserved`, or operation `assigned`, without
`send_may_occur` is provably not sent. A crash after `send_may_occur`, after
send, or after a response arrives but before `terminal_observed` durability is
`accepted_or_unknown`.

`terminal_observed` records the bounded terminal classification but does not
claim that its omitted count value or model content can be reconstructed.
`outcome_consumed` may be written only after an exact identity/revision join
proves a durable successor state that no longer needs the raw observation. The
accepted transaction amendment must make that handoff atomic or recoverably
idempotent. If such a successor is already durable after a crash, recovery may
idempotently advance the marker. If no successor exists and the required value
or content was intentionally not journaled, recovery returns the distinct
`terminal_result_unavailable` outcome, terminally closes the attempt/request,
and blocks by default; it never fabricates or replays the lost result.

`RecoverProviderOperationLifecycleAction` classifies and closes attempt and
operation records under their exact revisions. An invoked-but-unobserved
operation becomes `accepted_or_unknown`; a terminal observation without a
recoverable successor becomes `terminal_result_unavailable`. The owning
orchestrator may issue another provider call only under an explicitly accepted
duplicate-external-effect/spend policy, using a new model attempt and operation
ID. The default is to block for either ambiguous external effect or unavailable
terminal result. A policy-eligible cause alone never authorizes replay.

Every provider-operation terminal lifecycle fact also records delivery
disposition, including cancellation paths that remain outside `ProviderFailure`.
Thus cancellation never erases an ambiguous external effect.

Both `RawProviderModelResult` variants contain only engine-supplied identities,
bounded nonnegative usage, and optional bounded latency; neither accepts an
identity from the provider. Only `.complete` owns UTF-8 content. `.stopped`
contains no content member, so a missing/non-text provider output cannot be
represented by an empty-string sentinel.

`.stopped` publishes no candidate to `DecodeModelEnvelopeAction`. A `.complete`
result is still untrusted candidate data. Native structured output is only a
transport optimization: the engine always decodes and validates the entire
exact model envelope, identities, closed workflow-operation result, semantic assertions,
and no-invention requirements.

Explicit cancellation remains terminal `cancelled` and is propagated outside
the failure union. Provider failure is never converted to the model-content
`invalid` state because `invalid` enters schema/semantic repair. A provider
operation returns the closed `retryClass` and delivery disposition; the
compiled YAML transition may pass those facts to an explicit retry operation
allowed by policy. Terminal-outcome actions construct the corresponding delta;
the runner only validates/applies it and never chooses `blocked`, `failed`,
`cancelled`, retry, or fallback.

## 9. Action and orchestration ownership

| Owner | Sole responsibility |
| --- | --- |
| `DeriveProviderRequirementAction` | Return `required` only when the selected compiled graph contains the exact compiler-owned `model-provider` capability; otherwise return `not_required`. |
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
| `ResolveProviderModelBindingAction` | Resolve one compiled workflow operation's YAML-declared slot through `ValidatedRepositoryModelAllowlist` to its registry entry and effective limits; never accept a raw provider/model tuple or hidden route as authority. |
| `BuildImmutableUnitOwnerIdAction` | Validate one closed stage-specific unit-owner descriptor built only from canonical authority IDs; accept no model identity. |
| `BuildInitialModelRequestIdentityLedgerAction` | Produce the sole empty immutable request ledger for one trusted stage-run epoch and closed purpose registry. |
| `AssignModelRequestIdAction` | Allocate one purpose-bound ordinal from the current ledger revision and return an immutable successor; never mutate the current ledger or reassign a protocol retry. |
| `ValidateModelRequestBindingAction` | Prove exact ledger membership and epoch/unit/workflow-operation/purpose/ordinal binding without changing the ledger. |
| `BuildModelRequestAction` | Build one identified bounded provider-neutral request. |
| `ValidateStaticModelRequestCapacityAction` | Prove every provider-neutral deterministic binding/control/schema/input-byte/output-reservation ceiling before attempt reservation or authorization; it does not serialize a provider wire request. |
| `AdvanceModelAttemptAccountingAction` | Reserve the initial complete provider-attempt ordinal, or a later ordinal only under the YAML-selected operation instance's explicit compiler-validated `retry-limit`; it applies no workflow-global attempt ceiling. |
| `ReserveWorkflowTokenBudgetAction` | Reserve exact input tokens plus effective maximum output tokens against the selected policy's one total model-token budget for this workflow execution. |
| `ReconcileWorkflowTokenUsageAction` | Commit exact validated inference usage once, release a provably not-sent reservation, or retain the full reservation when delivery or exact usage is unavailable. |
| `AdvanceModelRequestLifecycleAction` | Propose the amended logical request compare-and-swap transition. |
| `AdvanceProviderOperationLifecycleAction` | Propose one count/inference lifecycle plus effect-journal compare-and-swap transition; perform no journal I/O. |
| `PrepareProviderOperationAuthorizationAction` | Fill one runner-private operation-bound lease slot through the provider-neutral preparation port and return only validated opaque lease-reference evidence. |
| `CountModelInputTokensAction` | Make exactly one interface count call for an already invoked count operation. |
| `ValidateExactModelInputCapacityAction` | Validate count identity/value and token/context ceilings, then build attempt/binding/model-visible-input-bound exact-count evidence. |
| `InvokeModelAction` | Make exactly one interface inference call for an already invoked inference operation. |
| `ValidateProviderInvocationObservationAction` | Validate operation identity, delivery, stop, usage, wire/content ceilings, and complete-candidate eligibility before decoding. |
| `RecoverProviderOperationLifecycleAction` | Join durable successors and classify/close reloaded attempt and operation records as provably not-sent, ambiguous external effect, or unavailable terminal result without replay. |
| `DecodeModelEnvelopeAction` | Decode returned candidate bytes; it never invokes a provider. |
| `ProviderOperationEffectJournalService` | Durably apply/reload the closed operation-effect CAS records through its accepted lock/transaction adapter; expose no model content or provider port. |
| Pipeline runner | Invoke bound children; own the per-execution token ledger, private authorization-lease table, and effect-journal handle; validate/apply deltas, lifecycle compare-and-swap transitions, explicit operation-local retry accounting, token reservation/reconciliation, deadlines, and cleanup; choose no branch or terminal outcome. |

`ModelProviderBootstrapOrchestrator` coordinates only the requirement and
provider-file child bindings described in Section 5. It is engine preparation,
not workflow behavior. Provider retry, fallback, and protocol-retry branches
must each be visible as YAML steps and transitions; their registered generic
operations perform one bounded responsibility and never select a successor.

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

The effect journal follows its accepted retention and recovery policy and
contains only the closed non-content facts in Section 8. Authorization lease
references may be recorded for same-process cleanup but their private table
entries and capabilities are never persisted; a restarted process finalizes
open journal records without reconstructing a credential.

Only concrete infrastructure adapters import provider clients, networking,
TLS, signing, or credential sources. Application and domain code import only
the common port and typed values. A provider adapter has no filesystem,
command, project-state, workflow, transaction, log-sink, or child-node
capability.

Ordinary metadata logs never contain raw provider bodies. Optional F0002 prompt
capture selects typed fragments before provider serialization, then applies its
existing opt-in, redaction, and byte limits. Logs are observations and have no
retry, validation, provider, or workflow authority.

Every raw/configured/validated request buffer, response buffer, binding,
transport handle, authorization table slot/capability, lease reference,
journal lock/handle, and observation has explicit ownership and deterministic
cleanup on success, rejection, timeout, cancellation, recovery, and operational
error. No failed bootstrap retains a partial or last-known registry; no failed
provider operation retains a stale successful response.

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
   unconditionally; the fixed run-preparation orchestrator conditionally asks
   F0008 to load only that `.sddproviders.json` file, and no provider reads it
   independently.
   Full host/target collision proof keeps that file role distinct from engine
   config and every configured/derived root even when loading is skipped.
3. The document has exactly the bounded
   `providers[] -> { provider, models[] -> { model, config } }` shape, and every
   common object and resolved provider variant is closed at its owning boundary.
4. Capabilities, limits, operations, tokenization, structured response, target,
   endpoint, and data-routing facts come only from compiled model contracts.
5. The repository example is never a runtime default or fallback. Its common
   shape can decode, but its OpenAI entries make whole-registry build fail until
   an OpenAI feature is compiled and accepted.
6. If the selected compiled graph's effective capability set has no exact
   `model-provider` capability, file probing/loading is unreachable; otherwise
   the entire exact file must validate before selected-workflow execution. A
   required branch captures it once; no active invocation rereads or refreshes
   that snapshot, and no prior invocation supplies a fallback. Provider
   failure or cancellation makes every selected-workflow child unreachable;
   prepared authority remains alive until workflow execution returns.
7. One invalid or unsupported sibling publishes no partial registry.
8. Every `.sddtoolkit.json` slot tuple and its options resolve exactly to one
   registry entry, compiled model contract, and exhaustive provider
   discriminator. Slots may reference some or all catalogue entries, never an
   absent entry; an unreferenced catalogue entry is not repository-authorized.
   The one validated allowlist stores slot-to-entry identities without copying
   provider configuration or contract facts. No adapter/client is stored in
   registry or pipeline data.
9. Project configuration contains no secret, executable behavior, arbitrary
   endpoint, retry policy, header, wire parameter, or capability claim.
10. Effective canonical, serialized request, header, encoded/decoded response,
    token, context, output, and provider-wire limits use the strictest
    applicable registered limits and checked arithmetic.
    Model-request IDs are engine-assigned from one immutable run-local ledger by
    exact revision; their unit, compiled workflow operation, purpose owner, and
    ordinal must all validate before request construction.
    The selected workflow policy contributes the only workflow-global limit:
    one positive total model-token budget initialized independently for each
    workflow execution.
11. Count evidence is exact and bound to the same attempt, binding, and
    `ModelVisibleInputId`; unavailable evidence prevents inference.
12. Provider-neutral static preflight precedes one reserved full-attempt
    ordinal. The initial ordinal is unconditional after preflight; every later
    ordinal requires a YAML-selected retry operation with its own explicit
    compiler-validated `retry-limit`. Exact provider serialization/wire-cap checks occur only inside an
    already invoked operation; `request_limit_exceeded` is `not_sent` but
    terminally consumes that attempt. Every count and inference operation has a
    distinct durably journaled runner-applied identity/lifecycle transition,
    and count/authorization failure consumes that attempt without inference.
13. Each call performs zero or one provider request with no hidden retry,
    fallback, backoff, credential acquisition/refresh, or second operation;
    any permitted credential I/O has separate accepted accounting.
14. Only an opaque validated lease reference enters the pipeline envelope; its
    move-only authorization capability stays in a single-use runner-private
    table with compare-and-swap consume and one cleanup owner.
15. One attempt reservation owns distinct count/inference journal records;
    `send_may_occur` is durable before transmission, and
    `terminal_observed -> outcome_consumed` proves the durable result handoff.
    Restart closes earlier records as not-sent, later open records as
    accepted-or-unknown, and an unconsumed terminal result with no durable
    successor as `terminal_result_unavailable`, all without replay.
16. Only the compiled YAML graph may choose an explicit registered retry
    operation, and every retry-capable operation instance supplies its own
    bounded `retry-limit`; no workflow policy, configuration file, provider, or
    runner supplies a retry default. Every retry uses a new ordinal, and an
    accepted-or-unknown delivery never auto-replays.
17. Provider failures never enter model-content repair or become `invalid`.
18. Only `complete` bounded UTF-8 content reaches envelope decoding, where the
    full envelope remains untrusted and authoritatively validated.
19. No provider operation receives filesystem, process, state, transaction,
    logger, command, completion, child-node, or unrestricted tool capability.
20. Credentials, signatures, raw bodies, headers, arbitrary provider metadata,
    and environment values never enter canonical state or ordinary logs.
21. The fake provider conforms to the same interface and keeps all model
    workflow increments deterministic without network access or credentials.
22. The packaged native executable needs only accepted target-owned runtime
    inputs, never repository examples, source files, build cache, or Zig.

## 13. Verification

Implementation evidence must cover:

- **File boundary:** unconditional configured-path registration; exact
  F0004-capability lookup; no-model-provider-capability graph bypass;
  exactly one capture for a required branch; immutable registry/allowlist after
  capture despite a later backing-source change; no active-run reread, refresh,
  monitoring, last-known fallback, or cross-invocation cache;
  missing, parent/child/example fallback, wrong kind, symlink, permissions,
  short read, file growth/shrink, exact/over size, collision with engine config
  and every configured/derived root by exact/case/normalization/alias/
  containment equivalence, cancellation, and deadline.
- **JSON/registry:** raw common decode versus closed variant-build diagnostics;
  reordered fields; empty, maximum, and over-limit
  collections; duplicate keys/identities; unknown provider/config/field;
  malformed UTF-8/JSON; unimplemented OpenAI entries; invalid sibling with no
  partial registry; exact ownership and cleanup.
- **Binding/limits:** all-catalogue and strict-subset slot selections, one slot
  tuple absent from the catalogue rejecting the complete binding set,
  unreferenced catalogue entries remaining unauthorized, exact and ambiguous
  tuples, unsupported options, target and data-policy rejection,
  workflow-operation/model/engine limit intersection, byte and token boundaries, request
  URI/JSON/schema amplification, request/body/header and encoded/decoded
  response caps, checked context equality/overflow, response wire/content
  separation, and structured-schema incompatibility.
- **Request and operation accounting:** closed request-purpose registries;
  malformed unit owners; duplicate purpose entries; unregistered or mismatched
  purposes; independent monotonic ordinals; stale ledger revisions; foreign or
  altered request IDs; exact canonical binding evidence; distinct
  count/inference IDs and operation records
  beneath one attempt record, lifecycle CAS, provider-neutral static-preflight
  ordering, operation-scoped wire-cap rejection that consumes the reserved
  attempt, count-once, count failure making inference unreachable, evidence
  binding, every assigned-branch close, durable effect-journal lock/CAS/
  redaction/retention, and crashes between attempt reservation, operation
  assignment, logical invoked, `send_may_occur`, first byte, response arrival,
  `terminal_observed`, durable successor commit, and `outcome_consumed`.
  Evidence distinguishes not-sent, accepted-or-unknown, successor-already-
  committed, and terminal-result-unavailable recovery; every permitted retry
  receives a new ordinal, every retry-capable operation instance declares and
  exhausts its own validated `retry-limit`, missing limits and policy-supplied
  retry defaults are rejected, cancellation is terminal, and the client never
  auto-retries. Per-execution token-ledger evidence covers initial isolation,
  exact and over-budget reservations, checked addition, exact-usage
  reconciliation, provably-not-sent release, retained ambiguous reservations,
  count-token non-duplication, and independence between two executions of the
  same workflow.
- **Port conformance:** identical golden provider-neutral cases through fake
  and real adapters; closed stop/failure mapping; bounded reads; malformed and
  partial observations; complete cleanup on every terminal branch.
- **Architecture/security:** dependency-import tests, fact-only registry,
  composition-injected common port, exhaustive private adapter
  dispatch, pipeline containing only authorization lease references, runner-
  private capability table one-use/cleanup tests, no operation port in an
  orchestrator or `NodeRuntime`, no provider imports outside adapters,
  secret/body/header canaries absent from state/journal/logs, and F0002
  fragment-only capture.
- **End to end/packaging:** fake-provider workflows first; relocated target
  files; clean native executable without source examples or development assets.
  Any live provider test is separately authorized, credential-gated,
  non-default, and excluded from deterministic CI.

## 14. Traceability

| Concern | Authority |
| --- | --- |
| Candidate-only LLM boundary | Design Sections 1, 3-4, 12, and 26.1 |
| Fixed conditional provider bootstrap and derivation | ADR 0004; Design Sections 3-6 and 13.1 |
| Common port, action, runner, and dependency direction | Design Sections 5-6 and 13.4; ADR 0001 |
| Current engine configuration ownership | Design Section 9; F0001; `design/paths.md` |
| Request/invoke/decode separation | Design Sections 12.1-12.4 and 13.4; `design/code.md` Sections 21-24 |
| Workflow-operation limits, retry, fallback, and repair authority | ADR 0005; Design Sections 12.5-12.7 and 21-22 |
| Provider-operation durability and recovery amendment | Accepted Section 7 contract; Design Sections 24-25 |
| Secret-safe logging | Design Sections 26.5 and 27; F0002 |
| Fake-first testing and native packaging | Design Sections 28 and 30-31 |
