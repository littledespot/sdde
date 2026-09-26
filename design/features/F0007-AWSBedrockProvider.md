# F0007 — AWSBedrockProvider

**Status:** Production integration accepted as part of F0006 completion.

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
      "config": {"region": "ap-southeast-2"}
    }]
  }]
}
```

`json: true` uses InvokeModel with `response_format.type: "json_schema"` and
`response_format.json_schema.schema` as an object ([AWS structured-output contract](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)).
`false` sends complete schema guidance without that native output constraint.
Neither changes engine validation or permits fallback after provider rejection.

The initial registered contracts are:

| Exact model | Explicit region | InvokeModel | CountTokens | Response modes |
| --- | --- | --- | --- | --- |
| `openai.gpt-oss-20b-1:0` | `ap-southeast-2` (Sydney) | Yes | No | Prompt-only; native schema projection |
| `anthropic.claude-3-5-haiku-20241022-v1:0` | `us-west-2` | Unresolved; see below | Yes | Prompt-only |

**Outstanding catalogue decision:** the unused Haiku registration predates this
amendment. Its native request requires a different codec and an explicit output
limit, incompatible with simply reusing the open-weight body. Removal has been
proposed for approval; the API transition is not complete while that incompatible
registration remains. No current project catalogue selects it.

- Both support the registered temperature control.
- GPT-OSS registers the explicit reasoning-effort values `low`, `medium` and `high`;
  Claude registers none.
- Unknown models, source regions, configuration fields, controls and capability claims
  reject.
- Only these in-region foundation-model targets are installed; geographic/global
  profiles and their data-routing policies are not silently enabled.
- Future support requires another trusted contract, not an inferred capability or
  model-name pattern.

- AWS documents [Sydney availability and capabilities for
  gpt-oss-20b](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-oss-20b.html).
- The [CountTokens
  example](https://docs.aws.amazon.com/bedrock/latest/userguide/count-tokens.html) uses
  the registered Claude 3.5 Haiku ID.
- Separate counting is an explicit YAML operation and cannot authorize inference or
  charge usage.
- Actual input/output usage accounting from inference is mandatory regardless of
  CountTokens support.

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

- Under the user-approved 25 September 2026 amendment, inference uses only
  `/model/<encoded-model>/invoke`; CountTokens uses `/model/<encoded-model>/count-tokens`.
- The shared open-weight codec emits ordered system/guidance text blocks in one
  `developer` message and user/evidence blocks in one `user` message. Explicit
  user/evidence input is required; no input text is invented.
- CountTokens wraps the exact serialized inference body as base64 in
  `input.invokeModel.body`. A model without exact-count support rejects before dispatch.
- Supported temperature remains `0` (§12.5); selected `reasoning_effort` is a
  top-level field. Both follow the existing binding, not adapter defaults.
- Model and streaming fields are omitted because the endpoint fixes them
  ([AWS model parameters](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-openai.html)).
  No output ceiling, tools, stop sequences or arbitrary parameters are added.
- Both response modes add the complete compiled result schema once to guidance.
  Native mode also sends its registered structural projection as a JSON object in
  `response_format.json_schema.schema`, with `type: "json_schema"` and name
  `sdde_model_envelope_v1`. Prompt-only mode omits `response_format`.
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

- Inference validates `prompt_tokens`, `completion_tokens` and `total_tokens`
  with checked `input + output == total`. Optional closed token-detail objects
  are metadata, never additional charges. No response-body latency is invented.
- One choice at index zero with `finish_reason: "stop"` must contain an assistant
  message. Its string `content` remains an untrusted candidate.
- Only the documented leading `<reasoning>...</reasoning>` framing is separated
  from final text. Reasoning-only, empty or absent final text yields
  `missing_final_text`; reasoning never becomes candidate content.
- Valid wire/usage retains actual usage on content rejection. Only missing final
  text is eligible for the existing bounded correction under §22.6; other invalid
  content remains terminal. The adapter never repairs JSON or retries.
- Refusal and tool-call metadata cannot become an answer. Unknown fields, wrong
  types, multiple choices and unknown finish reasons reject.

Recognized non-candidate finishes discard content and retain usage:

| AWS finish reason | F0006 outcome |
| --- | --- |
| `length` | `output_limit` |
| `tool_calls`, `function_call` | `unsupported_tool_request` |
| `content_filter` | `content_filtered` |
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
