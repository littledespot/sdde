# JSON — Model JSON output on the Claude and Bedrock routes

Research of 14 November 2026 into how Claude produces JSON and how the engine's provider routes
request and admit it, kept at this path at the user's request, and re-checked on 17 November 2026
against the current tree, the retained evidence and the providers' pages. Items use SPEC01's
format: the published-output class, owner, status, evidence and next step. The decisions it informs
are recorded in SPEC01 H5 (Claude's response mode, with ADR 0028:177-179) and SPEC01 §3 "Provider
doesn't enforce the response schema". A recommendation here is not a decision, and nothing here
grants approval.

## 1. Claude's JSON mechanism

Checked 17 November 2026 against Anthropic's
[structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) page.

| Topic | Fact |
| --- | --- |
| Mechanism | `output_config.format: {"type": "json_schema", "schema": {…}}` on the Messages API. The schema compiles to a grammar that constrains sampling of the final answer; "Grammar state resets between sections", so thinking blocks stay unconstrained. The page promises "Always valid: No JSON parsing errors". Strict tool use is the same pipeline for tool inputs. The engine sends no tools, citations or prefill, the last two being the features the page lists as incompatible. |
| Supported schema | Object, array, string, integer, number, boolean, null; `enum` of scalars; `const`; `anyOf`; `allOf` (not with `$ref`); local `$ref`/`$defs`; `required`; `additionalProperties: false`, which every object needs; ten string formats; simple `pattern`s; `minItems` of 0 or 1. |
| Unsupported schema | Recursion; external `$ref`; `minimum`, `maximum`, `multipleOf`; `minLength`, `maxLength`; array bounds beyond `minItems` of 0 or 1; any other `additionalProperties`. An unsupported feature returns a 400. |
| Root schema | No rule. The page neither requires `type: object` at the root nor mentions a root `anyOf`; its examples all use an object. |
| Limits per request | 24 optional properties and 16 union-typed properties (`anyOf` or a type array), counted across all strict schemas. A grammar that is still too large returns 400 "Schema is too complex for compilation"; compilation times out at 180 s. |
| Not guaranteed | A `refusal` stop; a `max_tokens` stop (incomplete output); the capitalization of string `enum` and `const` values, "typically in the first letter of a word following a space", with no error and no special stop. |
| Compilation | A new schema compiles on first use; compiled grammars stay cached for 24 hours from last use, keyed on the schema's structure. Anthropic adds a system prompt describing the format, so input tokens rise slightly. |
| Models | Claude Haiku 5.5 is listed. |

## 2. The engine's JSON path

- Every request carries ADR 0014's framing sentence and the complete schema as system text, in both
  response modes (`src/adapters/provider/model_text_request.zig:66-81`;
  `src/domain/model_controls.zig:7`).
- Native mode adds the provider projection: closed objects, `anyOf` for the compiler-proven
  disjoint alternatives, and no length, numeric or item bound except `minItems: 1`
  (`src/domain/model_schema_projection.zig:5-9`, `:139-152`, `:170-181`).
- Admission is the same in both modes (ADR 0006:284-285): one strict object, §22.6's opening
  normalization after a syntax error (`src/domain/model_envelope.zig:58-118`), the complete schema,
  then the domain validators. A rejection gets §22.6's protocol correction.
- The registered `claude-haiku-5-5` contract admits native mode and takes no temperature
  (`src/composition/provider_model_contracts.zig:11`, `:58-63`).

| Route | Catalogue | Native wire |
| --- | --- | --- |
| Anthropic Messages, `claude-haiku-5-5` | `"json": true`, set by D1 (`test/e2e/config/.sddproviders.json:7-8`); all six E2E slots (`test/e2e/wf-001-hello-world/.sddtoolkit.json:10-21`) | `output_config.format`, schema as an object, beside `effort` (`src/adapters/provider/anthropic_request.zig:68-88`) |
| Bedrock Converse, `openai.gpt-oss-20b-1:0`, family `gpt-oss` | `"json": true` (`:20-21`); no E2E slot since 17 November 2026, when all six moved to Claude | `outputConfig.textFormat` `json_schema`, schema as a JSON string, plus `reasoning_effort` (`src/adapters/provider/bedrock_request.zig:74-77`, `:101-123`) |
| Bedrock Converse, `au.anthropic.claude-haiku-5-5`, family `claude` | On the live-test allowlist (ADR 0029:131) but not in the E2E catalogue, which ADR 0029:32-33 says keeps it | `outputConfig.textFormat` plus `additionalModelRequestFields.output_config.effort` (`bedrock_request.zig:101-123`) |

## 3. Measurements

Every call retained on 17 November 2026, all GPT-OSS-20B in native mode at effort `low`: 245 calls
in the 24 E2E runs under `zig-out/e2e-spec/` (15–16 November 2026, four builds) and 250 replays in
the 25 `e2e-call` screens under `zig-out/e2e-call/` (15 November). A throwaway script re-parsed each
text block with a port of `parseOpeningPrefix` (`src/domain/model_envelope.zig:93-118`) and a
duplicate-key-rejecting parser, checked each parsed E2E answer against the native projection it was
sent with, and measured each captured native schema. The call evidence of the four Claude runs of
9 November is no longer retained; only the evaluation copies of the two published runs remain
(`evaluations/e2e/2026-11-09T21-31-48Z-da06…`, `…-f99e…`).

### 3.1 Output syntax

| Route | Calls | Clean | Opening §22.6 strips | Unrecoverable | Reasoning, no answer | Provider failure | Corrections |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Claude, prompt-only, `spec_generation`, effort `low`, 9 November | 22 | 22 | 0 | 0 | 0 | 0 | 0 |
| GPT-OSS-20B, native, E2E runs | 245 | 15 | 228: 216 `{"`, 6 repeated name, 6 partial name | 1 | 1 | 0 | 2 |
| GPT-OSS-20B, native, `e2e-call` screens | 250 | 18 | 232: 216 `{"`, 12 repeated name, 4 partial name | 0 | 0 | 0 | none (single calls) |

- **Claude:** four runs on 9 November, measured on 14 November. All 22 text blocks were clean,
  including those of the two runs that failed envelope decoding before ADR 0028:119-125; the other
  two, one per development case, published.
- **GPT-OSS openings:** §22.6 strips a fragment from 460 of the 494 text answers (93%). In the E2E
  runs the engine's `model.response_normalized/v1` records match the script exactly (216, 6, 6).
- **GPT-OSS failures:** the unrecoverable answer is `{"conflicts":{ "conflicts":[] }`
  (`2026-11-16T01-49-06Z-c36…` call 6): the member opener `{"conflicts":` and then a complete object,
  rejected as `UnexpectedEndOfInput`. The evaluation copy of `728d…`, one of the earlier prefix
  faults SPEC01 §3 records, describes the same form ("the JSON opened twice and never closed",
  `evaluations/e2e/2026-11-07T01-19-36Z-728d…/evaluation.md:10`), and §22.6 never tries it (§4
  "Checked, no change"). The reasoning-only answer is `2026-11-15T21-47-31Z-863…` call 1
  (`missing_final_text`, SPEC01 §3). The two corrections are their next calls; both were admitted
  and both runs published.
- **Conformance:** all 243 parsed E2E answers conform to the native projection they were sent with,
  so every syntax fault seen is in the opening.
- **Stops:** all 495 responses ended `end_turn`. SPEC01 §3 records two answers on 31 October that
  ended `end_turn` inside an open string; none in the retained calls.

### 3.2 Native schemas against the providers' limits

Bedrock allows 12 optional and 16 union-typed properties per schema, compiles a new schema in up to
about 90 seconds, and advises a read timeout of at least 120 seconds
([structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html));
both E2E catalogue entries set a 180-second deadline (`requestTimeoutMs: 180000`). Every property in
every captured schema is required, so neither provider's optional allowance is used, and the four
builds send the same schemas. The largest request kinds:

| Request | Union-typed properties | `anyOf` nodes | Properties | Depth |
| --- | --- | --- | --- | --- |
| Records generation | 9 | 10 | 34 | 10 |
| Entities generation | 3 | 4 | 20 | 9 |
| Brief generation | 3 | 4 | 17 | 7 |
| Scenario writing | 3 | 3 | 8 | 7 |
| Every other request | ≤ 1 | ≤ 3 | ≤ 12 | ≤ 10 |

- Records generation uses 9 of the 16 union allowance, or 10 if its root counts: the root is an
  `anyOf` of `records`, `clarification` and `inconclusive`. Eight of the nine are text fields typed
  string-or-fragments (SPEC01 Q7 C).
- Four request kinds (records, entities and brief generation, and content extraction) send a root
  `anyOf` with no `type`: 97 of the 245 native requests. Bedrock accepts it for GPT-OSS. Neither
  Anthropic nor AWS states a root rule for Claude, so whether Claude's compiler accepts it shows
  only on a live request, as does Anthropic's internal grammar-size limit (the largest schema is
  3,462 bytes).
- The 245 native requests carried 19 distinct schemas. Eight request kinds list the IDs the call is
  given as integer enums, so each of their schemas repeats across runs of one case but not across
  cases: a new feature compiles about eight new grammars on first use, each then cached for 24 hours
  (Anthropic from last use, Bedrock from first access).
- The 53 distinct string `enum` and `const` values are lowercase identifiers such as `claims` and
  `functional_requirement`, with no capitals or spaces.

## 4. Findings

### J1. Bedrock doesn't hold GPT-OSS-20B to the schema

- **Class:** successful completion; the route depends on an approved workaround.
- **Owner:** the provider, Bedrock Converse for `openai.gpt-oss-20b-1:0`. Status and the open
  question are SPEC01 §3's; ADR 0039:67-73 records the provider defect.
- **New evidence:**
  - §3.1: a fragment opens 93% of the retained native answers. A grammar held from the first token
    can't emit `{"{` or `{"kind":"{ "kind"`.
  - Every parsed answer conforms to the native projection (§3.1). That fits a grammar applied after
    the opening, and equally a model following the schema text the engine also sends, so SPEC01 §3's
    question, whether Bedrock applies the grammar partly or not at all, stays open.
  - The fault reproduces outside this engine. An aws-samples repository, on 30 October 2026 in
    `us-east-1`, sent a two-field object schema with no alternatives through `outputConfig` alone:
    gpt-oss-20b replies came back fenced or with a doubled opening brace, and `json.loads` accepted
    1 of 8 as returned ([issue #634](https://github.com/aws-samples/sample-per-model-bedrock/issues/634),
    [PR #635](https://github.com/aws-samples/sample-per-model-bedrock/pull/635); bot-maintained, not
    AWS documentation). In its control, gpt-oss-120b answered a prompt that never mentions JSON with
    the object only when `outputConfig` was present: the field steers the answer but doesn't
    constrain its opening.
  - The 12 September Bedrock probes (`zig-out/native-schema-probe/`, `native-schema-enum-probe/`,
    `native-schema-variant-probe/`), one sample each: a one-field schema came back clean in native,
    guided-native and prompt-only modes; of 8 schemas with alternatives, 5 opened with a fragment
    and 1 was unrecoverable.
  - AWS says Converse structured outputs "constrains model responses to follow a specific schema"
    and "Eliminates error rates and retry loops from prompt-based approaches"
    ([guide](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)). Its
    Converse example sends the schema as a JSON string, as the engine does. The
    [gpt-oss-20b card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-oss-20b.html)
    lists structured outputs among its `bedrock-runtime` features and `ap-southeast-2` as
    In-Region. Neither page makes an exception for reasoning models.
- **Next:** D2. Outside Converse, Bedrock documents `response_format` for open-weight models,
  through InvokeModel on the same `bedrock-runtime` host; ADR 0029's families cover Converse only
  (ADR 0029:62-63).

### J2. The Bedrock `claude` family has never sent native mode

- **Class:** successful completion.
- **Owner:** `src/adapters/provider/bedrock_request.zig:74-77`, `:101-123`; ADR 0029:65-73.
- **Status:** no live request has combined `outputConfig.textFormat` with
  `additionalModelRequestFields.output_config`. Offline, only the evaluator test encodes the pair,
  and it asserts only the effort (`test/harness/tests.zig:492-546`); the engine's native
  conformance test binds no effort (`src/provider_conformance_test.zig:710-719`) and its effort
  test runs prompt-only (`:780-861`).
- **Evidence:** AWS documents Converse `outputConfig.textFormat` for Claude on `bedrock-runtime`
  ([Claude structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-structured-outputs.html)),
  and the [Claude Haiku 5.5 card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-haiku-5-5.html)
  lists structured outputs on both endpoints. Neither page says how to send effort beside a format
  or mentions `additionalModelRequestFields`, and no AWS page says how Bedrock combines the two
  `output_config` sources. If Bedrock rejects the pair, the engine reports a typed `request_rejected`. If it drops
  the format, the answer is unconstrained but still fully validated, and nothing in the response
  says so.
- **Next:** none while no slot uses this family in native mode. On `bedrock-runtime`, Bedrock also
  takes Anthropic's own request body, in which `effort` and `format` share one `output_config` as
  `src/adapters/provider/anthropic_request.zig:68-88` writes it: through InvokeModel (with
  `anthropic_version`) and through the Anthropic Messages API (`/anthropic/v1/messages`). The
  `bedrock-mantle` Messages endpoint serves Claude Haiku 5.5 only in `us-gov-west-1`. ADR 0029
  covers Converse only, and ADR 0029:147-148 leaves Bedrock's Messages API endpoint undecided.

### J3. Claude's response mode is native and unmeasured

- **Class:** successful completion: a malformed answer costs a correction.
- **Owner:** the catalogue `json` flag (`design/contracts/12-model-boundary.md:359-361`); the
  decision is SPEC01 H5's, and ADR 0028:177-179 still lists it as waiting on measured
  compatibility.
- **Status:** set native by D1. Native mode is implemented, admitted by the registered contract (§2)
  and tested offline (`src/adapters/provider/anthropic_request.zig:92-108`). It has never been sent
  live: the entry ran prompt-only on 9 November, and every E2E slot selects it since 17 November.
- **Evidence:** §3.1 (no Claude answer failed to parse); the native projection emits only features in
  Claude's documented subset (§1; `src/domain/model_schema_projection.zig:139-181`); and §3.2 (the
  counts are within the explicit limits; the root `anyOf` and the grammar size are unverified).
- **Next:** the first approved Claude set measures native mode (D1).

### Checked, no change

- **§22.6 normalization** absorbs the GPT-OSS openings and also serves the GPT-OSS judge and the
  frozen calibration experiments, both native (`design/harness/evaluator.md:137-152`;
  `test/calibration/semantic-simplicity/protocol.json:10`). It recognizes three exact forms and
  salvages no other prefix (`design/contracts/22-repair.md:483-515`). Widening it to §3.1's
  member-value form would also mean trying it after `UnexpectedEndOfInput`, not only after a
  `SyntaxError` (`src/domain/model_envelope.zig:67`), to salvage more malformed text for one
  provider (AGENTS.md "Anti-overfitting rule"); each such answer was corrected.
- **The schema sent twice in native mode:** the text copy carries the bounds the projection drops
  (ADR 0006:124-134). Its size is SPEC01 C12's, and AGENTS.md rules out a cost-only change.
- **Prose inside JSON strings:** no invalid escape, control character or unterminated string in any
  retained answer. Composition compares decoded strings (`src/domain/model_envelope.zig:222`), so an
  escape style can't change admission.
- **Claude Haiku 5.5's request rules:** Anthropic's
  [migration guide](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide) says to
  omit `temperature`, `top_p` and `top_k`, and that an assistant prefill returns a 400. The engine
  sends neither: ADR 0028 lists temperature among the fields never sent, both Claude encoders refuse
  one before the call (`src/adapters/provider/anthropic_request.zig:36`;
  `src/adapters/provider/bedrock_request.zig:48`), and the request ends with its one user message.
  Adaptive thinking, on by default, stays outside the grammar, and ADR 0028 keeps thinking blocks as
  reasoning, never candidate text.

## 5. Decisions

**D1. Claude response mode (SPEC01 H5; ADR 0028:177-179). Decided 17 November 2026** (user, asked
what "implement" should cover, chose to set the flag now rather than wait for a Claude selection):
`test/e2e/config/.sddproviders.json:8` says `"json": true`, so every Claude request carries
`output_config.format`. The user also moved every E2E slot to `anthropic` / `claude-haiku-5-5` that
day (ADR 0029), so the next approved run sends native mode.

- **What the choice rests on:** the registered contract admits native mode (§2). Anthropic documents
  that sampling then follows the schema, except at a `max_tokens` or `refusal` stop, which the
  engine already reports as `output_limit` and `content_filtered` (ADR 0028), and in the
  capitalization of `enum` and `const` values; unverified here (§6). A casing change takes §22.6's
  existing schema correction; the Spec values are lowercase identifiers (§3.2). It records the mode
  ahead of the measurement ADR 0028:177-179 waits for, and uses the provider-enforced output
  ADR 0006's 12 September amendment set out to use.
- **What it gives up:** the earlier recommendation was a hygiene phase after the selection, run
  against the selection's prompt-only set as a reference. That reference extends SPEC01 §2 rule 7,
  which names the last kept state. With the flag set, the first Claude set has none, so a quality
  change in it isn't split between model and mode, and no rule 4 screen can precede it, since
  `e2e-call` keeps the captured response mode (`design/harness/e2e.md:113-114`). The phase's own
  class is malformed answers (J3), none of which Claude's 22 answers so far has shown. Its Keep if
  measures are the user's to set before that set (rule 6); no provider 400 and no new rejection
  class are proposed. Its revert is the one catalogue line (rule 1).
- **What shows on that first request:** each new schema compiles on first use, about eight per new
  feature (§3.2), and Anthropic stops a compilation at 180 seconds, the entry's whole request
  deadline. If Anthropic refuses the root `anyOf` or a grammar, its 400 `invalid_request_error` is a
  `request_rejected` (`src/adapters/provider/anthropic_response.zig:199`; any other error type is
  `response_invalid`, ADR 0028:149-151), and neither is retried
  (`src/domain/provider_failure.zig:19`). Content extraction, every run's first call, sends a root
  `anyOf`, so every run would stop there with nothing published.
- **Not changed:** ADR 0028:177-179 still says the mode waits for measured compatibility, and
  ADR 0028:91-92 still requires an approved compatibility probe before any live use. Amending an
  accepted ADR needs the user's word, and every live set needs its own approval.

**D2. GPT-OSS response mode (SPEC01 §3).** Should a GPT-OSS-20B set run with `"json": false`? For
example, a copy of the E2E catalogue says `"json": false` for `openai.gpt-oss-20b-1:0`, and requests
stop sending `outputConfig` while keeping the full schema text.

- **Yes:** the set shows whether the opening fragment comes from Bedrock's grammar path. The shipped
  catalogue can't be the one changed: the compatibility probe installs it and pins native mode
  (`test/calibration/semantic-simplicity/protocol.json:10`, compared at
  `test/harness/frozen_binding.zig:65`). The shipped cases now select Claude (ADR 0029:134-139), so a
  GPT-OSS set needs its own toolkit config as well as its own catalogue, and its own measured
  build (SPEC01 §2 rule 1). With no grammar at all, the model may fence or wrap its JSON, which is
  rejected and corrected, never stripped (ADR 0014); OpenAI says a schema in the prompt "doesn't
  guarantee the full adherence to the schema"
  ([harmony guide](https://developers.openai.com/cookbook/articles/openai-harmony)).
- **No:** the route keeps native mode, with §22.6 absorbing the fragment.
- **Recommendation:** no. The set can't retire §22.6, which the native judge still needs, and the
  fragment causes no published-output defect, so its only result would be a diagnosis of Bedrock,
  whose fault J1's outside reproduction already separates from this engine's request. The same
  applies to SPEC01 §3's deferred live comparison.

## 6. Open

- Any native Claude request, on either route: whether Anthropic's compiler accepts the projection's
  root `anyOf` (§3.2), its internal grammar-size limit, its compilation time against the
  180-second deadline, and the effect of its format prompt on output are unmeasured.
- Whether a provider's count limits make a schema "unsupported" under ADR 0006:120 and :284-285, so
  that the engine refuses it before the call rather than taking the provider's 400: undecided. No
  current schema is near a documented limit (§3.2).
- When Bedrock returns `malformed_model_output`: the Converse API reference lists it as a
  `stopReason` without defining it. Only the user guide for Amazon's own Nova models defines it, as
  "The model produced invalid output."
  ([response structure](https://docs.aws.amazon.com/nova/latest/userguide/complete-request-schema-response.html)).
  No retained response has it.
- How Bedrock combines `outputConfig.textFormat` with `additionalModelRequestFields.output_config`
  for Claude Haiku 5.5 (J2).
- Whether Bedrock's `response_format` enforces the schema for GPT-OSS-20B; the aws-samples
  measurement covers Converse only.
