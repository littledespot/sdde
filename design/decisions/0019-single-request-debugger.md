# ADR 0019: Inspect and replay one captured LLM request

- **Status:** Accepted
- **Date:** 2026-09-20
- **Decision authority:** Explicit user direction for a local browser debugger served by the native executable, with exact and modified replay at a single prompt level.
- **Amends:** ADR 0018 and design §§12, 26–28, 29 and 31.
- **Amended by:** [ADR 0020](0020-derived-exact-reference-lineage.md): debug
  descriptions advance to `model-request-debug/v6` and retain the exact-occurrence scope.
  [ADR 0011](0011-provider-owned-request-limits.md#no-output-token-allowance)
  (18 October 2026): descriptions advance to `model-request-debug/v7` without an
  output allowance.
  [ADR 0023](0023-advisory-post-generation-review.md#assignment-membership-at-response-admission-18-october-2026)
  (18 October 2026): descriptions advance to `model-request-debug/v8` and record
  applied assignment membership.
  [ADR 0011](0011-provider-owned-request-limits.md#model-maximum-output)
  (18 October 2026): descriptions advance to `model-request-debug/v9`, whose Bedrock
  provider configuration records the model's maximum output.
  [ADR 0030](0030-engine-owned-model-request.md) (22 October 2026, not yet
  implemented): `node_id` and `route_id` both name the originating `request-model`
  step, and the action ID records the stage. The implementation advances the
  description version if its shape changes. Its 23 October 2026 amendment's removal of
  provider token counting was implemented on 24 October 2026, so no token-count
  observation remains to correlate.

## Diagnostic execution boundary

`sdde --debugger <feature-directory>` serves an embedded browser interface on an
ephemeral IPv4 loopback port. The supplied directory uses the existing feature
identity beneath the current project's configured `paths.specs`. Startup loads the
current closed configuration and registered contracts. This is a native diagnostic
entry point, not a project workflow, workflow registry entry or engine continuation.
It does not execute project nodes, publish project artifacts, change approvals or
grant completion authority. No new production dependency is required.

Each selected call has Prompt, Context, Schema, Request, Response, Sources and Replay views.
Structured context is a presentation of captured data; exact raw content remains
available. Response views distinguish provider bytes, extracted model text, parsed
JSON, schema diagnostics and recorded workflow validation events. Replaying a call
does not execute semantic validators that require workflow state, and the UI must
state that distinction. A successful replay means a diagnostic provider exchange,
never workflow success.

## Capture and lineage

Debug/trace prompt rows additionally retain workflow ID, registered action ID,
call ID, call kind, original call ID, parent call ID and complete sanitized body
length. `node_id` names the expanded YAML invocation entry; `route_id` names its
request-preparation entry. Run ID plus call ID is the join identity. Retries link
to the preceding attempt and original call; repairs of response-produced values carry
their candidate's producing origin through the shared native repair packet. A native
authorized repair of an assembled candidate may have no single producing response:
it retains `repair` kind, its own original call and no parent. The native packet's
repair permit distinguishes that case from missing required response provenance;
it does not fabricate an origin or change repair authority. No correlation is guessed
from adjacent log rows, workflow names or prompt text.
Model and correlated validator events use that complete call ID in `correlation_id`,
including operation kind and attempt, so token-count observations cannot attach to
an inference call. Native semantic rejections use their recorded producing origin;
unattributed evidence remains explicitly uncorrelated.

The prompt column schema becomes `prompt-columns/v3`, with 37 columns; no legacy
reader is added. A separate `request_description` body records the provider/model,
region/config, selected slot, workflow/request entry, typed content, fixed protocol
prompt, exact validation schema and inference settings. `model-request-debug/v9`
captures the selected schema's complete expanded projection, including named
selections, composition parts and narrowed repair shapes; the native original-source witness and plain-prose selectors
used by the source-aware model-text wire validator; native wire-field bindings to
the composition registry, so the selected schema and diagnostic replay enforce the
same permitted insertions; the immutable exact-occurrence scope (ADR 0020); and
each applied exact-membership selection (ADR 0023), whose uniqueness the schema
bytes cannot express, so replay reapplies it through the same schema restriction
owner. This metadata is
diagnostic input, not provider-visible authority. Older descriptions remain
unchanged and reject readback; replay requires a new capture, with no compatibility
reader. The shared schema
compiler reconstructs selected object/tagged-union roots for diagnostic use;
constant-tagged selected roots are permitted without relaxing the external
workflow-resource profile. Shared node/depth bounds apply; the source-file byte
limit is not reapplied to expanded projections. Inspection and replay use this
same reconstruction.
Complete authored resources remain separate source evidence. Older descriptions
are rejected; current files never supply missing historical schema authority.
This description is credential-redacted, chunked and persisted through the same mandatory logging
pipeline. It is a diagnostic projection, never request or workflow authority.
Per-body byte lengths and contiguous chunk offsets prove complete reconstruction.

## Captured source navigation

The user-authorized source navigation extension retains diagnostic source metadata
through schema validation, subgraph expansion, compilation and registry ownership.
Each expanded step carries its authored ancestry, including top-level and nested
subgraph call entries. This map is explicit; generated IDs are never decoded to
infer ancestry. Registry validation checks the compiler projection, then owns the
original inventory-captured workflow bytes and resolved resource names/bytes.

At debug/trace, a separate `source_snapshot` body (`request-source/v1`) captures the
calling and request-preparation chains, original YAML bytes, structured authored
entries, and the exact retained request's bound resource aliases and file bytes.
Selected schema definitions and composition parts/paths are recorded from typed
request bindings. Built-in guidance without a file remains visible in Prompt.
Source text passes through the existing credential sanitizer and complete-body
fragment persistence. It is a diagnostic projection, never execution authority.

The Sources view navigates structural YAML selectors, not inferred line numbers.
It labels the structured declaration separately from the full raw captured file.
Resource navigation uses captured bytes through the authenticated call API and
requires no browser-supplied filesystem path. Missing snapshots are explicitly
unavailable; current source files cannot substitute for historical evidence.
Replay retains the original source snapshot. Modified input is marked as an
override, including an exact replay of an already modified request. Immutable
`request-replay/v6` records persist both fields and the native field bindings; no
older replay reader is added.

## Replay

Replay is a user-triggered POST for exactly one selected inference request. It
makes at most one provider call, with no automatic retries, surrounding workflow
execution or old-state restoration. Exact replay sends the captured wire body only
after reconstructing it from its closed description with the existing provider
serializer and proving byte equality. Missing, partial, redacted or inconsistent
request capture is ineligible for exact replay. Modified replay lets the user edit
only prompt/context/schema content; the canonical schema compiler and provider
serializer validate and assemble the new request. Provider, model and settings
remain those of the selected call and must still be permitted by the current
provider registry and repository model allowlist. Credentials are obtained afresh
from the existing authorization source, never from logs or the browser.
Settings carry no output-token allowance under
[ADR 0011](0011-provider-owned-request-limits.md#no-output-token-allowance)
(amended 18 October 2026); `model-request-debug/v9` has no such field. Its Bedrock
provider configuration records the model's documented maximum output, which replay
sends unchanged
([ADR 0011](0011-provider-owned-request-limits.md#model-maximum-output)).

**Converse amendment (user-directed, 15 October 2026):** Bedrock request construction,
capture, extraction and replay use the same canonical Converse codec as production
invocation. Current validated model registration supplies the typed reasoning
policy; a captured model name cannot choose a codec or invent controls. Historical
chat-format captures remain immutable inspection records and fail exact replay
reconstruction under this serializer. There is no legacy wire reader, migration,
fallback or automatic retargeting. New compatibility evidence requires a fresh
authorized current-model capture. Available provider reasoning is projected as
separate ordered diagnostic blocks (text/signature or opaque redacted content),
including when no final answer is eligible. The debugger renders it as inert text;
it cannot be used as candidate JSON, approval, completion or workflow evidence.

Every replay creates new immutable diagnostic request/result records beneath the
selected feature's `logs/debugger`, linked to the source run/call. The request is
durably saved before dispatch; available response bytes, usage and transport
outcome are saved before reporting a completed replay. Extraction and schema
diagnostics are derived from those retained bytes using the canonical validators. Originals
are never overwritten. Storage failure prevents dispatch or makes the replay fail;
it cannot silently discard a paid response or claim a complete record. Diagnostic
records are not read by workflow execution, recovery or publication.

Only loopback clients may connect. Same-origin checks and an unpredictable
process-local token protect data and replay endpoints. The server accepts no
browser-supplied paths, destinations, credentials, commands or workflow-state
changes. File access is descriptor-relative and no-follow; new records are
exclusive, owner-only files. Model text renders as text, never executable HTML.

## Verification

Offline tests cover exact reconstruction, wrong/missing chunks, attribution,
retry/repair chains, closed replay input, unchanged exact wire bytes, modified
prompt/context/schema, current provider authorization, one-call behavior,
immutable parent records, pre/post-dispatch storage failure, and HTTP access checks.
Capture rejections retain their typed boundary and cause through runner events,
terminal reports and finalization. If subsequent logging also fails, retain that
failure alongside the original capture diagnostic; neither permits dispatch or
completion. Parentless assembled-candidate repairs and their retries use the same
capture and debugger readback contract as other calls.
Native packaging embeds the UI and exercises debugger startup without the source
tree. Live provider replay remains separately authorized; offline evidence is not
E2E evidence.
