# ADR 0043: Model-facing exact-text names

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision authority:** User decision, 26 October 2026.
- **Amends:** [ADR 0013](0013-workflow-input-reuse.md) (the model-facing name of the
  deduplicated exact-value collection), the Spec prompts and schemas that name the term,
  and F0100.

## Decision

1. **Model-visible names only.** Wherever the engine shows the term to a model, in
   request packets, prompts, schemas, diagnostics and the content kinds a model reads
   or returns, `preserved_token` becomes `exact_text` and `preserved_tokens` becomes
   `exact_texts`. The reason: a model repeated the engine term in a published story.
2. **Internal names don't change.** Native Zig types, action IDs, native operation IDs,
   stored state and canonical records keep their names. Only model-facing projection
   and packet types name the collection `exact_texts`. The content kind maps at the
   model-facing codec: a union may declare `model_tags`, and the declared name is then
   the only one the codec emits or accepts for that variant. There is no alias or dual
   reader; the old name rejects at the codec. Models only read exact-text content; no
   response schema returns it.
3. **Request descriptions and replay** carry the new names.

## Consequences

- **Persistence.** No specification or state version changes.
- **Harness.** The exact-value harness reads the packet key only from retained
  captures made before this change, such as the frozen exact-value recognition corpus,
  so those historical readers keep the old key and say so. Current captures supply
  exact values through native exact scope. Frozen calibration exports keep their
  recorded names.
