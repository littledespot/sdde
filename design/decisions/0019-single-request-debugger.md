# ADR 0019: Inspect and replay one captured LLM request

- **Status:** Accepted
- **Date:** 2026-09-20
- **Decision authority:** Explicit user direction for a local browser debugger served by the native executable, with exact and modified replay at a single prompt level.
- **Amends:** ADR 0018 and design §§12, 26–28, 29 and 31. The overall design remains Proposed.

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
to the preceding attempt and original call; repairs carry their candidate's
producing origin through the shared native repair packet. No correlation is guessed
from adjacent log rows, workflow names or prompt text.
Model and correlated validator events use that complete call ID in `correlation_id`,
including operation kind and attempt, so token-count observations cannot attach to
an inference call. Native semantic rejections use their recorded producing origin;
unattributed evidence remains explicitly uncorrelated.

The prompt column schema becomes `prompt-columns/v3`, with 37 columns; no legacy
reader is added. A separate `request_description` body records the provider/model,
region/config, selected slot, workflow/request entry, typed content, fixed protocol
prompt, exact validation schema and inference settings. `model-request-debug/v2`
captures the selected schema's complete expanded projection, including named
selections, composition parts and narrowed repair shapes. The shared schema
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
`request-replay/v4` records persist both fields; no older replay reader is added.

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
Native packaging embeds the UI and exercises debugger startup without the source
tree. Live provider replay remains separately authorized; offline evidence is not
E2E evidence.
