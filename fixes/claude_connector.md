# Claude connector — direct Anthropic Messages API provider

**Prepared:** 16 October 2026, Australia/Melbourne. **Assessed and revised:**
18 October 2026, after code inspection and research against the live Anthropic
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
`85556b2f72accc32919a9180c04f0e01ceb18783`, including the accepted 18 October
amendment to ADR 0011. This review changes this proposal only; it does not amend
accepted authority or implement the connector. Existing unrelated worktree changes
are outside this review.

## 0. Feasibility assessment

**Verdict: blocked by an accepted contract, with additional unmeasured schema and
latency risks.** The Messages API requires `max_tokens`, while
[ADR 0011](../design/decisions/0011-provider-owned-request-limits.md#no-output-token-allowance),
design invariant 32 and acceptance criterion 31.12 prohibit sending any output-token
allowance. Neither restoring `maxOutputTokens` nor encoding a model maximum in the
adapter is authorized. Omitting the required API field is not a supported solution.
Decision §10.0 must resolve this conflict before implementation or live diagnostics.

This is an authority conflict, not a technical inability to obtain the value:
Anthropic's Models API publishes a nullable `max_tokens` maximum. An adapter could
transmit that provider-sourced maximum instead of choosing a lower SDDE ceiling.
That narrower option, raised during this review, is described in §10.0 and remains
unapproved. [Model metadata](https://platform.claude.com/docs/en/api/php/models).

The remaining proposal is conditional on that decision. Shared lifecycle and
accounting mechanisms can be reused, but provider routing, persisted evidence and
some diagnostics need deliberate contract work (§§4–6). A closed provider API
decoder also requires maintenance even with a pinned API version (§10.3).

| ID | Severity | Finding | Evidence | Consequence |
| --- | --- | --- | --- | --- |
| R0 | **Authority blocker** | The API requires `max_tokens`; current SDDE authority prohibits output allowances throughout configuration, preparation, transport and replay. | ADR 0011; Messages API reference | Obtain an explicit decision amending the affected authority, or defer direct Messages support. Do not infer an exception (§10.0). |
| R1 | **Unmeasured** | Anthropic limits union parameters and optional parameters (§3.3). The previous review reported 32 `anyOf` nodes for records and 16 for extraction in historical captures that are no longer available locally. | Structured-outputs documentation; historical figures retained in §3.3 | Re-measure current complete and derived schemas. Node counts do not establish the provider's parameter count or grammar acceptance. Any live check needs the §8 approvals; no automatic fallback or unapproved local capacity gate. |
| R2 | **Unmeasured** | The Spec workflow's shared request subgraph sets a **60-second** total deadline; diagnostic replay instead uses **300 seconds**. Claude latency and first-use grammar compilation have not been measured here. | [spec.workflow.yaml](../design/workflows/spec.workflow.yaml); [request_replay.zig](../src/adapters/provider/request_replay.zig); [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig) | Replay success does not prove workflow deadline compatibility. Measure cold and repeated schemas and each intended effort/model. A deadline change needs explicit workflow/policy scope (§10.9); streaming does not extend total time. |
| R3 | High | `max_tokens` is a hard limit on thinking **plus** visible text, and thinking is billed as output. Opus 5.5 cannot disable thinking. | Effort and thinking documentation | Thinking tokens add to the compiled 100,000-token workflow budget, which historical small-feature runs exhausted ([FIX04 F9](Z_FIX02.md#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures)). Select explicit effort for comparable measurements and retain `usage.output_tokens_details.thinking_tokens`; the configuration control remains optional. |
| R4 | Medium | Bedrock's deadline, cancellation, body retention and HTTP framing logic can be shared; endpoint and authentication remain provider-specific. | [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig) | Extract one exchange owner with closed provider projections and failure-path regression evidence (§5.6). |
| R5 | Medium | The authorization adapter is a single port that rejects any non-Bedrock configuration, and composition builds one provider. A missing key fails as `authentication_failed`, detected only when that provider's call is authorized. | [bedrock_authorization.zig](../src/adapters/provider/bedrock_authorization.zig); [model_provider_runtime.zig](../src/composition/model_provider_runtime.zig) | Mixed-provider workflows need per-provider authorization and credential material, dispatched by registry entry (§4, §10.8). |
| R6 | Medium | `count_tokens` returns an **estimate** that "might differ by a small amount" and can include system-added tokens. | Token-counting documentation | It must not be registered as the engine's exact token counter. The Spec workflow never counts tokens, so the first increment registers no counting capability (§3.7). |
| R7 | Medium | A 429 is not always retryable: the monthly spend-cap 429 has no `retry-after`, carries `error.details.error_code: "enforced_spend_limit_reached"`, and keeps failing. A user-set spend limit returns 400. Error types "will grow over time". | Errors and rate-limits documentation | The closed error decoder must accept `error.details`, classify the spend cap as non-retryable, and treat unknown types as `response_invalid` (§3.6). |
| R8 | Medium | Ordinary responses may include `usage.speed`, nullable refusal explanations, `container` and `diagnostics`; the earlier field inventory was incomplete. | Messages API and focused response documentation | Freeze exact presence, nullability and nested schemas in fixtures; reject unknown values without losing independently valid usage (§5.5). |
| R9 | Medium | Omitting `inference_geo` inherits the workspace default. Inference location and storage location are separate settings. | [Data residency](https://platform.claude.com/docs/en/manage-claude/data-residency) | Empty project configuration does not pin residency. Record the intended workspace's defaults and retention requirements (§10.10). |
| R10 | Low | Asking for private step-by-step reasoning can trigger `reasoning_extraction`; a short evidence explanation or a field named `detail` alone does not establish that problem. | [Refusals](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback) | Keep typed non-candidate stops and measure actual refusal behavior. |

**Feasibility by area:**

| Area | Assessment |
| --- | --- |
| Configuration selection (§2) | Existing selection chain is reusable; routing and credential ownership need generalization. |
| Request encoding (§5.4) | **Blocked (R0)** regardless of response mode. Other fields map to existing content parts. |
| Native structured output (§3.3) | **Uncertain (R1).** Prompt-only is a proposed fixed mode, still subject to R0 and quality evidence. |
| Response, usage, stop and reasoning decoding (§5.5) | Core outcomes fit; additional metadata needs an explicit diagnostic owner or raw-capture-only treatment. |
| Errors (§3.6) | Feasible; needs one decision on spend-cap and billing causes. |
| Transport (§5.6) | Feasible; refactor rather than duplicate. |
| Latency within current deadlines | **Uncertain (R2).** |
| Mixed providers (§2.1) | Feasible; requires the routing and authorization changes in §4. |
| Cost | Historical GPT-OSS totals are not a Claude estimate. Price actual per-request inclusive input and output using the selected model's tier, geography and refusal rules; thinking and tokenizer differences prevent transferring token totals (§3.4). |

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
mode; per-message effort; Claude on Bedrock, Vertex AI or Foundry. Existing compiled
Bedrock tuples do not imply support for every current Claude model or Bedrock API.
Each is a separate decision; several conflict with engine invariants (§7).

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

The following is a **proposed selection shape**, not a working configuration today:
Anthropic tuples are not registered, and R0 prevents an authorized wire request.
The retired `maxOutputTokens` field is deliberately absent.

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
    "spec_generation": { "provider": "anthropic", "model": "claude-opus-5-5", "reasoningEffort": "low" },
    "repair":          { "provider": "aws-bedrock", "model": "openai.gpt-oss-20b-1:0", "reasoningEffort": "low" }
  }
}
```

- `provider: "anthropic"` satisfies the existing lower-kebab provider grammar
  ([llm_provider_identity.zig](../src/domain/llm_provider_identity.zig)); Claude
  model IDs satisfy the model grammar. Current Claude IDs are pinned snapshots,
  including the dateless IDs. Serving infrastructure and safety behavior can still
  change; this does not promise reproducible model output.
  [Model IDs and versioning](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions).
- `config: {}` uses the existing `empty_object` configuration schema. The endpoint
  has no region, and endpoints and credentials stay out of project data.
- `json` is fixed per catalogue entry, so every slot using that model shares one
  response mode. The example uses `json: false` (prompt-only) until R1 is resolved.
- `maxOutputTokens` remains rejected under ADR 0011. No replacement control,
  required-output capability or hidden adapter constant is proposed as a workaround
  for R0.
- `reasoningEffort` is optional but should be set explicitly. When omitted, the
  request omits `output_config.effort` and the model's own default applies (§3.4).
- Unknown models, configuration fields and unsupported controls reject at the
  existing binding boundary. There is no model-name branching and no fallback.

### 2.1 Using both providers

Claude and Bedrock are independent peers selected per slot. The engine never chooses
between them itself.

| Selected workflow needs | Providers prepared | Credentials read |
| --- | --- | --- |
| No model operations | None | None |
| Bindings for pure preparation/validation only | Validate bindings; no provider-call capability | None |
| Provider calls on `aws-bedrock` only | Bedrock only | `AWS_BEARER_TOKEN_BEDROCK` |
| Provider calls on `anthropic` only | Anthropic only | `ANTHROPIC_API_KEY` |
| Provider calls on both | Both | Both, with timing subject to §10.8 |
| Catalogue lists an unused provider | No provider solely for that entry | No credential solely for that entry |

Rules:

- **Selection is per slot and fixed for the invocation.** Each model request uses the
  binding its originating step selected
  ([ADR 0012](../design/decisions/0012-workflow-owned-model-request.md)). Protocol
  corrections and retries keep that binding, so they stay on the same provider and
  model.
- **Provider construction follows selected workflow capability needs.** Validate
  bindings first. Preserve ADR 0004's binding-only path without credential I/O;
  catalogue membership or another workflow's slot grants no provider authority.
  A Bedrock-only call path never reads `ANTHROPIC_API_KEY`, and the converse holds.
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
- **Reports name the provider per call.** Existing reports contain binding data, but
  the persisted call-context schema still assumes Bedrock (§4). Make every producer
  and consumer carry exact typed provider/model/config identity before claiming
  mixed-run attribution.
- **Evaluation cohorts stay separate.** Mixing providers is valid for production
  configuration. An evaluation protocol that freezes one model, such as
  the [semantic-simplicity protocol](../test/calibration/semantic-simplicity/README.md)'s GPT-OSS-only panel, must not mix providers within a comparison.

## 3. External API contract

Facts below were checked against the live Anthropic documentation on
18 October 2026 (§12). Recheck them when the ADR is written and freeze the checked
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

This is an **external API illustration**, not an authorized SDDE request. Its
required `max_tokens` field demonstrates R0; the example value is not a proposed
engine default or configuration control.

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
- Sampling restrictions differ between model-specific and generic documentation.
  The proposed contract omits `temperature`, `top_p` and `top_k` entirely; it does
  not infer additional supported controls from permissive examples.
  [Haiku migration guidance](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide#remove-sampling-parameters).
- Assistant prefill returns 400 on current models; the engine never prefills.
- `thinking` is not sent. Omitting it runs adaptive thinking on all three models
  in §3.4.

### 3.3 Structured-output schema subset and limits

**Supported:** `object`, `array`, `string`, `integer`, `number`, `boolean`, `null`;
`enum` of strings, numbers, booleans or nulls; `const`; `anyOf`; `allOf` (not with
`$ref`); local references/definitions (confirm exact keyword support in the
projection fixtures); `default`; `required`;
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
prompt, which costs input tokens. Schema structure changes invalidate the grammar
cache; dynamic enums and derived response parts need separate measurement.

**Fit with the engine's existing projection.** The `bedrock` profile in
[model_schema_projection.zig](../src/domain/model_schema_projection.zig) already
removes string and numeric bounds and `maxItems`, reduces a nonzero `minItems` to 1,
emits `anyOf` instead of `oneOf`, and closes every object. This is a reuse candidate,
not proof of Anthropic compatibility. It does not establish grammar acceptance.
The previous review reported these measurements from Bedrock-projected schemas in
the 08:09 loan-renewal diagnostic; the source directory is now absent (§12), so
these figures were **not reproduced** during this review:

| Request (call) | Schema bytes | `anyOf` nodes | Optional properties |
| --- | --- | --- | --- |
| Content extraction (1) | 4,079 | 16 | 0 |
| Record generation (10–12) | 7,519 | 32 | 0 |
| Brief (7) | 2,616 | 9 | 0 |
| Story and entities (8, 9) | 1,444–1,592 | 5 | 0 |
| Source review (13–36) | 776–2,825 | 0–2 | 0 |

The historical samples reportedly had no optional properties. This does not cover
current schemas, generic response parts, repair or advisory paths. Count the exact
current schemas and retain reproducible measurements before choosing a response
mode. The documented parameter count is not necessarily the `anyOf` node count,
and satisfying published counts does not guarantee compilation. These are research
measurements, not permission to add local capacity gates (§5.7).
`oneOf` to `anyOf` stays safe because
[ADR 0006](../design/decisions/0006-minimal-model-response.md) requires alternatives
to be disjoint by JSON type or `kind` tag. Removed bounds remain enforced natively by
the complete schema
([§12.3](../design/contracts/12-model-boundary.md#123-provider-neutral-response-envelope)).

**Validation remains authoritative.** Anthropic documents possible capitalization
changes in string `enum` and `const` values even on normal completion. SDDE must
retain exact closed-value validation, not case-fold or silently alias the values.
Use existing protocol-correction rules only where already authorized. Native
grammar output never replaces the complete schema or semantic validators.
[Structured-output caveats](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#invalid-outputs).

**Schema data is sent too.** Grammar artifacts cache schemas separately from
message content. Review dynamic property names, enums, constants and patterns for
source data before selecting native mode; record applicable workspace retention
settings rather than claiming blanket zero retention (§10.10).
[API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention).

### 3.4 Models, thinking and effort

| Model | ID | Retirement not before | Price per MTok (in / out) | Thinking without `thinking` field | Turning thinking off | Effort default |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Opus 5.5 | `claude-opus-5-5` | 22 Sep 2027 | $4 / $20 | Adaptive, always on | Not possible; `disabled` returns 400 | `medium` |
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | 28 Sep 2027 | $2 / $10 | Adaptive | `between_tools` at `high` or below; `disabled` returns 400 | `high` |
| Claude Haiku 5.5 | `claude-haiku-5-5` | 7 Oct 2027 | $0.10 / $0.50 up to 100K prompt tokens; $0.50 / $2.50 above | Adaptive | `disabled` at `high` or below | `medium` |

Pricing is per request, using inclusive prompt size, not aggregate workflow usage.
Geography and other account settings can affect currency cost; record them with
any estimate. [Haiku pricing](https://platform.claude.com/docs/en/models/haiku-5-5/overview),
[data residency](https://platform.claude.com/docs/en/manage-claude/data-residency).

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
- **Stop details:** `{type: "refusal", category, explanation}` or null; both
  `category` and `explanation` can be null. `category` is
  `cyber`, `bio`, `frontier_llm`, `reasoning_extraction`, `general_harms` or null.
  A refusal returns HTTP 200 and may violate the requested schema. Upfront
  `cyber`, `general_harms` and uncategorized refusals are not billed; upfront
  `bio`, `frontier_llm` and `reasoning_extraction` refusals and partial-output
  refusals are billed. Reported usage still counts toward the engine budget.
  Currency estimates must not label every reported token as a billed charge.
  [Refusal behavior and billing](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback).
- **Usage:** `input_tokens`, `output_tokens`, nullable `cache_creation_input_tokens`
  and `cache_read_input_tokens`, nullable `cache_creation`
  (`ephemeral_5m_input_tokens`, `ephemeral_1h_input_tokens`), nullable
  `output_tokens_details` (`thinking_tokens`, an approximate observability figure
  included in `output_tokens`), nullable `server_tool_use`, nullable `service_tier`
  (`standard`, `priority`, `batch`), nullable `inference_geo`, and `speed`
  (`standard` or `fast`). Deferring fast-mode requests does not remove ordinary
  standard-speed response metadata.
  [Speed metadata](https://platform.claude.com/docs/en/build-with-claude/fast-mode#checking-which-speed-was-used).
  Total input is
  `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`;
  `output_tokens` already includes thinking and is used once for token accounting.
  There is no total field.

This is an inventory to turn into a closed wire schema, not a completed decoder
specification. Before implementation, resolve required/optional/null distinctions
and nested `container`, `diagnostics`, `server_tool_use` and cache metadata shapes
against the selected non-beta contract. Accept declared null/empty values; reject
unrequested tool effects and unknown variants rather than ignoring nested objects.
Generated examples can contradict focused stop documentation; fixtures must enforce
`stop_details == null` for non-refusal stops and distinguish missing from null where
the contract does. No real response capture was obtained during this review.
[Stop semantics](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons).

### 3.6 Errors

Error bodies are `{"type": "error", "error": {"type", "message", "details"?}, "request_id"}`.

| Status | `error.type` | Engine cause | Retry class |
| --- | --- | --- | --- |
| 400 | `invalid_request_error` | `request_rejected` | `never` |
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

A user-set spend-limit 400 remains generic `request_rejected` unless a documented
machine-readable discriminator supports a more precise cause. Do not add the old
proposal's message-text special case. Close `error.details` against documented
variants rather than accepting an arbitrary map. Malformed/non-JSON proxy or 413
bodies and inconsistent header/body request IDs need explicit rejection fixtures;
provider request IDs are diagnostic and never replace runner request identity.

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
models. New organizations may start in a lower Evaluation tier. Sequential engine
calls can still hit shared organization limits, workspace overrides or burst limits;
measure the selected account rather than assuming otherwise. Monthly spend caps
($500 on Start, $1,000 on Build) can stop all requests until the next month (R7).

## 4. Current Bedrock coupling

The provider port is neutral, but several shared types assume Bedrock. They must be
generalized before an Anthropic adapter can be added without parallel or
illegal-state fields.

| Location | Bedrock assumption | Required change |
| --- | --- | --- |
| [provider_dispatch.zig](../src/adapters/provider/provider_dispatch.zig) | `.port()` selects the single union member at construction | Adding a union variant alone cannot route mixed calls. Select invocation and authorization by trusted implementation identity per call. |
| [model_provider_runtime.zig](../src/composition/model_provider_runtime.zig) | Builds one Bedrock provider, authorization adapter and credential for workflows requiring provider authorization | Construct the provider set required by the selected call paths; preserve no-provider and binding-only paths without credential I/O. |
| [bedrock_authorization.zig](../src/adapters/provider/bedrock_authorization.zig) | The only authorization port; returns `authorization_denied` for any non-Bedrock configuration | Dispatch authorization by registry entry to the provider's own adapter; each deposits its own capability type. |
| [llm_provider_contracts.zig](../src/domain/llm_provider_contracts.zig) | `ProviderModelContract.bedrock_regions` and `bedrock_request_profile` | Replace with one tagged union of per-provider facts. Remove the Bedrock fields in the same change; do not add `anthropic_*` siblings. |
| [llm_provider_registry.zig](../src/domain/llm_provider_registry.zig) | `Entry.bedrock_request_profile` | Carry the same tagged union. |
| [model_capabilities.zig](../src/domain/model_capabilities.zig) | `StructuredResponse.bedrock_json_schema` is the only native mode | Add a typed Anthropic mode, or a shared native mode selected by provider facts. Output-allowance capabilities were removed under ADR 0011 and must not be restored by this proposal. |
| [model_schema_projection.zig](../src/domain/model_schema_projection.zig) | Profiles `complete` and `bedrock` | Prove the reusable projection against both providers' grammar subsets. Complexity measurement does not authorize a local capacity check (§5.7). |
| [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig), [bedrock_transport.zig](../src/adapters/provider/bedrock_transport.zig), [bedrock_http_head.zig](../src/adapters/provider/bedrock_http_head.zig) | Exchange core, endpoint, `Bearer` header and `x-amzn-*` headers in one file; transport request carries a `BedrockRegion` | Extract a shared exchange core and transport request with a closed endpoint union; keep endpoint and header projection per provider (§5.6). The head parser is already generic. |
| [root.zig:82](../src/composition/root.zig#L82), [bedrock_api_key_source.zig](../src/adapters/system/bedrock_api_key_source.zig) | Credential snapshot typed and sourced for Bedrock | Add a per-provider credential source; reuse the snapshot type if its rules are identical. |
| [request_replay.zig](../src/adapters/provider/request_replay.zig), [request_debugger.zig:45](../src/composition/request_debugger.zig#L45) | Replay and its authorization return Bedrock-only types | Dispatch replay by provider so Anthropic captures can be inspected and replayed. |
| [architecture_test.zig:89-112](../src/architecture_test.zig#L89-L112) | Import restrictions name only Bedrock files | Add equivalent restrictions for the Anthropic adapter files and the shared exchange core. |
| Harness invocation: [invoke.zig](../test/harness/e2e/invoke.zig), [E2E CLI](../test/harness/e2e/cli.zig), [environment.zig](../test/harness/environment.zig) | One generation key, a Bedrock credential snapshot/transport and a fixed generation/judge redaction pair | Inject typed selected-provider credentials; redact every selected secret across all exchanges, independently of judge selection. |
| Persisted evidence: [call_context.zig](../test/harness/e2e/call_context.zig), [trace.zig](../test/harness/e2e/trace.zig), [call/capture.zig](../test/harness/call/capture.zig) | `model-call-evidence/v1` requires a Bedrock region and has no provider field; trace and capture readers assume Bedrock | Version the changed closed shape deliberately; update all writers/readers together with provider/config identity. No fallback reader or migration that grants historical data current authority. |
| Diagnostics: [diagnostic_binding.zig](../test/harness/diagnostic_binding.zig), [call CLI](../test/harness/call/cli.zig), [compatibility CLI](../test/harness/compatibility/cli.zig), [inspection](../test/harness/compatibility/inspection.zig) | Bedrock request profiles, credential selection and replay | Route through the same typed provider contracts; retain exact request reconstruction and one-send bounds. |
| Harness policy: [frozen_binding.zig](../test/harness/frozen_binding.zig), [model_cost_policy.zig](../test/harness/model_cost_policy.zig) | Trace checks the frozen GPT-OSS evaluation binding; live cost policy separately permits only GPT-OSS | An explicitly approved generic compatibility path must not weaken the frozen evaluation cohort (§6, §10.5). |
| Packaging: [smoke.zig](../test/packaging/smoke.zig) | Provider bootstrap smoke covers Bedrock and region rejection | Add offline Claude-only/mixed bootstrap and debugger cases from a clean directory (§8). |

## 5. Proposed design

### 5.1 Owners

The table mirrors [F0007's ownership](../design/features/F0007-AWSBedrockProvider.md#responsibility-and-ownership).
Neither provider's adapter imports the other's.

| Owner | Responsibility |
| --- | --- |
| `composition/provider_model_contracts.zig` | Compiled Anthropic tuples and capabilities; no client or credential. |
| `domain/llm_provider_contracts.zig` | Provider-fact union, including the Anthropic variant and its validation. |
| `domain/model_capabilities.zig` | Supported native response mode and controls, without retired output-allowance fields. |
| `adapters/system/anthropic_api_key_source.zig` | Read one permitted variable once, only after valid bindings and a selected provider-call capability need. |
| `adapters/provider/anthropic_authorization.zig` | Deposit an Anthropic capability from preloaded material; no environment or I/O port. |
| `adapters/provider/anthropic.zig` | Implement the provider-neutral port through the existing lease-consumption boundary. |
| `adapters/provider/anthropic_request.zig` | Canonical Messages request projection. |
| `adapters/provider/anthropic_response.zig` | Strict closed response, usage, stop, reasoning and error normalization. |
| `adapters/provider/model_http_exchange.zig` (extracted) | Provider-neutral HTTPS exchange: deadline timer, body retention, redirect and framing rules; through [native_model_http.zig](../src/adapters/provider/native_model_http.zig); no retries. |
| `adapters/provider/bedrock_endpoint.zig`, `anthropic_endpoint.zig` | Closed endpoint, request-header and response-header projection per provider. |
| `adapters/provider/provider_dispatch.zig` | Exhaustive dispatch of invocation and authorization over both providers. |
| `composition/model_provider_runtime.zig` | Construct each required provider and wire it to the runner-owned lease table. |
| Pipeline runner | Remains sole authority for lifecycle, single-use leases, actual usage, stop logging and cleanup. Reuse these rules; exercise the new provider through them. |

File names are illustrative; the ADR fixes them.

The existing raw-result/reasoning types do not carry every proposed diagnostic:
`thinking_tokens`, refusal category, inference geography, API request ID and
`retry-after` need either explicitly documented raw-capture-only treatment or a
closed typed diagnostic owner with debugger/report projections. Decide this before
promising those fields in reports; diagnostic metadata grants no workflow authority.

### 5.2 Registry entry

```zig
.{
    .provider = .{ .bytes = "anthropic" },
    .model = .{ .bytes = "claude-opus-5-5" },
    .implementation_id = anthropic_implementation,
    .config_schema = .empty_object,
    .provider_facts = .{ .anthropic = .{} },
    .supported_reasoning_efforts = &.{ "low", "medium", "high", "xhigh", "max" },
    .capabilities = .{
        .input_token_count = false,
        .inference = true,
        .exact_token_counter = .unavailable,
        .structured_response = .anthropic_json_schema, // or .prompt_only after step 0
        .temperature = false,
    },
},
```

Registry validation must reject an Anthropic fact on a non-`empty_object` schema, a
Bedrock fact without regions, and a fact whose provider differs from the entry's
provider. Which models to register is decision §10.1. This illustrative entry is
conditional on R0; it does not supply the missing authority to send `max_tokens`.

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
  logs. In mixed runs, every selected generation and judge secret must be redacted
  from every provider's captures, including source/context/schema text, escaped
  JSON, errors and reasoning. Request content can itself contain secrets; it is not
  inherently safe because authentication normally uses a header.
- **Only the credentials a workflow needs are read** (§2.1).
- **Architecture evidence:** production must never import or read
  `TEST_ANTHROPIC_API_KEY`. Extend the existing test-variable isolation checks and
  prove authorization remains I/O-free and credentials are released on all paths.

### 5.4 Request encoder

| Engine input | Messages API field |
| --- | --- |
| `system` and `guidance` content parts, then the universal response-format guidance and schema guidance | `system`: text blocks, in order |
| `user` and `evidence` content parts | `messages[0]`: one `user` message of text blocks, in order; none is an error |
| No authorized engine source exists (R0) | API-required `max_tokens`; unresolved decision §10.0 |
| Binding `reasoning_effort` | `output_config.effort`; omitted when absent |
| `native_schema` mode | `output_config.format = {type: "json_schema", schema: <projected object>}` |
| `prompt_only` mode | No `format`; the complete schema stays in `system` guidance |
| Temperature | Never sent; a non-null value rejects as `request_rejected` before send |

Reuse the content-ordering policy of [bedrock_request.zig](../src/adapters/provider/bedrock_request.zig)
`writeInput` through a shared owner. Preserve provider-specific JSON encoding and
the existing complete/native-schema guidance distinctions. Prove stable order,
Unicode/escaping, empty-content rejection and no duplicate guidance in exact-byte
fixtures for both response modes; do not move prompt ownership into the adapter.

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
- Validate envelope identity: `type == "message"`, `role == "assistant"`, and
  returned model equals the registered selected model. Provider IDs and model
  assertions cannot replace runner-owned request association. Reject inconsistent
  stop metadata and unknown/duplicate fields, including nested ones.
- Retain `thinking` (signature and usually empty text) and `redacted_thinking`
  blocks as owned, ordered
  [provider reasoning](../src/domain/provider_reasoning.zig) diagnostics. The
  existing `text`/`redacted` block type fits unchanged. They never enter candidate
  content or gain workflow authority.
- Normalize usage under [ADR 0011](../design/decisions/0011-provider-owned-request-limits.md#workflow-token-accounting):
  inclusive input = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
  (declared absent/null optional cache counters count as 0); total = inclusive input
  + `output_tokens`. Do not add `thinking_tokens` or the cache-creation breakdown
  again. Reject negative, noninteger, out-of-range or overflowing counters and
  inconsistent breakdowns. Retain independently valid usage even when content is
  rejected or stopped; invalid/missing usage is unavailable, never fabricated.
- Account a received trusted observation exactly once before later capture,
  logging, cancellation or deadline failure. Both providers share the same total
  ledger, including advice. Test exact equality, overshoot and prohibition of
  subsequent calls across providers. Missing usage and invalid usage retain their
  different required/advisory consequences from ADR 0011; no new exception applies.
- Every non-candidate stop uses the existing `model.provider_stopped` warning with
  its exact typed reason; logging failure propagates. Partial output is never
  salvaged or given extra correction. Existing required/advisory disposition rules
  still own whether the stop fails work or records incomplete advice.
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
- One request per consumed lease, with the original deadline and no retries,
  redirects, proxy/endpoint discovery or credential chain. Preserve current HTTP
  connection-reuse policy; TCP keep-alive is a different mechanism and must not
  silently enable connection reuse.
- Keep request/response ownership explicit, join network/timer tasks on every
  path, and retain partial response bodies safely. Exercise cancellation before
  and during send, deadline expiry, allocation failure, malformed/duplicate
  headers, conflicting/truncated framing and partial bodies for both providers.
- Network calls stay compiled out of every test executable through
  `native_model_http.zig`; add the Anthropic endpoint to its denial test.

### 5.7 Schema compatibility and provider-owned capacity

Reuse deterministic validation of supported schema syntax at the projection owner.
Do **not** turn historical `anyOf` counts or published grammar limits into new
engine-enforced capacity gates: ADR 0011 prohibits static-capacity prediction,
including renamed provider-contract limits. The earlier proposal's automatic
pre-send complexity check is withdrawn pending explicit authority.

Once R0 is resolved, provider grammar rejections become typed `request_rejected`
outcomes. There is no per-request prompt-only fallback, schema weakening, truncation
or automatic splitting. A project may select prompt-only as its fixed catalogue
mode, with full native validation and separately measured quality. If an additional
pre-send grammar rule is desired, the ADR must distinguish syntax compatibility
from capacity prediction and obtain approval for any actual policy amendment.

## 6. Debugger, harness and evidence

- **Capture:** reuse the model exchange capture port and redact all selected
  secrets in requests and responses. Thinking signatures remain opaque diagnostic
  data. Do not claim raw source/context data is secret-free.
- **Inspection and replay** ([ADR 0019](../design/decisions/0019-single-request-debugger.md)):
  the current description is `model-request-debug/v7`, without an allowance.
  Reconstruct canonical bytes before send, preserve provider/model/settings and
  current registry authorization, persist the request before dispatch and the
  response before completion. Exactly one physical inference send occurs, with no
  workflow continuation. If R0 changes the wire contract, explicitly design its
  description/version and replay provenance together. Historical captures remain
  historical; no fallback readers or automatic upgrade grant current authority.
  Tests cover exact and modified replay, changed targets/settings, stale bindings,
  incomplete/redacted captures, non-candidate inspection, secrets in modified input
  and pre/post-send persistence failures, alongside existing Bedrock cases.
- **Compatibility probe:** current trace validation delegates to
  [frozen_binding.zig](../test/harness/frozen_binding.zig), which enforces the
  semantic-simplicity GPT-OSS cohort. The old `validateProbeWire` and
  `validateProbeDescription` names are no longer current. A generic compatibility
  binding contract must be separately approved and kept distinct from the frozen
  cohort. Adding a model to cost policy alone will not make the probe accept it.
  Keep the single inference-send bound and exact settings attribution.
- **Evidence schema:** change `model-call-evidence/v1` and all its producers and
  consumers together if provider/config identity changes (§4). Version mismatch,
  mismatched provider/config and historical evidence must reject as current input.
- **E2E and launchers:** add the test credential to `.env.e2e.example` and the
  launcher environment rules, provider-aware credential injection, and redaction
  of the complete selected-secret set. Case definitions gain Anthropic entries
  only under approved live-test policy; offline fixed scenarios remain integration
  tests, never substitute E2E evidence.
- **Evaluator:** the rubric judge's selection in [environment.zig](../test/harness/environment.zig)
  is a separate harness API enum. Adding an Anthropic judge is optional and needs its
  own decision; a Claude generator does not require a Claude judge.

## 7. Invariants and rejected alternatives

| Alternative | Decision | Reason |
| --- | --- | --- |
| Server-side refusal fallback (`fallbacks`) | Rejected | It reruns a refused request on another model inside the same call. Output would be attributed to a model the slot did not select, violating the no-substitution rule ([§12.3.1](../design/contracts/12-model-boundary.md#1231-bedrock-converse)). A refusal is a typed non-candidate stop. |
| Automatic prompt-only fallback when a schema is too complex | Rejected | A per-request mode switch is a hidden fallback. Response mode stays fixed per catalogue entry; an oversized schema fails typed (§5.7). |
| Restore `maxOutputTokens` or silently invent an adapter allowance | Rejected under current authority | ADR 0011 prohibits the control and sending an allowance. A provider-sourced maximum is technically possible but needs the explicit narrow decision in §10.0; it is not a user-configured limit. |
| Registering `count_tokens` as the exact counter | Rejected | The API documents it as an estimate (§3.7). |
| Model-name branching (`claude-*` prefix rules) | Rejected | Behavior comes only from compiled tuples and provider facts. |
| Credential chain (OAuth, profiles, `ANTHROPIC_AUTH_TOKEN`) | Rejected for this increment | One exact variable keeps credential authority explicit and testable. |
| Endpoint override (`base_url`) | Rejected | Endpoints are compiled constants; configuration would make endpoints project data. |
| Lenient decoding of unknown fields | Rejected by default | Closed parsing is required for external data. Decision §10.3 records the maintenance cost. |
| A separate Anthropic HTTP stack | Rejected | Duplicates the transport policy in `bedrock_http.zig` (§5.6). |
| Streaming to avoid the 60-second deadline | Rejected as a fix for R2 | The deadline bounds total exchange time; streaming changes delivery, not duration. It remains a later option for outputs that exceed non-streaming limits. |
| Prompt caching | Deferred | May reduce currency cost and latency. Cached input still counts fully in ADR 0011's inclusive token ledger, so it does not solve workflow token exhaustion. It changes request bytes and needs separate measurement. |
| Claude on Bedrock | Out of scope | Support depends on exact compiled tuple and API compatibility; do not infer that all current Claude models work through the existing Converse adapter. |

## 8. Implementation sequence

This is a conditional future sequence, not authorization to implement or execute
it. Resolve R0 first; then gather R1/R2 evidence before finalizing response mode and
deadline. Each implementation stage preserves Bedrock behavior and uses the
repository's build steps. No checks in this sequence ran during this document review.

0. **Authority and feasibility.** Decide §10.0 and the exact permitted models,
   metadata source (if used), diagnostic path and live-test policy (§10.5). First
   inventory current complete/derived schemas offline, including extraction,
   generation, repair and advice. Any subsequent live experiment needs explicit
   approval naming its tuple, settings, finite sends and cost authorization; manual
   requests are not an escape from policy. Measure actual current schemas and
   representative prompts, cold/repeated latency, output/thinking usage and typed
   rejections. Record artifact paths and hashes with results in FIX05. Make response
   mode (§10.2a) and deadline (§10.9) decisions from that evidence. These are
   diagnostics, not workflow or quality qualification.
1. **Generalize provider facts, routing and authorization, Bedrock only.** Replace the
   Bedrock fields with the provider-fact union,
   route invocation and authorization by implementation, and build providers per
   selected provider-call need. Remove the superseded fields in the same change.
   Tests: registry accepted and rejected cases; routing with fake providers for
   Bedrock-only, Anthropic-only and mixed slot configurations; only the referenced
   providers constructed and credentials read; no-provider/binding-only/unused
   catalogue and optional-branch cases; retries retaining their original binding;
   cross-provider capability substitution, replayed/expired leases and cleanup;
   unchanged Bedrock conformance and architecture rules. Keep retired output
   controls rejected unless an explicit amendment changes that exact contract.
   Verify: `zig build test-provider-conformance test-model-request-preparation test-model-request-workflow test-architecture`.
2. **Shared HTTP exchange, Bedrock only.** Extract the exchange core and Bedrock
   endpoint projection. Tests: existing Bedrock HTTP tests unchanged and passing;
   duplicate retained headers rejected per provider; framing, partial bodies,
   cancellation, deadline and allocation cleanup in §5.6.
   Verify: the Bedrock HTTP and transport suites plus `zig build test-architecture`.
3. **Anthropic codec and projection.** Request encoder and response decoder under
   the accepted R0 decision; shared syntax projection without new capacity gates.
   Tests: exact request bytes for both response modes,
   with and without effort; every stop reason; every usage field including nulls and
   `thinking_tokens` and `speed`; thinking and redacted blocks; unexpected citations
   and tool blocks rejected; unknown fields; every error row in §3.6 including spend-cap
   `details`; mismatched status and type; temperature rejected before send; complete
   native validation after projection. Add wrong-model/envelope fixtures, empty
   refusal, null explanations, inconsistent stop metadata, exact enum casing,
   duplicate fields, invalid/missing/overflowing usage and no double-counted caches
   or thinking. Exercise stop warnings and valid usage retained despite later errors.
   If provider metadata is accepted, test exact-model matching, null/invalid maximum,
   failed lookup, immutable invocation snapshots, no inference after failed
   preparation, and replay when current metadata differs from captured metadata.
   Verify: `zig build test-model-request-preparation test-provider-invocation-validation`
   plus the new codec suites registered in `build.zig`.
4. **Transport, credentials and composition.** Anthropic endpoint projection,
   credential source and authorization, wired through dispatch. Tests: offline
   integration of a complete workflow with a fake Anthropic transport in an unrelated
   domain; a mixed-provider workflow; credential absence and invalid key; redaction
   of the key from every capture; transport failure with partial body; deadline
   expiry; exact-once mixed usage and budget exhaustion during required work and
   advice. Verify: `zig build test-integration`.
5. **Debugger and harness.** Anthropic capture inspection and replay; generalized
   compatibility binding contract without weakening frozen cohort checks; evidence
   versioning, test credential handling and launcher tests (§6).
   Verify: `zig build test-provider-compatibility test-provider-compatibility-launcher smoke-provider-compatibility`.
6. **Full verification and packaging.** `zig build verify --summary all`, including
   clean-directory native packaging smoke. Add offline Claude-only and mixed
   bootstrap, unused provider entries, missing selected credential, unknown
   config/control rejection and debugger startup/readback. Run without the source
   tree, compiler, development assets or live network. No SDK or new runtime assets
   are expected.
7. **Live compatibility (separately approved).** After the cost-policy decision,
   one inference-send probe per registered Anthropic tuple, with any approved
   metadata lookup separately bounded and reported:
   `zig build provider-compatibility -- --case <approved-case> --live`. A compatible
   result qualifies only the observed request shape and settings. The probe sends
   only the workflow's first request, so it does not cover later schemas; step 0
   must cover those separately.
8. **Full live E2E (approval before each run).** Use explicitly identified target
   projects and workflow cases for intended Claude-only and mixed bindings, real
   selected services, and an independently selected rubric judge. Assess actual
   published output and record usage, stops, validation/publication results and
   semantic quality. A fake integration, replay or compatible probe cannot satisfy
   this acceptance criterion. If execution or evaluation cannot finish, record
   the unmet criterion without claiming E2E completion.

## 9. Documentation and governance

- **New ADR — direct Anthropic Messages API provider:** assign the next unused
  number at acceptance; 0023 and 0024 already govern other decisions. Record Claude
  and Bedrock as configuration-selected peer providers (§2.1), the provider ID,
  endpoint, API version pin, credential variable, provider-fact union, response-mode
  decision, R0 resolution, schema-capacity boundary, non-streaming scope, refusal
  and spend-cap handling,
  closed decoding, the shared HTTP exchange and the rejected alternatives in §7.
- **Feature document `design/features/F0009-AnthropicProvider.md`:** responsibility,
  configuration, credentials, request and schema projection, response and
  accounting, acceptance evidence, structured like
  [F0007](../design/features/F0007-AWSBedrockProvider.md). F0009 is currently unused.
- **Contract amendments:** a §12.3.2 Anthropic section beside
  [§12.3.1](../design/contracts/12-model-boundary.md#1231-bedrock-converse);
  [§9 configuration](../design/contracts/09-configuration.md) for the provider ID,
  `empty_object` configuration, keeping retired controls rejected; any explicitly
  approved R0 amendment to ADR 0011, invariant 32 and acceptance criterion 31.12;
  debugger/evidence schemas and their producers/readers; updates to
  [F0006](../design/features/F0006-LLMProviderInterface.md),
  [F0007](../design/features/F0007-AWSBedrockProvider.md) (shared exchange) and
  [F0008](../design/features/F0008-LLMProviderConfigService.md) where they describe
  a single provider; and the workflow definition if the deadline changes.
- **Harness documentation:** credential and launcher rules in
  [e2e.md](../design/harness/e2e.md) and `.env.e2e.example`.
- **FIX05:** record step-0 results, implementation progress and verification there
  once accepted.

## 10. Decisions required

0. **Required API field versus provider-owned maximum (blocking).** `max_tokens`
   bounds generated output for one response, including thinking; it is not a target
   length, input limit or SDDE execution budget. The API requires it even when the
   caller wants the provider's full capacity.

   **Provider-sourced option:** retrieve the exact selected model through
   `GET /v1/models/{model_id}`, validate its nullable integer `max_tokens`, and
   snapshot the provider-reported maximum for request encoding. The
   [Models API guidance](https://platform.claude.com/docs/en/models/overview#using-the-models-api)
   and [typed metadata schema](https://platform.claude.com/docs/en/api/php/models)
   document this source. No project/slot override, smaller local ceiling,
   budget-derived clamp or invented fallback is needed. A model can finish before
   the maximum. Standard synchronous limits must not be confused with the separate
   [Batch extended-output beta](https://platform.claude.com/docs/en/build-with-claude/batch-processing#extended-output-beta).

   This is a viable design option, not an accepted exception. The smallest authority
   amendment would allow an API-required field populated only from validated
   provider maximum metadata while continuing to prohibit engine-selected limits.
   It must name the changes to ADR 0011, invariant 32, acceptance criterion 31.12
   and request/replay contracts. Alternatively, retain current authority and defer
   direct Messages support. This review does not select either decision.

   If the metadata option is accepted, specify its narrow adapter/port, credential
   authorization, deadline, closed schema, selected-model identity check and
   per-invocation snapshot ownership. The read-only GET belongs in an explicitly
   approved preparation operation, never inside capability authorization or hidden
   inside the inference exchange. [ADR 0004](../design/decisions/0004-model-provider-bootstrap.md)
   requires a decision for a new conditional preparation concern; current inference
   and counting operations do not grant metadata discovery authority. Preserve
   binding-only preparation without network/credential I/O.

   Null, zero, invalid or unavailable metadata
   needs typed failure, never a hardcoded replacement. Discovery cannot register
   new models or capabilities. Distinguish metadata exchanges from inference sends
   in compatibility evidence. Persist the exact source/value needed to reconstruct
   a request; decide how replay handles a changed current provider maximum without
   silently altering captured bytes. No metadata lookup or implementation occurred
   in this review.
1. **Registered models.** Which Claude tuples to compile. Each needs its own entry
   and, before live use, its own compatibility probe. Haiku 5.5 is the fastest and
   cheapest; Opus 5.5 is the most capable of the three in §3.4 and cannot turn
   thinking off.
2. **Mixed providers per workflow.** Settled as a requirement by user direction on
   16 October 2026: configuration selects Claude or Bedrock per slot, and one
   workflow may use both (§2.1). The ADR must record this.
   - **2a. Response mode for Claude entries.** After step 0: native schema with the
     provider-owned capacity boundary in §5.7, or prompt-only (`json: false`).
     Prompt-only relies on the engine's validation and protocol correction instead
     of constrained decoding.
3. **Closed decoding against an evolving API.** New response fields reject until
   the decoder is updated. The API version permits additive output values, enum
   variants and changes in error conditions; it does not freeze a closed response
   schema. Define dated contract review, fixture refresh and offline regression
   procedures without an unknown-field escape hatch. Also decide which additional
   diagnostics are typed versus raw-capture-only (§5.1).
   [Versioning policy](https://platform.claude.com/docs/en/api/versioning).
4. **Refusal outcome.** Map `refusal` to the existing `content_filtered`, or add a
   distinct `refused` non-candidate stop that retains `stop_details.category`.
5. **Live-test cost policy.** [model_cost_policy.zig](../test/harness/model_cost_policy.zig)
   permits only Bedrock `openai.gpt-oss-20b-1:0` and rejects Claude tuples. Any live
   Anthropic probe or E2E run needs an explicit policy change naming the exact tuple
   and an approved generic compatibility path separate from frozen cohort checks.
   Manual diagnostic sends cannot bypass these requirements.
   Mixing a Claude slot into the [semantic-simplicity protocol](../test/calibration/semantic-simplicity/README.md)'s GPT-OSS-only evaluation would mix
   cohorts and is not permitted by that protocol.
6. **Billing and spend-cap errors.** Map 402 `billing_error` and the machine-typed
   spend-cap 429 to existing causes, or add a dedicated non-retryable cause.
   A user-set spend-limit 400 retains generic rejection unless a documented typed
   discriminator exists; message text cannot supply classification authority.
7. **Workflow token budget.** Claude output includes billed thinking tokens and a
   different tokenizer. The compiled 100,000-token workflow budget already stops full
   workflows on small features
   ([FIX04 F9](Z_FIX02.md#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures)).
   A Claude slot does not change that decision, but adds to it.
8. **Credential check timing in mixed workflows.** Today missing credentials fail
   when provider calls are authorized. Decide whether actual selected call paths
   need all their credentials before the first send, including the handling of
   inactive optional branches. Preserve no-provider and binding-only preparation
   without credential I/O; never require a key merely for an unused catalogue entry.
9. **Per-call deadline.** Keep the shared 60-second `timeout-ms`, raise it in the
   workflow definition for all providers, or introduce a typed per-binding deadline
   policy. Decide after step 0's latency measurements.
10. **Residency and retention.** Omitted `inference_geo` inherits the workspace
    default; inference geography and storage geography are distinct. Record the
    intended workspace settings and applicable retention requirements, including
    separately cached schemas, before production use. Do not infer Australian
    residency from the engine host or the Bedrock Sydney configuration. Adding an
    explicit geography control would require its own closed configuration decision.
    [Data residency](https://platform.claude.com/docs/en/manage-claude/data-residency),
    [API retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention).

## 11. Acceptance evidence

The connector is complete only when:

- decision 0 resolves R0 explicitly, step-0 results are recorded and decisions 2a
  and 9 are made; no API-required field is silently supplied under conflicting policy;
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
- for each registered tuple intended for live use, a separately approved single
  inference-send probe is `compatible`, with metadata exchanges reported separately;
- separately approved full production E2E cases establish the intended Claude-only
  and mixed-provider workflows, with required rubric assessment of actual published
  output under [§28.7](../design/contracts/28-testing.md). Report unfinished execution
  or evaluation as missing acceptance evidence.

Compatibility establishes request and response handling only. It does not establish
semantic quality, workflow completion or any FIX05 qualification.

## 12. Sources

External facts were rechecked on 18 October 2026. No credentialed metadata lookup,
inference call, compatibility probe or E2E run was performed:

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
- [Model metadata](https://platform.claude.com/docs/en/api/models/retrieve) and
  [typed ModelInfo](https://platform.claude.com/docs/en/api/php/models): nullable
  provider-published maximum, relevant to the unresolved §10.0 option.
- [Refusals](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback),
  [stop reasons](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)
  and [fast mode metadata](https://platform.claude.com/docs/en/build-with-claude/fast-mode):
  refusal billing/nullability, stop consistency and `usage.speed`.
- [Versioning](https://platform.claude.com/docs/en/api/versioning),
  [model IDs](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions),
  [data residency](https://platform.claude.com/docs/en/manage-claude/data-residency)
  and [retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention):
  API evolution, snapshot scope and deployment defaults.

Repository evidence: the current source and governing contracts linked throughout
this document. The earlier review cited request captures and `report.json` under
`zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/`; that
directory was absent during this review. Its schema counts remain explicitly
historical and unverified; its latency/token totals do not qualify the current
workflow. Refresh the schema inventory after ADR 0024's record-scheduling changes
and retain exact source revision, request/schema artifacts and measurement method.
