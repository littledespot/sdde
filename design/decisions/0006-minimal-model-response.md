# ADR 0006: Minimal model responses with runner-owned correlation

- **Status:** Accepted design amendment; implementation pending
- **Date:** 2026-09-05
- **Decision authority:** User direction to derive a token-efficient response
  standard and update documentation without code changes
- **Amends:** Design Sections 12.3, 12.7 and 22.4; F0006; F0007 Section 7
- **Supersedes:** The metadata-bearing model response and repair-response
  examples in `design/code.md`, and F0007's requirement to echo those identities

## Decision

`model-envelope/v1` names the engine's response-binding protocol, not a field
the model must reproduce. The model returns **one closed JSON result object**
conforming to the exact workflow-declared result schema. That object is the
whole model-visible response: no universal `result`, `payload` or `data`
wrapper, protocol-version field, or echoed execution metadata.

The compiled request selects exactly one shape:

- **One result variant:** return its declared candidate fields directly. Do
  not add a constant result-kind discriminator that the engine already knows.
- **Multiple result variants:** use one required root `kind` with distinct
  schema-declared literal values, plus that variant's fields directly. Each
  variant is a closed object; unknown kinds, mixed variants and extra fields
  reject. This is schema specialization, not two readers or an optional mode
  selected by the response.

Nested domain unions may retain their own necessary discriminators. No common
wrapper is inserted around them. Generation, clarification, context selection
and repair use this same rule; their allowed variants still come only from the
selected generic operation and YAML-declared schema. A discriminator classifies
candidate data, never chooses a node, retry, tool, approval or completion.

For example, a single-target replacement response is simply:

```json
{"replacement":"src/components/LoginForm.tsx"}
```

The authorization, expected revision, diagnostic, target and old-value
precondition are retained by the engine; the string grants no write authority.

## Information ownership

The runner retains the protocol version and exact request, attempt, provider
operation, workflow operation, unit, model binding, model-visible-input and
result-schema identities. Repair authorization and candidate revision remain
in that request's existing trusted context. Reuse those immutable authorities;
do not introduce a second correlation registry or a model-owned copy.

Before decoding, the engine validates the observation's association with the
exact invoked operation and current lifecycle. The decoded candidate retains
that association through validation, repair and commit. Unknown, stale or
foreign observations reject; they cannot be assigned to the latest request,
matched by arrival order, or correlated from model text. Losing the trusted
association loses the result; an echoed identifier cannot restore it.

`ValidateModelRequestBindingAction` owns pre-call request-ledger proof;
`ValidateProviderInvocationObservationAction` owns post-call association and
complete-result eligibility. `DecodeModelEnvelopeAction` parses the complete
JSON object; `ValidateModelPayloadSchemaAction` validates its bound result
schema. The proposed echo-checking `ValidateModelRequestIdentityAction` is
removed, not retained as a second identity authority.

Only data the model must supply or select belongs in its response: candidate
values, required evidence/citations, selected allowed IDs and necessary domain
discriminators. Preserve keyed multi-item association, such as repair
`replacementsByTargetId`, and validate the exact authorized key set; array
position is not a substitute. A fixed single target needs no echoed target ID.
Clarification IDs, ownership and deduplication remain engine-owned, while any
necessary subject selection and supporting evidence remain candidate data.

This is a semantic boundary, not a global ban on property names. A business
schema may legitimately declare a field named `status` or `requestId`; that
field never becomes engine status or request identity. Unrequested execution
metadata and the superseded outer envelope reject as unknown fields.

Provider failure, cancellation, stopped output, usage and latency remain in
F0006's separate typed observations. They are not model-generated result kinds.
Repair operation selection, authorization/revision checks and old-value CAS
remain mandatory even though their identities are not echoed.
`ValidateRepairEnvelopeAction` checks the retained repair authorization,
diagnostic and current candidate revision; it does not repeat generic
provider-observation validation.

## Schema, tokens and decoding

The selected result schema describes the entire compact response, not an
inner payload. Its exact captured resource and compiled contract determine the
allowed properties, required values, variants and finite bounds. No open
payload, model-selected schema, arbitrary executable validator or inferred
undeclared variant is admitted. Unsupported schema features reject before invocation;
this decision does not authorize a general-purpose JSON Schema engine.

Schema/version selection stays in compiled authority. Native output mode
receives the same complete semantic schema as prompt-only mode; a provider
must prove representability before using native mode. There is no silent
downgrade, coercion, field dropping or hidden retry.

Use concise meaningful field names, not opaque one-letter aliases or
positional tuples. Do not request restated instructions, rules, evidence
already bound to a fixed target, reasoning narratives or summaries unless the
declared task actually requires that content. Model input includes only needed
guidance, evidence, schema and explicitly declared examples; engine-only IDs
are not automatically serialized. Reuse resource aliases in YAML. Avoid
repeating schema/example text across prompt sections; any provider-required
duplication must remain explicit and exactly accounted by F0006/F0007.

Count and bound the actual model-visible input and output. Adding trusted
metadata to the internal decoded value creates no model tokens. Whitespace is
accepted within byte limits; minification is a token-saving preference, not a
reason to reject otherwise valid JSON. Keep semantic evidence and safety
constraints complete—never truncate them to satisfy a token budget.

Accept exactly one complete UTF-8 JSON object, with only optional surrounding
JSON whitespace. Reject duplicate keys at any depth, unknown properties,
missing required fields, wrong types/kinds, exceeded bounds, malformed JSON,
fences, commentary, trailing content or a second value. Do not extract JSON
from prose or convert a stopped response into a candidate. Schema validity
still proves neither semantic correctness nor authority; ordinary validators,
clarification handling and compiled YAML transitions remain mandatory.

## Acceptance evidence for implementation

- Single-shape and multi-variant results use only schema-required candidate
  fields; generation and unrelated arbitrary workflows share this contract.
- Exact call association survives decode; swapped requests/attempts, stale
  repair revisions and unbound observations reject without replay or guessing.
- Single-target repair omits identity echoes; group repair preserves exact
  target keys. Clarification/context variants grant no hidden continuation.
- Malformed, duplicate, unknown, incomplete, excessive and legacy-envelope
  responses reject. Required citations and selections cannot be omitted.
- Native and prompt-only modes have the same candidate meaning and rejection
  rules; unsupported native schemas fail before any provider call.
- Tests account for actual input/result bytes and exact model-specific token
  evidence. No fixed token-saving percentage is assumed.

No compatibility reader or legacy metadata-emitting prompt is retained when
implemented. This documentation amendment adds no runtime operation, provider
support, workflow branch or code change.
