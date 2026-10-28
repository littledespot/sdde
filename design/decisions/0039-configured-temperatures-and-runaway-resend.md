# ADR 0039: Configured temperatures; one re-send after a runaway

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision authority:** The user's decisions on 26 October 2026 on
  [FIX05](../../fixes/Z_FIX05.md#21-fix05-retired--28-october-2026) B9:
  - "if a run away issue occurs, then the the retry tempreture should be set to 1 and
    the same request should be tried again, if that fails then the workflow should stop
    executing";
  - "the respose must not be kept because it has no values … if a run away respose is
    given, then the same input request should be tried with a tempreture of 1, if the
    response back is still runaway then the workflow should stop with an error. if
    there is a no runaway response then is should be evaluated as all other responses";
  - "temperture must be configurable and should be loaded out of the .sddtoolkit, there
    should be temperture and temperture_runaway_retry";
  - "it must be logged if ht model fail on the first attempt and then retryed, the retry
    responses must all pass through the same validation checks";
  - on 27 October 2026: "if a run away error occurs on the first run then all the details
    should be logged of loglevel is debug then the same request should be tried with
    temperatureRunawayRetry and if the same issue occurs again then with workflow should
    be stopped and all the info should be logged if log level is debug" (Decision 4's
    debug capture). Asked whether a second runaway in a review step should also stop
    the run, the user accepted the recommendation that it doesn't ("update the docs with
    the above recommendations"): review keeps Decision 3 and ADR 0040.
- **Amended by:** [ADR 0040](0040-incomplete-review-published-marked-logged.md) (26
  October 2026, the user's "incomplete results must be published, but it must be
  indicated that the results are incompelete, and it must also be logged"): in advisory
  work, a runaway on the re-send ends that advice as incomplete, published, marked and
  logged, instead of stopping the workflow. Required work still stops. This text
  already reflects it.
- **Amended by:** [ADR 0041](0041-failed-run-incomplete-publication.md) (26 October
  2026): when required work stops on a repeated runaway, the run publishes its validated
  content as a failed incomplete specification, marked and logged.
- **Amends:**
  - [ADR 0011](0011-provider-owned-request-limits.md): a provider `output_limit` stop is
    re-sent once instead of ending the request ("SDDE does not retry … because of a
    stop", "receives no extra protocol correction", and the B9 amendment's "no
    `output_limit` correction"); advisory `output_limit` ends advice as incomplete only
    when the re-send also runs away;
  - [ADR 0012](0012-workflow-owned-model-request.md) and §12.5: the project
    configuration supplies the temperature; it is no longer engine-fixed at `0.1`;
  - [ADR 0023](0023-advisory-post-generation-review.md): an output-limit stop is re-sent
    before it can end advice as incomplete;
  - [ADR 0030](0030-engine-owned-model-request.md): the request's child graph gains
    the re-send beside its protocol correction;
  - [ADR 0009](0009-atomic-workflow-execution.md): "only explicit YAML transitions and
    operation-local `retry-limit` authorize retries" gains the re-send;
  - [ADR 0019](0019-single-request-debugger.md): request descriptions advance to
    `model-request-debug/v13`;
  - [ADR 0029](0029-bedrock-model-families.md): the `gpt-oss` family sends the
    configured temperature instead of `0.1`;
  - the evidence rule (now in AGENTS.md) against sampling changes and extra retries, which
    records this as an explicit engine-policy exception;
  - §9 (configuration shape and retry defaults), §12 (model controls, stops and
    `model-request-debug/v13`), the §13 model actions (a new
    `build-model-runaway-resend` action and the attempt-accounting rule), the
    [model-request operation catalogue](../contracts/model-request-operations.md),
    §17.3 (advisory review stops), §22 (correction bounds), §27 (attempt events),
    §31.12, the configuration schema
    and example, F0001, F0006, F0007, F0100, the [E2E harness](../harness/e2e.md), the
    [evaluator](../harness/evaluator.md), the README and the §32 index;
  - F0002 (the `model.runaway_resent` event and the `RunawayRepeated` diagnostic) and
    the E2E report (`spec-e2e-report/v10`).

  The overall design remains **Proposed design**.

## Context

GPT-OSS-20B, under schema-constrained decoding at temperature `0.1`, sometimes keeps
writing until it reaches the model's 16,384-token maximum, mostly blank lines after a
valid finding (FIX05 B9). The provider then stops it with `output_limit`. The partial
text has no value and has never been kept. Loan-renewal source review ran away four
times on exact-value subjects, at about 19,000 to 20,000 tokens each.

Under ADR 0011, a required runaway failed the run, and an advisory runaway ended that
advice as incomplete at once, so one runaway was enough to lose a finding. The
temperature was a compiled engine constant, so projects couldn't choose it.

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
   - Workflow definitions still can't set or override a temperature.
   - The shipped E2E configuration sets `temperature` to `0.1` and
     `temperatureRunawayRetry` to `1`.
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
     naming the step, the runaway attempt and its re-send.
     - In required work the workflow stops with that error. It publishes only its
       validated content, as a failed incomplete specification
       ([ADR 0041](0041-failed-run-incomplete-publication.md)).
     - In advisory work that advice ends incomplete (Decision 3).
   - Other stop reasons and provider failures are unchanged.
   - Two new single-responsibility actions carry it. Response admission admits a first
     runaway (an `output_limit` stop with valid usage, on an attempt that isn't itself a
     re-send) as `invalid` with no candidate, like a missing final answer, so a later
     accepted response clears it. `check-model-runaway` then routes a re-sendable
     runaway to `build-model-runaway-resend`, which builds the re-send, and everything
     else to the protocol correction. A repeated runaway is admitted as `failed`.
   - Attempt accounting reserves the re-send with its own count, one per attempt, and
     the compiled step allowance includes one re-send for each attempt it admits. Until
     ADR 0030's `request-model` step lands, the shared request-lifecycle subgraph routes
     the re-send back to attempt accounting.
   - The compiler enforces the route for every workflow: when a response admission's
     `invalid` continues to another step, that step must be `check-model-runaway`, whose
     re-send branch must reach `build-model-runaway-resend`, and a re-send is reachable
     only from that branch. An admission whose `invalid` ends the run directly is
     exempt, because it continues nothing.
   - A re-send must equal the attempt it repeats in every request field except its
     sampling, and attempt accounting rejects a second re-send of one attempt.
3. **An advisory runaway is re-sent before it can end advice.** Only a runaway on the
   re-send ends that advice as incomplete, with ADR 0023's `provider_output_limit`
   reason. Like every incomplete review, it is published, marked in the output and
   logged ([ADR 0040](0040-incomplete-review-published-marked-logged.md)). ADR 0023's
   other incomplete-advice reasons are unchanged.
4. **Accounting and evidence.**
   - Both attempts' actual usage counts once each against the one workflow budget
     (ADR 0011, ADR 0037). Overshoot stays fatal.
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
     failure events and the stop. Higher levels log only the events above. The 26 October
     hello-world run shows it: the runaway attempt sent at `0.1` and its full output
     (`max_tokens`, 16,384 output tokens), then the re-send sent at `1` and its response.
   - Each request and provider operation records its sampling: `configured` or
     `runaway_resend`. The temperature sent follows from it and the binding's two
     configured temperatures. Request descriptions record both temperatures and the
     sampling, so replay sends the same bytes. `model-request-debug` advances to v13,
     and authorization leases, invocation validation and attempt accounting check the
     sampling.
   - The E2E report's `attempts` mark each re-send with `resends`, the attempt it re-sends, so a run's
     runaways, re-sends and their outcomes can be counted. `spec-e2e-report` advances to
     v10.
5. **Every retry response passes the same checks.** A re-sent response, like every
   protocol correction's response, goes through exactly the checks a first response
   does, in the same order: observation and usage validation, envelope decoding,
   payload-schema validation, the native admission constraints (assignment membership
   and scenario coverage), domain validation, the evidence and repair rules, and every
   publication check. No check is skipped, relaxed or reordered for a retry, and a
   retry response can't be accepted on less evidence than a first response. A retry
   that succeeds removes no earlier failure from the logs or the report.

## Consequences

- **Evidence policy.** AGENTS.md forbids working around a model limitation with
  "sampling changes, extra retries". This rule is the user's explicit exception to it,
  recorded like the 18 October 2026 evaluator correction. It covers only a provider
  `output_limit` stop: it gives no other model limitation a retry or a sampling change.
  Development reports count runaways and re-sends, and what each re-send returned,
  separately.
- **Cost.** A re-send costs a full second request. The first runaway still costs its
  full output (about 19,000 tokens for GPT-OSS-20B), and a re-send that runs away again
  costs the same.
- **Families without a temperature.** Their re-send is the identical request. Whether
  it avoids a second runaway is unmeasured.
- **Persistence.**
  - Every `.sddtoolkit.json` must state both temperatures. The closed schema, the
    example and all fixtures change together, with no compatibility reader.
  - `model-request-debug/v12` descriptions no longer decode, so earlier captures can't
    be replayed.
  - `spec-e2e-report` v9 reports no longer decode, so `adjudicate-spec` on this build
    can't adjudicate the retained v9 runs; several were made by uncommitted builds. On
    27 October 2026 the user accepted that they stay unadjudicated (FIX05 R8).
  - Frozen calibration protocols keep their recorded `0.1`, and their binding checks
    compare the recorded temperature value and reject a re-send capture, so a runaway in
    a frozen experiment fails before its re-send is sent.
- **Harness.** The standalone evaluator's Bedrock temperature comes from its own
  `evaluation-config/v2` value, no longer from an engine constant.
- **Tests.**
  - Configuration: accepted `0`, `0.1` and `1`; rejected missing, negative, quoted,
    null and duplicate values for each member.
  - Request building: the configured `temperature` on every attempt of a temperature
    model; omission on both attempts for a family without one.
  - The re-send: identical bytes except the temperature; sent at a `retry-limit: 0`
    step; its admitted response publishes; its invalid response takes a correction at
    `temperature`; a correction that runs away is re-sent; a second runaway fails a
    required request with `RunawayRepeated` and ends an advisory request's advice
    incomplete with `provider_output_limit`; both attempts' usage is accounted.
  - Logging: one `model.runaway_resent` warning before each re-send, after the
    runaway's `model.provider_stopped`; none for any other stop; a logging rejection
    prevents the re-send; the failure events carry `RunawayRepeated`.
  - Debug capture: at `debug`, a repeated runaway leaves both attempts' requests, request
    descriptions and complete returned outputs in the prompt log before the failure
    events; at a higher level, only the events.
  - Same checks: a re-sent response is rejected exactly as a first response would be
    for malformed JSON, a schema violation, a missing assignment member and an
    uncovered scenario claim, and the E2E report marks the re-send attempt.
  - Replay: a v13 description round-trips each temperature, and a v12 description is
    refused.
