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

[ADR 0018](../decisions/0018-debug-model-exchange-logging.md) requires `debug` and
`trace` to capture every production model attempt's complete assembled request and
available raw returned body in the registered prompt stream. This includes prompts,
format guidance, schema, reference/code inputs, malformed output and failed attempts.
Capture is attempted before response admission or disposal; retries retain separate attempt
attribution. A failed attempt with no body has a typed `transport_outcome` record
distinct from actual `provider_body` bytes. Interrupted transport also captures
all received bytes as `partial_provider_body`; their provenance never claims a
complete response. The event stream remains metadata-only.
The selected graph activates its feature log after deterministic reference preflight.
A run-local directory capability binds newly created roots to subsequent reads and
publication. Shared publication and terminal barriers finalize the active sink;
close failure blocks before completion-state publication.

Redact the invocation's authorized credential values before splitting content into
ordered bounded fragments. Valid UTF-8 is retained directly; invalid UTF-8 uses
encoding-tagged base64. Reconstruction preserves the complete sanitized body without
truncation; a storage failure follows the existing fail-closed path after required
provider usage accounting. `logs.level` alone selects capture; higher thresholds
emit metadata only and the removed `promptCapture` field rejects. Prompt records
keep their registered `debug` severity and the configured event threshold.

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
