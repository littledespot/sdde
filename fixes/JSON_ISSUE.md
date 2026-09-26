# AWS Bedrock malformed JSON — findings and remediation

**Research date:** 21 September 2026. **Status:** both approved comparisons completed;
the user subsequently approved the narrow, logged normalization described below.
The provider defect and live workflow effectiveness remain unproven. This work
uses the existing [Chunk 18 owners](IMP_001.md#per-model-json-output--21-september-2026).

## InvokeModel-only amendment — 25 September 2026

The user selected InvokeModel as the sole Bedrock inference API. Generation,
correction, debugger replay and grading share the existing request/response
owners. Native mode sends `response_format.type: "json_schema"` with the selected
schema object; local validation, bounded retries and token accounting remain
mandatory. The old codec is removed, with no fallback. See
[F0007](../design/features/F0007-AWSBedrockProvider.md) for the current contract.

Historical captures below retain their original API/bytes; they are not evidence
of InvokeModel effectiveness. No live comparison was authorized for this change.

## Grading follow-up — 23 September 2026

The engine requests native output, but grading previously used an explicit
prompt-only profile. The user approved replacing that grading profile with the
existing shared native encoder and capability check. [FIX_002 §22](FIX_002.md#22-native-structured-output-for-grading--23-september-2026)
records implementation and pending live evidence. It does not resolve or broaden
the approved workaround for the distinct provider-prefix issue below.

## Conclusion

The retained September comparisons sent the documented native JSON Schema
configuration. They returned malformed text despite that configuration, followed
by unsuccessful bounded corrections. Internet research found related integration
failures, but **no verified public diagnosis or fix for this exact failure**.

The first comparison reproduced the prefix with a **142-byte native object schema**,
without unions or nested objects. The follow-up narrowed it further: a single plain
string passed, while the same field constrained with `const` returned malformed
JSON. Only that field's complete and native schemas changed. This identifies a
constant-associated difference in the measured pair, not the failing provider
component or a proven fix. Do not remove discriminator constraints from production
schemas. Use the retained passing/failing pair for AWS investigation or an approved
comparison of equivalent native constraint encodings through the shared projection.

## Approved prefix normalization — 21 September 2026

The user approved removal of the extraneous opening bytes and explicitly required
an alteration log. [§22.6](../design/contracts/22-repair.md#226-unparseable-output)
owns the exact contract; it supersedes this note's earlier recommendation against
any prefix removal.

- Try the original complete response first. After `SyntaxError` only, match the
  exact leading `{"{`, remove its first two bytes (`{"`) once, then strictly parse
  the entire remainder. Valid JSON, including a property named `{`, is unchanged.
- Keep one shared model-envelope decoder for both admission operations and
  debugger inspection. The existing domain handoff supplies its validated bytes
  to generation, review and repair consumers; composition uses the validated tree.
  Do not alter Bedrock extraction or raw captures.
- Continue through full schema and domain validation. A remaining syntax error
  uses its original diagnostic and existing correction flow; exhaustion still
  prevents publication. This cannot recover missing requirements.
- Retain a typed normalization fact. Emit warning `model.response_normalized`,
  diagnostic `REMOVED_LEADING_BRACE_QUOTE`, with node/request/attempt correlation.
  It means exactly two leading bytes were removed. A logging failure stops the
  runner; schema failure after normalization remains a separate rejection.
- Show normalization in the debugger beside the original text and derived tree.
  Requests, prompts, provider calls, retries and token accounting do not change.

Implementation uses the existing owners and adds no dependency, action, prompt or
configuration switch. Verification status is recorded below. No live call or E2E
run is authorized by this implementation request.

## Can the existing JSON correction action fix a poor initial response?

**Yes, when the initial response fails JSON decoding or its assigned schema.**
This is already the purpose of `build-model-protocol-retry`, and the failed run
below used it twice. No separate fixer or additional retry path is needed.
"Poor" content must be classified by the existing validators, not treated as a
new generic reason to call the model again.

| Initial response problem | Existing handling |
| --- | --- |
| Malformed JSON, duplicate keys or surrounding non-JSON text | Apply only the approved prefix normalization above; otherwise protocol correction with the exact original decoder diagnostic and rejected response. |
| Valid JSON with missing required fields, forbidden fields, wrong types or other bound-schema violations | The same correction action, with the schema diagnostic and schema-derived shape guidance. |
| Missing final answer | The same bounded continuation only after existing provider admission establishes eligible `missing_final_text`; reasoning is never substituted. |
| Schema-valid JSON that omits requirements, invents evidence or contains incorrect relationships | Domain validation/review, then an existing engine-authorized candidate repair where permitted. Protocol correction cannot reconsider meaning or change a review verdict. |
| A genuine missing user decision | Existing clarification handling; JSON correction cannot invent the answer. |

The [action](../src/actions/model/build_model_protocol_retry.zig) only prepares the
correction request. Existing workflow/runner owners invoke the model, validate the
response, enforce the assignment allowance and account every call against the global
token budget. The [shared builder](../src/domain/model_protocol_retry.zig) retains
the original task, input and selected schema, includes the latest rejected response
when one exists, and explains the actual error. It requests the **complete corrected
assigned response**, preserving unaffected entries and meaning. For a configured
part or selected repair, this means that part or replacement, not the whole workflow
candidate; unrelated admitted parts remain unchanged.

If correction passes JSON/schema admission, work continues through required domain
and full-candidate validation. If it remains invalid when the allowance is exhausted,
the workflow errors without publication. Fixing syntax alone neither restores an
omitted requirement nor proves semantic quality. These are the existing
[§22.6–22.7 boundaries](../design/contracts/22-repair.md#226-unparseable-output),
not new repair authority. Reusing this action is appropriate; its unsuccessful use
in the latest run is why provider-conformance investigation remains necessary.

## What our captured run establishes

Run `2026-09-20T22-07-24Z-4f7e04d262338e262caad159d63ba53f` used
`openai.gpt-oss-20b-1:0`, the then-current API, `ap-southeast-2`, temperature `0` and reasoning
effort `low`. See the [full analysis](FIX_001.md#latest-native-json-run--malformed-output-despite-native-schema)
and [report](../zig-out/e2e-spec/2026-09-20T22-07-24Z-4f7e04d262338e262caad159d63ba53f/report.json).

- All three requests included `outputConfig.textFormat.type: "json_schema"` and
  the same 6,834-byte projected schema. Its 50 object schemas all specify
  `additionalProperties: false`; it contains ten `anyOf` nodes, including the root.
  These are measurements, not evidence that complexity caused the failure.
- All three responses were HTTP 200 with `stopReason: "end_turn"`. Their final text
  began `{"{ "kind":"claims"` and failed JSON decoding at byte offset 5. The outer
  AWS response envelope was valid JSON; the model-generated string inside was not.
- Raw provider text equals captured model text. Both corrections included the
  parser error, location, original task/schema and rejected answer; the final one
  identified confirmed recurrence. The last two answers were byte-identical.
- The existing runner stopped after two corrections, accounted 7,857 tokens and
  published nothing. Neither the 100,000-token budget nor schema/domain validation
  caused the stop; parsing failed first.

## What current AWS documentation says

| Finding | Consequence for SDDE |
| --- | --- |
| Native structured outputs became generally available on 4 February 2026. [AWS announcement](https://aws.amazon.com/about-aws/whats-new/2026/02/structured-outputs-available-amazon-bedrock/) | Older reports about prompt-only or forced-tool output cannot establish a defect in the current native API. |
| InvokeModel open-weight requests use `response_format`, with the schema as an object. [AWS guide](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html) | This is the approved current API. Older captures used the prior documented `outputConfig.textFormat` field; they do not measure this route. |
| `JsonSchemaDefinition.schema` is a required string; `name` and `description` are optional. [API reference](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_JsonSchemaDefinition.html) | A serialized schema string is expected, not accidental double encoding. This definition has no `strict` field. |
| `strict: true` is a tool-definition option; schema output and strict tools are separate mechanisms. [AWS guide](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html) | Adding a tool or an unrecognized `strict` property is not required to enable the existing text-output contract. |
| The supported subset includes `const` and `anyOf` with limitations; unsupported schema features should produce HTTP 400. [AWS guide](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html) | No authoritative general prohibition on root `anyOf` for this text-output/model combination was found. Its actual behavior needs testing; HTTP 200 alone does not prove correct constraint enforcement. |
| The GPT-OSS-20B model card lists native structured outputs and Sydney availability. [Model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-oss-20b.html) | Our configured combination is documented. The observed violation merits provider investigation rather than an assumption that the feature is unavailable. |
| AWS warns that refusal and output-token exhaustion can yield nonconforming output, and recommends checking the stop reason and testing increasingly complex schemas. [AWS engineering article, 6 February 2026](https://aws.amazon.com/blogs/machine-learning/structured-outputs-on-amazon-bedrock-schema-compliant-ai-responses/) | Neither exception is reported in this run. Increasing output limits is not supported by these captures. |

The older captures used `end_turn` and the prior response envelope. Current
InvokeModel decoding checks `finish_reason`, final text and usage through the
shared response owner. Native constraints never replace SDDE's evidence,
relationship, provenance or publication checks.

## Public reports: useful distinctions, not a diagnosis

| First-hand report | Reported problem/remedy | Relevance here |
| --- | --- | --- |
| [LangChain AWS #571](https://github.com/langchain-ai/langchain-aws/issues/571), 6 August 2025 | GPT-OSS structured-output helper returns no parsed tool result. | Predates native structured outputs and uses a tool parser. It does not explain our native final-text failure. |
| [LiteLLM #35214](https://github.com/BerriAI/litellm/issues/35214), 30 July 2026 | Reporter finds `json_object` silently omitted from the outgoing Bedrock request; supplying `json_schema` works in that example. | Inspecting the actual wire request is essential. SDDE uses neither that library nor that mode; its native schema is present. This workaround is already satisfied here. |

These reports are observations by their authors, not AWS confirmation of our
provider-side cause. No matching public incident or patch was found for the
`{"{ "kind` prefix under native schema output. An incomplete search cannot prove
that no such incident exists.

## Recommended next steps

### 1. Completed diagnostic comparison — 21 September 2026

The user approved implementation of the three-call comparison. Existing native
request replay sent each input once with no automatic retry, workflow execution,
publication or grading. Model, region, native schema mode, temperature zero and low
reasoning stayed fixed. The older planned baseline had rotated out; the retained
22:07 run supplied the same initial wire request, with byte equality checked by
exact replay. Parent: `RUN-5618a467c810ac31720f1936495940ed` /
`request-1-inference-1`. Replay session:
`debugger-d5621bf93f7e02cdf30b0e0fff2648f7`.

| Probe | Request bytes | Native schema bytes | Input / output tokens | Provider latency | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Exact extraction baseline | 18,795 | 6,834 | 2,243 / 197 | 987 ms | Invalid JSON |
| Minimal closed object | 876 | 142 | 146 / 36 | 466 ms | Invalid JSON |
| Minimal root union | 1,156 | 262 | 175 / 30 | 400 ms | Invalid JSON |

All three responses were HTTP 200 with `end_turn`. Actual total usage was **2,827
tokens**. The minimal object returned:

```text
{"{ "kind":"present","value":"orchard" }
```

The union returned the same malformed opening. Both use the same small task and
input from the existing [object](../src/test_fixtures/bedrock-json-object.edit.json)
and [union](../src/test_fixtures/bedrock-json-union.edit.json) fixtures. Expected
output is `{"kind":"present","value":"orchard"}`. The existing debugger extracted
provider text successfully, rejected JSON and left schema validation unavailable.
No result became a workflow candidate.

[Retained results and provenance](evidence/bedrock-json-2026-09-21/results.json)
link all six exact request/response bodies independently of rotating harness runs.
The smallest AWS reproduction is the [object request](evidence/bedrock-json-2026-09-21/object.request.json)
and [object response](evidence/bedrock-json-2026-09-21/object.response.json).
No authorization header or credential is included. Existing replay records do not
retain AWS response-header request IDs; do not invent IDs for these calls.

One earlier local replay rejected before dispatch because the debugger environment
lacked a credential. After stopping that session, the checkout's existing E2E
credential was explicitly supplied through `AWS_BEARER_TOKEN_BEDROCK`; production
credential sourcing was unchanged. That local rejection made no AWS call.

**Disposition:** the minimal-object failure removes the evidence for a
union-specific or complexity-specific production workaround. It does not prove
which provider component failed, or measure a reliability rate: there was one
observation per condition. The minimal task and schema both differ from the
baseline; only the object/union pair isolates schema. Further API/model comparisons
need a new bounded approval under [§28.8](../design/contracts/28-testing.md#288-model-conformance-comparisons).
The three-call approval is consumed. No support submission or E2E run was included.
Those probes shared `const` tags, complete-schema prompt guidance and low
reasoning. The separately authorized comparison below isolates the field
constraint through the same replay owner.

### 1.1 Plain string versus constant — completed follow-up

The user's follow-up implementation request authorizes two diagnostic calls through
the same replay owner: one [plain string](../src/test_fixtures/bedrock-json-string.edit.json)
and one [constant](../src/test_fixtures/bedrock-json-constant.edit.json). Each contains
one required `value` field in a closed object. Both ask for the package name from
`Package: orchard`; `{"value":"orchard"}` satisfies both. Only that field's schema
changes, from string to `const: "orchard"`. The complete string schema retains the
compiler-required length bound; existing native projection omits that unsupported
bound. This does not change the projection or any production schema.

Each condition ran once with no retries. Model, region, native mode, temperature
and reasoning remained those of the retained 00:41 request. No workflow, publication,
grading, API switch or support submission occurred. Existing replay tests cover
malformed text, successful admission and a different string value: the last passes
the string schema and rejects the constant schema while retaining exact usage.

| Probe | Request bytes | Native schema bytes | Input / output tokens | Provider latency | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Plain string | 777 | 108 | 133 / 25 | 317 ms | JSON and schema valid |
| Constant | 764 | 110 | 129 / 27 | 356 ms | Invalid JSON |

Both responses were HTTP 200 with `end_turn`; the two calls used **314 tokens**.
The string response was exactly `{"value":"orchard"}`. The constant response was
`{"{"value":"orchard"}`, failing syntax at byte offset 4. Provider text was retained
unchanged. See the [exact exchanges and provenance](evidence/bedrock-json-constant-2026-09-21/results.json).
Replay session: `debugger-d6f88ffc0f2a012a138d7c5c5984319e`; parent:
`RUN-6de5a0b2ff9d25fbf78242d8527460dd` / `request-1-inference-1`.

**Disposition:** `const` is associated with failure in this controlled pair. It is
not proof that all constants fail or that Bedrock's native grammar alone caused it:
the complete schema shown in the prompt changed alongside the native constraint.
One observation per condition establishes no reliability rate. The next useful
comparison is an equivalent representation of the same constant constraint, such
as a singleton native `enum`, while retaining complete-schema guidance and all
other settings. That comparison needs bounded approval and must cover scalar
constant kinds through the existing projection owner before any production change.
No more calls are authorized by this completed two-call comparison.

### 2. Use the result to choose the smallest remedy

| Established result | Appropriate response |
| --- | --- |
| Plain string passes; the same field constrained with `const` fails | Use the measured pair for AWS investigation or an approved equivalent-encoding comparison. Keep canonical constant/discriminator validation intact. |
| Minimal closed-object native output is malformed | Escalate to AWS with the reproducible request. Investigate the serving/API path before modifying workflow shapes. |
| Minimal output works, but a controlled union comparison fails | Reduce the reproduction and request AWS clarification of the supported subset. A demonstrated projection defect belongs in `model_schema_projection`; preserve the complete canonical schema and reject unsupported mappings. |
| Only the complete extraction request fails | Bisect schema/task complexity with controlled comparisons. Consider further configured decomposition only when it measurably helps and retains complete validation, dependencies and provenance. |
| Another supported model consistently handles the same representative requests better | Consider an explicitly approved model selection through existing registry/catalogue owners. Require semantic-quality results as well as valid JSON. |
| Another API route fixes the same-model failure | Consider an explicitly approved provider-contract amendment through the existing adapter. API migration is not a YAML workaround or automatic fallback. |

There is currently no second native-schema-capable model in SDDE's trusted registry:
the other registered model, Claude 3.5 Haiku, is prompt-only. Comparing a new model
or region therefore requires a reviewed capability registration and authorization,
not merely editing a model string. See the [provider contract](../design/features/F0007-AWSBedrockProvider.md#external-configuration-and-supported-contracts).

### 3. AWS escalation ready; submission requires approval

Provide the [passing/failing pair](evidence/bedrock-json-constant-2026-09-21/results.json),
its recorded UTC times, model/region/API and expected answer. The earlier 22:07 workflow supplied
these AWS request IDs for the same failure class:

- Call 1: `c1b21d85-f2c3-4d2f-9627-18f5cd9dff7a`
- Call 2: `503b752c-5db4-4612-a1bc-7120bb113981`
- Call 3: `04a55b17-f2dc-41fc-91d5-b6d4d5132684`

Ask AWS why the constant-constrained request returned invalid JSON while its
plain-string counterpart passed, whether native constraints were applied, and whether a serving defect or documented
workaround exists. Share no credentials; any support submission needs separate authorization.

## Changes not justified by current evidence

- Do not expand the approved normalization into arbitrary character stripping,
  partial-object acceptance, reasoning substitution or weakened validation.
- Do not add a JSON-repair library/agent or another retry loop. Existing corrections
  already carry errors and preserve assignment/schema ownership.
- Do not increase retries, temperature or output limits on speculation, or switch
  model/API/region silently. Each is a different experiment, not a proven fix.
- Do not add prompt/schema copies for each failure. A confirmed shared projection
  defect is fixed once at its owner; production schema changes require complete
  consumer, repair, persistence and regression coverage.

## Diagnostic comparison verification (before normalization)

Before normalization, the four diagnostic fixtures were consumed directly by the
existing request-debugger test. Coverage verified canonical schema compilation, native object/union/string/constant
projection, identical task inputs within each pair, fixed model/settings, immutable
parent linkage, one exchange per explicit replay, malformed-prefix rejection,
successful admission, constant-value enforcement and retained usage. Scripted replies
verified the diagnostic machinery, not the live model. That comparison changed no
production prompt, schema, retry owner or provider adapter. Historical failure
tables retain the results observed then; current debugger inspection may normalize
the same captured text without changing the original workflow outcome.

**Checks after the follow-up:** `zig build test-model-logging
--global-cache-dir .zig-cache/global --summary all` passed **95/95 tests** with
the extended cases. Full `zig build verify --global-cache-dir .zig-cache/global
--summary all` passed **128/128 steps and 1,704/1,704 tests**, including native
packaging and debugger smoke checks. Evidence: `.zig-cache/json-constant-tests.log`
and `.zig-cache/json-constant-verify.log`. Retained body lengths/digests, isolated
field-schema changes and token totals were checked; independent parsing confirmed
the pass/failure split. Documentation links, Zig formatting and `git diff --check`
passed. The observed plain-string success does not establish a production remedy.

Unrepairable JSON must continue to terminate with an error and no publication.
After offline normalization verification, obtain separate approval for a published,
scored E2E run. The completed diagnostics
and offline tests establish no improvement in live model reliability.

## Normalization implementation verification

The shared decoder, detailed/combined admission, runner logging and debugger now
follow §22.6. Regression coverage includes unrelated objects, valid brace-prefixed
keys, strict non-model parsing, remaining malformed/duplicate/trailing data,
schema rejection/recovery, original evidence, allocation cleanup and exact usage.
Independent offline parsing of the retained comparison captures confirms that all
four malformed responses become complete JSON objects after the two-byte removal;
the already-valid string response is unchanged. This establishes syntax recovery,
not schema/domain correctness or live workflow success.

**Verification:** `zig build test-model-request-workflow --global-cache-dir
.zig-cache/global --summary all` passed **217/217 tests**. Decoder, debugger and
logging/atomic-execution checks passed their targeted suites. Full `zig build
verify --global-cache-dir .zig-cache/global --summary all` passed **128/128 steps
and 1,710/1,710 tests**, including architecture, formatting and clean native
packaging/debugger smoke checks. Results: `.zig-cache/json-normalization-workflow.log`
and `.zig-cache/json-normalization-verify.log`. `git diff --check` passed.

Requests/prompts and provider wire bytes are unchanged. No live model call or E2E
run occurred; live reliability and a published, scored specification remain open.
