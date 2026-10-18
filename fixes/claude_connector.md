# Claude connector — direct Anthropic Messages API provider

**Prepared:** 16 October 2026, Australia/Melbourne. **Assessed and revised:**
18 October 2026, after code inspection and research against the live Anthropic
documentation (§12).

**Status:** **Proposal; not accepted and not implemented.** This document describes
the work needed to add a second production model provider that calls the
Anthropic Messages API directly. It changes provider architecture, so it needs an
accepted ADR defining the implementation scope before any code change. That ADR
must distinguish bounded diagnostic enablement from production qualification;
evidence-dependent decisions in §10 close at the gates in §8. It is not an active
backlog: [FIX05](FIX05.md) is the sole active fix record under the
[fix-record convention](README.md). Once accepted, its normative content moves into
an ADR and a feature document (§9), and implementation progress is recorded in FIX05.
It authorizes no live call, no E2E run and no production dependency. The governing
[design](../design/design.md) remains **Proposed design**.

**Selected configuration decision (18 October 2026):** by explicit user direction,
store `max_tokens` in each Anthropic model's `config` in `.sddproviders.json`.
This replaces the proposed runtime Models API lookup. The remaining connector
proposal is not accepted; this update changes neither engine code nor governing
contracts. Required contract amendments are tracked in §9 and §10.0.

**Shared-code requirement (18 October 2026):** the user requires common Bedrock and
Claude behavior to have one implementation. §§4–6 identify the shared owners and
the provider-specific projections; §§8 and 11 require Bedrock to migrate through
those owners before Claude is added. This review updates this document only.

**Repository revision inspected:** `c100912245abfedf54871aa5751fedf64091a359`,
with a clean worktree at the start of this final architectural review, including
the accepted 18 October amendment to ADR 0011. This review changes this proposal
only; it does not amend accepted authority or implement the connector.

## 0. Feasibility assessment

**Verdict: technically feasible as a second provider, but not implementation-ready
or production-qualified.** Common owners and closed protocol projections fit the
engine boundaries. The remaining work includes governing contract alignment,
complete-response accounting across terminal races, closed readback validation,
and a diagnostic path that can gather the still-missing schema/latency evidence.
These are concrete prerequisites, not evidence that the connector already works.
The Messages API requires `max_tokens`,
while
[ADR 0011](../design/decisions/0011-provider-owned-request-limits.md#no-output-token-allowance),
design invariant 32 and acceptance criterion 31.12 prohibit sending any output-token
allowance. The user's selected change places this required Anthropic request
parameter in the provider catalogue, under `providers[].models[].config.max_tokens`.
Slots do not regain `maxOutputTokens`. Record this narrow change in the governing
contracts before implementation (§9); no further storage-location decision is needed.

The configured value is captured with the catalogue and sent unchanged. It is a
catalogue-maintained request ceiling, not a value discovered from the provider at
runtime. Use the provider's documented model maximum when full output capacity is
wanted; the engine supplies no default, lookup, clamp or fallback (§2).

The remaining proposal still requires its other decisions. Shared lifecycle and
accounting mechanisms can be reused, but provider routing, persisted evidence and
some diagnostics need deliberate contract work (§§4–6). A closed provider API
decoder also requires maintenance even with a pinned API version (§10.3).

| ID | Severity | Finding | Evidence | Consequence |
| --- | --- | --- | --- | --- |
| R0 | **Contract alignment required** | The user selected per-model `config.max_tokens` in `.sddproviders.json`; ADR 0011 and related contracts still prohibit all output allowances. | User direction, 18 October 2026; ADR 0011 | Record the selected provider-configuration exception in governing contracts before implementation; keep slot controls rejected and preserve exact capture/replay (§10.0). |
| R1 | **Unmeasured** | Anthropic limits union parameters and optional parameters (§3.3). The previous review reported 32 `anyOf` nodes for records and 16 for extraction in historical captures that are no longer available locally. | Structured-outputs documentation; historical figures retained in §3.3 | Re-measure current complete and derived schemas. Node counts do not establish the provider's parameter count or grammar acceptance. Any live check needs the §8 approvals; no automatic fallback or unapproved local capacity gate. |
| R2 | **Unmeasured** | The Spec workflow's shared request subgraph sets a **60-second** total deadline; diagnostic replay instead uses **300 seconds**. Claude latency and first-use grammar compilation have not been measured here. | [spec.workflow.yaml](../design/workflows/spec.workflow.yaml); [request_replay.zig](../src/adapters/provider/request_replay.zig); [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig) | Replay success does not prove workflow deadline compatibility. Measure cold and repeated schemas and each intended effort/model. A deadline change needs explicit workflow/policy scope (§10.9); streaming does not extend total time. |
| R3 | High | `max_tokens` is a hard limit on thinking **plus** visible text, and thinking is billed as output. Opus 5.5 cannot disable thinking. | Effort and thinking documentation | Thinking tokens add to the compiled 100,000-token workflow budget, which historical small-feature runs exhausted ([FIX04 F9](Z_FIX02.md#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures)). Select explicit effort for comparable measurements and retain `usage.output_tokens_details.thinking_tokens`; the configuration control remains optional. |
| R4 | High | Sharing only HTTP would still duplicate authorized invocation, credential lifetime, capture, request projection, response assembly and replay inspection. These mechanisms currently sit in Bedrock-named modules. | [aws_bedrock.zig](../src/adapters/provider/aws_bedrock.zig); [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig); [request_replay.zig](../src/adapters/provider/request_replay.zig) | Extract the common owners in §5.1 and migrate Bedrock first. Claude supplies protocol projections; it does not copy the provider lifecycle. |
| R5 | Medium | Authorization currently accepts only Bedrock, and composition builds one provider. Snapshot validation, capability deposit/destruction and lease use are common mechanics. | [bedrock_authorization.zig](../src/adapters/provider/bedrock_authorization.zig); [model_provider_runtime.zig](../src/composition/model_provider_runtime.zig) | Use one shared authorization mechanism with provider-tagged material and exhaustive routing. Preserve distinct credential identities and the single runner lease table (§5.3, §10.8). |
| R6 | Medium | `count_tokens` returns an **estimate** that "might differ by a small amount" and can include system-added tokens. | Token-counting documentation | It must not be registered as the engine's exact token counter. The Spec workflow never counts tokens, so the first increment registers no counting capability (§3.7). |
| R7 | Medium | A 429 is not always retryable: the monthly spend-cap 429 has no `retry-after`, carries `error.details.error_code: "enforced_spend_limit_reached"`, and keeps failing. A user-set spend limit returns 400. Error types "will grow over time". | Errors and rate-limits documentation | The closed error decoder must accept `error.details`, classify the spend cap as non-retryable, and treat unknown types as `response_invalid` (§3.6). |
| R8 | High | `usage.speed` is nullable, and SDK representations disagree on whether several nullable response members may be omitted. Nested values have capability and accounting significance. | Messages API, focused documentation and official SDK types (§3.5) | Freeze a dated non-beta presence/nullability manifest and negative fixtures. Client defaults cannot authorize omitted wire fields; retain usage only after its validated trust boundary (§5.5). |
| R9 | Medium | Omitting `inference_geo` inherits the workspace default. Inference location and storage location are separate settings. | [Data residency](https://platform.claude.com/docs/en/manage-claude/data-residency) | The proposed `max_tokens` configuration does not pin residency. Record the intended workspace's defaults and retention requirements (§10.10). |
| R10 | Low | Asking for private step-by-step reasoning can trigger `reasoning_extraction`; a short evidence explanation or a field named `detail` alone does not establish that problem. | [Refusals](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback) | Keep typed non-candidate stops and measure actual refusal behavior. |
| R11 | High | A complete HTTP body can be retained after a timer/cancellation race, but current transport failure paths do not carry a validated receipt through to usage accounting. Sharing the existing code alone does not fulfill the proposal's retention promise. | [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig), [bedrock_transport.zig](../src/adapters/provider/bedrock_transport.zig), [bedrock_response.zig](../src/adapters/provider/bedrock_response.zig) | Specify and test a shared receipt/terminal-outcome contract (§5.6). Reconcile independently valid usage once while preserving cancellation/deadline failure; never infer usage from partial or invalid bytes. |
| R12 | High | Persisted descriptions deserialize a type named `ValidatedProviderConfig`; generic decoding alone will not prove a new numeric `max_tokens` value positive or consistent with its provider. | [model_request_description.zig](../src/domain/model_request_description.zig) `Description.decode` | Reuse canonical configuration semantics at every description/evidence readback before inspection, authorization or replay; add malformed persisted-value cases (§6). |
| R13 | Medium | Current compiled-registry validation enforces one implementation per provider but does not prevent different providers sharing an implementation ID. The proposed dispatch selects by that ID. | [llm_provider_contracts.zig](../src/domain/llm_provider_contracts.zig) `Registry.validate` | Require coherent provider/facts/schema/implementation identity and one closed protocol/authentication projection per ID before credentials are read (§5.2). |
| R14 | Medium | The former step 0 required live feasibility evidence before building the currently absent Anthropic diagnostic path. | [compatibility CLI](../test/harness/compatibility/cli.zig), [diagnostic_binding.zig](../test/harness/diagnostic_binding.zig) | Stage offline design, approved diagnostic enablement, then feasibility decisions (§8). Do not treat the existing Bedrock-only probe as usable for Claude. |
| R15 | Medium | Captured-call diagnostics permit explicit model/effort rebinding, unlike exact debugger replay; copying the source `max_tokens` would select the wrong model configuration. | [diagnostic_binding.zig](../test/harness/diagnostic_binding.zig) `rebind` | Rebinding creates a new request using the target catalogue config, preserving the source and reporting both bindings (§6). |

**Feasibility by area:**

| Area | Assessment |
| --- | --- |
| Configuration selection (§2) | Existing selection chain is reusable; routing and credential ownership need generalization. |
| Request encoding (§5.4) | Catalogue-to-wire mapping selected; governing contract amendments remain required (R0). Other fields map to existing content parts. |
| Native structured output (§3.3) | **Uncertain (R1).** Prompt-only is a proposed fixed mode, still subject to R0 and quality evidence. |
| Response, usage, stop and reasoning decoding (§5.5) | Core outcomes fit; additional metadata needs an explicit diagnostic owner or raw-capture-only treatment. |
| Usage under cancellation/deadline races (§5.6) | **Contract work required (R11).** Ordinary response capture already retains observations; complete-response terminal races need their own shared correction and evidence. |
| Errors (§3.6) | Feasible; needs one decision on spend-cap and billing causes. |
| Transport (§5.6) | Feasible; refactor rather than duplicate. |
| Latency within current deadlines | **Uncertain (R2).** |
| Mixed providers (§2.1) | Feasible; requires the routing and authorization changes in §4. |
| Diagnostic readiness (§6, §8) | **Not available today.** Extend the shared diagnostic path under accepted scope before requesting live feasibility evidence. |
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

The following is the **selected configuration shape for the proposal**, not a
working configuration today: Anthropic tuples and their configuration schema are
not implemented. The repository's provider catalogue is named `.sddproviders.json`;
no `providers.json` alias or new file is introduced by this documentation update.

```jsonc
// .sddproviders.json
{
  "providers": [
    {
      "provider": "anthropic",
      "models": [
        {
          "model": "claude-opus-5-5",
          "json": false,
          "config": { "max_tokens": 128000 }
        }
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
- Anthropic uses a new closed `anthropic` configuration schema containing required
  `max_tokens`. The field belongs to each model entry, because supported values
  depend on the model. Endpoints and credentials stay out of project data.
- `json` is fixed per catalogue entry, so every slot using that model shares one
  response mode. The example uses `json: false` (prompt-only) until R1 is resolved.
- `config.max_tokens` is a required positive integer representable by its typed
  wire value. Missing, null, zero, negative, fractional, string and overflowing
  values reject, as do duplicate or unknown fields. `128000` is an explicit example
  value for the illustrated model, never an engine default or a demonstrated safe
  non-streaming setting under the 60-second workflow deadline. Maintain the value
  against the selected model's documented API limits; the engine does not perform
  a metadata lookup or predict capacity. An API-unsupported value produces the
  provider's typed rejection, with no automatic adjustment.
- The API permits `max_tokens: 0` for cache population without generation. The
  positive-value rule here belongs to this inference operation's scope; cache-only
  requests are excluded. It is not a claim that the API's minimum is one.
  [Messages API](https://platform.claude.com/docs/en/api/messages/create).
- Every slot bound to the same provider/model entry uses that entry's value.
  Capture it once with the catalogue; corrections and retries retain it. A change
  takes effect on a fresh invocation, not through a mid-workflow catalogue reread.
- Only Anthropic model `config` accepts `max_tokens` in this increment. Reject it
  at slot, provider-root and generic model-entry level, and in Bedrock config.
  Slot-level `maxOutputTokens` remains rejected. Bedrock still omits
  `inferenceConfig.maxTokens`.
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

The documented ten-minute expectation check is an SDK safeguard, not a documented
direct-HTTP rejection rule. Anthropic advises against large non-streaming
`max_tokens` values because idle connections can fail. The 128K model maximum does
not establish feasibility within SDDE's deadline. Measure the selected settings;
do not add an inferred local limit or treat streaming as an automatic fallback.
[Long requests](https://platform.claude.com/docs/en/api/errors#long-requests).

### 3.2 Request fields

This illustrates native-schema mode (`json: true`) using §2's configured value.
The request's `max_tokens` is copied exactly from the selected model's validated
`config.max_tokens`;
it is not computed from the execution budget or a model metadata request.

```json
{
  "model": "claude-opus-5-5",
  "max_tokens": 128000,
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
  (`standard`, `priority`, `batch`), nullable `inference_geo`, and nullable `speed`
  (`standard`, `fast` or null). Deferring fast-mode requests does not remove ordinary
  standard-speed response metadata.
  [Speed metadata](https://platform.claude.com/docs/en/build-with-claude/fast-mode#checking-which-speed-was-used).
  Total input is
  `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`;
  `output_tokens` already includes thinking and is used once for token accounting.
  There is no total field.

The following closes the proposed nested-value policy for this tool-free,
non-beta request. It does not resolve whether each outer field may be omitted:

| Field | Accepted present value | Rejected value |
| --- | --- | --- |
| `container` | Null | Every non-null container, including `{}`; no container tool was requested. |
| `diagnostics` | Null, because the request omits diagnostics | Non-null objects, including `{}`; a requested-but-pending comparison is a different API state. |
| `usage.server_tool_use` | Null or exactly `web_fetch_requests: 0` and `web_search_requests: 0` | Positive counts, missing/unknown members, invalid numbers. |
| `usage.cache_creation` | Null or both nonnegative integer `ephemeral_1h_input_tokens` and `ephemeral_5m_input_tokens`, consistent with the parent counter | Empty/partial objects, unknown members, invalid or inconsistent counters. Never add the breakdown twice. |
| `usage.output_tokens_details` | Null or exactly integer `thinking_tokens` with `0 <= thinking_tokens <= output_tokens` | Empty/partial objects, unknown members or an inconsistent count. The approximate breakdown is not another charge. |

Sources: official [container](https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/src/anthropic/types/container.py),
[cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics),
[server-tool usage](https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/src/anthropic/types/server_tool_usage.py),
[cache creation](https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/src/anthropic/types/cache_creation.py),
and [thinking usage](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#pricing).

**Presence is still a contract-freeze gate.** The official
[TypeScript response types](https://raw.githubusercontent.com/anthropics/anthropic-sdk-typescript/main/src/resources/messages/messages.ts)
declare these outer fields required and nullable; the Python
[Message](https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/src/anthropic/types/message.py)
and [Usage](https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/src/anthropic/types/usage.py)
models default them to `None`. Client defaults do not prove wire omission valid.
Record the selected non-beta contract, pinned source revision and absent/null/value
fixtures before finalizing the decoder. Do not interpret arbitrary empty objects
or missing fields as null, or import SDK permissiveness into the closed parser.
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
APIs that this connector does not call. Retry classes stay derived from typed
failure facts by the shared owner (§5.5); the connector performs no retries itself,
and `retry-after` is retained only as diagnostic data.

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

The documented output-token rate limit counts actual generated output;
`max_tokens` does not reserve that many tokens against OTPM. A larger ceiling can
permit more actual work and longer latency, but is not itself a rate-limit charge.
This does not alter SDDE's separate actual-usage ledger or authorize reservations.
[Output rate accounting](https://platform.claude.com/docs/en/api/rate-limits#cache-aware-itpm).

## 4. Current Bedrock coupling and shared-code gaps

The provider port is neutral, but several shared types assume Bedrock. They must be
generalized before an Anthropic adapter can be added without parallel or
illegal-state fields.

| Location | Bedrock assumption | Required change |
| --- | --- | --- |
| [provider_dispatch.zig](../src/adapters/provider/provider_dispatch.zig) | `.port()` selects the single union member at construction | Use a closed per-call selector of codec/endpoint/credential identity inside shared adapters; do not dispatch to copied lifecycle implementations. |
| [aws_bedrock.zig](../src/adapters/provider/aws_bedrock.zig) | `Provider.exchange`, `rejectedBeforeSend`, `captureBody`, `count` and `invoke` mix common authorized exchange mechanics with Bedrock codecs | Extract one shared provider adapter for lease consumption, validation, call storage, capture and observation assembly. Remove the superseded Bedrock lifecycle implementation; do not create an Anthropic copy. |
| [model_provider_runtime.zig](../src/composition/model_provider_runtime.zig) | Builds one Bedrock provider, authorization adapter and credential for workflows requiring provider authorization | Construct the provider set required by the selected call paths; preserve no-provider and binding-only paths without credential I/O. |
| [bedrock_authorization.zig](../src/adapters/provider/bedrock_authorization.zig) | `prepare`, `secret` and `destroy` use a Bedrock-named key type and payload | Extract one in-memory API-key authorization mechanism with explicit provider identity; preserve foreign-capability rejection when sharing payload code. |
| [llm_provider_contracts.zig](../src/domain/llm_provider_contracts.zig) | `ProviderModelContract.bedrock_regions` and `bedrock_request_profile` | Replace with one tagged union of per-provider facts. Remove the Bedrock fields in the same change; do not add `anthropic_*` siblings. |
| [llm_provider_config_schema.zig](../src/domain/llm_provider_config_schema.zig), [llm_provider_config.zig](../src/domain/llm_provider_config.zig), [llm_provider_document.zig](../src/domain/llm_provider_document.zig) | Closed schemas/config values support only `empty_object` and `aws_bedrock` | Add a closed `anthropic` schema and validated config carrying per-model `max_tokens`; thread the captured value through binding, preparation, authorization and evidence. Reuse the existing catalogue decoder. |
| [llm_provider_registry.zig](../src/domain/llm_provider_registry.zig) | `Entry.bedrock_request_profile` | Carry the same tagged union. |
| [model_capabilities.zig](../src/domain/model_capabilities.zig) | `StructuredResponse.bedrock_json_schema` is the only native mode | Add a typed Anthropic mode, or a shared native mode selected by provider facts. Output-allowance capabilities were removed under ADR 0011 and must not be restored by this proposal. |
| [model_schema_projection.zig](../src/domain/model_schema_projection.zig) | Profiles `complete` and `bedrock` | Prove the reusable projection against both providers' grammar subsets. Complexity measurement does not authorize a local capacity check (§5.7). |
| [bedrock_request.zig](../src/adapters/provider/bedrock_request.zig) | `TextSchema`, `encode` and `writeInput` combine reusable text/schema preparation with Converse serialization | Share the typed text/schema view and ordering policy with both encoders and replay; keep API-specific JSON wrappers in their codecs. |
| [bedrock_response.zig](../src/adapters/provider/bedrock_response.zig) | `DecodeDiagnostic`, field readers, `Inference`, text accumulation, `decodeInference` and `transportFailure` mix common support with AWS wire parsing | Extract narrow decoding/assembly helpers and shared failure classification that preserves origin, stage and delivery distinctions. Keep each API's field, stop and error contract in its own decoder. |
| [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig), [bedrock_transport.zig](../src/adapters/provider/bedrock_transport.zig), [bedrock_http_head.zig](../src/adapters/provider/bedrock_http_head.zig) | Exchange core, endpoint, `Bearer` header and `x-amzn-*` headers in one file; transport request carries a `BedrockRegion` | Extract a shared exchange core and transport request with a closed endpoint union; keep endpoint and header projection per provider (§5.6). The head parser is already generic. |
| [bedrock_api_key.zig](../src/adapters/provider/bedrock_api_key.zig), [bedrock_api_key_source.zig](../src/adapters/system/bedrock_api_key_source.zig) | Common snapshot capture/zeroing and one exact environment-variable read are named for Bedrock | Share snapshot/material ownership and the production source mechanism; select the exact variable through a closed provider identity. Keep harness test-variable selection outside production. |
| [request_replay.zig](../src/adapters/provider/request_replay.zig), [request_debugger.zig](../src/composition/request_debugger.zig) | `prepare` and `inspect` mix Bedrock codec calls with common schema, field-policy, envelope and payload checks | Keep one replay adapter/inspection pipeline. Dispatch only provider projections and reuse the production codecs and shared transport. |
| [architecture_test.zig:89-112](../src/architecture_test.zig#L89-L112) | Import restrictions name only Bedrock files | Add equivalent restrictions for the Anthropic adapter files and the shared exchange core. |
| Harness invocation: [invoke.zig](../test/harness/e2e/invoke.zig), [E2E CLI](../test/harness/e2e/cli.zig), [environment.zig](../test/harness/environment.zig) | One generation key, a Bedrock credential snapshot/transport and a fixed generation/judge redaction pair | Inject typed selected-provider credentials; redact every selected secret across all exchanges, independently of judge selection. |
| Persisted evidence: [call_context.zig](../test/harness/e2e/call_context.zig), [trace.zig](../test/harness/e2e/trace.zig), [call/capture.zig](../test/harness/call/capture.zig) | `model-call-evidence/v1` requires a Bedrock region and has no provider field; trace and capture readers assume Bedrock | Version the changed closed shape deliberately; update all writers/readers together with provider/config identity. No fallback reader or migration that grants historical data current authority. |
| Diagnostics: [diagnostic_binding.zig](../test/harness/diagnostic_binding.zig), [call CLI](../test/harness/call/cli.zig), [compatibility CLI](../test/harness/compatibility/cli.zig), [inspection](../test/harness/compatibility/inspection.zig) | Bedrock request profiles, credential selection and replay | Route through the same typed provider contracts; retain exact request reconstruction and one-send bounds. |
| Harness policy: [frozen_binding.zig](../test/harness/frozen_binding.zig), [model_cost_policy.zig](../test/harness/model_cost_policy.zig) | Trace checks the frozen GPT-OSS evaluation binding; live cost policy separately permits only GPT-OSS | An explicitly approved generic compatibility path must not weaken the frozen evaluation cohort (§6, §10.5). |
| Packaging: [smoke.zig](../test/packaging/smoke.zig) | Provider bootstrap smoke covers Bedrock and region rejection | Add offline Claude-only/mixed bootstrap and debugger cases from a clean directory (§8). |

**Review conclusion:** the earlier proposal named separate `anthropic.zig`,
`anthropic_authorization.zig` and credential-source implementations without assigning
their common mechanics a single owner. HTTP extraction alone would not meet the
shared-code requirement. Replay inspection and the harness's direct mutation of
`provider.aws_bedrock.transport` also need common boundaries. The following design
replaces that copy-and-adapt path; shared code must not remain in a Bedrock module
that the Claude connector imports as a sibling.

## 5. Proposed design

### 5.1 Owners

Preserve [F0007's responsibility boundaries](../design/features/F0007-AWSBedrockProvider.md#responsibility-and-ownership),
while moving common mechanics out of provider-specific modules. The names below
are illustrative; the single-owner boundaries are requirements of this proposal.
Provider codecs/projections never import their sibling provider.

| Owner | Responsibility |
| --- | --- |
| `composition/provider_model_contracts.zig` | Compiled Anthropic tuples and capabilities; no client or credential. |
| `domain/llm_provider_contracts.zig` | Provider-fact union and validated Anthropic configuration containing a distinct typed `max_tokens` value. |
| `domain/llm_provider_config_schema.zig`, `domain/llm_provider_config.zig` | Canonical closed parsing and validation of per-model Anthropic `config.max_tokens`; no defaults or capacity prediction. |
| `domain/model_capabilities.zig` | Supported native response mode and controls, without retired output-allowance fields. |
| `adapters/provider/api_key_material.zig` (extracted) | One `Snapshot`/`Material` implementation for validation, owned copying and secure zeroing, reused by both API-key providers. |
| `adapters/system/provider_api_key_source.zig` (extracted) | One exact-variable read mechanism selected by closed production provider identity, after valid bindings and an actual provider-call capability need. |
| `adapters/provider/api_key_authorization.zig` (extracted) | One preloaded-material capability deposit/extraction/destruction mechanism, with explicit provider identity. No environment or network I/O. |
| `adapters/provider/model_provider.zig` (extracted) | One implementation of the provider port's authorized exchange: consume lease, invoke canonical checks, manage call storage/capability lifetime, capture, send once and return owned observations. No workflow accounting or retry authority. |
| `adapters/provider/model_text_request.zig` (extracted) | One pure typed text/schema view for role grouping, protocol/schema guidance and supported schema projection; used by production and replay for both providers. |
| `domain/model_schema_projection.zig` | Existing single schema traversal with closed syntax profiles; never a second schema source or capacity predictor. |
| `adapters/provider/bedrock_request.zig`, `anthropic_request.zig` | API-specific JSON encoding from the shared prepared view and validated provider facts/config. No copied ordering or guidance policy. |
| `adapters/provider/provider_response_support.zig` (extracted) | Common closed-field/scalar/path diagnostics using `strict_json`; API field sets and null rules remain codec-owned. |
| `adapters/provider/provider_response_assembly.zig` (extracted) | Common exact text/reasoning ownership and normalized observation construction, reusing existing domain usage/result types. No candidate admission or token charging. |
| `domain/provider_failure.zig` (extracted) | One pure retry-eligibility classifier from provider-neutral origin/stage, normalized cause and delivery facts. No HTTP types, status/header values, provider error enums, adapter imports or retry execution. |
| `adapters/provider/bedrock_response.zig`, `anthropic_response.zig` | Closed API envelopes, usage-counter interpretation, stop/error mappings and protocol-specific validation, producing the shared normalized result. |
| `adapters/provider/model_http_transport.zig`, `model_http_head.zig` (extracted) | One transport request/response/failure contract and the existing generic HTTP head reader. |
| `adapters/provider/model_http_exchange.zig` (extracted) | One HTTPS implementation for deadlines, cancellation, body retention and framing through `native_model_http.zig`; no retries. |
| `adapters/provider/bedrock_endpoint.zig`, `anthropic_endpoint.zig` | Pure provider-specific URL/path, authentication-header and retained-response-header projection. |
| `adapters/provider/provider_dispatch.zig` | Closed infrastructure selection of the above projections by trusted implementation identity; no string registry, service locator or duplicate operation execution. |
| `composition/model_provider_runtime.zig` | Construct the bounded selected provider/material set and wire common adapters to the existing runner lease/capture ports. |
| Existing runner/application owners | Sole lifecycle, lease table, invocation association, token accounting, stop logging and cleanup authority. Common infrastructure does not acquire these capabilities. |
| Existing replay service and adapter | One diagnostic preparation/inspection/send path using production codecs and HTTP; diagnostic authorization stays separate from workflow leases (§6). |
| Existing harness trace/call evidence | One transport decorator and closed evidence contract for both providers; no Anthropic-specific capture pipeline (§6). |

Shared infrastructure uses closed tagged provider facts and narrow existing ports.
It must not become a generic callback engine or capability bag. A common mechanism
accepts only the typed data it needs; provider-specific policy is represented by a
closed projection, not booleans or arbitrary URL/header/config maps.

Keep three layers distinct: the workflow provider adapter consumes a runner lease;
the HTTP exchange knows transport and bytes; diagnostic replay uses its own
authorization and shares codecs/HTTP without manufacturing a workflow lease.
Domain code stays free of HTTP, credentials and provider implementations, and the
workflow orchestrator stays capability-free.

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
    .config_schema = .anthropic,
    .provider_facts = .{ .anthropic = .{} },
    .supported_reasoning_efforts = &.{ "low", "medium", "high", "xhigh", "max" },
    .capabilities = .{
        .input_token_count = false,
        .inference = true,
        .exact_token_counter = .unavailable,
        .structured_response = .anthropic_json_schema, // provisional; qualify in step 7
        .temperature = false,
    },
},
```

Registry validation must reject an Anthropic fact on a non-`anthropic` schema, a
Bedrock fact without regions, and a fact whose provider differs from the entry's
provider. The compiled implementation ID must resolve to exactly one closed
provider/protocol/authentication projection consistent with those facts and schema.
Multiple models within that provider may share its ID; different provider families
cannot alias it. Reject unknown IDs and mismatches at registry/composition validation
before credential reads, not only when extracting a capability. Current
`Registry.validate` enforces the forward provider-to-implementation relationship
only; add the reverse coherence checks and negative fixtures for mixed dispatch.

The registry declares the supported configuration schema; the numeric
`max_tokens` value comes only from the selected catalogue entry, never a compiled
default. Which models to register is decision §10.1. Implementation still requires
the governing contract updates in R0.

### 5.3 Credentials

- **One material owner:** extract the current
  [bedrock_api_key.zig](../src/adapters/provider/bedrock_api_key.zig)
  `Snapshot.capture`/`deinit` and `Material` into the common module in §5.1. Both
  providers use its non-empty, non-whitespace printable-ASCII validation, owned
  copy, allocation-failure handling and secure zeroing. Do not add a second
  Anthropic snapshot or cleanup implementation.
- **Production source:** one system adapter selects exactly `ANTHROPIC_API_KEY`
  or `AWS_BEARER_TOKEN_BEDROCK` from trusted provider identity. Read each required
  variable once, after binding validation. No arbitrary environment-variable name,
  trimming, fallback chain or refresh is accepted. An unset Anthropic variable is
  `unavailable` even when a Bedrock credential exists.
- **Harness:** `TEST_ANTHROPIC_API_KEY`, following the existing `TEST_` convention in
  [environment.zig](../test/harness/environment.zig) and `.env.e2e.example`. Harness
  selection passes raw test material through the same pure snapshot validator;
  production source code never imports test-variable names or selection policy.
- **One authorization mechanism:** extract `prepare`, payload allocation/deposit,
  `secret` and `destroy` from `bedrock_authorization.zig`. Each capability retains
  typed provider/implementation identity, checked against the validated binding
  when consumed. A shared destructor pointer alone cannot distinguish providers.
  Foreign provider material, swapped capabilities and a mismatched endpoint must
  reject before send. Keep the single runner-owned lease table and consume once.
  Snapshots outlive all deposited capabilities; teardown destroys leases before
  zeroing snapshots. Authorization stays entirely in memory.
- **Redaction:** the key is a capture secret. It is sent only as the `x-api-key`
  header and must never appear in captured request bodies, descriptions, reports or
  logs. In mixed runs, every selected generation and judge secret must be redacted
  from every provider's captures, including source/context/schema text, escaped
  JSON, errors and reasoning. Request content can itself contain secrets; it is not
  inherently safe because authentication normally uses a header.
- **One redaction owner:** composition wires the complete selected-secret set with
  explicit lifetimes into the existing
  [model exchange capture](../src/application/model_exchange_capture.zig) and
  [redaction](../src/domain/model_log_redaction.zig) path. Provider codecs do not
  receive other providers' credentials or implement their own sanitizers. The
  endpoint projection receives only the consumed capability's matching credential.
- **Only the credentials a workflow needs are read** (§2.1).
- **Architecture evidence:** production must never import or read
  `TEST_ANTHROPIC_API_KEY`. Extend the existing test-variable isolation checks and
  prove authorization remains I/O-free and credentials are released on all paths.

### 5.4 Request encoder

| Engine input | Messages API field |
| --- | --- |
| `system` and `guidance` content parts, then the universal response-format guidance and schema guidance | `system`: text blocks, in order |
| `user` and `evidence` content parts | `messages[0]`: one `user` message of text blocks, in order; none is an error |
| Selected catalogue entry's validated `anthropic.max_tokens` configuration | Required `max_tokens`, copied unchanged into every inference request using that binding |
| Binding `reasoning_effort` | `output_config.effort`; omitted when absent |
| `native_schema` mode | `output_config.format = {type: "json_schema", schema: <projected object>}` |
| `prompt_only` mode | No `format`; the complete schema stays in `system` guidance |
| Temperature | Never sent; a non-null value rejects as `request_rejected` before send |

Extract `TextSchema` and the content-ordering policy of
[bedrock_request.zig](../src/adapters/provider/bedrock_request.zig) `writeInput`
into the shared typed `model_text_request` view. It retains relative order within
system/guidance parts, appends universal response guidance and the full schema
exactly once, and retains relative order within user/evidence parts. Require user
or evidence content; never invent, trim, merge or reorder text. The prepared view
borrows invocation-owned immutable data or explicitly owns its derived schema.

Production encoding, diagnostic reconstruction and Bedrock's supported counting
path all use that view and the existing schema-projection traversal. Converse
serializes its text-block shape and native schema string; Messages serializes its
text-block discriminator and native schema object. Those protocol differences stay
in their codecs. No second role loop, guidance injector, schema walker or replay
encoder is introduced. Prove Bedrock bytes unchanged, plus stable order, Unicode,
escaping, empty-content rejection and one-time guidance in both modes. Prompt
content and schema authority remain with existing workflow/domain owners.

### 5.5 Response decoder

Both codecs use `strict_json` for syntax, UTF-8 and duplicate-key rejection and the
common closed-field/scalar/path helpers extracted from `bedrock_response.zig`.
The shared helpers do not decide which API fields are allowed, required or
nullable. Each codec retains its own envelope, tool/citation/refusal rules,
status/error discriminators and usage-breakdown semantics. An Anthropic response
must not become acceptable to the Bedrock decoder merely because both eventually
produce the same domain types.

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
  Use one common owned text/reasoning accumulator and normalized-result assembler,
  extracted from the generic portions of `decodeMessage`, `Inference` and
  `decodeInference`. Codecs supply validated blocks and typed outcomes; they do
  not duplicate allocation cleanup or final `RawProviderModelResult` construction.
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
  Counter extraction and cache-breakdown checks remain API-specific; common
  checked arithmetic and final validation use the single `ProviderUsage` owner.
  When `thinking_tokens` is present, validate its relationship to `output_tokens`
  under §3.5 even if its reporting destination is raw-capture-only.
  Bedrock supplies its reported total for consistency checking; Anthropic derives
  a total from its documented components. Do not drop Bedrock's total check merely
  because Anthropic has no total field.
- Common assembly reuses `provider_reasoning`, `CompleteOwnedUtf8` and
  `RawProviderModelResult`; exact-call association and candidate eligibility remain
  in `provider_invocation_validation`. API error decoding returns a typed cause;
  one shared classifier derives retry eligibility from typed origin/stage, cause
  and delivery facts for authorization, transport and API failures. Preserve the
  existing distinction: an expired lease is a pre-send `timeout` with retry class
  `never`, while a transport timeout may be `policy_eligible`, even when no bytes
  were sent. Cause or delivery alone cannot determine eligibility. Retry execution
  remains exclusively with existing workflow policy. Codecs translate wire status,
  headers and error discriminators into provider-neutral facts; the domain classifier
  neither reads those wire fields nor imports transport/provider implementations.
- Preserve the trust boundary before usage retention. Current Bedrock decoding
  validates envelope/usage metadata before normalizing an observation; invalid
  candidate content after that boundary can retain trusted usage. Shared code must
  not salvage counters from an invalid or unassociated envelope. Any broader
  recovery rule would need shared-contract review and both providers' negative
  cases, not a Claude-specific catch-and-continue branch.
- Preserve and reconcile independently valid usage exactly once even when response
  capture, logging, cancellation or deadline failure blocks completion. The adapter
  retains the observation; the existing runner owns accounting. Both providers
  share the same total ledger, including advice. Test exact equality, overshoot and
  prohibition of subsequent calls across providers. Missing usage and invalid usage retain their
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

- The shared `model_provider` adapter owns the sequence now in
  `aws_bedrock.Provider.exchange`: consume one lease, run canonical invocation and
  binding checks, resolve matching typed material, encode, capture before send,
  perform one exchange, retain its observation and return an independently owned
  decoded result. It also owns call-arena/capability lifetime and pre-send failure
  capture. Neither codec may consume leases, write captures or initiate HTTP.
  Pre-send capture failure yields zero sends; post-response capture failure cannot
  discard the received observation needed by runner accounting.
- Extract the provider-neutral parts of `bedrock_http.zig` into one shared exchange:
  runtime cancellation and deadline checks, the concurrent network and timer tasks,
  body retention through `response_body_on_error`, the content-length send, redirect
  rejection, identity-only encoding and terminal framing checks.
- Each provider supplies a closed endpoint projection: URL, request headers and the
  response headers to retain. Bedrock keeps `Bearer` authorization and
  `x-amzn-errortype`/`x-amzn-requestid`; Anthropic sends `x-api-key` and
  `anthropic-version` and retains `request-id` and `retry-after`. Duplicate response
  headers of a retained name reject, as today.
- Move the transport types out of `bedrock_transport.zig` and the generic head
  reader out of `bedrock_http_head.zig`; use one implementation of each. A closed
  target/authentication variant prevents cross-provider key/endpoint pairing.
  The HTTP layer receives a typed target, not an arbitrary URL/header bag. Bedrock
  retains its percent-encoded model path and Converse/CountTokens operation paths;
  Anthropic's unsupported counting operation rejects before HTTP.
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

**Complete receipt versus terminal failure (R11).** The current
`response_body_on_error` retains bytes and a completeness flag only. A timer-winning
path can return failure after a complete response exists; `errorResponse` then
short-circuits decoding. Those bytes alone do not prove valid framing, headers,
status, envelope or request association. Mechanical extraction must not claim to
solve that gap.

Specify a shared typed contract that can preserve a complete receipt alongside a
terminal cancellation/deadline outcome. HTTP retains the completely framed raw
receipt and validated head facts; the selected codec validates the API envelope and
usage. The provider observation port exposes normalized provider-neutral evidence
alongside the terminal outcome. Existing runner validation proves association and
reconciles trusted usage once while still applying the terminal failure. Do not
add raw HTTP status, headers or wire envelopes to domain/application contracts to
solve this problem.
No stopped execution gains candidate admission, publication or retry authority.
Join existing tasks before inspecting retained state; do not wait beyond the
deadline for another response. Partial bodies, invalid heads/envelopes and
unassociated receipts remain unavailable for accounting, never salvaged or estimated.
Allocation failure remains explicit rather than a fabricated zero-usage result.

This is a shared-contract correction under the existing accounting invariant,
separate from the behavior-preserving extraction. Require deterministic tests for
network completion versus timer/cancellation, response-capture failure after a
complete receipt, and incomplete/invalid receipts for both providers. The design
must specify failure precedence and exact-once cleanup without weakening the
existing runner's cancellation, budget or logging rules.

Sharing this transport does not merge diagnostic replay with workflow execution.
Replay uses the same codecs, HTTP types and exchange implementation under its
existing diagnostic authorization and deadline. It does not create a runner lease,
charge a workflow ledger or continue a workflow.

### 5.7 Schema compatibility and provider-owned capacity

Reuse deterministic validation of supported schema syntax at the projection owner.
Do **not** turn historical `anyOf` counts or published grammar limits into new
engine-enforced capacity gates: ADR 0011 prohibits static-capacity prediction,
including renamed provider-contract limits. The earlier proposal's automatic
pre-send complexity check is withdrawn pending explicit authority.

Once R0's contract amendments are recorded, provider grammar rejections become typed `request_rejected`
outcomes. There is no per-request prompt-only fallback, schema weakening, truncation
or automatic splitting. A project may select prompt-only as its fixed catalogue
mode, with full native validation and separately measured quality. If an additional
pre-send grammar rule is desired, the ADR must distinguish syntax compatibility
from capacity prediction and obtain approval for any actual policy amendment.

## 6. Debugger, harness and evidence

- **Configuration readback is a trust boundary (R12):** the current
  [description decoder](../src/domain/model_request_description.zig) decodes directly
  into `ValidatedProviderConfig`. The type name is not validation of persisted
  bytes. Extract/reuse one pure provider-configuration semantic validator for the
  catalogue, versioned descriptions and call evidence. Every reader validates the
  positive `max_tokens` and provider/config discriminator before typed inspection,
  reconstruction or authorization. Current registry/allowlist authorization remains
  a separate prerequisite for request reconstruction and send; read-only historical
  display neither reauthorizes a call nor substitutes current catalogue values into
  its captured configuration. Do not add separate debugger or harness rules.
  Test missing, zero, null, negative, fractional, string,
  overflow, duplicate/unknown members and wrong-provider configurations at readback,
  as well as a valid value and exact unchanged round trips.
- **One replay implementation:** retain
  [application/request_replay.zig](../src/application/request_replay.zig) as the
  owner of immutable parents, exact-byte checks, persistence order and the one-send
  rule. Generalize the existing provider replay adapter rather than adding
  `anthropic_replay.zig`. Its preparation uses the shared text/schema view and
  selected production encoder. After production envelope decoding, one common
  inspection path runs the existing model-envelope, text-composition, exact-scope
  and complete payload-schema validators. Retain precise diagnostic paths without
  copying those validators into either codec or harness.
- **Capture:** reuse the model exchange capture port and redact all selected
  secrets in requests and responses. Thinking signatures remain opaque diagnostic
  data. Do not claim raw source/context data is secret-free.
- **Inspection and replay** ([ADR 0019](../design/decisions/0019-single-request-debugger.md)):
  the current description is `model-request-debug/v7`, without an allowance.
  The new Anthropic provider-config shape must retain the exact captured
  `max_tokens` value in prepared requests, descriptions and call evidence; update
  the closed version contract and all producers/readers together. Keep the value
  in provider configuration, without adding a duplicate slot control.
  Reconstruct canonical bytes before send, preserve provider/model/settings and
  current registry authorization, persist the request before dispatch and the
  response before completion. Exactly one physical inference send occurs, with no
  workflow continuation. Replay retains the captured value and rejects a changed
  current configuration when it no longer authorizes that request; it never
  rewrites the request using today's catalogue or a fetched maximum. Historical
  captures remain historical; no fallback readers or automatic upgrade grant
  current authority.
  Tests cover exact and modified replay, changed targets/settings/configured
  `max_tokens`, stale bindings,
  incomplete/redacted captures, non-candidate inspection, secrets in modified input
  and pre/post-send persistence failures, alongside existing Bedrock cases.
- **Explicit diagnostic rebinding is a new request:**
  [diagnostic_binding.rebind](../test/harness/diagnostic_binding.zig) and the
  [captured-call CLI](../test/harness/call/cli.zig) already permit explicit model/effort
  selection within the captured provider. This is distinct from exact/modified
  debugger replay. Keep the source capture immutable; validate the target catalogue
  entry and use its captured `config.max_tokens`, never the source model's value.
  Record original and effective provider/model/config/effort separately and apply
  the same one-send and cost-policy gates. Preserve the CLI's same-provider rule;
  a `--model` string cannot infer a provider or authorize cross-provider rebinding.
  Test two Anthropic models with different values, invalid target config, stale
  source evidence and attempted provider substitution.
- **Compatibility probe:** current trace validation delegates to
  [frozen_binding.zig](../test/harness/frozen_binding.zig), which enforces the
  semantic-simplicity GPT-OSS cohort. The old `validateProbeWire` and
  `validateProbeDescription` names are no longer current. A generic compatibility
  binding contract must be separately approved and kept distinct from the frozen
  cohort. Adding a model to cost policy alone will not make the probe accept it.
  Keep the single inference-send bound and exact settings attribution.
- **Later-request feasibility preparation:** the first-request compatibility probe
  and capture-dependent replay cannot alone supply generation, repair and advice
  samples before a successful Claude run. The approved diagnostic increment must
  allow explicit offline preparation/selection of those requests using the existing
  canonical preparation and validation owners. Record current content/schema,
  field-policy, exact-scope and selected-binding provenance; label fixture-generated
  inputs as diagnostic samples. They are neither historical live captures nor E2E
  evidence. Do not require prior successful Claude E2E, invent earlier calls or use
  unapproved cross-provider rebinding. Each selected sample still has one authorized
  send and the existing capture/inspection path; no parallel diagnostic engine.
- **One harness interception point:** replace the direct mutation of
  `provider.aws_bedrock.transport` in `Trace.prepare` with a shared transport
  decorator wired by composition. Both providers pass through the same physical
  send counter, receipt/capture association, failure retention and one-send gate.
  Extend the existing call-context decoder and captured-call selector with typed
  provider facts; do not create separate Claude trace, evidence or report pipelines.
  Shared fake-HTTP fixtures parameterize provider target/header projections instead
  of duplicating the Bedrock HTTP fixture and lifecycle assertions.
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
  The existing [Bedrock harness adapter](../test/harness/bedrock.zig) already uses
  production codecs/transport and must migrate to their shared owners too. Do not
  copy production wire logic into a new harness adapter. Consolidating the separate
  existing OpenAI judge HTTP stack is additional scope, not a prerequisite here.

## 7. Invariants and rejected alternatives

| Alternative | Decision | Reason |
| --- | --- | --- |
| Server-side refusal fallback (`fallbacks`) | Rejected | It reruns a refused request on another model inside the same call. Output would be attributed to a model the slot did not select, violating the no-substitution rule ([§12.3.1](../design/contracts/12-model-boundary.md#1231-bedrock-converse)). A refusal is a typed non-candidate stop. |
| Automatic prompt-only fallback when a schema is too complex | Rejected | A per-request mode switch is a hidden fallback. Response mode stays fixed per catalogue entry; an oversized schema fails typed (§5.7). |
| Restore slot `maxOutputTokens` or silently invent an adapter value | Rejected | The selected source is Anthropic model `config.max_tokens` in `.sddproviders.json`. No slot override, implicit default, budget-derived clamp or hardcoded fallback applies (§10.0). |
| Runtime Models API lookup for `max_tokens` | Not selected | The provider catalogue supplies the required value. No extra metadata operation, credentialed discovery or automatic catalogue update is part of this design. |
| Registering `count_tokens` as the exact counter | Rejected | The API documents it as an estimate (§3.7). |
| Model-name branching (`claude-*` prefix rules) | Rejected | Behavior comes only from compiled tuples and provider facts. |
| Credential chain (OAuth, profiles, `ANTHROPIC_AUTH_TOKEN`) | Rejected for this increment | One exact variable keeps credential authority explicit and testable. |
| Endpoint override (`base_url`) | Rejected | Endpoints are compiled constants; configuration would make endpoints project data. |
| Lenient decoding of unknown fields | Rejected by default | Closed parsing is required for external data. Decision §10.3 records the maintenance cost. |
| A separate Anthropic HTTP stack | Rejected | Duplicates the transport policy in `bedrock_http.zig` (§5.6). |
| Copy `aws_bedrock.zig`, authorization, key storage or replay for Claude | Rejected | Shared HTTP alone does not centralize lease use, capture, cleanup, schema guidance or inspection. Use the common owners in §5.1. |
| Claude imports Bedrock helpers; old helpers remain behind aliases | Rejected | Common policy moves to provider-neutral owners and all consumers migrate. Remove superseded implementations and compatibility wrappers together. |
| One permissive response decoder for both APIs | Rejected | Share parsing/assembly mechanisms; preserve each API's closed envelope, nullable fields, usage interpretation and stop/error tables. |
| Callback/plugin registry for provider differences | Rejected | Trusted closed dispatch and narrow typed projections suffice. No service locator or generic capability bag is introduced. |
| Streaming to avoid the 60-second deadline | Rejected as a fix for R2 | The deadline bounds total exchange time; streaming changes delivery, not duration. It remains a later option for outputs that exceed non-streaming limits. |
| Prompt caching | Deferred | May reduce currency cost and latency. Cached input still counts fully in ADR 0011's inclusive token ledger, so it does not solve workflow token exhaustion. It changes request bytes and needs separate measurement. |
| Claude on Bedrock | Out of scope | Support depends on exact compiled tuple and API compatibility; do not infer that all current Claude models work through the existing Converse adapter. |

## 8. Implementation sequence

This is a conditional future sequence, not authorization to implement or execute
it. Record the selected R0 change in governing contracts first. An accepted ADR
must authorize the bounded shared-contract and diagnostic increment before code
changes; production qualification remains pending R1/R2 evidence. Today's
Bedrock-only probe cannot collect that evidence for Claude. Build and verify the
common diagnostic path before approving any live feasibility experiment.
Each stage uses repository build steps. Separate mechanical extraction from the
R11 contract correction and preserve all unrelated Bedrock behavior. No checks in
this sequence ran during this document review.

0. **Authority and offline feasibility.** Record the selected catalogue-owned `max_tokens`
   decision (§10.0) and its contract amendments. Decide the exact permitted models,
   diagnostic scope, error/refusal normalization, credential timing and diagnostic
   metadata treatment. Resolve the response-field presence manifest (§3.5) against
   pinned official sources with accepted/rejected fixtures. Inventory current
   complete/derived schemas offline, including extraction,
   generation, repair and advice. Record source revision and reproducible schema
   artifacts. Identify provisional response modes/settings for explicit diagnostic
   cases without claiming compatibility or changing the production deadline.
   The accepted scope must permit steps 1–6 while leaving response-mode/deadline
   qualification to step 7. If authority cannot make that distinction, stop before
   implementation rather than requiring an unavailable probe or bypassing policy.
1. **Common authorized provider boundary, Bedrock first.** Generalize provider facts
   and closed selection. Extract the shared key material/source, preloaded
   authorization and authorized provider adapter from the Bedrock implementation.
   Route production Bedrock through them, keeping the existing runner lease table,
   capture ports and accounting owners. Remove the replaced lifecycle, snapshot and
   authorization implementations in the same change; do not leave compatibility
   wrappers. Preserve binding-only preparation and exact credential-read timing.
   Tests: existing Bedrock conformance, request/lease association, expired/reused
   capabilities, zero sends after pre-send capture failure, response observation
   retained after capture failure, and cleanup on cancellation/allocation failure.
   Retarget architecture checks to the new owners without dropping their rules.
   Verify: `zig build test-provider-conformance test-model-request-preparation test-model-request-workflow test-architecture`.
2. **Common wire support and transport, Bedrock first.** Extract the shared
   text/schema view, response support/assembly, failure classification, transport
   types, head reader and HTTP exchange. Keep Converse encoding/decoding and the
   Bedrock endpoint projection as protocol-specific modules. Migrate production,
   replay and the Bedrock harness adapter to these owners; remove old helper bodies.
   Tests: unchanged Bedrock request bytes and response behavior; shared content and
   ownership cases; existing HTTP/framing/deadline tests; exact replay reconstruction
   and inspection. Generalize fixtures, retaining assertions rather than creating
   copied Claude suites. No new provider is needed to prove this extraction.
   In a separately reviewable contract change, implement R11's complete-receipt and
   terminal-outcome propagation through the existing accounting owner. Prove both
   race orderings, terminal failure retention, exact-once usage and cleanup, and
   rejection of partial/invalid receipts before adding Claude. Do not describe this
   correction as behavior-preserving extraction.
   Verify: existing provider conformance, HTTP/transport and debugger suites through
   `build.zig`, plus `zig build test-architecture`.
3. **Anthropic configuration and protocol projections.** Add the closed Anthropic
   config with required typed `max_tokens`, and its request/response/endpoint
   projections under the recorded R0 decision. Use the common owners from steps 1–2;
   do not add a second provider lifecycle, authorization implementation, snapshot,
   HTTP client, schema traversal or inspection pipeline.
   Tests: exact request bytes for both response modes,
   with and without effort; every stop reason; every usage field including nulls and
   `thinking_tokens` and `speed`; thinking and redacted blocks; unexpected citations
   and tool blocks rejected; unknown fields; every error row in §3.6 including spend-cap
   `details`; mismatched status and type; temperature rejected before send; complete
   native validation after projection. Add wrong-model/envelope fixtures, empty
   refusal, null explanations, inconsistent stop metadata, exact enum casing,
   duplicate fields, invalid/missing/overflowing usage and no double-counted caches
   or thinking. Exercise stop warnings and valid usage retained despite later errors.
   Test that two registered Anthropic tuples can retain different configured
   values, slots sharing one tuple use the same value, and every request/correction
   encodes its captured value unchanged. Cover immutable catalogue snapshots,
   rejection before credentials/send for malformed config, no default or clamp,
   typed provider rejection of unsupported values and stale-config replay.
   Reject retired slot controls and `max_tokens` at the wrong catalogue/slot level
   or in Bedrock config. Cover missing, null, zero, negative, fractional, string,
   overflowing, unknown and duplicate configuration values, including persisted
   description/evidence readback through the same semantic validator. Check the
   provider/facts/schema/implementation relation before credential I/O. Run the shared
   conformance matrix (§11.1) through both real protocol projections.
   Verify: `zig build test-model-request-preparation test-provider-invocation-validation`
   plus the new codec suites registered in `build.zig`.
4. **Mixed-provider composition.** Wire Anthropic's closed credential selection and
   protocol projections into the same provider/authorization/transport owners as
   Bedrock. Tests: offline
   integration of a complete workflow with a fake Anthropic transport in an unrelated
   domain; a mixed-provider workflow; credential absence and invalid key; redaction
   of the key from every capture; transport failure with partial body; deadline
   expiry; exact-once mixed usage and budget exhaustion during required work and
   advice; no-provider, binding-only, unused-catalogue and optional-branch cases;
   cross-provider key/capability/endpoint substitution; retries retaining their
   binding; all selected secrets redacted across providers. Verify: `zig build test-integration`.
5. **Debugger and harness.** Add Anthropic to the shared replay/inspection and trace
   decorator; test that both providers use the same paths. Generalize the
   compatibility binding contract without weakening frozen cohort checks; evidence
   versioning, test credential handling and launcher tests (§6).
   Prove exact replay retains source configuration while explicit same-provider
   diagnostic rebinding records and uses the target configuration. The resulting
   diagnostic executable must prepare and inspect both providers offline and
   enforce the approved tuple/settings/send policy before any live authorization.
   Include explicit offline preparation/selection of later generation, repair and
   advice samples with the provenance in §6, so step 7 does not depend on a prior
   successful Claude E2E run or fabricated historical captures.
   Verify: `zig build test-provider-compatibility test-provider-compatibility-launcher smoke-provider-compatibility`.
6. **Full verification and packaging.** `zig build verify --summary all`, including
   clean-directory native packaging smoke. Add offline Claude-only and mixed
   bootstrap, unused provider entries, missing selected credential, unknown
   config/control rejection and debugger startup/readback. Run without the source
   tree, compiler, development assets or live network. Review imports and the whole
   diff for duplicate helpers and bypasses under §11.1. No SDK or new runtime assets
   are expected.
7. **Live feasibility and compatibility (separately approved).** Only after steps
   0–6, the cost-policy decision and explicit approval naming tuple, settings,
   finite sends and cost authorization, collect R1/R2 evidence using the now-built
   shared diagnostic path. Manual HTTP requests are not an escape from policy.
   Measure current representative schemas/prompts, cold/repeated latency,
   output/thinking usage and typed rejections; retain exact request/schema artifacts,
   source revision and hashes in FIX05. A first-request probe cannot qualify later
   generation, repair or advice schemas: select those explicitly through the
   approved single-request diagnostic path, recording their preparation provenance.
   Make response-mode (§10.2a) and deadline (§10.9) decisions from these results.
   Any resulting contract/code change needs its applicable offline verification
   before qualification. Failure to meet the accepted deadline or schema contract
   blocks the selected mode; it cannot trigger fallback, a clamp or weaker validation.

   Each registered tuple also needs its one-inference-send compatibility probe with
   exact selected catalogue `max_tokens`:
   `zig build provider-compatibility -- --case <approved-case> --live`. A compatible
   result qualifies only the observed request shape and settings. Neither this probe
   nor the preceding diagnostics establishes full-workflow or quality qualification.
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
  decision, the selected catalogue-owned `max_tokens` contract, schema-capacity
  boundary, non-streaming scope, refusal and spend-cap handling, closed decoding,
  the shared HTTP exchange and the rejected alternatives in §7. Separate permission
  to build/test the bounded diagnostic increment from permission for live calls and
  evidence that the connector is production-qualified.
- **Feature document `design/features/F0009-AnthropicProvider.md`:** responsibility,
  configuration, credentials, request and schema projection, response and
  accounting, acceptance evidence, structured like
  [F0007](../design/features/F0007-AWSBedrockProvider.md). F0009 is currently unused.
- **Contract amendments:** a §12.3.2 Anthropic section beside
  [§12.3.1](../design/contracts/12-model-boundary.md#1231-bedrock-converse);
  [§9 configuration](../design/contracts/09-configuration.md) for the provider ID,
  closed Anthropic configuration with required `config.max_tokens`, keeping retired
  slot controls rejected; the R0 amendment to ADR 0011, invariant 32 and acceptance
  criterion 31.12 that records this selected provider-configuration exception;
  debugger/evidence schemas and their producers/readers; updates to
  [F0006](../design/features/F0006-LLMProviderInterface.md),
  [F0007](../design/features/F0007-AWSBedrockProvider.md) (shared provider,
  authorization, credential, codec-support and transport owners) and
  [F0008](../design/features/F0008-LLMProviderConfigService.md) where they describe
  a single provider; the shared complete-receipt/terminal-outcome propagation needed
  to meet existing accounting authority (R11); and the workflow definition if the
  deadline changes. Include persisted configuration revalidation and diagnostic
  rebinding semantics, rather than documenting only catalogue parsing.
- **Harness documentation:** credential and launcher rules in
  [e2e.md](../design/harness/e2e.md) and `.env.e2e.example`.
- **FIX05:** record offline inventory, implementation progress, step-7 feasibility
  evidence and verification there once accepted.

## 10. Selected decisions and remaining decisions

0. **Catalogue-owned `max_tokens` — selected by user direction, 18 October 2026.** `max_tokens`
   bounds generated output for one response, including thinking; it is not a target
   length, input limit or SDDE execution budget. The API requires it even when the
   caller wants the provider's full capacity.

   Store it at `providers[].models[].config.max_tokens` in `.sddproviders.json`
   for each Anthropic model (§2). The catalogue is the sole runtime source; it is
   captured once per invocation and parsed into the closed Anthropic configuration.
   All slots selecting that entry share its value. Copy it unchanged into the
   Messages body and preserve it through authorization, retries, capture and replay.
   Missing or malformed configuration fails before provider authorization/send.
   There is no slot override, implicit default, runtime metadata lookup, budget
   clamp or fallback. Bedrock retains its existing request behavior.

   This is explicitly configured provider request data. To use the model's full
   output capacity, maintain the catalogue value at the provider's documented
   maximum for the selected synchronous API mode. The engine does not verify that
   relationship through live discovery or impose another static capacity gate;
   unsupported values receive typed provider rejection. A change requires a fresh
   invocation, and replay cannot substitute a new value into historical bytes.

   The location decision is settled. Before implementation, record its narrow
   exception in ADR 0011, invariant 32, acceptance criterion 31.12, provider-config
   contracts and versioned request/evidence/replay contracts (§9). Slot-level
   `maxOutputTokens`, local byte/token capacity gates, hidden defaults and automatic
   clamping remain excluded. This documentation-only update does not perform those
   amendments or implement the connector.
1. **Registered models.** Which Claude tuples to compile. Each needs its own entry
   and, before live use, its own compatibility probe. Haiku 5.5 is the fastest and
   cheapest; Opus 5.5 is the most capable of the three in §3.4 and cannot turn
   thinking off.
2. **Mixed providers per workflow.** Settled as a requirement by user direction on
   16 October 2026: configuration selects Claude or Bedrock per slot, and one
   workflow may use both (§2.1). The ADR must record this.
   - **2a. Response mode for Claude entries.** Qualify after step 7: native schema with the
     provider-owned capacity boundary in §5.7, or prompt-only (`json: false`).
     Prompt-only relies on the engine's validation and protocol correction instead
     of constrained decoding.
3. **Closed decoding against an evolving API.** New response fields reject until
   the decoder is updated. The API version permits additive output values, enum
   variants and changes in error conditions; it does not freeze a closed response
   schema. Define dated contract review, fixture refresh and offline regression
   procedures without an unknown-field escape hatch. Also decide which additional
   diagnostics are typed versus raw-capture-only (§5.1). Resolve the SDK
   required-nullable versus defaulted-optional discrepancy in §3.5 through an
   explicit pinned wire manifest; neither client convenience defaults nor one
   successful sample establishes all permitted absence/null cases.
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
   policy. Decide after step 7's latency measurements; the existing 60-second
   production deadline stays in force until an explicit amendment is accepted.
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

- the selected decision 0 is recorded in governing contracts, the offline inventory
  and step-7 feasibility results are recorded, and decisions 2a and 9 are made;
- closed Anthropic catalogue configuration requires `max_tokens`, and accepted and
  rejected fixtures prove exact propagation through preparation, authorization,
  wire encoding, retries, evidence and replay without slot overrides or discovery;
- the ADR, feature document and contract amendments are accepted;
- the dated non-beta wire manifest resolves required/optional/null distinctions,
  and accepted/rejected fixtures cover its nested metadata and thinking breakdown;
- R11's complete-response race tests prove usage reconciliation without discarding
  terminal failures; partial/invalid receipts never become accounting evidence;
- registry implementation identity, persisted configuration validation and explicit
  diagnostic rebinding have the negative cases in §§5.2 and 6;
- registry, capability, codec, schema-projection, transport, credential, redaction,
  routing, authorization, debugger and harness tests exist with accepted and
  rejected cases at their owning boundaries;
- both providers use the shared owners in §5.1; the cross-provider conformance and
  structural ownership checks in §11.1 pass;
- Bedrock conformance and offline integration pass; request bytes and unrelated
  behavior remain unchanged, with R11's shared correction explicitly tested;
- offline integration passes for Bedrock-only, Claude-only and mixed slot
  configurations, with no cross-provider fallback;
- `zig build verify --summary all` passes, including native packaging smoke;
- superseded Bedrock-only fields and extracted lifecycle, authorization, credential,
  request-support, response-support, HTTP and replay helper implementations are
  removed from their old locations; no aliases or parallel paths remain;
- for each registered tuple intended for live use, a separately approved single
  inference-send probe is `compatible` with its exact catalogue configuration;
- separately approved full production E2E cases establish the intended Claude-only
  and mixed-provider workflows, with required rubric assessment of actual published
  output under [§28.7](../design/contracts/28-testing.md). Report unfinished execution
  or evaluation as missing acceptance evidence.

Compatibility establishes request and response handling only. It does not establish
semantic quality, workflow completion or any FIX05 qualification.

### 11.1 Evidence that common code is actually shared

Run common scenarios through the production shared adapters and both real protocol
projections, with fake narrow transport/clock/capture ports. Two copied suites or
two unrelated fake provider implementations do not establish common ownership.
Parameterize the existing conformance fixtures by typed provider cases; keep
wire-specific accepted/rejected fixtures alongside their individual codecs.

| Shared boundary | Required evidence |
| --- | --- |
| Registry and persisted configuration | Coherent provider/facts/schema/implementation identity before credential reads. Catalogue and description/evidence readback share semantic validation; malformed numeric values and cross-provider configs cannot acquire validated authority. |
| Credential material and authorization | One snapshot/deposit/cleanup implementation; invalid/missing keys, allocation failure, expired/reused lease and foreign provider capability reject. The common payload's provider tag prevents swapping keys even though both use the same destructor. |
| Authorized exchange | One lease consumption and at most one HTTP exchange per invocation; pre-send capture rejection sends nothing; post-response capture rejection preserves the observation for existing accounting. Cancellation and partial/error paths release call storage exactly once. |
| Text/schema preparation | Both modes preserve mixed content order, Unicode/escaping and guidance exactly once. Empty user/evidence rejects. Production, supported Bedrock counting and replay consume the same prepared view; extracted Bedrock wire bytes remain unchanged. |
| Schema projection and decoding | One schema traversal and `strict_json` owner. Each codec rejects the other API's envelope and API-exclusive fields or variants; shared spellings remain accepted where independently permitted by that API's contract. Unsupported nulls, unknown/duplicate fields, numeric coercion and overflow reject without relaxing either wire contract. |
| Response ownership and normalization | Exact text joins add no characters; whitespace-only/missing final text and reasoning-only responses cannot become candidates. Text/reasoning allocation failures and transfers clean up once. Candidate rejection/stops retain usage only after its trusted envelope boundary. |
| Usage and failure policy | Provider-specific counters normalize through the common checked usage owner; Bedrock reported totals remain checked. One classifier preserves failure origin/stage, cause and delivery distinctions, including expired-lease versus transport timeouts. Mixed calls share the runner ledger, equality/overshoot rules and stop warnings; no second charge or automatic retry appears. |
| HTTP transport | The same exchange/head reader handles both endpoint projections: duplicate retained headers, framing/truncation, identity encoding, redirects, timer/network races, cancellation and partial bodies. Wrong-provider authentication/target pairing rejects. Test executables cannot connect through either path. |
| Complete receipt and terminal outcome | Both race orderings preserve independently validated usage exactly once while cancellation/deadline/logging failure stays blocking. Partial bodies, invalid headers/envelopes and foreign receipts remain unusable; cleanup occurs exactly once. Only normalized evidence crosses the provider port. |
| Replay and inspection | Production-equivalent request reconstruction for both providers/modes; shared native inspection. Changed provider/configuration including `max_tokens`, incomplete captures and persistence failures reject correctly. No workflow lease or continuation is created. |
| Explicit diagnostic rebinding | Same-provider model selection creates a separately authorized request using the target catalogue's `max_tokens`; source captures stay immutable and original/effective bindings are reported. No inferred provider switch or source-limit substitution. |
| Harness capture and redaction | Interleaved Bedrock/Claude calls pass through one decorator and one evidence decoder; the one-send gate and receipt identity hold for either provider. Every selected secret is removed from every provider's captured content, errors and reasoning through the existing redactor. |

Architecture/import checks must enforce the structural evidence as well as behavior:

- Provider request/response/endpoint modules contain only their wire projection and
  closed protocol validation. They cannot import sibling provider modules, consume
  leases, acquire credentials/read credential sources, capture/log exchanges or
  open network connections. An endpoint projection may format only the explicitly
  supplied matching credential into its fixed authentication header.
- Both paths use the common authorized adapter and shared HTTP implementation;
  `native_model_http` remains the sole native connection boundary. Replay shares
  the lower layers under its separate diagnostic authority, not a second HTTP stack.
- Invocation association, complete-candidate admission, lifecycle, usage charging,
  stop logging, retry transitions and publication remain with their existing
  domain/application owners. No new common adapter takes over those policies.
- The common domain failure classifier accepts only neutral typed facts. HTTP
  statuses/headers, wire error strings and adapter dependencies remain outside it.
- Production, debugger and Bedrock harness consumers stop importing the extracted
  Bedrock-named helpers. Move/retarget the corresponding architecture assertions;
  do not delete a rule simply because its old filename disappears.
- Review the complete diff for duplicated role grouping, guidance injection,
  schema traversal, field-reader helpers, failure classification, secure cleanup,
  capture handling and replay validators. Shared code has one cohesive owner;
  equivalent code under new names or forwarding compatibility wrappers is not an
  acceptable completed extraction.

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
  `request-id`, request size limits and long-request guidance; SDK safeguards are
  distinguished from direct-HTTP requirements.
- [Rate limits](https://platform.claude.com/docs/en/api/rate-limits): tier limits,
  spend caps, the spend-cap 429, response headers and actual-output OTPM accounting.
- Official SDK response types and cache/thinking diagnostics linked in §3.5:
  nullable `speed`, nested value shapes and the unresolved wire-presence distinction.
  These mutable sources need pinned revisions at contract freeze; they are evidence,
  not engine dependencies or substitutes for closed validation.
- [Bedrock inference configuration](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_InferenceConfiguration.html):
  confirms omitted `maxTokens` uses the model's maximum, preserving the existing
  Bedrock behavior while Anthropic requires explicit request configuration.
- [Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting):
  estimate semantics, pricing, rate limits and tokenizer note.
- [Models overview](https://platform.claude.com/docs/en/models/overview): IDs, pricing,
  defaults, latency class and retirement dates.
- [Effort](https://platform.claude.com/docs/en/build-with-claude/effort) and
  [Thinking](https://platform.claude.com/docs/en/build-with-claude/thinking): effort
  levels and defaults, thinking display, billing and per-model thinking controls.
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

The shared-code review additionally traced the provider adapter, credential and
authorization modules, request/response codecs, HTTP/head/transport modules,
production/replay composition and harness consumers linked in §§4–6. It identified
proposed extraction boundaries; it did not refactor code, execute tests or make
live provider calls.

The final architectural review rechecked those boundaries at the revision above,
added R11–R15 and the response-presence gate in R8, and corrected the feasibility
sequence. These findings come from source inspection and official documentation;
race behavior, API compatibility, latency and quality still need the stated
executable evidence. Only this proposal was edited.
