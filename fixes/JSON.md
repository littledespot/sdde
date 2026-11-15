# JSON — Model JSON output on the Claude and Bedrock routes

Research of 14 November 2026 into how Claude produces JSON and how the engine's provider routes
request and admit it, kept at this path at the user's request. Items use SPEC01's format: the
published-output class, owner, status, evidence and next step. The decisions it informs are
recorded in SPEC01 H5 (Claude's response mode, with ADR 0028:177-179) and SPEC01 §3 "Provider
doesn't enforce the response schema". A recommendation here is not a decision, and nothing here
grants approval.

## 1. Claude's JSON mechanism

Checked 14 November 2026 against Anthropic's
[structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) page.

| Topic | Fact |
| --- | --- |
| Mechanism | `output_config.format: {"type": "json_schema", "schema": {…}}` on the Messages API. The schema compiles to a grammar that constrains sampling of the final answer, not of thinking blocks; the page promises "Always valid: No JSON parsing errors". Strict tool use is the same pipeline for tool inputs; the engine sends no tools. |
| Supported schema | Object, array, string, integer, number, boolean, null; `enum` of scalars; `const`; `anyOf`; `allOf` (not with `$ref`); local `$ref`/`$defs`; `required`; `additionalProperties: false`, which every object needs; ten string formats; simple `pattern`s; `minItems` of 0 or 1. |
| Unsupported schema | Recursion; `minimum`, `maximum`, `multipleOf`; `minLength`, `maxLength`; array bounds beyond `minItems` of 0 or 1; any other `additionalProperties`. An unsupported feature returns a 400. |
| Limits per request | 24 optional properties and 16 union-typed properties (`anyOf` or a type array), counted across all strict schemas. A grammar that is still too large returns 400 "Schema is too complex for compilation"; compilation times out at 180 s. |
| Not guaranteed | A `refusal` stop; a `max_tokens` stop (incomplete output); the capitalization of string `enum` and `const` values, "typically in the first letter of a word following a space", with no error and no special stop. |
| Compilation | A new schema compiles on first use; compiled grammars stay cached for 24 hours from last use. Anthropic adds a system prompt describing the format, so input tokens rise slightly. |
| Models | Claude Haiku 5.5 is listed. |

## 2. The engine's JSON path

- Every request carries ADR 0014's framing sentence and the complete schema as system text, in both
  response modes (`src/adapters/provider/model_text_request.zig:66-81`;
  `src/domain/model_controls.zig:7`).
- Native mode adds the provider projection: closed objects, `anyOf` for the compiler-proven
  disjoint alternatives, and no length, numeric or item bound except `minItems: 1`
  (`src/domain/model_schema_projection.zig:5-9`, `:159-170`).
- Admission is the same in both modes (ADR 0006:284-285): one strict object, §22.6's opening
  normalization after a syntax error (`src/domain/model_envelope.zig:58-118`), the complete schema,
  then the domain validators. A rejection gets §22.6's protocol correction.

| Route | Catalogue | Native wire |
| --- | --- | --- |
| Anthropic Messages, `claude-haiku-5-5` | `"json": false` (`test/e2e/config/.sddproviders.json:7-8`) | `output_config.format`, schema as an object (`src/adapters/provider/anthropic_request.zig:68-88`) |
| Bedrock Converse, `openai.gpt-oss-20b-1:0`, family `gpt-oss` | `"json": true` (`:20-21`); all six E2E slots (`test/e2e/wf-001-hello-world/.sddtoolkit.json:10-21`) | `outputConfig.textFormat` `json_schema`, schema as a JSON string, plus `reasoning_effort` (`src/adapters/provider/bedrock_request.zig:74-77`, `:101-123`) |
| Bedrock Converse, `au.anthropic.claude-haiku-5-5`, family `claude` | Live-test allowlist only (ADR 0029:131) | `outputConfig.textFormat` plus `additionalModelRequestFields.output_config.effort` (`bedrock_request.zig:101-123`) |

## 3. Measurements

Every call under `zig-out/e2e-spec/` that left call evidence: 943 calls in 120 runs, 8–13 November
2026 UTC; 26 further runs were `input_invalid` and sent nothing. A throwaway script re-parsed each
`end_turn` text block with a port of `parseOpeningPrefix` (`src/domain/model_envelope.zig:93-118`)
and a duplicate-key-rejecting parser, and measured each captured native schema.

### 3.1 Output syntax

| Route | Calls | Clean | Opening §22.6 strips | Unrecoverable | Reasoning, no answer | Provider failure | Corrections |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Claude, prompt-only, `spec_generation`, effort `low` | 22 | 22 | 0 | 0 | 0 | 0 | 0 |
| GPT-OSS-20B, native | 921 | 49 | 848: 806 `{"`, 27 repeated name, 15 partial name | 1 | 5 | 18 | 9 |

- **Claude:** four runs on 9 November. All 22 text blocks were clean, including those of the two
  runs that failed envelope decoding before ADR 0028:119-125; the other two, one per development
  case, published.
- **GPT-OSS openings:** the engine's `model.response_normalized/v1` records count 846 of them
  (804, 27, 15). The other two (`2026-11-12T20-10-15Z-6d1…` call 6, `2026-11-12T20-18-33Z-9b2…`
  call 10) were stripped and then rejected by the composition check, so they left no candidate and
  no record. The 12 runs of 13 November show 104 openings in 110 answers.
- **GPT-OSS failures:** the provider failures are 403 `AccessDeniedException` (11–12 November).
  The unrecoverable answer repeats its first member inside an array,
  `{"token_classifications":[{"token_classifications":[…` (`2026-11-09T19-51-56Z-916…` call 2), a
  form §22.6 doesn't recognize; its correction was admitted. Three reasoning-only responses in a
  row exhausted the link step of `2026-11-12T03-04-23Z-c4b…` (`missing_final_text`, then
  `retry_limit`), the only failed run with a syntax or missing-answer rejection.
- **GPT-OSS corrections:** five follow a syntax or missing-answer rejection, four a schema or
  domain rejection.
- No call stopped at `max_tokens`. SPEC01 §3 records two answers on 31 October that ended
  `end_turn` inside an open string; none since.

### 3.2 Native schemas against the providers' limits

Bedrock allows 12 optional and 16 union-typed properties per schema, compiles a new schema in up to
about 90 seconds, and advises a read timeout of at least 120 seconds
([structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html));
both E2E catalogue entries set a 180-second deadline (`requestTimeoutMs: 180000`). Every property in
every captured schema is required, so neither provider's optional allowance is used. The largest
request kinds:

| Request | Union-typed properties | `anyOf` nodes | Properties | Depth |
| --- | --- | --- | --- | --- |
| Records generation | 13 | 14 | 43 | 10 |
| Entities generation | 4 | 6 | 24 | 10 |
| Brief generation | 4 | 5 | 21 | 7 |
| Records repair | 3 | 3 | 8 | 6 |
| Every other request | ≤ 1 | ≤ 3 | ≤ 41 | ≤ 10 |

- Records generation uses 13 of the 16 union allowance, or 14 if its root counts: the root is an
  `anyOf` between the records result and a clarification. Most of its unions are text fields typed
  string-or-fragments, which SPEC01 Q7 D7.5 would narrow to a plain string where no insertion is
  offered.
- Whether any schema exceeds Anthropic's internal grammar-size limit shows only on a live request.
- The 60 distinct string `enum` and `const` values are lowercase identifiers such as `claims` and
  `preserve`, with no capitals or spaces.

## 4. Findings

### J1. Bedrock doesn't hold GPT-OSS-20B to the schema

- **Class:** successful completion; the route depends on an approved workaround.
- **Owner:** the provider, Bedrock Converse for `openai.gpt-oss-20b-1:0`. Status and the open
  question are SPEC01 §3's; ADR 0039:67-73 records the provider defect.
- **New evidence:**
  - §3.1, across the route's 116 runs, the newest included. A grammar held from the first token
    can't emit `{"{` or `{"kind":"{ "kind"`.
  - The 12 September Bedrock probes (`zig-out/native-schema-probe/`, `native-schema-enum-probe/`,
    `native-schema-variant-probe/`) show the fragment on small schemas with alternatives. A
    one-field schema came back clean in native, guided-native and prompt-only modes.
  - AWS says Converse structured outputs "constrains model responses to follow a specific schema"
    and "Eliminates error rates and retry loops from prompt-based approaches"
    ([guide](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)). Its
    Converse example sends the schema as a JSON string, as the engine does. The
    [gpt-oss-20b card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-oss-20b.html)
    lists structured outputs among its `bedrock-runtime` features and `ap-southeast-2` as
    In-Region. Neither page makes an exception for reasoning models.
- **Next:** D2. Outside Converse, Bedrock documents `response_format` for open-weight models; using
  it would be a new Bedrock endpoint, which ADR 0029 doesn't cover (ADR 0029:62-63, :147-148).

### J2. The Bedrock `claude` family has never sent native mode

- **Class:** successful completion.
- **Owner:** `src/adapters/provider/bedrock_request.zig:74-77`, `:101-123`; ADR 0029:65-73.
- **Status:** no test, offline or live, combines `outputConfig.textFormat` with
  `additionalModelRequestFields.output_config`: the native conformance test binds no effort
  (`src/provider_conformance_test.zig:710-719`) and the effort test runs prompt-only (`:780-823`).
- **Evidence:** AWS documents Converse `outputConfig.textFormat` for Claude on `bedrock-runtime`
  ([Claude structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-structured-outputs.html)).
  That page says nothing about effort or `additionalModelRequestFields`, and no AWS page says how
  Bedrock combines the two `output_config` sources. If Bedrock rejects the pair, the engine reports
  a typed `request_rejected`. If it drops the format, the answer is unconstrained but still fully
  validated, and nothing in the response says so.
- **Next:** none while no slot uses this family in native mode. Bedrock also serves the Anthropic
  Messages API (same page), whose body carries `effort` and `format` in one `output_config`, as
  `src/adapters/provider/anthropic_request.zig:68-88` writes it; ADR 0029:147-148 leaves that
  endpoint undecided.

### J3. Claude's response mode is open

- **Class:** successful completion: a malformed answer costs a correction.
- **Owner:** the catalogue `json` flag (`design/contracts/12-model-boundary.md:352-354`); the
  decision belongs to SPEC01 H5 and ADR 0028:177-179.
- **Status:** prompt-only in the E2E catalogue; native mode implemented and tested offline
  (`src/adapters/provider/anthropic_request.zig:92-108`), never sent live.
- **Evidence:** §3.1 (no Claude answer failed to parse) and §3.2 (every captured schema fits Claude's
  documented subset and explicit limits).
- **Next:** D1.

### Checked, no change

- **§22.6 normalization** absorbs the GPT-OSS openings and also serves the GPT-OSS judge and the
  frozen calibration experiments, both native (`design/harness/evaluator.md:137-151`;
  `test/calibration/semantic-simplicity/protocol.json:10`). Widening it to the nested repeat would
  salvage more malformed text for one provider (AGENTS.md "Anti-overfitting rule").
- **The schema sent twice in native mode:** the text copy carries the bounds the projection drops
  (ADR 0006:124-134). Its size is SPEC01 C12's, and AGENTS.md rules out a cost-only change.
- **Prose inside JSON strings:** no invalid escape, control character or unterminated string in any
  retained answer. Composition compares decoded strings (`src/domain/model_envelope.zig:222`), so an
  escape style can't change admission.

## 5. Decisions

**D1. Claude response mode (SPEC01 H5; ADR 0028:177-179).** Only if you select Claude Haiku 5.5 for
a slot: should its catalogue entry say `"json": true`? For example,
`test/e2e/config/.sddproviders.json:8` becomes `"json": true`, and every Claude request also carries
`output_config.format`.

- **Yes:** Anthropic documents that sampling then follows the schema, except at a `max_tokens` or
  `refusal` stop and in the capitalization of `enum` and `const` values; unverified here (§6). A
  casing change takes §22.6's existing schema correction; the Spec values are lowercase identifiers
  (§3.2). The model input changes (Anthropic's format prompt), so the first native set is measured
  (SPEC01 §2). The first request for each schema waits for compilation, which Anthropic stops at
  180 seconds, the entry's whole request deadline. Anthropic refuses a schema past 16 union-typed
  properties with a 400 (§6).
- **No:** nothing changes; no Claude answer has failed to parse so far.
- **Recommendation:** yes, as a hygiene phase (SPEC01 §2 rule 6): the target is its own class,
  malformed JSON, and it is kept on the guards plus no provider 400 and no new rejection class. It
  settles the response mode that ADR 0028:177-179 left waiting on measured compatibility, with the
  provider-enforced output ADR 0006's 12 September amendment set out to use.

**D2. GPT-OSS response mode (SPEC01 §3).** Should a GPT-OSS-20B set run with `"json": false`? For
example, a copy of the E2E catalogue says `"json": false` for `openai.gpt-oss-20b-1:0`, and requests
stop sending `outputConfig` while keeping the full schema text.

- **Yes:** the set shows whether the opening fragment comes from Bedrock's grammar path. The shipped
  catalogue can't be the one changed: the compatibility probe installs it and pins native mode
  (`test/calibration/semantic-simplicity/protocol.json:10`, compared at
  `test/harness/frozen_binding.zig:65`), and ADR 0029:134-137 requires the probe to accept the
  shipped cases. So it needs its own catalogue, or an ADR 0029 amendment, and its own measured
  build (SPEC01 §2 rule 1). With no grammar at all, the model may fence or wrap its JSON, which is
  rejected and corrected, never stripped (ADR 0014); OpenAI says a schema in the prompt "doesn't
  guarantee the full adherence to the schema"
  ([harmony guide](https://developers.openai.com/cookbook/articles/openai-harmony)).
- **No:** the route keeps native mode, with §22.6 absorbing the fragment.
- **Recommendation:** no. The set can't retire §22.6, which the native judge still needs, and the
  fragment causes no published-output defect, so its only result would be a diagnosis of Bedrock. The same applies to SPEC01 §3's deferred live comparison.

## 6. Open

- Any native Claude request, on either route: Anthropic's internal grammar-size limit and the effect
  of its format prompt on output are unmeasured.
- Whether a provider's count limits make a schema "unsupported" under ADR 0006:284-285, so that the
  engine refuses it before the call rather than taking the provider's 400: undecided.
- When Bedrock returns `malformed_model_output`; AWS defines it only in its Nova guide.
- How Bedrock combines `outputConfig.textFormat` with `additionalModelRequestFields.output_config`
  for Claude Haiku 5.5 (J2).
- Whether Bedrock's `response_format` enforces the schema for GPT-OSS-20B.
