# Claude connector — direct Anthropic Messages API provider

**Prepared:** 16 October 2026, Australia/Melbourne. **Assessed and revised:**
16 October 2026, after code inspection and research against the live Anthropic
documentation (§12).

**Status:** **Proposal; not accepted and not implemented.** This document describes
the work needed to add a second production model provider that calls the
Anthropic Messages API directly. It changes provider architecture, so it needs an
accepted ADR and the decisions in §10 before any code change. It is not an active
backlog: [FIX05](FIX05.md) is the sole active fix record under the
[fix-record convention](README.md). Once accepted, its normative content moves into
an ADR and a feature document (§9), and implementation progress is recorded in FIX05.
It authorizes no live call, no E2E run and no production dependency. The governing
[design](../design/design.md) remains **Proposed design**.

**Repository revision inspected:** uncommitted working tree on
`4f25a0603d14b1d7413f3e992e53c931c97c40eb`.

## 0. Feasibility assessment

**Verdict: feasible, with two unresolved blockers that must be measured before the
design is frozen.** Transport, authentication, usage accounting, reasoning retention
and error handling all map onto existing engine types without new authority, new
dependencies or changes to workflow semantics. Most of the engineering cost is not
the Anthropic code itself but removing Bedrock assumptions from shared types (§4).

| ID | Severity | Finding | Evidence | Consequence |
| --- | --- | --- | --- | --- |
| R1 | **Blocker until measured** | Anthropic structured outputs allow at most **16 parameters with union types** and **24 optional parameters** per request, and reject larger grammars with 400 "Schema is too complex for compilation". The workflow's projected records-generation schema has **32** `anyOf` nodes; content extraction has **16** (§3.3). | Structured-outputs documentation; schemas measured from the 08:09 loan-renewal run's request captures | Native schema mode (`json: true`) is likely rejected for record generation. The exact counting rule is not published, so one cheap live check is needed (§8 step 0). If confirmed, Claude entries must use prompt-only mode or the affected requests must fail typed before send; no silent per-request fallback (§7). |
| R2 | **Blocker until measured** | Every model call has a hard **60-second** wall-clock deadline: `timeout-ms: 60000` in the shared `model-request-body` subgraph becomes the operation deadline enforced by the HTTP timer. GPT-OSS calls take about 1 second; Claude latency with adaptive thinking, plus first-request grammar compilation, is unmeasured. | [spec.workflow.yaml](../design/workflows/spec.workflow.yaml) `authorize` step; [workflow_provider_authorization.zig:20-24](../src/application/workflow_provider_authorization.zig#L20-L24); [bedrock_http.zig:48-75](../src/adapters/provider/bedrock_http.zig#L48-L75) | Calls exceeding 60 s end as `timeout` failures. The deadline is a workflow-definition parameter shared by all providers; raising it is a workflow change, and a per-provider deadline would need a new typed policy (§10.9). Streaming would not help: the deadline bounds total time. |
| R3 | High | `max_tokens` is a hard limit on thinking **plus** visible text, and thinking is billed as output. Opus 5.5 cannot disable thinking. | Effort and thinking documentation | Thinking tokens add to the compiled 100,000-token workflow budget, which small features already exhaust ([FIX04 F9](Z_FIX02.md#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures)). Effort must be set explicitly per slot and measured with `usage.output_tokens_details.thinking_tokens`. |
| R4 | Medium | The Bedrock HTTP adapter is about 90% provider-neutral (deadline timer, body retention, redirect and framing rules). Only the endpoint, the `Bearer` header and two `x-amzn-*` response headers are Bedrock-specific. | [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig) | A separate `anthropic_http.zig` would duplicate delicate transport code. Extract one shared HTTPS exchange core with a closed per-provider endpoint and header projection (§5.6). |
| R5 | Medium | The authorization adapter is a single port that rejects any non-Bedrock configuration, and composition builds one provider. A missing key fails as `authentication_failed`, detected only when that provider's call is authorized. | [bedrock_authorization.zig](../src/adapters/provider/bedrock_authorization.zig); [model_provider_runtime.zig](../src/composition/model_provider_runtime.zig) | Mixed-provider workflows need per-provider authorization and credential material, dispatched by registry entry (§4, §10.8). |
| R6 | Medium | `count_tokens` returns an **estimate** that "might differ by a small amount" and can include system-added tokens. | Token-counting documentation | It must not be registered as the engine's exact token counter. The Spec workflow never counts tokens, so the first increment registers no counting capability (§3.7). |
| R7 | Medium | A 429 is not always retryable: the monthly spend-cap 429 has no `retry-after`, carries `error.details.error_code: "enforced_spend_limit_reached"`, and keeps failing. A user-set spend limit returns 400. Error types "will grow over time". | Errors and rate-limits documentation | The closed error decoder must accept `error.details`, classify the spend cap as non-retryable, and treat unknown types as `response_invalid` (§3.6). |
| R8 | Low | Several response and usage fields are nullable, and the response can carry `container` and `diagnostics`. | Messages API reference | The closed decoder needs the exact field list in §3.5, including nulls. |
| R9 | Low | The direct API has no region configuration in this design; responses report `usage.inference_geo` (for example `"global"`). The Bedrock configuration deliberately pins Sydney. | Messages API reference; rate-limits documentation | If data residency matters, the direct API may not meet it (§10.10). |
| R10 | Low | Requests that ask for step-by-step reasoning in output fields can trigger a `reasoning_extraction` refusal. Review schemas contain explanation fields such as `detail`. | Structured-outputs documentation | Refusals are typed non-candidate stops; their frequency must be measured, not prompted around. |

**Feasibility by area:**

| Area | Assessment |
| --- | --- |
| Configuration selection (§2) | Feasible with existing chain; only per-provider routing is new. |
| Request encoding (§5.4) | Feasible; direct mapping from existing content parts. |
| Native structured output (§3.3) | **Uncertain (R1).** Prompt-only mode is feasible regardless. |
| Response, usage, stop and reasoning decoding (§5.5) | Feasible; every field maps to an existing engine type. |
| Errors (§3.6) | Feasible; needs one decision on spend-cap and billing causes. |
| Transport (§5.6) | Feasible; refactor rather than duplicate. |
| Latency within current deadlines | **Uncertain (R2).** |
| Mixed providers (§2.1) | Feasible; requires the routing and authorization changes in §4. |
| Cost | Low for Haiku 5.5; for a run shaped like the 08:09 loan-renewal diagnostic (93,431 input and 7,571 output tokens on GPT-OSS), base prices give about $0.01 on Haiku 5.5, $0.26 on Sonnet 5.5 and $0.53 on Opus 5.5, before thinking tokens and tokenizer differences. This is an illustration, not an estimate. |

## 1. Outcome and scope

**Observable outcome:** the engine supports both Claude (direct Anthropic API) and
Amazon Bedrock as peer providers, and configuration alone decides which one each
model slot uses. A project selects a provider per slot by editing
`.sddproviders.json` and `.sddtoolkit.json`; no code, build flag or workflow
definition changes. The engine performs the same prepared, authorized, accounted and
validated model exchange for either provider. A project may use only Bedrock, only
Claude, or both in one workflow, for example Claude for `spec_generation` and
Bedrock for `repair` (§2.1).

**In scope:**

- non-streaming inference (`POST /v1/messages`);
- native structured output (`output_config.format`), subject to R1, and prompt-only
  schema guidance;
- reasoning effort (`output_config.effort`);
- typed usage, stop, refusal and error normalization;
- debugger capture, inspection and single-request replay;
- the development harness, compatibility probe and E2E launcher.

**Non-goals for the first increment:** token counting (R6); streaming; tool use;
batches; the Files API; prompt caching (`cache_control`); server-side refusal
fallbacks; OAuth, profile or workload-identity credentials; `inference_geo`; fast
mode; per-message effort; Claude on Bedrock, Vertex AI or Foundry (Claude on Bedrock
already uses the existing Bedrock connector). Each is a separate decision; several
conflict with engine invariants (§7).

**No new dependency.** The connector uses `std.http` through the existing single
connection boundary, as the Bedrock connector does. There is no official Anthropic
SDK for Zig; the connector implements the documented HTTP contract directly.

## 2. Configuration and selection

Selection reuses the existing chain without a new mechanism:

1. The compiled registry ([provider_model_contracts.zig](../src/composition/provider_model_contracts.zig))
   declares each supported `provider`/`model` tuple, its implementation and its
   capabilities. Only compiled tuples are supported.
2. `.sddproviders.json`, located through `.sddtoolkit.json` `paths.providers`, lists
   the tuples a project may use and their closed configuration. It is captured once
   per invocation ([ADR 0004](../design/decisions/0004-model-provider-bootstrap.md)).
3. `.sddtoolkit.json` `models.slots` binds each slot to one catalogue entry.

```jsonc
// .sddproviders.json
{
  "providers": [
    {
      "provider": "anthropic",
      "models": [
        { "model": "claude-opus-5-5", "json": false, "config": {} }
      ]
    },
    {
      "provider": "aws-bedrock",
      "models": [
        { "model": "openai.gpt-oss-20b-1:0", "json": true, "config": { "region": "ap-southeast-2" } }
      ]
    }
  ]
}

// .sddtoolkit.json (excerpt)
"models": {
  "slots": {
    "spec_generation": { "provider": "anthropic", "model": "claude-opus-5-5", "reasoningEffort": "low", "maxOutputTokens": 16384 },
    "repair":          { "provider": "aws-bedrock", "model": "openai.gpt-oss-20b-1:0", "reasoningEffort": "low", "maxOutputTokens": 16384 }
  }
}
```

- `provider: "anthropic"` satisfies the existing lower-kebab provider grammar
  ([llm_provider_identity.zig](../src/domain/llm_provider_identity.zig)); Claude
  model IDs satisfy the model grammar. Current Claude IDs are pinned snapshots,
  including the dateless IDs, so they do not move like an alias.
- `config: {}` uses the existing `empty_object` configuration schema. The endpoint
  has no region, and endpoints and credentials stay out of project data.
- `json` is fixed per catalogue entry, so every slot using that model shares one
  response mode. The example uses `json: false` (prompt-only) until R1 is resolved.
- `maxOutputTokens` is **required** for every Anthropic slot because the API requires
  `max_tokens`. Binding validation rejects a slot that omits it; the engine supplies
  no default. Thinking counts against this limit (R3).
- `reasoningEffort` is optional but should be set explicitly. When omitted, the
  request omits `output_config.effort` and the model's own default applies (§3.4).
- Unknown models, configuration fields and unsupported controls reject at the
  existing binding boundary. There is no model-name branching and no fallback.

### 2.1 Using both providers

Claude and Bedrock are independent peers selected per slot. The engine never chooses
between them itself.

| Configuration | Providers prepared | Credentials read |
| --- | --- | --- |
| Every slot on `aws-bedrock` | Bedrock only | `AWS_BEARER_TOKEN_BEDROCK` |
| Every slot on `anthropic` | Anthropic only | `ANTHROPIC_API_KEY` |
| Slots on both | Both | Both |
| Catalogue lists both, but the selected workflow's slots use one | Only the one used | Only that provider's |

Rules:

- **Selection is per slot and fixed for the invocation.** Each model request uses the
  binding its originating step selected
  ([ADR 0012](../design/decisions/0012-workflow-owned-model-request.md)). Protocol
  corrections and retries keep that binding, so they stay on the same provider and
  model.
- **The provider set comes from the selected bindings.** After binding validation,
  composition builds exactly the providers those bindings reference and reads only
  their credentials. A Bedrock-only workflow never reads `ANTHROPIC_API_KEY`, and a
  Claude-only workflow never reads the Bedrock token.
- **Routing is by registry entry.** Each call is dispatched by its binding's
  `implementation_id`, never by inspecting the model name. Authorization is
  dispatched the same way.
- **No cross-provider fallback.** A Bedrock failure is never retried on Claude, or the
  reverse. With current behavior, a missing credential makes that provider's calls
  fail as `authentication_failed` at authorization, before they are sent; they are
  never routed to the other provider. Switching provider is a configuration change
  for the next invocation. Whether every required credential must be present before
  the first send of any provider is decision §10.8.
- **Shared engine policy.** Both providers use the same request preparation, schema
  validation, accounting, workflow token budget, per-call deadline, capture and
  publication rules. A mixed workflow's token budget counts tokens from both
  providers; each provider's usage is accounted from its own response.
- **Reports name the provider per call.** E2E and compatibility reports already record
  provider and model per slot and per exchange. They must keep doing so, so mixed
  runs are attributable.
- **Evaluation cohorts stay separate.** Mixing providers is valid for production
  configuration. An evaluation protocol that freezes one model, such as
  the [semantic-simplicity protocol](../test/calibration/semantic-simplicity/README.md)'s GPT-OSS-only panel, must not mix providers within a comparison.

## 3. External API contract

Facts below were checked against the live Anthropic documentation on
16 October 2026 (§12). Recheck them when the ADR is written and freeze the checked
date in the feature document.

### 3.1 Transport

| Item | Value |
| --- | --- |
| Inference endpoint | `POST https://api.anthropic.com/v1/messages` |
| Required headers | `x-api-key: <key>`, `anthropic-version: 2023-06-01`, `content-type: application/json` |
| Response headers to retain | `request-id` (also `request_id` in error bodies); `retry-after` when present |
| Request size limit | 32 MB; larger requests return 413 before reaching the API |
| Long requests | Streaming or batches are recommended for long requests, "especially those over 10 minutes"; idle connections may be dropped, and TCP keep-alive reduces that risk |
| Credential | API key from one environment variable (§5.3) |

Endpoints and the API version are compiled constants, never configuration. No
`anthropic-beta` header is sent in the first increment.

### 3.2 Request fields

```json
{
  "model": "claude-opus-5-5",
  "max_tokens": 16384,
  "system": [{"type": "text", "text": "…"}],
  "messages": [{"role": "user", "content": [{"type": "text", "text": "…"}]}],
  "output_config": {
    "effort": "low",
    "format": {"type": "json_schema", "schema": { "type": "object", "…": "…" }}
  }
}
```

- `model`, `max_tokens` and `messages` are required. Current models accept up to
  128K output tokens on the synchronous API.
- `system` accepts a string or an array of text blocks with non-empty `text`.
- `output_config.effort` accepts `low`, `medium`, `high`, `xhigh`, `max` or null.
  `output_config.format` is `{type: "json_schema", schema: <object>}`; the schema is
  a **JSON object**, whereas Bedrock Converse takes a JSON string in a different
  field.
- `temperature`, `top_p` and `top_k` are deprecated: models after Opus 4.6 reject any
  `temperature` other than 1.0 and any `top_k`. The engine sends none of them.
- Assistant prefill returns 400 on current models; the engine never prefills.
- `thinking` is not sent. Omitting it runs adaptive thinking on all three models
  in §3.4.

### 3.3 Structured-output schema subset and limits

**Supported:** `object`, `array`, `string`, `integer`, `number`, `boolean`, `null`;
`enum` of strings, numbers, booleans or nulls; `const`; `anyOf`; `allOf` (not with
`$ref`); local `$ref`/`$defs`/`definitions`; `default`; `required`;
`additionalProperties: false` (required on objects); listed string formats; array
`minItems` of 0 or 1 only; simple `pattern` regexes.

**Not supported:** recursive schemas; complex types in enums; external `$ref`;
`minimum`, `maximum`, `multipleOf`; `minLength`, `maxLength`; array constraints
beyond `minItems` 0 or 1 (so no `maxItems`); other `additionalProperties` values;
backreferences, lookaround and word boundaries in patterns. `oneOf` is not listed.

**Complexity limits per request**, across all strict schemas:

| Limit | Value |
| --- | --- |
| Optional parameters | 24 |
| Parameters with union types (`anyOf` or type arrays) | 16 |
| Strict tools | 20 (not used) |
| Grammar compilation timeout | 180 seconds; further grammar-size limits are undisclosed |

Compiled grammars are cached for 24 hours from last use; the first request with a
new schema has extra compilation latency. Structured outputs also add a system
prompt, which costs input tokens.

**Fit with the engine's existing projection.** The `bedrock` profile in
[model_schema_projection.zig](../src/domain/model_schema_projection.zig) already
removes string and numeric bounds and `maxItems`, reduces a nonzero `minItems` to 1,
emits `anyOf` instead of `oneOf`, and closes every object. That matches the
supported feature list. It does not address the complexity limits. Measured on the
Bedrock-projected schemas captured in the 08:09 loan-renewal diagnostic:

| Request (call) | Schema bytes | `anyOf` nodes | Optional properties |
| --- | --- | --- | --- |
| Content extraction (1) | 4,079 | 16 | 0 |
| Record generation (10–12) | 7,519 | 32 | 0 |
| Brief (7) | 2,616 | 9 | 0 |
| Story and entities (8, 9) | 1,444–1,592 | 5 | 0 |
| Source review (13–36) | 776–2,825 | 0–2 | 0 |

No schema has optional properties, so the 24-parameter limit is not at risk. The
union limit is: if every `anyOf` node counts, record generation exceeds 16 and content
extraction sits exactly at it. The documentation counts "parameters", which may not
equal nodes. Resolve this with the step-0 check before choosing a response mode.
`oneOf` to `anyOf` stays safe because
[ADR 0006](../design/decisions/0006-minimal-model-response.md) requires alternatives
to be disjoint by JSON type or `kind` tag. Removed bounds remain enforced natively by
the complete schema
([§12.3](../design/contracts/12-model-boundary.md#123-provider-neutral-response-envelope)).

### 3.4 Models, thinking and effort

| Model | ID | Retirement not before | Price per MTok (in / out) | Thinking without `thinking` field | Turning thinking off | Effort default |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Opus 5.5 | `claude-opus-5-5` | 22 Sep 2027 | $4 / $20 | Adaptive, always on | Not possible; `disabled` returns 400 | `medium` |
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | 28 Sep 2027 | $2 / $10 | Adaptive | `between_tools` at `high` or below; `disabled` returns 400 | `high` |
| Claude Haiku 5.5 | `claude-haiku-5-5` | 7 Oct 2027 | from $0.10 / from $0.50 | Adaptive | `disabled` at `high` or below | `medium` |

All three have 1M-token context, 128K maximum output, structured outputs and effort
levels `low` to `max`. Comparative latency is "moderate", "fast" and "fastest"
respectively. Consequences:

- **Registry:** `temperature: false` for every entry; the engine's 0.1 temperature
  rule applies only where temperature is supported
  ([§12.5](../design/contracts/12-model-boundary.md#125-low-capability-model-operating-rules)).
- **Thinking stays on.** The encoder never sends `thinking`. Turning it off differs
  per model and is impossible on Opus 5.5, so the first increment keeps one uniform
  rule: effort is the only reasoning control, mapped from `reasoningEffort`.
- **Effort affects all output tokens**, including visible text, not only thinking.
  Setting effort to the model's default is identical to omitting it.
- **Thinking display defaults to `"omitted"`** on all three: thinking blocks arrive
  with an empty `thinking` field and an opaque `signature` that carries the
  encrypted reasoning. Thinking is billed as output whether or not it is displayed.
- **Tokenizer:** Claude models from Opus 4.7 onward use a tokenizer that produces
  about 30% more tokens than earlier Claude models for the same text. Counts are not
  comparable with GPT-OSS; measure them against the workflow budget.

### 3.5 Response

A non-streaming response is a `message` object with these top-level fields:
`id`, `type` (`"message"`), `role` (`"assistant"`), `model`, `content`,
`stop_reason` (non-null when not streaming), `stop_sequence` (nullable),
`stop_details` (nullable), `usage`, `container` (nullable) and `diagnostics`
(nullable).

- **Content blocks used by this design:** `text` (`text`, nullable `citations`),
  `thinking` (`thinking`, `signature`) and `redacted_thinking` (`data`, opaque and
  encrypted). Tool, server-tool and container blocks cannot appear without tools and
  reject as `response_invalid`.
- **Stop reasons:** `end_turn`, `max_tokens`, `stop_sequence`, `tool_use`,
  `pause_turn`, `refusal`, `model_context_window_exceeded`.
- **Stop details:** `{type: "refusal", category, explanation}` or null. `category` is
  `cyber`, `bio`, `frontier_llm`, `reasoning_extraction`, `general_harms` or null.
  A refusal returns HTTP 200, is billed, and its output may not match the schema.
- **Usage:** `input_tokens`, `output_tokens`, nullable `cache_creation_input_tokens`
  and `cache_read_input_tokens`, nullable `cache_creation`
  (`ephemeral_5m_input_tokens`, `ephemeral_1h_input_tokens`), nullable
  `output_tokens_details` (`thinking_tokens`, an approximate observability figure
  included in `output_tokens`), nullable `server_tool_use`, nullable `service_tier`
  (`standard`, `priority`, `batch`) and nullable `inference_geo`. Total input is
  `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`;
  `output_tokens` is authoritative for billing. There is no total field.

### 3.6 Errors

Error bodies are `{"type": "error", "error": {"type", "message", "details"?}, "request_id"}`.

| Status | `error.type` | Engine cause | Retry class |
| --- | --- | --- | --- |
| 400 | `invalid_request_error` | `request_rejected` | `never` |
| 400 | `invalid_request_error`, message reports a user-set spend limit | `request_rejected` (decision §10.6) | `never` |
| 401 | `authentication_error` | `authentication_failed` | `never` |
| 402 | `billing_error` | `authorization_denied` (decision §10.6) | `never` |
| 403 | `permission_error` | `authorization_denied` | `never` |
| 404 | `not_found_error` | `model_unavailable` | `never` |
| 413 | `request_too_large` | `request_rejected` | `never` |
| 429 | `rate_limit_error` with `details.error_code: "enforced_spend_limit_reached"` | Decision §10.6; never retryable | `never` |
| 429 | `rate_limit_error`, otherwise | `throttled` | `policy_eligible` |
| 500 | `api_error` | `service_unavailable` | `policy_eligible` |
| 504 | `timeout_error` | `timeout` | `policy_eligible` |
| 529 | `overloaded_error` | `service_unavailable` | `policy_eligible` |

As in the Bedrock decoder, a failure classifies only when **both** status and type
match a mapping; anything else, including new error types the API may add, is
`response_invalid`. Classification must not depend on message text; the spend-cap
case is identified by `details.error_code`. 409 `conflict_error` concerns resource
APIs that this connector does not call. Retry classes stay derived from the cause by
the existing owner; the connector performs no retries itself, and `retry-after` is
retained only as diagnostic data.

### 3.7 Token counting (deferred)

`POST /v1/messages/count_tokens` is free, has its own rate limit, accepts the same
model-visible input without `max_tokens`, and returns `{"input_tokens": N}`. The
documentation describes the result as an **estimate** that may differ slightly from
the input actually billed and may include system-added tokens. The engine's exact
counter capability (`exact_token_counter = provider_input_token_count`) would
therefore misrepresent it. The Spec workflow's shared request subgraph never counts
tokens, so the first increment registers `input_token_count: false` and
`exact_token_counter: unavailable`. A later increment can add an explicitly
estimated counter type if a workflow needs one.

### 3.8 Rate and spend limits

Limits are per organization and model: on the Start tier, 1,000 requests, 2,000,000
uncached input tokens and 400,000 output tokens per minute for each of the three
models. New organizations may start in a lower Evaluation tier. The engine sends
one request at a time, so rate limits are unlikely to bind. Monthly spend caps
($500 on Start, $1,000 on Build) can stop all requests until the next month (R7).

## 4. Current Bedrock coupling

The provider port is neutral, but several shared types assume Bedrock. They must be
generalized before an Anthropic adapter can be added without parallel or
illegal-state fields.

| Location | Bedrock assumption | Required change |
| --- | --- | --- |
| [provider_dispatch.zig](../src/adapters/provider/provider_dispatch.zig) | Union with one `aws_bedrock` variant | Add an `anthropic` variant; route by `implementation_id`. |
| [model_provider_runtime.zig](../src/composition/model_provider_runtime.zig) | Builds one Bedrock provider, one authorization adapter and one credential per invocation | Build one provider and one authorization adapter per provider referenced by the selected bindings. |
| [bedrock_authorization.zig](../src/adapters/provider/bedrock_authorization.zig) | The only authorization port; returns `authorization_denied` for any non-Bedrock configuration | Dispatch authorization by registry entry to the provider's own adapter; each deposits its own capability type. |
| [llm_provider_contracts.zig](../src/domain/llm_provider_contracts.zig) | `ProviderModelContract.bedrock_regions` and `bedrock_request_profile` | Replace with one tagged union of per-provider facts. Remove the Bedrock fields in the same change; do not add `anthropic_*` siblings. |
| [llm_provider_registry.zig](../src/domain/llm_provider_registry.zig) | `Entry.bedrock_request_profile` | Carry the same tagged union. |
| [model_capabilities.zig](../src/domain/model_capabilities.zig) | `StructuredResponse.bedrock_json_schema` is the only native mode; no "requires output allowance" capability | Add the Anthropic native mode (or a provider-neutral native mode with its projection chosen by provider facts), and add a `requires_max_output_tokens` capability checked in `Capabilities.supports` beside the existing `supports_max_output_tokens` rule. |
| [model_schema_projection.zig](../src/domain/model_schema_projection.zig) | Profiles `complete` and `bedrock` | Reuse or rename the restricted profile after the step-0 check; add a typed pre-send complexity check if R1 is confirmed (§5.7). |
| [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig), [bedrock_transport.zig](../src/adapters/provider/bedrock_transport.zig), [bedrock_http_head.zig](../src/adapters/provider/bedrock_http_head.zig) | Exchange core, endpoint, `Bearer` header and `x-amzn-*` headers in one file; transport request carries a `BedrockRegion` | Extract a shared exchange core and transport request with a closed endpoint union; keep endpoint and header projection per provider (§5.6). The head parser is already generic. |
| [root.zig:82](../src/composition/root.zig#L82), [bedrock_api_key_source.zig](../src/adapters/system/bedrock_api_key_source.zig) | Credential snapshot typed and sourced for Bedrock | Add a per-provider credential source; reuse the snapshot type if its rules are identical. |
| [request_replay.zig](../src/adapters/provider/request_replay.zig), [request_debugger.zig:45](../src/composition/request_debugger.zig#L45) | Replay and its authorization return Bedrock-only types | Dispatch replay by provider so Anthropic captures can be inspected and replayed. |
| [architecture_test.zig:89-112](../src/architecture_test.zig#L89-L112) | Import restrictions name only Bedrock files | Add equivalent restrictions for the Anthropic adapter files and the shared exchange core. |
| Harness: [trace.zig](../test/harness/e2e/trace.zig), [compatibility inspection](../test/harness/compatibility/inspection.zig), [environment.zig](../test/harness/environment.zig), [model_cost_policy.zig](../test/harness/model_cost_policy.zig) | Trace wraps `provider.aws_bedrock.transport`; probe checks a Bedrock region; credentials and cost policy list Bedrock only | Generalize the trace wrapper and probe binding check; add the test credential; extend the cost policy only by explicit decision (§10.5). |

## 5. Proposed design

### 5.1 Owners

The table mirrors [F0007's ownership](../design/features/F0007-AWSBedrockProvider.md#responsibility-and-ownership).
Neither provider's adapter imports the other's.

| Owner | Responsibility |
| --- | --- |
| `composition/provider_model_contracts.zig` | Compiled Anthropic tuples and capabilities; no client or credential. |
| `domain/llm_provider_contracts.zig` | Provider-fact union, including the Anthropic variant and its validation. |
| `domain/model_capabilities.zig` | `requires_max_output_tokens` and the native structured-response mode. |
| `adapters/system/anthropic_api_key_source.zig` | Read exactly one permitted environment variable once, after selected-workflow binding validation. |
| `adapters/provider/anthropic_authorization.zig` | Deposit an Anthropic capability from preloaded material; no environment or I/O port. |
| `adapters/provider/anthropic.zig` | Implement the provider-neutral port through the existing lease-consumption boundary. |
| `adapters/provider/anthropic_request.zig` | Canonical Messages request projection. |
| `adapters/provider/anthropic_response.zig` | Strict closed response, usage, stop, reasoning and error normalization. |
| `adapters/provider/model_http_exchange.zig` (extracted) | Provider-neutral HTTPS exchange: deadline timer, body retention, redirect and framing rules; through [native_model_http.zig](../src/adapters/provider/native_model_http.zig); no retries. |
| `adapters/provider/bedrock_endpoint.zig`, `anthropic_endpoint.zig` | Closed endpoint, request-header and response-header projection per provider. |
| `adapters/provider/provider_dispatch.zig` | Exhaustive dispatch of invocation and authorization over both providers. |
| `composition/model_provider_runtime.zig` | Construct each required provider and wire it to the runner-owned lease table. |
| Pipeline runner | Unchanged: lifecycle, single-use leases, actual-usage accounting and cleanup. |

File names are illustrative; the ADR fixes them.

### 5.2 Registry entry

```zig
.{
    .provider = .{ .bytes = "anthropic" },
    .model = .{ .bytes = "claude-opus-5-5" },
    .implementation_id = anthropic_implementation, // ordinal 2
    .config_schema = .empty_object,
    .provider_facts = .{ .anthropic = .{} },
    .supported_reasoning_efforts = &.{ "low", "medium", "high", "xhigh", "max" },
    .capabilities = .{
        .input_token_count = false,
        .inference = true,
        .exact_token_counter = .unavailable,
        .structured_response = .anthropic_json_schema, // or .prompt_only after step 0
        .temperature = false,
        .supports_max_output_tokens = true,
        .requires_max_output_tokens = true,
    },
},
```

Registry validation must reject an Anthropic fact on a non-`empty_object` schema, a
Bedrock fact without regions, and a fact whose provider differs from the entry's
provider. Which models to register is decision §10.1.

### 5.3 Credentials

- **Production:** read only `ANTHROPIC_API_KEY`, with the same rules as
  [bedrock_api_key_source.zig](../src/adapters/system/bedrock_api_key_source.zig):
  read once, non-empty printable ASCII, zeroed on release, no fallback variables and
  no credential chain. An unset `ANTHROPIC_API_KEY` is `unavailable`, even if another
  credential source exists on the machine.
- **Harness:** `TEST_ANTHROPIC_API_KEY`, following the existing `TEST_` convention in
  [environment.zig](../test/harness/environment.zig) and `.env.e2e.example`.
- **Redaction:** the key is a capture secret. It is sent only as the `x-api-key`
  header and must never appear in captured request bodies, descriptions, reports or
  logs.
- **Only the credentials a workflow needs are read** (§2.1).

### 5.4 Request encoder

| Engine input | Messages API field |
| --- | --- |
| `system` and `guidance` content parts, then the universal response-format guidance and schema guidance | `system`: text blocks, in order |
| `user` and `evidence` content parts | `messages[0]`: one `user` message of text blocks, in order; none is an error |
| Binding `max_output_tokens` | `max_tokens`; missing is rejected at binding |
| Binding `reasoning_effort` | `output_config.effort`; omitted when absent |
| `native_schema` mode | `output_config.format = {type: "json_schema", schema: <projected object>}` |
| `prompt_only` mode | No `format`; the complete schema stays in `system` guidance |
| Temperature | Never sent; a non-null value rejects as `request_rejected` before send |

Reuse the content ordering of [bedrock_request.zig](../src/adapters/provider/bedrock_request.zig)
`writeInput`. Move it to one shared owner rather than duplicating it.

### 5.5 Response decoder

| `stop_reason` | Engine outcome |
| --- | --- |
| `end_turn` with non-empty joined text | Candidate |
| `end_turn` without text | Rejected: `missing_final_text` |
| `max_tokens` | Non-candidate: `output_limit` |
| `model_context_window_exceeded` | Non-candidate: `context_limit` |
| `refusal` | Non-candidate: `content_filtered`, unless decision §10.4 adds `refused` |
| `tool_use`, `pause_turn` | Non-candidate: `unsupported_tool_request` |
| `stop_sequence` | Non-candidate: `malformed_output`; the engine sends no stop sequences |
| Any other value | `response_invalid` |

- Join `text` blocks in order without inserting characters. A `text` block with
  non-null `citations` is `response_invalid`, because no citation source is sent.
- Retain `thinking` (signature and usually empty text) and `redacted_thinking`
  blocks as owned, ordered
  [provider reasoning](../src/domain/provider_reasoning.zig) diagnostics. The
  existing `text`/`redacted` block type fits unchanged. They never enter candidate
  content or gain workflow authority.
- Normalize usage under [ADR 0011](../design/decisions/0011-provider-owned-request-limits.md#workflow-token-accounting):
  inclusive input = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
  (null counts as 0); total = inclusive input + `output_tokens`. Retain
  `thinking_tokens` as a diagnostic. Usage is retained for every received response,
  including rejected and non-candidate ones.
- Decoding is closed against the field list in §3.5, with nulls accepted where the
  API declares them. An unknown field rejects with a precise path diagnostic, as the
  Converse decoder does. Each API addition therefore needs a decoder update
  (decision §10.3).

### 5.6 HTTP exchange

- Extract the provider-neutral parts of `bedrock_http.zig` into one shared exchange:
  runtime cancellation and deadline checks, the concurrent network and timer tasks,
  body retention through `response_body_on_error`, the content-length send, redirect
  rejection, identity-only encoding and terminal framing checks.
- Each provider supplies a closed endpoint projection: URL, request headers and the
  response headers to retain. Bedrock keeps `Bearer` authorization and
  `x-amzn-errortype`/`x-amzn-requestid`; Anthropic sends `x-api-key` and
  `anthropic-version` and retains `request-id` and `retry-after`. Duplicate response
  headers of a retained name reject, as today.
- One request per exchange, with the operation's original deadline, no retries and
  no redirects. Consider TCP keep-alive if the per-call deadline is raised (§3.1).
- Network calls stay compiled out of every test executable through
  `native_model_http.zig`; add the Anthropic endpoint to its denial test.

### 5.7 Schema complexity check (if R1 is confirmed)

If step 0 confirms that projected union counts are rejected, add a deterministic
pre-send check at the schema-projection owner, driven by limits declared in the
Anthropic provider facts. A request whose projected schema exceeds them fails with a
typed `request_rejected` diagnostic before send. It never switches that request to
prompt-only mode. A project that needs those requests on Claude configures the
model with `json: false`. Whether the check runs at workflow binding (for every
schema the bound steps can send) or per request is part of the ADR.

## 6. Debugger, harness and evidence

- **Capture:** reuse the model exchange capture port. Request bodies contain no
  secret; responses are captured with the key in the redaction list. Thinking
  signatures are opaque diagnostic data.
- **Inspection and replay** ([ADR 0019](../design/decisions/0019-single-request-debugger.md)):
  replay must re-encode an Anthropic description byte-identically and keep the
  rejection of changed targets. Without this, Anthropic exchanges cannot be
  inspected or replayed.
- **Compatibility probe:** generalize the binding check in
  [trace.zig](../test/harness/e2e/trace.zig) (`validateProbeWire`,
  `validateProbeDescription`) from a Bedrock region to the provider facts. Keep the
  one-send bound.
- **E2E and launchers:** add the test credential to `.env.e2e.example` and the
  launcher environment rules. Fixture `.sddproviders.json` and case configurations
  gain Anthropic entries only for approved live cases.
- **Evaluator:** the rubric judge's selection in [environment.zig](../test/harness/environment.zig)
  is a separate harness API enum. Adding an Anthropic judge is optional and needs its
  own decision; a Claude generator does not require a Claude judge.

## 7. Invariants and rejected alternatives

| Alternative | Decision | Reason |
| --- | --- | --- |
| Server-side refusal fallback (`fallbacks`) | Rejected | It reruns a refused request on another model inside the same call. Output would be attributed to a model the slot did not select, violating the no-substitution rule ([§12.3.1](../design/contracts/12-model-boundary.md#1231-bedrock-converse--user-directed-transport-amendment-15-october-2026)). A refusal is a typed non-candidate stop. |
| Automatic prompt-only fallback when a schema is too complex | Rejected | A per-request mode switch is a hidden fallback. Response mode stays fixed per catalogue entry; an oversized schema fails typed (§5.7). |
| Engine default for `max_tokens` | Rejected | A silent default is a fallback, and [ADR 0011](../design/decisions/0011-provider-owned-request-limits.md) leaves limits to the provider and explicit configuration. Binding rejects the slot instead. |
| Registering `count_tokens` as the exact counter | Rejected | The API documents it as an estimate (§3.7). |
| Model-name branching (`claude-*` prefix rules) | Rejected | Behavior comes only from compiled tuples and provider facts. |
| Credential chain (OAuth, profiles, `ANTHROPIC_AUTH_TOKEN`) | Rejected for this increment | One exact variable keeps credential authority explicit and testable. |
| Endpoint override (`base_url`) | Rejected | Endpoints are compiled constants; configuration would make endpoints project data. |
| Lenient decoding of unknown fields | Rejected by default | Closed parsing is required for external data. Decision §10.3 records the maintenance cost. |
| A separate Anthropic HTTP stack | Rejected | Duplicates the transport policy in `bedrock_http.zig` (§5.6). |
| Streaming to avoid the 60-second deadline | Rejected as a fix for R2 | The deadline bounds total exchange time; streaming changes delivery, not duration. It remains a later option for outputs that exceed non-streaming limits. |
| Prompt caching | Deferred | Could cut repeated-prefix cost, which matters for the token budget in [FIX04 F9](Z_FIX02.md#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures): cache reads cost 5% of base input on Opus 5.5 and Sonnet 5.5. It changes request bytes and accounting, and the minimum cacheable prefix may exceed current prompts. Needs its own decision and measurement. |
| Claude on Bedrock through the existing connector | Out of scope | Already possible by registering Bedrock tuples; it is not the direct API. |

## 8. Implementation sequence

Step 0 resolves R1 and R2 before the design is frozen. Steps 1 and 2 change no
external behavior. Each step ends with all existing tests passing.

0. **Feasibility checks (separately approved live calls, outside the engine).** With
   a test key and the cost policy unchanged, send by hand:
   - each projected schema from §3.3 (records, extraction, brief) with a trivial
     prompt and a small `max_tokens`, to see whether compilation succeeds or returns
     "Schema is too complex for compilation";
   - one representative records-generation prompt per candidate model at the
     intended effort and `maxOutputTokens`, recording wall-clock latency, first-request
     compilation latency, `output_tokens` and `thinking_tokens`.

   Record the results in FIX05, then decide the response mode (§10.2a) and the
   deadline (§10.9). Cost is a few cents. These calls are diagnostic evidence only.
1. **Generalize provider facts, routing and authorization, Bedrock only.** Replace the
   Bedrock fields with the provider-fact union, add `requires_max_output_tokens`,
   route invocation and authorization by implementation, and build providers per
   selected binding. Remove the superseded fields in the same change.
   Tests: registry accepted and rejected cases; routing with fake providers for
   Bedrock-only, Anthropic-only and mixed slot configurations; only the referenced
   providers constructed and only their credentials read; a retry staying on its
   original provider; missing output allowance rejected; unchanged Bedrock
   conformance; architecture rules.
   Verify: `zig build test-provider-conformance test-model-request-preparation test-model-request-workflow test-architecture`.
2. **Shared HTTP exchange, Bedrock only.** Extract the exchange core and Bedrock
   endpoint projection. Tests: existing Bedrock HTTP tests unchanged and passing;
   duplicate retained headers rejected per provider.
   Verify: the Bedrock HTTP and transport suites plus `zig build test-architecture`.
3. **Anthropic codec and projection.** Request encoder, response decoder and, if
   needed, the complexity check. Tests: exact request bytes for both response modes,
   with and without effort; every stop reason; every usage field including nulls and
   `thinking_tokens`; thinking and redacted blocks; unexpected citations and tool
   blocks rejected; unknown fields; every error row in §3.6 including spend-cap
   `details`; mismatched status and type; temperature rejected before send; complexity
   limits accepted and rejected.
   Verify: `zig build test-model-request-preparation test-provider-invocation-validation`
   plus the new codec suites registered in `build.zig`.
4. **Transport, credentials and composition.** Anthropic endpoint projection,
   credential source and authorization, wired through dispatch. Tests: offline
   integration of a complete workflow with a fake Anthropic transport in an unrelated
   domain; a mixed-provider workflow; credential absence and invalid key; redaction
   of the key from every capture; transport failure with partial body; deadline
   expiry. Verify: `zig build test-integration`.
5. **Debugger and harness.** Anthropic capture inspection and replay; generalized
   probe binding check; test credential handling; launcher tests.
   Verify: `zig build test-provider-compatibility test-provider-compatibility-launcher smoke-provider-compatibility`.
6. **Full verification and packaging.** `zig build verify --summary all`, including
   clean-directory native packaging smoke. No new runtime assets are expected.
7. **Live compatibility (separately approved).** After the cost-policy decision, one
   one-send probe per registered Anthropic tuple:
   `zig build provider-compatibility -- --case <approved-case> --live`. A compatible
   result qualifies only the observed request shape and settings. The probe sends
   only the workflow's first request (content extraction), so it does not exercise
   the records schema; step 0 covers that. Any full E2E run needs its own approval.

## 9. Documentation and governance

- **ADR 0023 — direct Anthropic Messages API provider:** records Claude and
  Bedrock as configuration-selected peer providers (§2.1), the provider ID,
  endpoint, API version pin, credential variable, provider-fact union, response-mode
  and complexity-check decision, non-streaming scope, refusal and spend-cap handling,
  closed decoding, the shared HTTP exchange and the rejected alternatives in §7.
- **Feature document `design/features/F0009-AnthropicProvider.md`:** responsibility,
  configuration, credentials, request and schema projection, response and
  accounting, acceptance evidence, structured like
  [F0007](../design/features/F0007-AWSBedrockProvider.md). F0009 is currently unused.
- **Contract amendments:** a §12.3.2 Anthropic section beside
  [§12.3.1](../design/contracts/12-model-boundary.md#1231-bedrock-converse--user-directed-transport-amendment-15-october-2026);
  [§9 configuration](../design/contracts/09-configuration.md) for the provider ID,
  `empty_object` configuration and the required `maxOutputTokens`; updates to
  [F0006](../design/features/F0006-LLMProviderInterface.md),
  [F0007](../design/features/F0007-AWSBedrockProvider.md) (shared exchange) and
  [F0008](../design/features/F0008-LLMProviderConfigService.md) where they describe
  a single provider; and the workflow definition if the deadline changes.
- **Harness documentation:** credential and launcher rules in
  [e2e.md](../design/harness/e2e.md) and `.env.e2e.example`.
- **FIX05:** record step-0 results, implementation progress and verification there
  once accepted.

## 10. Decisions required

1. **Registered models.** Which Claude tuples to compile. Each needs its own entry
   and, before live use, its own compatibility probe. Haiku 5.5 is the fastest and
   cheapest; Opus 5.5 is the most capable of the three in §3.4 and cannot turn
   thinking off.
2. **Mixed providers per workflow.** Settled as a requirement by user direction on
   16 October 2026: configuration selects Claude or Bedrock per slot, and one
   workflow may use both (§2.1). The ADR must record this.
   - **2a. Response mode for Claude entries.** After step 0: native schema with the
     §5.7 complexity check, or prompt-only (`json: false`). Prompt-only relies on the
     engine's validation and protocol correction instead of constrained decoding.
3. **Closed decoding against an evolving API.** Accept that new response fields
   reject until the decoder is updated, with the `anthropic-version` pin and captured
   fixtures as the change signal.
4. **Refusal outcome.** Map `refusal` to the existing `content_filtered`, or add a
   distinct `refused` non-candidate stop that retains `stop_details.category`.
5. **Live-test cost policy.** [model_cost_policy.zig](../test/harness/model_cost_policy.zig)
   permits only Bedrock `openai.gpt-oss-20b-1:0` and rejects Claude tuples. Any live
   Anthropic probe or E2E run needs an explicit policy change naming the exact tuple.
   Mixing a Claude slot into the [semantic-simplicity protocol](../test/calibration/semantic-simplicity/README.md)'s GPT-OSS-only evaluation would mix
   cohorts and is not permitted by that protocol.
6. **Billing, spend-cap and spend-limit errors.** Map 402 `billing_error`, the
   spend-cap 429 and the user-set spend-limit 400 to existing causes, or add a
   dedicated non-retryable cause so reports distinguish an exhausted account from a
   permission problem or a malformed request.
7. **Workflow token budget.** Claude output includes billed thinking tokens and a
   different tokenizer. The compiled 100,000-token workflow budget already stops full
   workflows on small features
   ([FIX04 F9](Z_FIX02.md#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures)).
   A Claude slot does not change that decision, but adds to it.
8. **Credential check timing in mixed workflows.** Today a missing credential is
   detected only when that provider's call is authorized, so the other provider's
   calls may already have run. Recommended: after binding validation, require
   credentials for every provider the bindings reference before the first send.
9. **Per-call deadline.** Keep the shared 60-second `timeout-ms`, raise it in the
   workflow definition for all providers, or introduce a typed per-binding deadline
   policy. Decide after step 0's latency measurements.
10. **Data residency.** The direct API reports `inference_geo` but this design sends
    no geography control. If Australian or other residency is required, record
    whether the direct API is acceptable before registering it for production.

## 11. Acceptance evidence

The connector is complete only when:

- step-0 results are recorded and decisions 2a and 9 are made;
- the ADR, feature document and contract amendments are accepted;
- registry, capability, codec, schema-projection, transport, credential, redaction,
  routing, authorization, debugger and harness tests exist with accepted and
  rejected cases at their owning boundaries;
- Bedrock conformance and offline integration are unchanged;
- offline integration passes for Bedrock-only, Claude-only and mixed slot
  configurations, with no cross-provider fallback;
- `zig build verify --summary all` passes, including native packaging smoke;
- the superseded Bedrock-only fields and the duplicated transport code are removed,
  with no parallel path;
- for each registered tuple intended for live use, a separately approved one-send
  probe is `compatible`.

Compatibility establishes request and response handling only. It does not establish
semantic quality, workflow completion or any FIX05 qualification.

## 12. Sources

External facts were read on 16 October 2026:

- [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs):
  request shape, supported features, complexity limits, grammar caching, refusal and
  `max_tokens` behavior.
- [Messages API reference](https://platform.claude.com/docs/en/api/messages/create):
  required fields, `output_config`, deprecated sampling parameters, response, usage,
  content blocks, stop reasons and stop details.
- [Errors](https://platform.claude.com/docs/en/api/errors): status codes, error shape,
  `request-id`, request size limits and long-request guidance.
- [Rate limits](https://platform.claude.com/docs/en/api/rate-limits): tier limits,
  spend caps, the spend-cap 429 and response headers.
- [Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting):
  estimate semantics, pricing, rate limits and tokenizer note.
- [Models overview](https://platform.claude.com/docs/en/models/overview): IDs, pricing,
  defaults, latency class and retirement dates.
- [Effort](https://platform.claude.com/docs/en/build-with-claude/effort) and
  [Thinking](https://platform.claude.com/docs/en/build-with-claude/thinking): effort
  levels and defaults, thinking display, billing and per-model thinking controls.

Repository evidence: the 08:09 loan-renewal diagnostic's request captures and
`report.json` under
`zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/` (schema
measurements, token totals and GPT-OSS latency), and the source files linked in §0
and §4.
