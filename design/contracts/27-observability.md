# 27. Observability

Part of the [proposed design](../design.md#27-observability). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

- The runner constructs one pure `WorkflowLog` binding from the selected compiled workflow's
  registry-validated four-character shortcode.
- Actions call `workflowLog.log(&delta, fact)` to append attributed telemetry without performing
  I/O; runner lifecycle facts use the same active binding.
- The resulting `NodeDelta.telemetryFactsAdded` values pass through the discrete logging actions
  described in Section 13.9.

[View the Observability events sample](../code.md#observability-events).

[View the feature logging pipeline](../diagrams/06-feature-logging.md).

Event fields include the validated four-character workflow shortcode, run/feature/stage/node IDs, parent/correlation IDs, attempt, duration, workflow model-operation/model-slot identity, token usage, diagnostic codes, repair unit kind, command ID, exit code, and evidence status. Field definitions are registry-owned and sensitive content is excluded or redacted before serialization.

- Candidate diagnostics retain typed rule, target, rejected value and admissible scope.
- The producing request's assignment position in the existing identity ledger, attempt ordinal
  and operation kind survive request-body release and join only to the current execution's
  operation ledger.
- Repair updates origin only for its selected replacement; untouched siblings retain their
  original call attribution.
- Console, event and report projections consume this evidence without parsing model text again
  or creating repair authority.

Useful metrics:

- model calls and tokens by stage/unit;
- initial-pass and post-repair validation rate;
- repairs by diagnostic code and preset;
- average atomic repairs per accepted unit;
- schema-failure rate by workflow model operation;
- preset path rejection rate;
- command pass/failure duration;
- task throughput and blocked dependency count;
- abandoned workflow execution count;
- unsupported reference formats.
- authority-reconciliation outcomes and gap reasons by earliest owner and requirement kind, including upstream-rework and administrative-block counts.

The metrics distinguish deterministic rejection from semantic-review rejection. This is necessary to see whether failures come from model capability, poor initial guidance, preset errors, or repository problems.
