# ADR 0011: Provider-owned request limits; actual workflow token accounting

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Repeated explicit user direction; no further approval required
- **Scoped amendment:** 2026-10-10, explicitly user-approved optional slot output
  allowance. Other capacity, accounting and retry boundaries remain unchanged.
- **B9 amendment:** 2026-10-17, explicit user approval for feature-owned entities
  and diagnostic slot allowances of 2,048 tokens; no new cardinality caps or
  `output_limit` correction.
- **Advisory pool withdrawn:** 2026-10-17, by user direction; one total token limit.
- **Output allowance removed:** 2026-10-18, by explicit user direction: "there
  should be no output token limits". This supersedes the 2026-10-10 optional slot
  allowance and B9's 2,048-token diagnostic allowances. Provider-applied stops must
  be logged.
- **Model maximum output:** 2026-10-18, by explicit user direction ("Send model's
  max output"; 16,384 for `openai.gpt-oss-20b-1:0`; "yes, allow the max" for the
  grader). Omitting `maxTokens` did not apply the model's maximum: a live Bedrock
  response stopped at exactly 4,096 output tokens with no allowance sent. Each
  Bedrock model's documented maximum is now recorded and sent. See "Model maximum
  output".
- **Transport amendment:** 2026-10-15, explicit user direction to use Bedrock
  Converse for model switching. This replaces the previous chat wire mapping only.
- **Amends:** Design Sections 3, 9, 12–13, 17, 20, 22, 24, 28 and 31; ADRs 0004–0006;
  F0001, F0005–F0007; and their samples and diagrams
- **Amended by:** [ADR 0030](0030-engine-owned-model-request.md) (22 October 2026, not
  yet implemented). A request's protocol correction runs inside its `request-model`
  step under that step's `retry-limit`, not as an explicit YAML transition. The runner
  still accounts every attempt's actual usage against the one workflow budget. Its
  23 October 2026 amendment removes CountTokens and all provider token counting, and
  adds a required `requestTimeoutMs` beside `maxOutputTokens` in every catalogue entry
  (see "Model maximum output"). Actual-usage accounting is unchanged.

## Decision

### Provider-owned per-call limits

- The called provider API owns its request, response and context-size limits.
- SDDE does not impose additional engine-enforced byte/token capacity ceilings on
  model calls through operations, slots, model contracts or transport.
- It does not predict whether a request or response will fit, narrow a request to a
  local ceiling, or reject a call because an estimated input or output is too large.
- Provider rejections and stopped responses are normalized, recorded safely and
  propagated as typed outcomes.

- There are no model-call `input-bytes`, `output-bytes`, `input-tokens` or
  `output-tokens` YAML parameters, capacity-intersection contracts, receive/wire byte
  budgets, serialized-size proofs or static-capacity gates.
- Renaming these restrictions as memory safety, transport budgets or provider-contract
  facts does not make them permitted.
- Missing values for these retired contracts are not configuration errors,
  implementation prerequisites or approval questions.

### No output-token allowance

Amended 2026-10-18 by explicit user direction. A requested allowance truncates
output and degrades results, so SDDE never sends one below the model's documented
maximum (see "Model maximum output").

- No slot, model contract, binding, prepared request, correction or replay can
  narrow the output maximum. The provider catalogue (and the grader's evaluator
  configuration) is the stated authority for that maximum and must record the
  model's documented value; the engine does not verify it against the provider.
- The closed configuration rejects `models.slots.<slot>.maxOutputTokens`.
- Request descriptions advanced to `model-request-debug/v7`, which had no allowance
  field. Older captures stay historical evidence, read only by their explicit
  historical readers.
- The model's own maximum is the only output ceiling. When a provider stops a
  response for any non-candidate reason, including that maximum, the runner logs
  `model.provider_stopped` at warning level with the exact stop reason. Actual usage
  is still accounted, and the typed outcome is unchanged. SDDE does not retry,
  clamp, truncate or invent a fallback because of a stop.

### Model maximum output

Amended 2026-10-18 by explicit user direction. Bedrock applies a default smaller
than a model's maximum when a Converse request omits `inferenceConfig.maxTokens`
(GPT-OSS-20B stopped at exactly 4,096), so omission is itself a hidden limit.

- Each Bedrock entry in the provider catalogue records the model's documented
  maximum output as `providers[].models[].config.maxOutputTokens`: required,
  positive and exact, with no default, runtime lookup, clamp or fallback. The
  shipped value for `openai.gpt-oss-20b-1:0` is 16,384: AWS documents "16K", and
  retained calibration runs show Bedrock accepts and reaches a 16,384 allowance for
  this model in `ap-southeast-2`.
- Under [ADR 0030](0030-engine-owned-model-request.md) as amended on 23 October 2026 (not yet implemented),
  every catalogue entry also declares a required positive `requestTimeoutMs`: the
  provider-operation deadline, sized to the time the model takes to return this
  maximum. It replaces the workflow's `timeout-ms`.
- The frozen semantic-simplicity protocol (schema 2) records the same maximum, and
  its binding checks reject a request or description carrying any other value.
- Every Bedrock inference request sends that value as `inferenceConfig.maxTokens`
  unchanged; CountTokens requests carry none. All slots selecting the entry share
  it, and no slot, binding or request can narrow it.
- The development grader's `evaluation-config/v2` records its judge model's
  documented maximum as `max_output_tokens`, sent the same way.
- Request descriptions advance to `model-request-debug/v9`, whose provider
  configuration carries the value, so replay sends the same request.
- A value the provider rejects is a typed provider rejection. A stop at the
  maximum is still logged as `model.provider_stopped`.

### Workflow token accounting

There is one total limit: the native workflow policy's positive
`totalModelTokenBudget`, currently **100,000 tokens**, initialized freshly for every
execution. It covers all model work, including post-generation source and principle
advice, which has no pool or allowance of its own. Native advisory classification
controls only the permitted non-budget incomplete-assessment outcome; it does not
partition token usage.

- Record actual API-reported input plus output tokens after every inference call,
  including retries and stopped output, exactly once against that total.
- For Converse, normalize input usage as `inputTokens + cacheReadInputTokens +
  cacheWriteInputTokens` (absent optional cache counters are zero), then add
  `outputTokens`. Check arithmetic and reported `totalTokens`; invalid usage is
  unavailable for accounting and remains a fatal native validation failure.
  Genuinely missing usage on otherwise valid advisory evidence may instead end
  advice as incomplete. This follows the
  [AWS cache accounting contract](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html).
- Any inference call may overshoot: retain its full usage, return
  `WorkflowTokenBudgetExceeded`, and prohibit further model calls globally.
  The same fatal budget rule applies during required work and advice; global
  exhaustion or overshoot cannot produce incomplete advice. At exact equality the
  admitted current result may proceed, but no further model call may start.
- Missing usage is never estimated or fabricated. It prohibits further model
  calls. Missing usage during advice records incomplete advice and may continue
  through native validation and publication; missing usage during required work
  retains its ordinary workflow failure.
- No pre-call token reservation, mandatory counting, capacity prediction,
  budget-derived output allowance or per-class usage subtotal exists. Trusted association,
  native validation, security, cancellation, deadline, logging and operational failures
  remain blocking; incomplete advice is not a blanket failure-to-success route.

### B9 runaway-output policy

B9's 2,048-token `spec_generation` and `repair` allowances were withdrawn on
2026-10-18 with the whole control (see "No output-token allowance"). Runaway output is
now bounded only by the model's own documented maximum, sent explicitly (see "Model
maximum output"), and the execution's total token budget.
Each stop is logged as `model.provider_stopped`. Historical captures and frozen
calibration settings remain unchanged and cannot acquire current binding authority
by substitution.

No per-family record cardinality cap is added. Under §17, entity records are
instead authored once by the feature-wide entities unit, with independent support
selections and native ownership checks. Other record batches cannot emit entities.
A provider `output_limit` remains a typed non-candidate stop: partial text never
becomes a candidate, is never salvaged, and receives no extra protocol correction.
Mandatory work fails; advisory work records incomplete advice under its native
assessment policy. The model binding and existing explicit protocol retry rules
otherwise remain unchanged.

### Retry and safety boundaries

- Retries remain explicit YAML transitions with operation-local `retry-limit`.
- Provider adapters do not retry, truncate, repartition or select fallback calls on
  their own.
- Only complete responses can become untrusted candidates.

- Exact request identity, model-slot authorization, supported controls, schema
  validation, credential protection, cancellation and deadlines remain required.
- Existing configuration/resource-read, logging, command and closed-schema constraints
  keep their separate responsibilities; they cannot be repurposed as model-call size
  ceilings.

## Acceptance

- The typed model-slot parameter is the sole new-binding selection; ADR 0012 allows
  consumers to retain that request through typed data dependencies. No capacity
  field, intersection, wire budget or static-capacity service exists.
- Fake-provider and compiler tests cover rejected retired size parameters,
  registration/preparation without capacity configuration, complete valid payloads
  beyond former byte ceilings, preserved size failures/stops and schema rejection.
- Tests cover rejection of a slot `maxOutputTokens`, the catalogue maximum's
  required positive value, its exact `maxTokens` in every Bedrock inference request
  and absence from CountTokens, rejection of a description carrying the retired
  field, and `model.provider_stopped` for every closed stop reason, including
  log-failure propagation. Provider maxima are not encoded as local capacity checks.
- Accounting tests must cover the single aggregate ledger across all inference,
  full overshoot retention, global subsequent-call prohibition, unavailable usage,
  execution isolation and explicit-only retries. Global-budget failures must stay
  fatal during advice as well as required work. Native advisory continuation must
  retain current incomplete-assessment evidence and all mandatory publication checks.
- Architecture tests require the retired capacity fields and local size-failure variants
  to remain absent.
- Configuration/resource capture bounds retain separate negative tests.
