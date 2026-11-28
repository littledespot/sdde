# ADR 0039: Configured temperatures; one re-send after a runaway

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision authority:** User decisions, 26 and 27 October 2026 and 1 November 2026
- **Amends:** ADRs [0009](0009-atomic-workflow-execution.md),
  [0011](0011-provider-owned-request-limits.md),
  [0012](0012-workflow-owned-model-request.md),
  [0019](0019-single-request-debugger.md), [0029](0029-bedrock-model-families.md) and
  [0030](0030-engine-owned-model-request.md); the AGENTS.md evidence rule against
  sampling changes and extra retries, as an explicit engine-policy exception; §9, §12,
  the §13 model actions, the
  [model-request operation catalogue](../contracts/model-request-operations.md), §22, §27,
  §31.12, F0001, F0002, F0006, F0007, F0100, the [E2E harness](../harness/e2e.md) and the
  [evaluator](../harness/evaluator.md). The overall design remains **Proposed design**.

## Context

A model sometimes keeps writing until it reaches its maximum output, mostly blank lines
after a valid answer. The provider then stops it with `output_limit`. The partial text
has no value and is never kept.

## Decision

1. **Two configured temperatures.** `.sddtoolkit.json` has two required root members:
   - `temperature`: sent on every inference request;
   - `temperatureRunawayRetry`: sent on a runaway re-send (Decision 2).

   Each is a JSON number, zero or greater, with no engine default. The closed
   configuration type decodes both once at bootstrap. A missing, negative, quoted, null
   or duplicate value fails as `ENGINE_CONFIG_PARSE_ERROR`.
   - The provider owns its accepted range. A value it rejects is a typed provider
     rejection (ADR 0011), not a configuration rule.
   - A model whose registered contract sends no temperature (the `converse`, `luna`
     and `claude` Bedrock families, and the Anthropic Messages API) still omits it on
     every attempt, including the re-send.
   - Workflow definitions can't set or override a temperature.
2. **A runaway is re-sent once.** A runaway is a response the provider stopped with
   `output_limit`.
   - Its partial text never becomes a candidate and is never sent back to the model; at
     `debug` it is logged in full (Decision 4).
   - The engine sends the identical request again: the same messages, schema, guidance,
     binding and maximum output, with `temperatureRunawayRetry` as the only change.
   - The re-send isn't a protocol correction. It carries no diagnostic, doesn't include
     the partial text and doesn't use the step's `retry-limit`. Every request step gets
     it, including one with `retry-limit: 0`.
   - Its response is handled like any other (Decision 5). A failed check takes the
     ordinary protocol correction under the step's `retry-limit`. A correction is an
     ordinary attempt and is sent at `temperature`.
   - The rule applies to each attempt. A protocol correction that runs away is re-sent
     once in the same way.
   - A runaway on the re-send ends the request with the diagnostic `RunawayRepeated`,
     naming the step, the runaway attempt and its re-send. The workflow stops with that
     error.
   - Other stop reasons and provider failures are unchanged.
   - Two single-responsibility stages of the `request-model` step carry it. Response
     admission admits a first runaway (an `output_limit` stop with valid usage, on an
     attempt that isn't itself a re-send) as `invalid` with no candidate, like a missing
     final answer, so a later accepted response clears it. The runaway check then routes
     a re-sendable runaway to the re-send stage, which builds the re-send, and everything
     else to the protocol correction. A repeated runaway is admitted as `failed`.
   - Attempt accounting reserves the re-send with its own count, one per attempt, and
     the step's allowance is 2 x (1 + `retry-limit`) provider calls: each attempt, with
     its one re-send. The `request-model` orchestrator returns the re-send to attempt
     accounting (ADR 0030).
   - The route is fixed in the orchestrator, not checked per workflow: an admission's
     `invalid` continues to the runaway check, whose re-send branch reaches the re-send
     stage, and a re-send is reachable only from that branch. A runaway takes the
     re-send, not the correction; an invalid response takes one protocol correction.
   - A re-send must equal the attempt it repeats in every request field except its
     sampling, and attempt accounting rejects a second re-send of one attempt.
3. Withdrawn. The number is kept so that Decisions 4 and 5 keep theirs.
4. **Accounting and evidence.**
   - Both attempts' actual usage counts once each against the one workflow budget
     (ADR 0011). Overshoot stays fatal.
   - Each stop still logs `model.provider_stopped`.
   - **Every re-send is logged.** Before the re-send is sent, the runner emits one
     warning `model.runaway_resent` for the runaway attempt: its operation, slot,
     `OUTPUT_LIMIT` diagnostic and reported tokens. The re-send is then its own attempt,
     with its own `model.requested` and `model.completed` events under the next attempt
     number. A re-send that runs away also logs its own `model.provider_stopped`, and
     the request's failure events carry `RunawayRepeated`. The event is emitted at the
     re-send's provider-call step, after the step allowance, accounting, assignment,
     authorization and token-budget checks pass and immediately before the send, so a
     refused re-send is never logged as re-sent and a logging rejection prevents the
     send.
   - **At `debug` or `trace`, every runaway is logged in full**, through
     [ADR 0018](0018-debug-model-exchange-logging.md)'s capture. For the runaway attempt
     and for its re-send, the prompt log keeps the complete assembled request, its request
     description (both configured temperatures and the sampling), the provider request
     with the temperature it sent, and the complete returned output with the provider's
     stop reason and token counts. A repeated runaway's output is logged before the
     failure events and the stop. Higher levels log only the events above.
   - Each request and provider operation records its sampling: `configured` or
     `runaway_resend`. The temperature sent follows from it and the binding's two
     configured temperatures. Request descriptions record both temperatures and the
     sampling, so replay sends the same bytes, and authorization leases, invocation
     validation and attempt accounting check the sampling. Replay refuses a description
     that records no sampling.
   - The E2E report's `attempts` mark each re-send with `resends`, the attempt it
     re-sends, so a run's runaways, re-sends and their outcomes can be counted.
5. **Every retry response passes the same checks.** A re-sent response, like every
   protocol correction's response, goes through exactly the checks a first response
   does, in the same order: observation and usage validation, envelope decoding,
   payload-schema validation, the native admission constraints (assignment membership,
   statement exclusivity and claim agreement), domain validation, the evidence and repair rules, and every
   publication check. No check is skipped, relaxed or reordered for a retry, and a
   retry response can't be accepted on less evidence than a first response. A retry
   that succeeds removes no earlier failure from the logs or the report.

## Consequences

- **Evidence policy.** AGENTS.md forbids working around a model limitation with
  "sampling changes, extra retries". This rule is the user's explicit exception to it,
  recorded like the evaluator's one mechanical correction. It covers only a provider
  `output_limit` stop: it gives no other model limitation a retry or a sampling change.
  Development reports count runaways and re-sends, and what each re-send returned,
  separately.
- **Cost.** A re-send costs a full second request. The first runaway still costs its
  full output, and a re-send that runs away again costs the same.
- **Families without a temperature.** Their re-send is the identical request. Whether
  it avoids a second runaway is unmeasured.
- **Persistence.**
  - Every `.sddtoolkit.json` must state both temperatures, with no compatibility reader.
  - Frozen calibration protocols keep their recorded temperature, and their binding
    checks compare the recorded temperature value and reject a re-send capture, so a
    runaway in a frozen experiment fails before its re-send is sent.
- **Harness.** The standalone evaluator's Bedrock temperature comes from its own
  `evaluation-config/v2` value, not from an engine constant.
