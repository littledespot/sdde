# F0001 — SDDToolKitConfigService

**Status:** Proposed feature design

**Implementation readiness:** Ready for the bounded JSON-reader increment.

**Classification:** Core, read-only configuration provider

**Scope:** SDDE engine development. This document does not authorize running
SDDE against a target project.

**Governing authority:** [Engine design](../design.md), especially Sections
5-6, 9, 13.1, 25-26, and 28-31; [path contract](../paths.md); the accepted
[configuration schema](../schemas/sddtoolkit-config-v2.schema.json); and its
[example instance](../examples/.sddtoolkit.json).

---

## 1. Responsibility

F0001 treats the native executable's current working directory, captured once
at invocation start, as the project root. It reads that directory's exact
`.sddtoolkit.json` once, decodes it directly into one owned immutable
`SDDToolKitConfig`, and makes that value available to declared consumers for
the current invocation.

It owns configuration transport and structural decoding only. It does not
interpret logging, model, or path settings as operational policy.

## 2. Minimal design

The implementation has three actions:

| Action | Sole responsibility |
| --- | --- |
| `LocateExactEngineConfigAction` | Canonicalize the invocation working directory as the project root and resolve only its exact `.sddtoolkit.json` child. Any failure to resolve a safe readable file returns `ENGINE_CONFIG_READ_ERROR`. Do not search a parent or child directory. |
| `ReadEngineConfigAction` | Read that validated no-follow regular file into owned bytes up to the internal 1 MiB guard; any failure returns `ENGINE_CONFIG_READ_ERROR`. |
| `DecodeSDDToolKitConfigAction` | Parse those bytes directly into the exact closed v2 `SDDToolKitConfig`; any JSON, version, or structural failure returns `ENGINE_CONFIG_PARSE_ERROR`. |

There is no generic JSON-document action or intermediate JSON tree. JSON
syntax parsing is part of decoding one known JSON contract.

The runner invokes the actions, validates/applies their deltas, constructs one
`SDDToolKitConfigService`, and owns its accepted value at the single typed key
`engine.config@1`. The composition root only constructs the adapter and
bindings. No action calls another action.

## 3. Configuration shape

The reader-facing contract mirrors the repository fixture:

```text
SDDToolKitConfig {
  version: "2.0",
  logs: LogsConfig,
  models: ModelsConfig,
  paths: PathsConfig
}

LogsConfig {
  level: string,
  console: boolean, // optional pipe-delimited mirror; file logging is always enabled
  promptCapture: ("request" | "response" | "reference_body" | "code_body")[]
}

ModelsConfig {
  slots: map<ModelSlotName, {
    provider: string,
    model: string,
    reasoningEffort?: string
  }>
}

PathsConfig {
  specs: string,
  references: string,
  specsArchive: string,
  workflows: string,
  toolchainPreset: string,
  principles: string,
  templates: string
}
```

The root and every fixed nested object are closed by
`sddtoolkit-config-v2.schema.json`. Missing, duplicate, unknown, or wrong-kind
members are rejected. Model slot names are data, but every slot value has the
same closed shape. `promptCapture` is a unique list of at most the four closed
selectors shown above; an empty list disables body capture. The version must be
exactly `2.0`. All sink, format, size, retention, flush, redaction, failure,
prompt-size, and lock values are F0002 compiler constants, not configuration.
There is no file-output switch: every admitted F0002 record is written to its
feature/run `.log` file. `console` can only add or suppress the same safe
pipe-delimited row on `stderr`; it can never replace or disable the file write.

Structural decoding does not grant operational authority. In particular:

- a decoded path string is not normalized, contained, or authorized;
- a decoded log level or prompt-capture selector list is not canonical or
  validated logging policy; and
- a decoded provider/model string is not a resolved model route.

## 4. Query and ownership contract

A consumer that needs configuration declares `engine.config@1` and receives a
borrowed `*const SDDToolKitConfig` from
`SDDToolKitConfigService.config()`. It queries typed fields directly, for
example `config.logs.level` or `config.paths.specs`.

This service is the only configuration value and query mechanism. There are no copied
section values, section-specific registry keys, string-key getters, JSON
Pointer APIs, mutable settings singletons, caches, or reader capabilities.

Semantic ownership remains outside F0001:

| Consumer | Owned semantic work |
| --- | --- |
| Logging-policy compiler | Canonicalize `config.logs.level` once, validate console/prompt choices, inject every F0002 operational constant, and produce the persisted logging-policy fragment. |
| Model-route compiler | Validate `config.models` and resolve registered providers, models, and routes. |
| Path-policy compiler | Validate `config.paths` against the project root and construct typed root capabilities. |

Consumers may read the immutable configuration but cannot mutate it, trigger a
reread, obtain raw bytes, or gain filesystem access. The runner releases the
complete owned value once on every terminal invocation branch.

## 5. File and failure contract

The runtime uses only `<invocation-working-directory>/.sddtoolkit.json`. The
working directory is captured and canonicalized once as the project root; the
runtime does not search ancestors or descendants and does not accept aliases,
alternate names, environment overrides, repository examples, packaged assets,
or default documents. The file is opened read-only, no-follow, beneath that
root and read under the compiler-owned `maxEngineConfigBytes = 1,048,576`
(1 MiB) limit. This limit is not configurable. A file whose byte length exceeds
the limit is rejected before decoding; the reader also enforces the same limit
while reading so a stale or inaccurate size observation cannot bypass it.

F0001 exposes exactly two terminal configuration errors:

| Error | Meaning |
| --- | --- |
| `ENGINE_CONFIG_READ_ERROR` | The exact current-directory file cannot be safely and completely read. This includes missing, permissions/I/O failure, unsafe type/symlink/alias, working-directory failure, and exceeding the internal 1 MiB guard. |
| `ENGINE_CONFIG_PARSE_ERROR` | The bytes cannot be decoded as the exact closed v2 config. This includes malformed JSON, trailing content, unsupported version, and missing, unknown, duplicate, or wrong-kind members. |

Either error makes bootstrap return terminal `failed`, makes the executable
exit nonzero, and prevents every workflow node, model call, F0002 feature log,
and project write. The low-level cause may appear in bounded human-readable
diagnostic detail, but it does not create another public error code or control
branch.

This pre-release proof of concept has no compatibility target. Config `2.0` is
updated in place, obsolete v2 drafts are rejected, and F0001 contains no
migration, alias, dual-reader, or fallback branch.

Neither error publishes a partial config, writes a cache, creates project
content, calls a model, or starts runtime logging.

## 6. F0002 handoff

F0002 never reads configuration. Its bootstrap path is:

```text
.sddtoolkit.json
  -> F0001 SDDToolKitConfig
  -> logging-policy compiler reads config.logs
  -> validated persisted logging policy
  -> F0002 runtime logging
```

F0001 owns JSON structure, the logging compiler owns logging semantics, and
F0002 owns runtime record processing and storage. No boundary repeats another
owner's work.

## 7. Acceptance criteria

1. The invocation working directory is the project root and only its exact
   `.sddtoolkit.json` child is considered; no ancestor or descendant search is
   performed.
2. Locate, read, and typed decode remain separate actions.
3. Decode goes directly from owned bytes to one closed owned
   `SDDToolKitConfig`; no generic JSON tree is retained or published.
4. A successful invocation reads and decodes the file once.
5. The runner constructs exactly one `SDDToolKitConfigService` and publishes
   its immutable value at `engine.config@1`.
6. Consumers query typed fields without a second config value, cache, generic
   getter, or reread path.
7. Structural success grants no logging, model, path, command, transaction, or
   workflow authority.
8. Semantic validation occurs once in the owning consumer.
9. All resources are released once on success, rejection, cancellation,
   timeout, and operational failure.
10. The packaged executable works without repository examples, the source
    tree, build cache, or Zig toolchain.
11. `maxEngineConfigBytes` is the compiler-owned constant 1,048,576; exactly
    that many bytes may be decoded and 1,048,577 bytes are rejected.
12. The public configuration failure surface contains only
    `ENGINE_CONFIG_READ_ERROR` and `ENGINE_CONFIG_PARSE_ERROR`; every failure
    maps to exactly one of them and both terminate before workflow work.

## 8. Verification

Tests must cover the owning boundaries rather than every incidental parser
branch:

- root binding: exact current-directory file, proof that parent/child configs are
  ignored, missing-file terminal `ENGINE_CONFIG_READ_ERROR`/nonzero exit, wrong type, symlink,
  exact 1 MiB acceptance, 1 MiB plus one-byte rejection, short-read/growth
  enforcement, and no-fallback cases;
- decoding: the repository fixture, reordered members, malformed JSON,
  unsupported version, and representative missing/unknown/wrong-kind cases at
  each closed nesting level, checked against the published v2 schema and all
  mapped to `ENGINE_CONFIG_PARSE_ERROR`;
- ownership: one read/decode, immutable typed queries, no mutation or reread,
  semantic rejection remaining with the relevant consumer, and cleanup on
  every terminal class; and
- packaging: a clean target directory containing only its own valid
  `.sddtoolkit.json`.

## 9. Traceability

| Concern | Authority |
| --- | --- |
| Current-directory project-root binding and config shape | Design Section 9 and 13.1 |
| Action/runner/composition-root boundaries | Design Sections 5-6 |
| Path safety | Design Sections 11, 25-26 and `design/paths.md` |
| Logging handoff | Design Sections 13.1, 13.9, and 26.5; F0002 |
| Verification and packaging | Design Sections 28, 30-31 |
