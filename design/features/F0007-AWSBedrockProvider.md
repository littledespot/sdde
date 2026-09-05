# F0007 — AWSBedrockProvider

**Status:** Proposed feature design

**Implementation readiness:** Blocked. F0006 and its governing amendments are
accepted. Production implementation still requires accepted
compiler-registered Bedrock model contracts, target/region/data-routing policy,
schema representability for any native structured-output mode, and approval
of the concrete AWS transport dependency. Counting is optional and never an
inference prerequisite; provider token/context limits are reported by the API. The environment-only API-key source is accepted: the
engine reads `AWS_BEARER_TOKEN_BEDROCK` and never accepts a hardcoded key. No
dependency or live AWS activity is authorized here.

**Compatibility:** None. The first implementation supports only provider ID
`aws-bedrock`, registered targets, synchronous Bedrock Runtime operations, and
the closed configuration below. Authentication uses only a preloaded snapshot
of `AWS_BEARER_TOKEN_BEDROCK`. It has no alternate provider name, endpoint
override, inline key, automatic retry, streaming path, auth document,
unregistered model target, or arbitrary model-specific request map.

**Classification:** Infrastructure LLM-provider adapter

**Scope:** SDDE engine development. This document does not authorize an AWS
request, credential lookup, IAM change, model enablement or purchase, live
smoke test, or project-content mutation.

**Governing authority:** [Engine design](../design.md), especially Sections 1,
3-6, 9, 12-13.4, 21-22, and 26-31; [ADR 0001 — Zig native
engine](../decisions/0001-zig-engine.md); [F0006 —
LLMProviderInterface](F0006-LLMProviderInterface.md); [F0001 —
SDDToolKitConfigService](F0001-SDDToolKitConfigService.md); [F0008 —
LLMProviderConfigService](F0008-LLMProviderConfigService.md); and [F0002 —
LogService](F0002-LogService.md); and accepted [ADR 0005 — workflow-defined
operations](../decisions/0005-workflow-defined-operations.md). External protocol references are the AWS
documentation for [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html),
[CountTokens](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CountTokens.html),
[Converse token-count input](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseTokensRequest.html),
[structured output](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html),
[inference-profile region support](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html),
[Bedrock endpoints](https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints.html),
[Bedrock API-key use](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-use.html),
[Bedrock API-key reference](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-reference.html),
[Bedrock IAM policy practices](https://docs.aws.amazon.com/bedrock/latest/userguide/security_iam_id-based-policy-examples.html),
and the [Amazon Nova 2 Lite model
card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-lite.html).

---

## 1. Responsibility

`AWSBedrockProvider` has one responsibility: translate one validated and
accounted F0006 operation to one registered Amazon Bedrock Runtime operation,
then normalize its bounded observation to the provider-neutral algebra.

It conforms directly to `LLMProviderInterface`; it does not introduce a second
AWS gateway or runtime base class. AWS types remain in infrastructure. Domain
and application code receive only F0006 values and observations.

The first transport subset is:

- provider discriminator `aws-bedrock`;
- trusted regional `bedrock-runtime` HTTPS endpoints;
- synchronous `Converse` for inference;
- `CountTokens` only for registered models for which AWS supports that
  operation;
- bearer authentication through a separately preloaded, single-use API-key
  capability sourced only from `AWS_BEARER_TOKEN_BEDROCK`; and
- ordered text-only system and message input, with either registered
  prompt-only response guidance or registered native structured output.

Every response remains untrusted candidate data. HTTP success, a Bedrock
`end_turn`, native structured output, or provider token usage has no validation,
workflow, persistence, approval, or completion authority.

## 2. Increment boundary and owners

F0007 begins with:

- one immutable `ValidatedProviderModelBinding` tagged `aws_bedrock`;
- one identified provider-neutral request with exact compiled workflow model-operation identity, full
  `model-envelope/v1` schema, ordered content, controls, `ModelVisibleInputId`,
  and effective limits;
- one assigned `ProviderOperationId` and, before network I/O, proof of its
  durably journaled runner-applied `send_may_occur`/`invoked` transition;
- exact input-token evidence for inference; and
- one validated opaque authorization lease reference whose nonserializable
  backing capability remains in the runner-private table and is bound to the
  same provider, operation ID, source region, service, deadline, and request.

It ends with one F0006 token-count or invocation observation, or propagated
terminal cancellation. It does not decode the SDDE envelope, validate operation
semantics, select a retry/fallback, mutate state, log raw content, or invoke a
pipeline node.

Responsibilities remain narrow:

| Owner | Sole responsibility |
| --- | --- |
| `PrepareProviderOperationAuthorizationAction` | Call only F0006's provider-neutral preparation port with closed F0006 values and a runner-private lease slot; return only validated opaque reference evidence and import no AWS type. |
| `AWSBedrockEnvironmentAPIKeySource` | Read only `AWS_BEARER_TOKEN_BEDROCK` once when the selected invocation requires Bedrock, validate it under the secret-byte bound, and return an invocation-owned secret snapshot. |
| `AWSBedrockOperationAuthorizationAdapter` | Implement the preparation port behind infrastructure and deposit an already loaded, operation-bound API-key capability into the runner-private slot without reading the environment. |
| `AWSBedrockProvider` | Translate one typed operation and normalize one bounded provider observation. |
| `AWSBedrockRuntimePort` | Send and receive at most one already authorized Bedrock Runtime request under its deadline, cancellation, and wire budget. |
| Trusted endpoint resolver | Resolve one registered partition/region and fixed `bedrock-runtime` service to one trusted HTTPS origin. |
| Composition root | Construct the fixed Bedrock model contracts, endpoint policy, provider adapter, environment source, and narrow infrastructure implementations; it does not read or retain the key itself. |
| Pipeline runner | Own the single-use authorization table and effect-journal handle, apply lifecycle transitions, expose only opaque lease references, and finalize every slot on every path. |

`AWSBedrockProvider` exhaustively matches the already validated
`aws_bedrock` union tag and operation kind as a defensive internal invariant.
It does not repeat provider configuration, target, capability, or limit
validation owned by F0006 registry and binding actions.

Authorization preparation occurs while the operation is `assigned`. Failure
moves that operation directly to terminal without a provider request. After the
private slot is filled, the runner applies and durably journals
`assigned -> invoked`; only then may the provider compare-and-swap consume the
lease and send one request. The envelope-visible reference cannot serialize,
log, rebind, reuse, or reveal the backing capability. Authorization preparation
does not read the environment: it consumes the invocation-owned snapshot
created by `AWSBedrockEnvironmentAPIKeySource`. Filesystem, credential-process,
metadata, STS, generation, exchange, and refresh sources are prohibited.

No owner above receives project filesystem, command, workflow-state,
transaction, log-sink, completion, child-binding, or unrestricted tool
capability unless its one listed responsibility explicitly requires a narrower
port.

## 3. Exact Bedrock provider-file variant

F0008 owns the bounded read of the exact `paths.providers`
`.sddproviders.json`; F0006 owns generic decoding of those untrusted bytes.
The Bedrock portion intentionally matches the current example's lean shape:

```json
{
  "providers": [
    {
      "provider": "aws-bedrock",
      "models": [
        {
          "model": "global.amazon.nova-2-lite-v1:0",
          "config": {
            "region": "ap-southeast-2"
          }
        }
      ]
    }
  ]
}
```

For `provider: "aws-bedrock"`, each model object contains exactly `model` and
`config`; `config` contains exactly one required member:

| Field | Contract |
| --- | --- |
| `model` | Exact case-sensitive identifier joined to one compiler-registered `AWSBedrockModelContract`; it is not treated as an unbounded opaque `modelId`. |
| `config.region` | Exact registered AWS source region for the target, partition, endpoint, operation set, and accepted data-routing policy. |

Unknown fields reject the complete provider registry. In particular, the file
cannot contain an endpoint URL, hostname, partition override, FIPS/dual-stack
switch, API/access/secret/session key or bearer token, profile, role ARN, external ID,
credential source, environment-variable name, metadata endpoint, credential
process, retry count, proxy, CA bundle, header, guardrail, tool, request
metadata, token limit, context window, structured-output flag, tokenizer, or
arbitrary model JSON.

The provider file catalogues a configured registered instance; it does not
place that instance in the repository allowlist or describe model capability.
Only an exact `.sddtoolkit.json` `models.slots` reference may select it for the
repository, and that reference still grants no capability beyond the
compiler-owned contract. The contract is representative of:

```text
AWSBedrockModelContract {
  model: ProviderModelId,
  target: BedrockInferenceTarget,
  partition: RegisteredAWSPartition,
  permittedSourceRegions: RegisteredAWSRegionSet,
  destinationScope: RegisteredBedrockDestinationScope,
  requiredDataRoutingPolicy: RegisteredBedrockDataRoutingPolicy,
  operations: RegisteredBedrockOperationSet,
  exactTokenCounter:
    bedrock_count_tokens {
      relation: RegisteredBedrockCountTokensRelation
    } |
    unavailable,
  responseMode:
    prompt_only |
    native_model_envelope_v1 { schemaFeatureProfileId },
  supportedControls: RegisteredBedrockInferenceControlSet,
  wireBudgets: RegisteredBedrockWireBudgetProof
}
```

The first target union is closed:

```text
BedrockInferenceTarget =
  | foundation_model { modelId }
  | geographic_inference_profile { inferenceProfileId }
  | global_inference_profile { inferenceProfileId }
```

Its destination scope is also closed:

```text
RegisteredBedrockDestinationScope =
  | in_region
  | geographic {
      destinationsBySourceRegion:
        ClosedMap<RegisteredAWSRegion, RegisteredAWSRegionSet>
    }
  | worldwide_commercial_regions_including_future
```

The exact registered model string determines the tag; project input cannot
reclassify it. Prompt-management resources, provisioned/custom/imported models,
application inference profiles, marketplace endpoints, SageMaker endpoints,
agents, and every other Bedrock target kind are rejected in this increment.

Binding proves the selected source region belongs to the target's partition,
supports both required operations, and satisfies the accepted destination and
data-residency policy. A foundation-model target is in-region. A geographic
profile uses the exact compiler-registered finite destination set for the
selected source region, which AWS states does not change. A global profile is
not represented by a compiled finite list: its scope is
`worldwide_commercial_regions_including_future`. It is accepted only when
policy explicitly authorizes worldwide routing, including future AWS commercial
Regions, and is prohibited wherever any geographic residency constraint
applies. `global` is never interpreted as local to `config.region`.

The current example's `global.amazon.nova-2-lite-v1:0` is therefore useful as a
shape example but not automatic runtime authority. AWS documents Nova 2 Lite as
supporting global inference while not supporting CountTokens or structured
output. Its accepted contract must therefore reject explicit count or native
schema operations, but lack of counting does not block prompt-only inference.
Its model contract and global data-routing policy must still be explicitly
accepted. No heuristic tokenizer or optimistic feature flag is permitted.

The example's OpenAI entries are likewise not executable through F0007. The
current provider and toolkit examples are not asserted to be a jointly runnable
fixture, and neither creates fallback behavior.

## 4. Endpoint, environment, and data-routing policy

The endpoint resolver consumes only the validated source region, registered
partition, fixed service name `bedrock-runtime`, and compiled AWS DNS-suffix
policy. It returns one trusted HTTPS origin. Project values are never
concatenated into a URL. Every 3xx response is rejected without following it,
including a same-origin redirect.

The concrete client treats the host environment as hostile input. It must not
silently inherit `AWS_ENDPOINT_URL` or equivalent endpoint overrides, proxy
settings, custom CA-bundle overrides, retry settings, region variables,
profiles, request headers, AWS access-key variables, or arbitrary SDK
configuration. The sole accepted environment input is
`AWS_BEARER_TOKEN_BEDROCK`; it supplies authentication only and cannot alter
the endpoint, region, model, request, policy, or retry behavior. All other
environment inputs are disabled or ignored before client construction.
Negative tests use canary values to prove they cannot redirect or alter a
request.

For inference profiles, `config.region` selects the source endpoint only. The
registered target contract and accepted policy own the destination scope and
data-residency consequences. Binding fails before API-key environment access when
source, partition, target, model availability, geographic destination set or
worldwide scope, or policy does not match exactly.

## 5. API-key and authorization boundary

Amazon Bedrock Runtime requests use bearer authentication. The API key comes
only from the process environment variable `AWS_BEARER_TOKEN_BEDROCK`. The
variable name is fixed by the engine and cannot be configured by a repository,
workflow, CLI argument, provider file, prompt, or model response. The provider
file contains no authentication choice or secret.

No key value may be hardcoded in source, generated code, binaries, examples,
fixtures, tests, configuration, workflow YAML, prompts, command arguments, or
headers stored outside the transient request adapter. Tests create synthetic
canary values at runtime and never contain a usable key. Direct key parameters,
fallback variables, AWS access-key variables, profiles, shared files,
credential processes, container or instance metadata, role assumption, STS,
and a generic AWS default credential chain are not permitted.

`AWSBedrockEnvironmentAPIKeySource` is the sole key reader. It reads the exact
variable once per engine invocation, only after the selected compiled workflow
and validated model binding establish that Bedrock authorization is required.
It rejects a missing, empty, or over-limit value without trimming or
fallback, copies the bytes into one invocation-owned nonserializable secret
snapshot, and never rereads the environment. The snapshot is non-refreshing and
is destroyed when the invocation ends. API-key creation, exchange, expiry
extension, rotation, caching across invocations, and automatic refresh are out
of scope.

That snapshot is F0006's preloaded authorization source. Preparing an
operation-bound lease from it is in-memory and no-I/O. The environment reader
has no model-operation, network, filesystem, process-launch, state, logging, or
workflow capability. The authorization adapter has no environment port.

`AWSBedrockOperationAuthorizationAdapter` is the infrastructure implementation
of F0006's provider-neutral preparation port. The common application action
imports no AWS type. The adapter deposits one move-only capability, already
bound to an operation, provider, region, endpoint, and deadline, into the
supplied runner-private slot; only its opaque validated reference enters the
pipeline. At invocation,
`AWSBedrockProvider` compare-and-swap consumes that lease through the narrow
runner-owned lease port and may use it to construct one transient
`Authorization: Bearer` header. It cannot refresh the key, select another
source, make STS or metadata calls, expose the token, or retry with a different
identity. A missing, expired, mismatched, or already consumed lease terminates
before send.

API-key bytes and authorization headers never enter provider-neutral requests,
pipeline state, diagnostics, logs, prompt capture, or serialized operation
evidence. Deployment authority should permit only the registered operations
and targets. F0007 does not create, edit, rotate, or validate API keys or IAM
policies and does not enable a model.

## 6. Optional exact token-count operation

Counting runs only when explicitly selected by the compiled workflow. It does
not authorize inference, reserve budget, or enforce token/context capacity.

When the registered model contract selects
`bedrock_count_tokens { relation }`,
`countInputTokens` maps one already invoked `input_token_count` operation to
one synchronous CountTokens request for the same source region and target:

```text
POST /model/{registered target}/count-tokens
Content-Type: application/json
Accept-Encoding: identity
{
  "input": {
    "converse": {
      "system": exact translated system blocks,
      "messages": exact translated ordered messages
    }
  }
}
```

Only fields in AWS's `ConverseTokensRequest` contract may be present. The first
increment sends no tool configuration or `additionalModelRequestFields`.
CountTokens does not accept the Converse output configuration, so the
`ModelVisibleInputId` binds the exact model-visible text projection, response
guidance mode, and full schema identity shared by the two operations;
prompt-only schema guidance is included before counting.

Canonical serialization is bounded by `maxCountTokensRequestBytes`, including
the fixed wrapper and worst-case JSON/URI escaping. Header count and bytes are
bounded separately. These checks complete before authorization-header
construction or network I/O; an
over-limit body is `request_limit_exceeded`/`not_sent`, consumes the already
reserved full model attempt, and consumes no AWS request.

The response uses separate small compiler-registered header-count, header-byte,
and identity-encoded body caps and is accepted only when complete, well-formed,
and containing one nonnegative bounded `inputTokens` integer. The observation
binds that number to the exact operation ID, binding ID, and
`ModelVisibleInputId`.

The registered count relation identifies the exact supported text/schema
projection and protocol. Any claim that a count equals inference input usage
requires a proven relation for that mode; it is never an inference gate.

If the model contract says `unavailable`, an explicitly requested count
operation rejects before send; inference remains independently supported. A
missing or malformed successful count normalizes to
`exact_token_count_unavailable`; authorization, throttling, timeout, and service
failures retain their common cause with operation kind `input_token_count`.
For example, a CountTokens `AccessDeniedException` is
`authorization_denied`, not an ambiguous count failure.

A runtime `ValidationException` is `request_rejected`. F0007 never parses AWS
error-message text to infer unsupported CountTokens capability; support is a
compiler-registered preflight fact.

F0007 never estimates tokens from bytes, characters, words, or a related model.
CountTokens has no internal retry or implicit successor. Only compiled YAML
transitions may choose a subsequent operation or an explicitly authorized
retry; a count failure is not a hidden engine-wide inference gate.

## 7. Converse request translation

`invoke` consumes the identified request and operation-bound authorization,
without count evidence, and translates one invoked `inference` operation to exactly:

```text
POST /model/{canonical registered target}/converse
Content-Type: application/json
Accept-Encoding: identity
```

The target path uses the fixed AWS canonical-URI encoding rule; no project or
SDK path builder may reinterpret it. The canonical JSON body has only this
synchronous Converse subset:

| Provider-neutral value | Bedrock field |
| --- | --- |
| Registered target | URI `modelId` |
| Ordered system/guidance text | `system[].text`, preserving item and byte order |
| Ordered user/evidence messages | `messages[]` and `content[].text`, preserving roles and order |
| Optional registered temperature | `inferenceConfig.temperature` only when the exact model contract supports it |
| Complete `model-envelope/v1` schema | `outputConfig.textFormat` only for a compatible `native_model_envelope_v1` contract |

```text
ConverseBody {
  system: [{ text: <ordered guidance text> }, ...],
  messages: [
    { role: <registered role>, content: [{ text: <ordered message text> }, ...] },
    ...
  ],
  inferenceConfig?: { temperature: <validated registered value> },
  outputConfig?: <the exact native structure below>
}
```

Optional members are present only under the stated registered condition; no
empty placeholder or `null` form is accepted. No engine token ceiling or
workflow-budget-derived `maxTokens` is sent. Provider token/context limits
remain provider-owned and their rejection or stop is normalized below.

The adapter uses one canonical JSON serializer. URI escaping, JSON escaping,
content length, host selection, and bearer-header construction are mechanical
adapter transformations with golden tests. Unsupported content or a control
such as the current unregistered `reasoningEffort` fails before I/O; no field
is silently dropped.

Serialization enforces `maxConverseRequestBytes` plus separate header
count/byte ceilings before authorization-header construction or network I/O.
The proof includes the fixed wrapper, URI/JSON escaping, and, in native mode,
the schema's second encoding as a JSON string. `canonicalInputBytes` is not
substituted for this bound. An over-limit request is
`request_limit_exceeded`/`not_sent`, consumes the already reserved attempt, and
is never partially transmitted.

The first implementation sends none of:

- `additionalModelRequestFields` or
  `additionalModelResponseFieldPaths`;
- tools, tool results, or strict tool use;
- guardrail configuration or guard content;
- prompt resources or prompt variables;
- request metadata, performance configuration, or service tier;
- images, documents, video, S3 locations, cache points, reasoning blocks, or
  provider-managed context; or
- streaming, asynchronous, stored conversation, agent, knowledge-base,
  browsing, or provider tool capability.

Native structured output is registered per exact model and schema feature
profile. Bedrock supports a subset of JSON Schema Draft 2020-12, so a versioned
compiler-owned `BedrockJSONSchemaFeatureProfile` must prove representability.
The projected schema is the complete compact result object defined by
[ADR 0006](../decisions/0006-minimal-model-response.md) and the workflow's
declared result schema. `model-envelope/v1` is selected by the engine, not
echoed in model output. Request, operation, unit, revision and binding identities
remain in the trusted call context; the model returns only result fields and,
when alternatives exist, one root `kind`. There is no outer result wrapper.

The exact native projection is:

```text
"outputConfig": {
  "textFormat": {
    "type": "json_schema",
    "structure": {
      "jsonSchema": {
        "schema": <canonical complete compact-result schema JSON string>,
        "name": "sdde_model_envelope_v1"
      }
    }
  }
}
```

The description member is omitted. The type, name, omission policy, schema
canonicalization, and member order are fixed and versioned; project data cannot
alter them.

Positive and negative fixtures cover every supported and prohibited schema
feature. Failure to represent the full schema blocks before the request.
Provider rejection never triggers an unaccounted prompt-only repeat. In
`prompt_only`, `outputConfig` is absent and the full schema remains in bounded,
engine guidance. Both modes still require authoritative engine decode and
validation. Native representability does not depend on CountTokens support.

## 8. Converse response normalization and limits

The transport first enforces registered response header-count and header-byte
ceilings. Requests send `Accept-Encoding: identity`; a response with any
`Content-Encoding` other than absent/`identity` is rejected before entity-body
decoding. No transparent decompressor may bypass accounting.

It also enforces a total `maxConverseTransportBytes` cap over received HTTP
framing, headers, and entity-body octets, then enforces
`maxConverseResponseBodyBytes` while reading the body. These caps are
derived by the registered `BedrockWireBudgetProof` using checked arithmetic,
the fixed protocol version and wrapper, bounded usage fields, and worst-case
JSON escaping for `maxModelEnvelopeBytes`. It is not equated to the content
limit or left as an unexplained constant. CountTokens has separate, smaller
transport/header/body caps under the same identity-encoding rule.

After strict response decoding, the adapter separately enforces:

```text
modelEnvelopeContentBytes <= effectiveOperationOutputBytes
reportedTotalTokens == reportedInputTokens + reportedOutputTokens
```

Usage values are nonnegative integers with checked addition. Overflow,
unsupported cache/accounting fields, inconsistent usage, or a crossed
header/body/content cap fails closed without truncation. There is no token
ceiling or comparison with a previous count. The runner records actual input
plus output usage in the execution ledger, including stopped output; an
overshoot returns the workflow-budget error and prevents subsequent calls.

Strict bounded decoding reads the known `stopReason` before applying content
shape rules. `end_turn` requires exactly one assistant output message and one
complete UTF-8 text block. A recognized non-candidate stop may legitimately
carry no text or a non-text provider output; the adapter boundedly parses only
the fixed outer shape needed for usage/stop classification, discards all output
content, and never exposes or executes it. AWS request IDs, headers, trace data,
provider error bodies, arbitrary additional fields, and raw response JSON never
enter the F0006 result.

Stop normalization is exhaustive:

| Bedrock stop reason | Exact F0006 observation |
| --- | --- |
| `end_turn` | `.completed(rawResult = .complete { content, ... })`; bounded text may proceed to envelope decoding. |
| `stop_sequence` | `.failed(cause = response_invalid)`; no workflow operation authorizes provider stop sequences. |
| `max_tokens` | `.completed(rawResult = .stopped { reason = output_limit, ... })`; content is discarded and no candidate exists. |
| `tool_use` | `.completed(rawResult = .stopped { reason = unsupported_tool_request, ... })`; no tool is executed. |
| `guardrail_intervened` or `content_filtered` | `.completed(rawResult = .stopped { reason = content_filtered, ... })`; no candidate. |
| `malformed_model_output` or `malformed_tool_use` | `.completed(rawResult = .stopped { reason = malformed_output, ... })`; no candidate. |
| `model_context_window_exceeded` | `.completed(rawResult = .stopped { reason = context_limit, ... })`; no candidate. |
| Unknown value | `.failed(cause = response_invalid)`; there is no forward-compatible default. |

Only `complete` content reaches `DecodeModelEnvelopeAction`, where it remains
untrusted. Usage and latency are bounded observations, not evidence of
validity, completeness, or provider capacity.

## 9. Failure normalization and retry ownership

Classification uses the operation kind and decoded AWS exception
discriminator, not HTTP status alone:

| AWS/transport outcome | F0006 cause | Retry class |
| --- | --- | --- |
| Missing, expired, or rejected API key | `authentication_failed` | `never` |
| `AccessDeniedException` | `authorization_denied` | `never` |
| `ValidationException` | `request_rejected` | `never` |
| `ResourceNotFoundException` | `model_unavailable` | `never` |
| `ModelErrorException` (424) with `originalStatusCode` `408`, `429`, `500`, or `503` | `service_unavailable` | `policy_eligible` |
| `ModelErrorException` with `originalStatusCode` `400`, `409`, or `422` | `request_rejected` | `never` |
| `ModelErrorException` with `originalStatusCode` `401` / `403` / `404` | `authentication_failed` / `authorization_denied` / `model_unavailable` | `never` |
| `ModelErrorException` with missing, conflicting, or unregistered nested status | `response_invalid` | `never` |
| `ModelNotReadyException` (429) | `service_unavailable` | `policy_eligible` |
| `ThrottlingException` (429) | `throttled` | `policy_eligible` |
| `ModelTimeoutException` (408) or local operation deadline | `timeout` | `policy_eligible`, still constrained by delivery disposition |
| `InternalServerException` (500) | `service_unavailable` | `policy_eligible` |
| `ServiceUnavailableException` (503) | `service_unavailable` | `policy_eligible` |
| TLS, DNS, connection, send/receive, or transport interruption | `transport_failed` | `policy_eligible` |
| Serialized request body/path/header cap exceeded before send | `request_limit_exceeded` | `never` |
| Malformed/unknown success or error body, unknown exception discriminator, invalid response shape/usage | `response_invalid` | `never` |
| Response header/body or canonical envelope-content cap exceeded | `response_limit_exceeded` | `never` |
| Missing or malformed successful exact count | `exact_token_count_unavailable` | `never` |

CountTokens retains the same causes with operation kind `input_token_count`;
Converse uses `inference`. If a status and decoded discriminator conflict, the
response is invalid rather than guessed. Bounded diagnostics may expose only
operation identity, normalized cause/retry class, a safe status class, and a
closed public rule code—never AWS error text or raw data.

Delivery disposition is classified independently:

- local binding/serialization/authorization rejection before any request byte is
  `not_sent`;
- a completely decoded AWS success or exception response is
  `response_received`; and
- any timeout, cancellation, crash, connection loss, or receive failure after
  transmission begins is `accepted_or_unknown`.

The adapter never infers delivery from HTTP status or error prose. Recovery of
an invoked operation without a durable terminal observation is
`accepted_or_unknown`, never an automatic replay. The default terminal result
is blocked for ambiguous external effect/provider spend; only an explicitly
accepted duplicate-effect policy may permit a new separately reserved attempt.

`AWSBedrockProvider` cannot write or inspect the effect journal. It receives an
`InvokedProviderOperation` only after the runner durably commits
`send_may_occur`; `AWSBedrockRuntimePort` rejects any call without that proof.
On restart, F0006 recovery classifies journal records before a workflow may
reserve another provider operation. A crash before `send_may_occur` is
not-sent; a crash from that commit until `terminal_observed` is durable is
ambiguous, including after AWS returned a response that was not durably
recorded. A durable `terminal_observed` AWS success is not recoverable merely
from its non-content journal facts: recovery must prove the exact durable
CountTokens-evidence or model-result successor and idempotently mark
`outcome_consumed`; without that successor it returns
`terminal_result_unavailable` and blocks by default. Only an accepted
duplicate-effect/spend policy may authorize a new attempt, never reuse of the
old operation.

All AWS SDK/client automatic retries, adaptive retries, redirect retries, and
API-key refresh retries inside the provider call are disabled. One F0006
interface call corresponds to zero or one bearer-authorized AWS request.
Provider backoff hints may be normalized as bounded non-authoritative facts
only if accepted policy defines them; the adapter never sleeps or chooses
another model.

A protocol-retry operation is not a provider-failure retry owner; it remains
restricted to decoder/workflow-result-schema failures after a response. Only
the compiled YAML transition may choose a declared provider-retry operation
from cause, retry class, delivery disposition, and policy. The runner
reserves/applies the new attempt and lifecycle but chooses no branch.
Exhaustion blocks or fails; it never weakens policy. Provider failure is not
model-content `invalid` and never enters semantic repair.

Explicit runner cancellation remains terminal `cancelled`, aborts or abandons
in-flight transport under the accepted port, and releases all owned state.
Its operation terminal fact still records `not_sent` or
`accepted_or_unknown`. Cancellation and timeout never become a successful empty
response.

## 10. Ownership, cleanup, and concurrency

Every endpoint value, environment API-key snapshot, transient authorization
header, request body, lease slot/ref, authorization capability, effect-journal
handle, transport handle, raw response buffer, decoded AWS value, and normalized
observation has one owner and deterministic destruction on success, rejection,
cancellation, timeout, recovery, and operational failure.

Before consume, the runner-private table exclusively owns each move-only,
nonserializable, nonloggable authorization capability. A successful one-use CAS
moves ownership to `AWSBedrockProvider`, which destroys it after the call. If no
consume occurs, the table finalizes it. The envelope contains only the opaque
reference, never the capability. Journal records persist no reference backing
or API key and cannot reconstruct one after restart. Raw bodies remain
adapter-private until `.complete` text is moved into the bounded F0006 result;
all output for `.stopped` is discarded and all AWS storage is destroyed.

The initial engine executes provider work sequentially. F0007 introduces no
concurrent calls. Later concurrency requires accepted overlay, operation-ID,
client, authorization-capability, quota, cancellation, resource-conflict, and
failpoint evidence; client thread safety alone is insufficient.

## 11. Security and observability

- Only authorized infrastructure modules import AWS, HTTP/TLS, environment, or
  API-key handling APIs; application/domain code imports only F0006 types.
- Project input cannot choose an origin, redirect, proxy, CA override,
  credential source, header, request field, provider tool, target tag, or
  destination region set.
- `AWSBedrockProvider` has no filesystem/process authority; the common
  authorization action has only the provider-neutral preparation port, and its
  AWS infrastructure implementation has no model-operation port.
- The API key, authorization header, environment snapshot, raw bodies,
  endpoints, and AWS error details never enter canonical state, diagnostics,
  the provider-operation effect journal, prompt capture, or metadata logs.
- F0002 prompt capture uses only pre-serialization typed fragments with
  opt-in selectors, redaction, and limits. A Bedrock wire body is never captured
  opaquely.
- AWS account-side invocation logging is external operator policy, not F0002 or
  workflow authority, and requires separate data-governance review before live
  use.

## 12. Explicit non-responsibilities

F0007 does not implement:

- provider-file discovery, generic JSON decoding, registry construction, slot
  selection, or workflow-operation selection;
- prompt/guidance semantics, envelope decoding, candidate validation, repair,
  attempt accounting, retry, or fallback;
- streaming, `InvokeModel`, OpenAI-compatible APIs, Anthropic Messages, prompt
  management, tools, guardrails, S3 content, agents, knowledge bases, browsing,
  stored sessions, or asynchronous inference;
- implicit region discovery, custom endpoints, SigV4 credentials, direct API-key
  parameters, API-key generation/refresh, or any default credential chain;
- IAM/model enablement, quota management, billing policy, or AWS account
  administration;
- an exact tokenizer for Nova 2 Lite; or
- selection of an AWS SDK, C ABI, HTTP/TLS library, linking strategy,
  or supported platform matrix.

## 13. Acceptance criteria

1. `AWSBedrockProvider` conforms directly to F0006 and no AWS type crosses into
   domain/application code.
2. F0006's common decoder accepts the example's exact
   `providers/provider/models/model/config` hierarchy. In a Bedrock-only
   executable, its unimplemented OpenAI sibling then fails whole-registry
   validation; a Bedrock entry accepts only exact `config.region`.
3. Provider data cannot declare a capability, limit, endpoint, target tag,
   tokenizer, structured-output mode, credential, retry, header, or arbitrary
   request field.
4. Every Bedrock catalogue model joins exactly to a compiled Bedrock contract
   and one of the three closed target variants; all other target kinds fail
   before I/O. Invocation additionally requires an exact repository-allowlist
   slot reference to that catalogue entry.
5. Source region, partition, target availability, geographic destination set or
   worldwide scope, and data-routing policy validate before authorization.
6. Global inference requires acceptance of worldwide routing including future
   commercial Regions and is prohibited under geographic residency constraints;
   the example's source region is not its only processing region.
7. Host endpoint, proxy, CA, retry, region, profile, access-key, and header
   overrides cannot alter the constructed client. Only
   `AWS_BEARER_TOKEN_BEDROCK` is read, and it can affect authentication only.
8. The common authorization action imports no AWS type. A narrow infrastructure
   source reads `AWS_BEARER_TOKEN_BEDROCK` once per Bedrock-requiring invocation
   into an owned, bounded, non-refreshing snapshot; missing, empty, or
   over-limit input fails before send. Lease preparation is then in-memory
   and no-I/O. The move-only capability stays in a runner-private single-use
   table; only its validated opaque reference enters the pipeline.
9. CountTokens is called only for an explicitly selected, registered supported
   count operation, at most once for that operation identity. Inference works
   without counting.
10. Nova 2 Lite cannot silently use CountTokens or native structured output;
    an accepted prompt-only contract does not require a tokenizer.
11. Checked canonical input and serialized CountTokens/Converse request/header
    byte safety pass at their defined pre-I/O gates. No engine token/context
    preflight or output-token reservation is imposed.
12. Inference is exactly one synchronous Converse request with SDK/client
    automatic retries disabled.
13. Only the Section 7 request subset is reachable; unsupported content or
    controls fail before I/O and are never silently omitted.
14. Native response schema, when registered, covers the complete exact
    compact result under `model-envelope/v1` (not engine-only identity fields),
    uses the fixed Section 7 projection, passes the
    versioned Bedrock schema-feature proof, and requires no count prerequisite.
15. Native response rejection never triggers an unaccounted prompt-only call;
    every result still passes engine decoding and validation.
16. Request headers/bodies, response headers/identity-encoded bodies, and
    canonical envelope caps are separate, proven, and enforced without
    truncation or transparent decompression.
17. Returned Converse usage is internally consistent and accounted from API
    input plus output totals, never from a prior count or output allowance.
18. Every known stop reason and AWS exception maps to one exact observation;
    unknown, inconsistent, or unregistered nested status fails closed.
19. Every failure records `not_sent`, `response_received`, or
    `accepted_or_unknown`; `send_may_occur` is durable before transmission,
    distinct CountTokens/Converse records join one attempt record, and
    `terminal_observed -> outcome_consumed` proves the result handoff.
    Invoked-without-terminal and terminal-result-unavailable recovery never
    auto-replay.
20. Provider failures never become model-content `invalid`; only an accepted
    capability-free provider/generation retry owner chooses a new attempt, and
    the runner only validates/applies its accounting.
21. No adapter retry, sleep, fallback, repair, state mutation, or workflow
    transition is possible.
22. The API key, authorization header, environment snapshot, bodies, endpoints,
    and AWS-native metadata never enter state, diagnostics, prompt capture, or
    ordinary logs; no real or placeholder key is hardcoded in source, examples,
    fixtures, workflow YAML, configuration, prompts, binaries, or arguments.
23. All owned AWS, transport, API-key, request, and response resources are
    destroyed exactly once on every terminal branch.
24. Deterministic CI uses the F0006 fake provider. Any live test is explicit,
    API-key-gated, non-default, separately authorized, and excluded from
    deterministic CI.
25. The packaged native executable requires no repository example, AWS CLI,
    Node.js, Zig toolchain, source tree, or development cache.

## 14. Verification

Implementation evidence must cover:

- **Configuration/contracts:** exact lean Bedrock entry; reordered fields;
  missing/unknown/prohibited fields; invalid provider/model/region; duplicate
  tuple; common-decode/unimplemented-provider registry rejection; all accepted
  and rejected target tags; source/partition/geographic-scope mismatch;
  worldwide/future-region acceptance and residency denial; unsupported
  operation/control/schema mode.
- **Environment/endpoint:** trusted region and DNS resolution, HTTPS-only,
  every 3xx rejection, canary endpoint/proxy/CA/retry/region/access-key
  environment overrides, exact sole recognition of
  `AWS_BEARER_TOKEN_BEDROCK`, and no project-created origin.
- **API key/authorization:** provider-neutral action/import boundary; missing,
  empty, and over-limit environment values; exact one-read snapshot;
  no reread, fallback, generation, refresh, default chain, file, process,
  metadata, STS, or hardcoded-key path; preloaded lease expiry/deadline; private
  lease-slot fill, envelope-visible opaque ref only, stale/mismatched/reused ref
  rejection, capability operation binding and one-time CAS move; exact transient
  bearer header; runtime-created secret canaries; cleanup before and after
  invocation.
- **Token count:** registered support and Nova unsupported case; exact request
  content/order; zero/boundary/overflow counts; missing/malformed count;
  AccessDenied, throttle, timeout, service failure, cancellation, wire cap;
  optional count association and registered relation; one call per explicit
  count operation; inference without a counter or count evidence.
- **Request/schema:** golden URI, system/message order, UTF-8/JSON escaping,
  exact/over request and header caps including schema double-encoding,
  absent `maxTokens`, supported temperature, prompt-only omission, fixed full-envelope
  `outputConfig` structure/name/description omission, every allowed/prohibited
  Bedrock JSON Schema feature, and negative fixtures for every undeclared
  request field/content kind.
- **Response/limits:** valid complete text; every known and unknown stop;
  non-text/nonexistent output on known non-candidate stops; missing/multiple text
  on `end_turn`; invalid UTF-8/JSON; negative/overflow/inconsistent usage and
  no count prerequisite; exact/exceeded header/body/content caps; provider
  output/context stops and workflow actual-usage exhaustion; rejected
  content encoding; short read; cancellation/timeout at each receive boundary;
  deterministic cleanup.
- **Failures/accounting:** exception-discriminator mapping for representative
  AWS 400/403/404/408/424 nested-status cases/429/500/503 responses,
  status/discriminator conflict, malformed error, TLS/DNS/transport failure,
  `not_sent`/`response_received`/`accepted_or_unknown`, one attempt record with
  distinct CountTokens/Converse operation records, and durable journal crashes
  before/after `send_may_occur`, first byte, response, `terminal_observed`,
  successor commit, and `outcome_consumed`. Recovery fixtures cover both an
  idempotently joined durable successor and `terminal_result_unavailable`
  without replay, plus no raw-error leakage, disabled retries, and a new
  runner-owned attempt before any second call.
- **Architecture/security:** AWS and environment imports confined to their
  narrow adapters; common
  authorization action depends only on the provider-neutral port; AWS
  authorization adapter lacks model-operation authority; pipeline values
  contain only lease refs and the private table is runner-owned; provider lacks
  filesystem/process/state/log/transaction/tool capability; no provider port in
  orchestrators or `NodeRuntime`; F0002 fragment-only capture.
- **Packaging:** fake-provider clean native smoke tests without AWS tooling or
  API keys. A separately authorized live smoke test receives its dedicated
  least-privilege non-production key only through
  `AWS_BEARER_TOKEN_BEDROCK` and is never deterministic CI.

## 15. Traceability

| Concern | Authority |
| --- | --- |
| Common interface, provider file, registry, and operation algebra | F0006 Sections 1-10 |
| Provider adapter and dependency boundary | Design Sections 5-6 and 26; ADR 0001 |
| Request/invoke/decode and operation accounting | Design Sections 12.1-12.4 and 13.4; accepted F0006 Section 7 amendment |
| Workflow-operation capacity, schema, retry, and repair | Design Sections 12.5-12.7 and 21-22; ADR 0005 |
| Candidate trust, response limits, and secrets | Design Sections 3-4, 26.1, 26.5, and 27; F0002 |
| Bedrock request/response/error protocol | AWS Converse, CountTokens, and structured-output references linked above |
| Bedrock target, endpoint, API-key authorization, and least privilege | AWS Nova model card, endpoint, API-key, and IAM references linked above |
| Fake-first testing and native packaging | Design Sections 28 and 30-31; F0006 Sections 12-13 |
