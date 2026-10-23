# ADR 0028: Anthropic Messages API provider on shared provider owners

- **Status:** Accepted amendment
- **Date:** 2026-10-21
- **Decision authority:** The user's instruction "implement a claude connector" on
  21 October 2026, referring to the proposal in
  [fixes/claude_connector.md](../../fixes/claude_connector.md). The user also
  required that "the implementation must strive to reusability", with one common
  layer that both connectors use. The user then chose:
  - "All three" models: Claude Haiku 5.5, Sonnet 5.5 and Opus 5.5;
  - "Yes, same stop": a refusal is the existing `content_filtered` stop;
  - "Yes, access denied": an out-of-credit or spend-cap error is
    `authorization_denied` and is never retried;
  - "No, fail at first Claude call": a missing key fails when that provider's call
    is authorized, as a missing Bedrock key does today.

  The 16 October direction that configuration selects Claude or Bedrock per slot,
  with both allowed in one workflow, still applies. The 18 October direction stored
  the required Anthropic `max_tokens` in each catalogue model entry. Later that day
  [ADR 0011](0011-provider-owned-request-limits.md#model-maximum-output) made the
  catalogue's `maxOutputTokens` the model's documented maximum for Bedrock. This ADR
  uses that one field for both providers.
- **Amends:**
  - ADR 0011 "Model maximum output", which now applies to every provider's catalogue
    entry, not only Bedrock's;
  - design invariant 32 and acceptance criterion 31.12, in the same way;
  - ADR 0004, whose single Bedrock credential becomes one exact variable per
    selected provider;
  - ADR 0019, whose request description admits Anthropic provider configuration;
  - §9 configuration, §12.3 (a new §12.3.2 beside §12.3.1 Bedrock Converse), and
    F0006–F0008 where they describe a single provider.

  The overall design remains **Proposed design**. The connector proposal stays an
  unaccepted source document. Its normative content moves here and into
  [F0009](../features/F0009-AnthropicProvider.md).
- **Amended by:** [ADR 0030](0030-engine-owned-model-request.md) (23 October 2026;
  not yet implemented except the token-counting removal, implemented 24 October 2026).
  It changes:
  - "Configuration" (`{"maxOutputTokens": N}` "with no other field"): `config` also
    requires a positive `requestTimeoutMs`, the provider-operation deadline;
  - "One token budget, deadline …": the budget stays shared, but each catalogue entry
    now carries its own deadline;
  - the shared-owners row for `domain/llm_provider_config_schema.zig`, which gains the
    required `requestTimeoutMs`;
  - "Deadline" under "Not decided here", now settled per model. Claude's entries start at
    the shared 180,000 ms until a measured maximum-output time replaces it;
  - "Token counting": provider token counting is removed for every provider
    (implemented 24 October 2026).

## Context

The engine had one production provider, Amazon Bedrock Converse. Its credential
storage, authorization, call lifecycle, request text layout, HTTP exchange and
response assembly lived in Bedrock-named modules, so a second provider could only
copy them. The user wants Claude through the Anthropic Messages API as a peer, with
the shared behaviour implemented once.

## Decision

### Peer providers selected by configuration

- `.sddproviders.json` lists Anthropic and Bedrock models. `.sddtoolkit.json`
  binds each slot to one entry. A workflow may use either provider, or both.
- Each call keeps its slot's binding, including its retries and protocol
  corrections. There is no cross-provider fallback, no model-name branching and no
  engine choice between providers.
- One token budget, deadline, capture path and set of validation and publication
  rules apply to both providers.

### Shared owners

Common mechanics have exactly one implementation. Provider modules hold only wire
projections and never import a sibling provider.

| Owner | Responsibility |
| --- | --- |
| `domain/llm_provider_contracts.zig` | `ProviderFacts`, a union tagged by provider family that replaces the Bedrock-only contract fields. Bedrock facts carry regions and request profile; Anthropic carries none. The tag also names the configuration schema. |
| `domain/llm_provider_config_schema.zig` | Closed catalogue configuration for each family, with the shared required `maxOutputTokens`. |
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
21 October 2026. F0009 records the wire manifest.

- **Provider and models:** provider ID `anthropic`; models `claude-haiku-5-5`,
  `claude-sonnet-5-5` and `claude-opus-5-5`. Each needs its own approved
  compatibility probe before live use.
- **Configuration:** `{"maxOutputTokens": N}`, required and positive, with no other
  field. The documented maximum is 128,000 for each model. It is sent unchanged as
  `max_tokens`.
- **Endpoint:** `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`,
  `anthropic-version: 2023-06-01` and `content-type: application/json`.
  - No beta header is sent. The endpoint and version are compiled constants.
  - The `request-id` and `retry-after` response headers are retained.
- **Credential:** production reads exactly `ANTHROPIC_API_KEY`. The harness reads
  `TEST_ANTHROPIC_API_KEY`.
  - Keys are read once, after binding validation, and only for families bound to the
    selected workflow's model slots.
  - A missing key makes that family's authorization fail as `authentication_failed`.
    There is no startup check.
- **Request:**
  - **Text:** system and guidance parts, then the response-format and schema
    guidance, become `system` text blocks. User and evidence parts become one
    `user` message.
  - **Effort:** `reasoningEffort` maps to `output_config.effort`.
  - **Native schema:** sends `output_config.format = {type: "json_schema", schema}`,
    using the shared projection as a JSON object.
  - **Prompt-only:** keeps the full schema in system guidance and sends no format.
  - **Fields never sent:** `temperature`, `top_p`, `top_k`, `thinking`, `stop_sequences`,
    tools, caching, `inference_geo` and `speed`. The registry declares
    `temperature: false`.
- **Token counting:** the counting endpoint returns an estimate, so no Anthropic
  model registers token counting.
- **Response:** decoding is closed against the dated manifest.
  - **Envelope:** `type` must be `message`, `role` must be `assistant`, and `model`
    must equal the selected model.
  - **Content:** only `text` blocks with null `citations`, `thinking` blocks and
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
  `error.type` match the table in F0009. Everything else is `response_invalid`.
  - `402 billing_error` and a `429` whose `error.details.error_code` is
    `enforced_spend_limit_reached` are `authorization_denied` and never retry.
  - Message text never classifies.
- **Diagnostics:** thinking-token counts, refusal categories, service tier, speed and
  inference geography stay in the captured raw response only. The request ID is
  retained as Bedrock's is.

### Model maximum output, for every provider

ADR 0011's rule applies to every catalogue entry. Each entry records its model's
documented maximum as `config.maxOutputTokens`, and every inference request sends
it: Bedrock as `inferenceConfig.maxTokens`, Anthropic as `max_tokens`. No slot,
binding, correction or replay can narrow it.

### Versions

- `model-request-debug/v9` is unchanged. Its closed provider-configuration union
  gains the Anthropic variant, and every existing description keeps its bytes and
  meaning, so no captured description changes version. Readback validates the
  configuration through the same typed rules as the catalogue.
- The harness call evidence advances to `model-call-evidence/v2`, which carries the
  provider and its configuration instead of a Bedrock-only region.

## Not decided here

- **Live use.** The live cost policy still permits only Bedrock GPT-OSS-20B. A live
  Anthropic probe or E2E run needs a policy change that names the model, and its own
  approval.
- **Response mode.** Whether Claude entries use native schema or prompt-only waits for
  measured compatibility. Both are implemented, and the catalogue's `json` flag
  selects one.
- **Deadline.** The shared 180-second request deadline applies unchanged. Whether
  Claude needs a different one waits for latency measurements.
- **Out of scope:**
  - streaming, prompt caching, tools, batches and Claude through Bedrock or other
    clouds;
  - an explicit inference-geography control and an Anthropic grader;
  - the separate complete-receipt race correction (proposal R11), an existing shared
    accounting gap that this ADR does not change.

## Consequences

- Bedrock behaviour is unchanged. Its request bytes and response handling are
  preserved, and existing Bedrock tests prove this through the shared owners.
- The Bedrock-named lifecycle, authorization, key, transport, head-reader and
  dispatch modules are removed, with no aliases.
- A future provider adds a contract entry, a configuration schema and its own
  endpoint, encoder and decoder projections. It reuses everything else.
