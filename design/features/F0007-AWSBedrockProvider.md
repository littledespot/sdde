# F0007 — AWSBedrockProvider

**Status:** Production integration accepted as part of F0006 completion. The
2026-10-15 user-directed amendment uses Bedrock Converse for inference and
preserves provider reasoning as separate, owned diagnostic data.

- The user explicitly includes production contracts, concrete authorization/count/
  inference implementations, applicable native-schema checks and shared adapter
  conformance in F0006 completion.
- The F0007 label is not a deferral or approval gate for that work.
- No third-party production dependency is added: transport uses the already pinned Zig
  standard library.
- Live AWS requests, credential inspection, IAM changes and model enablement require
  separate authorization.

## Responsibility and ownership

Bedrock implements the existing [F0006](F0006-LLMProviderInterface.md) port.
It translates one authorized request and normalizes one response. It never
chooses a workflow transition, retries, decodes the model's result JSON,
charges tokens, or grants success authority.

| Owner | Responsibility |
| --- | --- |
| `composition/provider_model_contracts.zig` | Immutable supported-model facts; no client or credential. |
| F0008 and F0006 bootstrap | Capture the configured provider file once, validate its complete catalogue and repository slot allowlist. |
| `adapters/system/bedrock_api_key_source.zig` | Read the exact permitted environment variable once after selected-workflow binding validation. |
| `adapters/provider/bedrock_authorization.zig` | Deposit a capability from preloaded material; no environment or I/O port. |
| `adapters/provider/aws_bedrock.zig` | Implement the sole provider-neutral port using the existing lease-consumption boundary. |
| `bedrock_request.zig` / `bedrock_response.zig` | Canonical request projection / strict AWS response normalization. |
| `bedrock_http.zig` | One HTTPS exchange with its original deadline, without retries or redirects. |
| `composition/model_provider_runtime.zig` | Wire implementations to existing YAML bindings and the runner-owned lease table. |
| Pipeline runner | Own lifecycle, single-use leases, actual-usage accounting and cleanup. |

The infrastructure-private exhaustive dispatch has one `aws_bedrock` variant.
Domain registry entries contain only facts. There is no second provider
registry, provider journal, feature transaction, saved response, or recovery
gate. An interrupted atomic execution is abandoned; another run starts afresh.

## External configuration and supported contracts

`.sddtoolkit.json` selects the file through `paths.providers`. That immutable
`.sddproviders.json` catalogue contains exact provider/model tuples and closed
configuration. The repository's `models.slots` authorizes some or all catalogue
entries, never an absent entry. No model or region is a runtime default.

```json
{
  "providers": [{
    "provider": "aws-bedrock",
    "models": [{
      "model": "openai.gpt-oss-20b-1:0",
      "json": true,
      "config": {"region": "ap-southeast-2", "maxOutputTokens": 16384}
    }]
  }]
}
```

`maxOutputTokens` is the model's documented maximum output (AWS documents "16K" for
GPT-OSS-20B, and retained runs show Bedrock accepts and reaches 16,384). It is
required, positive and
sent unchanged; there is no default.

`json: true` uses Converse with `outputConfig.textFormat.type: "json_schema"`
and `outputConfig.textFormat.structure.jsonSchema.schema` as a JSON string
([AWS structured-output contract](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)).
`false` sends complete schema guidance without that native output constraint.
Neither changes engine validation or permits fallback after provider rejection.

The compiled registry supports these exact contracts:

| Exact model | Explicit source region | Converse | CountTokens | Response modes | Registered reasoning policy | Temperature |
| --- | --- | --- | --- | --- | --- | --- |
| `openai.gpt-oss-20b-1:0` | `ap-southeast-2` (Sydney) | Yes | No | Prompt-only; native schema projection | OpenAI effort: `low`, `medium`, `high` | Fixed `0.1` |
| `anthropic.claude-3-5-haiku-20241022-v1:0` | `us-west-2` | Yes | Yes | Prompt-only | None | Fixed `0.1` |
| `global.openai.gpt-6-luna` | `ap-southeast-2` (Sydney) | Yes | No | Prompt-only; native schema with required strict flag | Provider default only; documented medium | Omitted |

The current Luna tuple is an explicitly registered **global inference profile**
with Sydney as its source region. It may route worldwide and provides no
Australian-residency guarantee. The base `openai.gpt-6-luna` model is not available
for in-region runtime invocation, and the US geographic profile is not supported
from Sydney. These are exact registrations, not model-name pattern rules. AWS's
[current Luna model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-6-luna.html)
confirms Converse, native JSON Schema, global-profile Sydney availability,
Standard tier only and no CountTokens support (checked 2026-10-15).

AWS documents default medium reasoning and several effort options, but does not
establish their exact Converse override fields. SDDE's evidence-backed subset
admits only omission of explicit reasoning and temperature controls. It neither
sends an inferred field nor claims adjustable-temperature support. The native
JSON profile additionally requires
`additionalModelRequestFields.text.format.strict: true`. No performance or model
quality conclusion follows from API availability.

- Unknown models, source regions, configuration fields, controls and capability claims
  reject.
- Future support requires another trusted contract, not an inferred capability or
  model-name pattern.
- Existing GPT-OSS and earlier Haiku registrations remain production contracts and
  offline conformance representatives. They do not qualify current-model outcomes.
- The separate development [live-test cost policy](../../test/harness/model_cost_policy.zig)
  permits only Bedrock `openai.gpt-oss-20b-1:0` for generation, grading and
  captured-call diagnostics. Sonnet, Sol, Haiku, Luna, direct OpenAI
  and other aliases reject before credentials or network use. Production
  catalogue policy remains independent.
- The rubric judge retains its native-schema gate; GPT-OSS-20B satisfies the registered
  capability contract without fallback. See the [evaluator contract](../harness/evaluator.md).

Separate counting is an explicit YAML operation and cannot authorize inference or
charge usage. Actual inference input/output usage accounting is mandatory
regardless of CountTokens support. The [CountTokens contract](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CountTokens.html)
accepts the same Converse input where the selected model supports counting.

## Credentials and transport

- Only `AWS_BEARER_TOKEN_BEDROCK` supplies the API key.
- The environment source captures it once after exact workflow selection and
  model-binding validation, and only if the graph declares authorization preparation.
- Missing, empty, whitespace-containing or non-ASCII values fail without trimming or
  fallback.
- The owned snapshot is non-refreshing; copied secret bytes are zeroed on cleanup.
- Tests generate synthetic canaries at runtime, never hardcoded keys.

- Preparing a lease is entirely in-memory.
- The existing runner table binds it to the exact request, binding, operation and
  deadline.
- The adapter consumes it once; wrong, stale, expired, foreign or reused evidence cannot
  send a request.
- Pipeline data contains only opaque references, never the secret or a provider client.
- The invocation destroys the runner and its leases before the key snapshot.

- The fixed endpoint is `https://bedrock-runtime.<registered-region>.amazonaws.com`.
- The model ID is percent-encoded as one URI path segment.
- Requests use POST, `Content-Type: application/json`, `Accept-Encoding: identity`, and
  one transient bearer header.
- Proxy, endpoint, region, retry, profile, credential-chain and CA-bundle environment
  overrides are not initialized.
- TLS uses system trust.
- Redirects and non-identity content encoding reject; neither causes a resend.

- The standard HTTP head parser reads through growing invocation-owned storage, so a
  fixed socket buffer does not become an engine header-size limit.
- The request and complete response have no engine byte ceilings.
- One network task is raced against the original monotonic deadline and joined before
  releasing call storage; this is not parallel workflow execution.
- Cancellation stays cancellation.
- Transmission uncertainty stays `accepted_or_unknown`.
- Socket read/write errors retain cancellation separately from HTTP framing errors.
- EOF before a declared body ends rejects without publishing partial data.

## Request and schema projection

- Inference uses only
  `/model/<encoded-model>/converse`; CountTokens uses
  `/model/<encoded-model>/count-tokens`.
- The canonical [Converse codec](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html)
  emits ordered system/guidance text blocks in `system` and user/evidence blocks
  in one `user` message. Explicit user/evidence input is required; no input text
  is invented. Model ID is supplied by the authorized endpoint target.
- CountTokens sends `input.converse` with the same `system`, `messages` and
  `additionalModelRequestFields`. It omits inference/output controls absent from
  the [count input contract](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseTokensRequest.html).
  A model without exact-count support rejects before dispatch.
- Supported temperature is `0.1` (§12.5), serialized under
  `inferenceConfig.temperature`; unsupported temperature is omitted.
- The compiled `BedrockRequestProfile` selects verified model-specific request
  fields: `.openai_oss` projects GPT-OSS `reasoning_effort`, while `.openai_luna`
  supplies the required native JSON strict-format flag and admits no explicit
  reasoning override. `.none` supplies no additional profile fields. Neither the
  project nor a model-name prefix selects the wire contract.
- Every inference request sends the catalogue's `maxOutputTokens`, the model's
  documented maximum, as `inferenceConfig.maxTokens`; thinking and final text share
  it. Omitting it let Bedrock apply a smaller default (GPT-OSS-20B stopped at 4,096)
  ([ADR 0011](../decisions/0011-provider-owned-request-limits.md#model-maximum-output)).
  No local limit below that maximum, reservation or silent control substitution is
  introduced.
- No streaming, tools, stop sequences or arbitrary request parameters are added.
- Both response modes add the complete compiled result schema once to guidance.
  Native mode also sends its registered structural projection as a JSON string in
  `outputConfig.textFormat.structure.jsonSchema.schema`, with type `json_schema`
  and name `sdde_model_envelope_v1`. Luna native mode also emits
  `additionalModelRequestFields.text.format.strict: true`; prompt-only mode
  omits both native output fields. No service-tier override is sent, retaining
  the model's supported Standard default.
- This is derived data, never a second schema source.
- Under [ADR 0006](../decisions/0006-minimal-model-response.md), closed objects,
  required fields, types, enums and constants are retained; disjoint tagged `oneOf`
  becomes `anyOf`, and a positive array minimum becomes `minItems: 1`.
- Bounds unsupported by [Bedrock's schema
  subset](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
  remain in complete guidance and authoritative engine validation.
- No error triggers a response-mode fallback.
- Both modes require the same explicit YAML response validation, strict JSON decoding
  and payload validation.

## Response, failure and accounting

- All bodies use the existing strict JSON boundary: invalid UTF-8, duplicate keys,
  trailing content, unknown fields and wrong wire types reject.
- Count success contains exactly one nonnegative integer `inputTokens`, bound to the
  original operation, binding and input.
- No tokenizer approximation is used.

- Inference validates Converse `usage.inputTokens`, `outputTokens` and
  `totalTokens`, including optional closed cache counters/details with checked
  arithmetic. AWS's [prompt-caching contract](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html)
  reports uncached input separately: inclusive input is `inputTokens +
  cacheReadInputTokens + cacheWriteInputTokens`; inclusive input plus output must
  equal `totalTokens`. Implicit caching can occur without explicit cache points.
  Optional validated `metrics.latencyMs` remains provider-reported metadata.
- `usage.serverToolUsage` is optional and accepts only a closed empty object.
  This supported wire shape comes from a captured native Converse response, retained as an
  [offline regression fixture](../../src/test_fixtures/bedrock_converse_usage/response.json).
  AWS's published [TokenUsage schema](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_TokenUsage.html)
  does not describe this field. No nonempty member contract is inferred: null,
  scalar, array and nonempty object values reject. This metadata grants no tool
  capability and changes neither token arithmetic nor candidate authority.
- Response inspection retains the shared decoder's rejection reason and escaped
  field path. Unknown usage remains unaccountable; compatibility reports preserve
  the decoding diagnostic instead of replacing it with a missing-usage label.
- `stopReason: "end_turn"` with an assistant `output.message` permits candidate
  text extraction. Text blocks concatenate exactly in order without separators,
  JSON scanning, reasoning-tag stripping or rewriting provider text.
- Closed `reasoningContent` blocks are separate diagnostic values: readable
  `reasoningText` with optional signature, or base64 `redactedContent`. They
  never join the candidate or authorize a workflow transition.
- `RawProviderModelResult.complete`, `.stopped` and `.rejected` can each own an
  optional ordered reasoning diagnostic. Ownership moves from decoder to provider
  observation; destroying that observation frees every block/signature/redacted
  buffer on each terminal path. See [F0006's lifetime contract](F0006-LLMProviderInterface.md#8-closed-request-observation-and-failure-algebra).
- Valid reasoning and usage survive absent/invalid final text and non-candidate
  stops. Reasoning-only, empty or absent final text yields `missing_final_text`.
  Provider-redacted reasoning remains unreadable; it is not decrypted or invented.
- Only missing final text is eligible for existing bounded correction under §22.6;
  other invalid content remains terminal. The adapter never repairs JSON or retries.
- Refusal, unexpected tool use, malformed blocks and unknown stop reasons cannot
  become an answer. No reasoning block becomes a substitute final response.

The debugger's **Response → Provider reasoning** card presents these diagnostics
separately from extracted text, parsed candidate JSON and schema results. The raw
credential-redacted provider response also remains available. Reasoning is neither
semantic proof nor an input to completion, repair authority or workflow decisions.

Recognized non-candidate stops retain usage and any valid reasoning diagnostics:

| AWS `stopReason` | F0006 outcome |
| --- | --- |
| `max_tokens` | `output_limit` |
| `tool_use`, `malformed_tool_use` | `unsupported_tool_request` |
| `content_filtered`, `guardrail_intervened` | `content_filtered` |
| `malformed_model_output`, unexpected `stop_sequence` | `malformed_output` |
| `model_context_window_exceeded` | `context_limit` |
| Unknown | `invalid_content` rejection |

- AWS exception discrimination follows the [restJson1 error
  encoding](https://smithy.io/2.0/aws/protocols/aws-restjson1-protocol.html#operation-error-serialization):
  the header, `__type` or `code` must resolve to one recognized shape name after the
  specified namespace/colon normalization.
- Status or discriminator disagreements reject.
- Authentication, access denial, validation, missing model, throttling, model readiness,
  timeout and service failures retain their closed F0006 causes.
- `ModelErrorException` requires its recognized nested status.
- Error prose never determines retryability and is never exposed.
- Malformed successful counts return `exact_token_count_unavailable`.

No request bytes sent means `not_sent`; a complete response means
`response_received`; transport interruption after transmission begins means
`accepted_or_unknown`. Only YAML can select an explicit retry with a new
attempt and lease. The adapter does not back off, refresh, reroute or replay.
Under [ADR 0030](../decisions/0030-engine-owned-model-request.md) (not yet implemented), a
protocol correction is a stage of the `request-model` step, bounded by its `retry-limit`,
with a new attempt and lease. The adapter still never retries.

- The existing runner charges actual inference usage once, including stopped output.
- An overshoot remains recorded and rejects the execution; later calls are prohibited.
- Missing/unusable usage after possible delivery blocks subsequent calls without
  fabricating zero.
- Response validation and lifecycle closure never charge tokens again.

## Acceptance evidence

- Shared fake/Bedrock conformance covers exact association, count/inference,
  single-use authorization, deadlines, failures, cancellation and owned cleanup.
- Wire fixtures cover canonical projection, URI encoding, strict response and
  usage rejection, secret redaction, native projection, unsupported
  counting, status/type agreement and growing HTTP headers.
- Fixtures prove every inference request carries exactly the configured `maxTokens`,
  that a missing, zero, negative or oversized catalogue value rejects, and that
  CountTokens retains identical model-visible input without inference controls or
  clamping.
- [Concrete HTTP tests](../../src/bedrock_http_test.zig) exercise the actual serializer,
  response reader and deadline race over event-controlled in-memory connections.

  - They prove one bearer header and request per call, fragmented writes/reads,
    in-flight timeout/cancellation, truncated and malformed bodies, completion during
    cancellation cleanup, no redirect/service-error resend, and task/connection cleanup
    under allocation or scheduling failure.
  - Only connection establishment is substituted at compile time; production remains
    bound to Zig's HTTPS opener.
  - These tests perform no DNS, TLS handshake or AWS request.
- YAML tests use the real production composition and adapter with a deterministic
  transport: complete lifecycle, count then inference, missing-key termination,
  budget overshoot and execution isolation. No test silently bypasses a ledger.
- Packaged tests run externally configured provider workflows without source-
  tree fallback or development assets, and stop without network when keys are
  absent. Architecture checks enforce the same narrow boundaries.

Run `zig build test-provider-conformance test-model-request-workflow --summary all`
and the repository-wide `zig build verify --summary all`. Live calls are not
part of deterministic acceptance and remain separately authorized.
