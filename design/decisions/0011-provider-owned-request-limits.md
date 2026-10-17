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
- **Transport amendment:** 2026-10-15, explicit user direction to use Bedrock
  Converse for model switching. This replaces the previous chat wire mapping only.
- **Amends:** Design Sections 3, 9, 12–13, 17, 20, 22, 24, 28 and 31; ADRs 0004–0006;
  F0001, F0005–F0007; and their samples and diagrams

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

### Optional provider-request output allowance

- `models.slots.<slot>.maxOutputTokens` is an optional positive integer request
  control. Closed decoding checks positivity and native integer representability;
  the registered model contract must support the control.
- When present, send the requested value unchanged. When absent, omit the provider
  field and delegate its default to the provider. Bedrock `Converse` maps the
  control to `inferenceConfig.maxTokens` through the shared request encoder.
- This is a provider-enforced requested allowance, not an engine capacity ceiling
  or a claim that the response will fit. The API still owns its supported maximum
  and any rejection or stopped-response outcome. SDDE does not predict, reserve,
  clamp, truncate, invent a fallback or add retries because of this control.
- Configuration, validated slot/binding, prepared request and authorization retain
  the same optional control. Correction retains the originating binding; capture
  records its exact presence/value, and replay retains those captured settings
  while validating them against the current binding. Current configuration cannot
  silently replace a captured allowance.
- This amendment does not add an evaluator setting, a YAML size parameter or a
  cumulative budget-derived allowance. It does not alter actual-usage accounting.

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

The per-slot provider request allowance remains the existing optional control.
Both current diagnostic cases share the source configuration at
`test/e2e/wf-001-hello-world/.sddtoolkit.json`, which explicitly requests **2,048**
output tokens for `spec_generation` and `repair`. This is a diagnostic setting,
not an engine default, provider-maximum assertion or size ceiling, and no promise
that future assignments fit. Historical captures and frozen calibration settings
remain unchanged and cannot acquire current binding authority by substitution.

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
- Output-allowance tests cover omission, positive values, invalid types/ranges,
  unsupported controls, exact wire projection and changed-control rejection across
  binding, authorization, correction, capture and replay. Provider maxima are not
  encoded as local capacity checks.
- Accounting tests must cover the single aggregate ledger across all inference,
  full overshoot retention, global subsequent-call prohibition, unavailable usage,
  execution isolation and explicit-only retries. Global-budget failures must stay
  fatal during advice as well as required work. Native advisory continuation must
  retain current incomplete-assessment evidence and all mandatory publication checks.
- Architecture tests require the retired capacity fields and local size-failure variants
  to remain absent.
- Configuration/resource capture bounds retain separate negative tests.
