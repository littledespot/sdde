# ADR 0043: Model-facing exact-text names

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision authority:** The user's decision on 26 October 2026, "2 yes" and "update
  with recommendations and implement", approving the recommendation to rename the
  model-facing `preserved_token` to `exact_text` and `preserved_tokens` to
  `exact_texts`.
- **Amends:** [ADR 0013](0013-workflow-input-reuse.md) ("a separate deduplicated
  `preserved_tokens` collection"), §12 and §17 packet descriptions, the Spec prompts
  and schemas that name the term, F0100 and the §32 index. The overall design remains
  **Proposed design**.

## Context

Model packets label an exact source value, such as `Hello, World!`, with the engine
term `preserved_token`. Hello-world's user story has repeated it in four evaluated runs
("the preserved token"), so engine vocabulary reaches a business specification.

## Decision

1. **Model-visible names only.** Wherever the engine shows the term to a model, in
   request packets, prompts, schemas, diagnostics and the content kinds a model reads
   or returns, `preserved_token` becomes `exact_text` and `preserved_tokens` becomes
   `exact_texts`.
2. **Internal names don't change.** Native Zig types, action IDs, native operation IDs,
   stored state and canonical records keep their names. Only model-facing projection
   and packet types name the collection `exact_texts`. The content kind maps at the
   model-facing codec: a union may declare `model_tags`, and the declared name is then
   the only one the codec emits or accepts for that variant. There is no alias or dual reader; the old name rejects at the
   codec. Models only read exact-text content; no response schema returns it.
3. **Request descriptions and replay** carry the new names, within ADR 0039's
   `model-request-debug/v13`.

## Consequences

- **Persistence.** No specification or state version changes.
- **Harness.** The exact-value harness reads the packet key only from retained
  captures made before this change, such as the frozen exact-value recognition corpus,
  so those historical readers keep the old key and say so. Current captures supply
  exact values through native exact scope. Frozen calibration exports keep their
  recorded names.
- **Tests.** Packets and prompts carry only the new names (a scan of every Spec prompt,
  schema and context file); the codec encodes and decodes `exact_text` and rejects
  `preserved_token`; stored state and internal identifiers are unchanged.
