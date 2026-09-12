# ADR 0014: Universal response-format guidance

- **Status:** Accepted
- **Date:** 2026-09-12
- **Decision authority:** Explicit user instruction to apply universal response
  guidance without local fixes, duplicate authority or verbose workflow templates
- **Amends:** Design Section 12.2; ADRs 0006 and 0012's prompt-ownership wording

## Decision

Every model request states the engine's existing JSON response framing:

> Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.

The provider-neutral response-controls contract owns this one constant.
Provider serializers emit it once as system-level guidance for initial calls,
semantic review, repair and protocol retries in any workflow, in both
`prompt-only` and supported `native-schema` modes. Explicit input-token counting
uses the same model-visible projection as inference. Test evaluators reuse the
same constant.

The instruction is serialized beside the existing response schema; it is not
appended to the workflow content retained across retries. This prevents retry
duplication without text matching, filtering, flags or an additional prompt
assembly service. Workflow templates omit redundant framing instructions.

Workflows still select their task prompts, input and compiled result schema.
The schema remains the sole authority for fields, types, variants and bounds.
This sentence describes framing only: it supplies no business rules, default
schema, model selection, retry authority or completion authority. No new
configuration or YAML parameter is introduced.

Strict decoding and schema validation remain mandatory. Fenced responses still
reject; the engine does not strip fences or extract JSON from prose. The model
can still disobey the instruction, so live output and rubric evidence must be
reported separately from mechanical conformance tests.

## Acceptance

- Serialized requests contain the shared instruction exactly once, including
  retries, both response modes and both evaluator providers.
- Unrelated result schemas retain their exact schema and input bytes.
- Inference and explicit counting project the same model-visible content.
- Malformed JSON and schema violations still reject under existing validators.
- Live evidence retains the actual outbound instruction and returned result;
  neither a fake response nor an unpublished candidate establishes E2E success.
