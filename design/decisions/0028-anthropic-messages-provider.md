# ADR 0028: Anthropic Messages API provider on shared provider owners

- **Status:** Accepted
- **Date:** 2026-10-21
- **Decision authority:** User decisions, 16, 18 and 21 October 2026 and 10, 17, 21 and
  25 November 2026
- **Amends:** ADR 0011 "Model maximum output"; ADR 0019; design invariant 32 and
  acceptance criterion 31.12; §9, §12.3 and F0006–F0008. The overall design remains
  **Proposed design**.
- **Amended by:** [ADR 0029](0029-bedrock-model-families.md),
  [ADR 0030](0030-engine-owned-model-request.md)

## Context

Claude through the Anthropic Messages API is a peer of Amazon Bedrock Converse, with the
shared behaviour implemented once.

## Decision

### Peer providers selected by configuration

- `.sddproviders.json` lists Anthropic and Bedrock models. `.sddtoolkit.json`
  binds each slot to one entry. A workflow may use either provider, or both.
- Each call keeps its slot's binding, including its retries and protocol
  corrections. There is no cross-provider fallback, no model-name branching and no
  engine choice between providers.
- One token budget, capture path and set of validation and publication rules apply
  to both providers. Each catalogue entry carries its own deadline
  ([ADR 0030](0030-engine-owned-model-request.md#request-deadline)).

### Shared owners

Common mechanics have exactly one implementation. Provider modules hold only wire
projections and never import a sibling provider.

| Owner | Responsibility |
| --- | --- |
| `domain/llm_provider_contracts.zig` | `ProviderFacts`, a union tagged by provider family. Bedrock facts carry the compiled family (ADR 0029); Anthropic carries none. The tag also names the configuration schema. |
| `domain/llm_provider_config_schema.zig` | Closed catalogue configuration for each family, with the shared required `maxOutputTokens` and `requestTimeoutMs`. |
| `domain/model_capabilities.zig`, `domain/model_schema_projection.zig` | One native JSON-schema capability and one native grammar projection for both providers. |
| `domain/provider_failure.zig` | One retry classifier from neutral facts: pre-send failures never retry; otherwise the cause decides. |
| `adapters/provider/provider_api_key.zig`, `adapters/system/provider_api_key_source.zig` | One key snapshot with validation and secure zeroing. One exact environment variable per family. |
| `adapters/provider/api_key_authorization.zig` | One in-memory capability mechanism. Each capability is tagged with its family, and a capability from another family never yields a key. |
| `adapters/provider/model_provider.zig` | One provider-port implementation: consume the lease, validate, encode, capture, send once, decode and clean up. |
| `adapters/provider/model_text_request.zig` | One ordered view of system and guidance text, the response-format and schema guidance, and the user and evidence text. |
| `adapters/provider/model_http_transport.zig`, `model_http_head.zig`, `model_http_exchange.zig` | One transport contract, head reader and HTTPS exchange, with a closed target union per family. |
| `adapters/provider/provider_response_support.zig`, `provider_response_assembly.zig` | Closed-field checks with error paths, exact text joining, reasoning ownership and normalized-result construction. |
| `bedrock_*.zig`, `anthropic_*.zig` | Per-family endpoint, request encoder and response decoder only. |
| `adapters/provider/request_replay.zig` | One debugger preparation, send and inspection path, dispatching only those projections. |

### Anthropic contract

These facts were checked against the Anthropic documentation on
21 October 2026. The response decoder, `adapters/provider/anthropic_response.zig`,
implements the dated wire manifest, including the error table.

- **Provider and models:** provider ID `anthropic`; models `claude-haiku-5-5`,
  `claude-sonnet-5-5` and `claude-opus-5-5`. `claude-sonnet-5-5` and `claude-opus-5-5`
  each need an approved compatibility probe before live use; `claude-haiku-5-5` is in
  live use by the user's direction of 17 November 2026 (ADR 0029).
- **Configuration:** `{"maxOutputTokens": N, "requestTimeoutMs": M}`, both required
  positive integers, with no other field. The documented maximum output is 128,000
  for each model and is sent unchanged as `max_tokens`. `requestTimeoutMs` is the
  provider-operation deadline (ADR 0030).
- **Endpoint:** `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`,
  `anthropic-version: 2023-06-01` and `content-type: application/json`.
  - No beta header is sent. The endpoint and version are compiled constants.
  - The `request-id` and `retry-after` response headers are retained.
- **Credential:** production reads exactly `ANTHROPIC_API_KEY`. The harness reads
  `TEST_ANTHROPIC_API_KEY`.
  - Keys are read once, after binding validation, and only for families bound to the
    selected workflow's model slots.
  - A missing or malformed key makes that family's authorization fail as `authentication_failed`;
    the failure line says which (`credential=missing|malformed`, contract 08). There is no
    startup check: a missing key fails when that provider's call is authorized.
- **Request:**
  - **Text:** system and guidance parts, then the response-format and schema
    guidance, become `system` text blocks. User and evidence parts become one
    `user` message.
  - **Effort:** `reasoningEffort` maps to `output_config.effort`.
  - **Native schema:** sends `output_config.format = {type: "json_schema", schema}`,
    using the shared projection as a JSON object. Native schema is the only response
    mode, and the catalogue has no `json` member.
  - **Fields never sent:** `temperature`, `top_p`, `top_k`, `thinking`, `stop_sequences`,
    tools, caching, `inference_geo` and `speed`. The registry declares
    `temperature: false`.
- **Response:** decoding is closed against the dated manifest.
  - **Presence:** a field the manifest documents as nullable may be absent and
    reads as null. A non-nullable documented field, at any depth, must be present: for
    example the envelope's `id`, `type`, `role`, `model`, `content`, `stop_reason` and
    `usage`, usage's `input_tokens` and `output_tokens`, and a thinking block's `signature`.
    An undocumented field still rejects.
  - **Envelope:** `type` must be `message`, `role` must be `assistant`, and `model`
    must equal the selected model.
  - **Content:** only `text` blocks with null or absent `citations`, `thinking` blocks and
    `redacted_thinking` blocks are accepted. Thinking blocks are kept as provider
    reasoning and never become candidate text.
  - **Stops:**

    | Stop reason | Outcome |
    | --- | --- |
    | `end_turn` | The candidate |
    | `max_tokens` | `output_limit` |
    | `model_context_window_exceeded` | `context_limit` |
    | `refusal` | `content_filtered` |
    | `tool_use`, `pause_turn` | `unsupported_tool_request` |
    | `stop_sequence` | `malformed_output` |

  - **Stop details:** `stop_details` must be null unless the stop reason is
    `refusal`.
- **Usage:** inclusive input is `input_tokens` plus both cache counters. Total is
  inclusive input plus `output_tokens`.
  - `thinking_tokens` is already inside `output_tokens` and is checked against it,
    not added.
  - Usage survives a rejected or stopped candidate once the envelope is valid.
- **Errors:** a failure is classified only when both the HTTP status and
  `error.type` match the decoder's error table. Everything else is
  `response_invalid`.
  - `402 billing_error` and a `429` whose `error.details.error_code` is
    `enforced_spend_limit_reached` are `authorization_denied` and never retry.
  - Message text never classifies.
- **Diagnostics:** thinking-token counts, refusal categories, service tier, speed and
  inference geography stay in the captured raw response only. The request ID is
  retained as Bedrock's is.

### Model maximum output, for every provider

[ADR 0011](0011-provider-owned-request-limits.md#model-maximum-output) owns the rule; it
applies to every catalogue entry of every provider.

### Versions

- The request description's (`model-request-debug`) closed provider-configuration
  union has an Anthropic variant. Readback validates the configuration through the
  same typed rules as the catalogue.
- The harness call evidence (`model-call-evidence`) carries the provider and its
  configuration instead of a Bedrock-only region. ADR 0030 records its current version
  and historical readers.

## Not decided here

- Streaming, prompt caching, tools, batches and Claude through clouds other than
  Bedrock (ADR 0029's `claude` family).
- An explicit inference-geography control and an Anthropic grader.
- The complete-receipt race correction, an existing shared accounting gap that this ADR
  does not change.

## Consequences

- Bedrock's request bytes and response handling run through the shared owners, and its
  tests prove them there.
- No Bedrock-named lifecycle, authorization, key, transport, head-reader or dispatch
  module exists, and none has an alias.
- A future provider adds a contract entry, a configuration schema and its own
  endpoint, encoder and decoder projections. It reuses everything else.
