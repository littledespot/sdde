# F0001 — SDDToolKitReader

**Status:** Proposed feature design

**Implementation readiness:** Ready for the bounded JSON-reader increment.
Domain-specific policy compilation and validation remain separate features.

**Classification:** Core, read-only configuration provider

**Mutability:** Strictly read-only. This feature receives no project,
configuration, state, command, model, transaction, or logging capability.

**Scope:** SDDE engine development. This document specifies the engine feature;
it does not authorize running SDDE against a target project.

**Governing authority:** This feature follows the action, ownership, path, and
configuration boundaries in [the engine design](../design.md), especially
Sections 5-6, 9, 13.1, 15, 25-26, and 28-31, plus the focused
[path contract](../paths.md). The current reader-facing JSON shape is shown by
[`design/examples/.sddtoolkit.json`](../examples/.sddtoolkit.json). That file
is a schema example, never a runtime default, packaged asset, search location,
or fallback.

---

## 1. Purpose

`SDDToolKitReader` has one responsibility: read the exact project
`.sddtoolkit.json` once, decode it into one immutable `SDDToolKitConfig`, and
make that configuration available for read-only queries during the current
engine invocation.

The reader provides configuration information. It does not interpret that
information as logging, model, path, workflow, command, or persistence policy.
The service that owns a configuration section owns its semantic validation and
conversion into operational policy.

The public result is the immutable configuration value, not a reader object,
filesystem handle, JSON parser, mutable cache, service locator, or generic
string-keyed settings API. The runner owns the accepted value in its immutable
envelope and exposes only the section view declared by each consumer's typed
node contract. The composition root constructs those bindings; it does not
execute the reader or move configuration data itself.

## 2. Observable outcome

For one engine invocation:

1. Starting from the trusted invocation working directory, the engine selects
   the nearest canonical ancestor containing the exact basename
   `.sddtoolkit.json`.
2. The selected file's directory is the canonical project root.
3. The exact file is opened read-only, no-follow, and beneath that root.
4. The file is read completely under engine-owned byte, time, and resource
   limits.
5. The captured bytes are decoded once as JSON into one owned
   `SDDToolKitConfig`.
6. The decoded root has the reader-facing shape in Section 4.
7. The runner retains that immutable value for the current invocation and
   supplies const section views only through declared typed data keys.
8. No consumer rereads, reparses, mutates, replaces, or persists the document.
9. A missing, unsafe, oversized, malformed, or structurally invalid document
   fails closed before a model call or workflow side effect.

## 3. Single-responsibility decomposition

F0001 is one logical configuration-provider feature implemented through
separate responsibilities:

| Component | Sole responsibility | Must not do |
| --- | --- | --- |
| `LocateExactEngineConfigAction` | Select the nearest exact `.sddtoolkit.json` and bind its containing directory as the canonical project root. | Read bytes, parse JSON, select a fallback, or accept a caller-provided alternate filename. |
| `ReadEngineConfigAction` | Read that one validated, bounded, no-follow resource into owned bytes. | Locate another file, decode JSON, apply a domain policy, or expose the filesystem. |
| `ParseEngineConfigAction` | Parse JSON syntax from the captured bytes into an owned generic JSON document. | Read a file, apply the typed config shape, apply domain semantics, or choose defaults. |
| `DecodeSDDToolKitConfigAction` | Convert the parsed JSON document into the closed reader-facing `SDDToolKitConfig` shape. | Compile operational policy, validate path containment, resolve model providers, canonicalize log levels, or select a sink. |
| Pipeline runner | Invoke each bound reader action, validate/apply its delta, own the accepted immutable configuration, and satisfy declared typed section-view dependencies. | Parse or interpret values, expose ambient lookup, or grant an undeclared section. |
| Composition root | Construct the concrete read adapter, reader action bindings, and section-specific consumer graph. | Execute nodes, own runtime data, interpret settings, or transport configuration values. |
| Section-owning consumer | Validate and compile the semantics of its supplied section. | Reread the file, reinterpret another section, or make the reader an operational authority. |

No action invokes another action or orchestrator. The runner invokes each
registered action, validates/applies its delta, and supplies the next declared
input. The composition root alone constructs concrete adapters and bindings.

## 4. Reader-facing JSON shape

The current reader-facing document shape is represented by
[`design/examples/.sddtoolkit.json`](../examples/.sddtoolkit.json):

```text
SDDToolKitConfig {
  version: "1.0",
  logs: LogsConfig,
  models: ModelsConfig,
  paths: PathsConfig
}
```

### 4.1 Logging configuration

```text
LogsConfig {
  level: string,
  format: string,
  timestamp: boolean,
  output: string,
  promptLogs: PromptLogsConfig
}

PromptLogsConfig {
  enabled: boolean,
  logFile: string,
  includeResponse: boolean,
  maxResponseLength: u64
}
```

F0001 proves only this structural shape and value kinds. A logging-policy owner
decides which spellings, combinations, limits, destinations, and compatibility
rules are permitted. In particular, `logFile` remains configuration data; it
is not a validated path or filesystem capability merely because the reader
decoded it.

### 4.2 Model configuration

```text
ModelsConfig {
  slots: map<ModelSlotName, ModelSlotConfig>
}

ModelSlotConfig {
  provider: string,
  model: string,
  reasoningEffort?: string
}
```

The reader preserves slot names and values. Model-route/profile owners validate
registered slot names, provider/model identifiers, optional reasoning effort,
availability, and fallback policy.

### 4.3 Path configuration

```text
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

The reader requires these seven members once and exposes their strings as
configuration information. Path-policy owners normalize them, join them to the
canonical project root, prove containment and portability, and construct typed
root capabilities. No F0001 value is an actionable path.

### 4.4 Closed structural decoding

The root and fixed nested records reject missing, duplicate, and unknown
members. `models.slots` is the one keyed collection: slot keys are data and its
values use the closed `ModelSlotConfig` shape. JSON numbers required as
unsigned integers reject negative, fractional, or out-of-`u64`
representations. Strings must be valid UTF-8 JSON scalars. The root `version`
discriminator must equal the supported reader contract version `1.0`;
selecting the closed structural contract is not domain-policy interpretation.

Structural acceptance is not semantic acceptance. A section-owning consumer
must still validate every value from unknown through its closed domain schema
before the value can influence an operation.

## 5. Read-only query contract

The accepted result is an owned immutable value:

```text
SDDToolKitConfig {
  version,
  logs,
  models,
  paths
}
```

Declared consumers query a const view of exactly the section they require
through a typed data key. A view borrows from the one runner-owned
`SDDToolKitConfig`; it is not a copied projection or a second authority:

| Typed key | Consumer | Supplied view | Not supplied |
| --- | --- | --- | --- |
| `engine.config.logs@1` | Logging-policy compiler | `*const LogsConfig` | Models, paths, raw JSON, file handle, or reader capability. |
| `engine.config.models@1` | Model-route/profile compiler | `*const ModelsConfig` | Logging, paths, raw JSON, or filesystem access. |
| `engine.config.paths@1` | Root/path compiler | `*const PathsConfig` plus the separately validated project-root descriptor | Logging, models, raw JSON, or unrestricted path authority. |
| `engine.config.version@1` | Declared bootstrap/reporting consumer | The accepted `version` scalar | Any configuration section. |

`engine.config@1` is the runner-owned lifetime root for the complete value and
is not an ordinary consumer key. The four section keys are compiler-registered
const accessors into that owner; resolving them performs no copy, conversion,
validation, filesystem access, or policy decision. Only
`DecodeSDDToolKitConfigAction` produces the owner. No projection-building
action or independently persisted section value exists.

The view may be queried through typed fields such as `logs.level` or
`paths.specs`. There is no `get(string)`, JSON Pointer API, reflection-based
property map, consumer-selected default, or whole-document getter for ordinary
services.

Adding a future top-level section requires extending the closed
`SDDToolKitConfig` type, declaring its sole consumer/semantic owner, and adding
accepted and rejected structural tests. It must not introduce a second reader
or generic lookup facility.

## 6. Lifetime and ownership

- The read adapter owns the byte allocation until its candidate delta is
  applied or destroyed.
- The parser owns the JSON tree until structural decoding completes or fails.
- `SDDToolKitConfig` owns all decoded strings, maps, and nested records.
- The runner owns the accepted configuration for the current invocation; the
  composition root owns only construction of its bindings.
- Consumers borrow const section views only for their declared lifetime and
  cannot retain mutable aliases.
- One deterministic `deinit` releases the complete owned configuration on
  every terminal invocation branch.
- A new invocation performs a new read and decode. There is no watch, hot
  reload, cross-run singleton, serialized reader cache, or hidden fallback.

## 7. Failure contract

Expected rejection is a closed result distinct from unexpected operational
failure. Stable diagnostic codes cover at least:

- exact configuration not found;
- alias, symlink, directory, or special resource;
- ancestor-walk or byte limit exceeded;
- short/incomplete read or resource replacement;
- invalid UTF-8/JSON, trailing content, or duplicate member;
- root value is not an object;
- missing, unknown, or wrong-kind structural member;
- unsupported reader contract version;
- invalid integer representation; and
- cancellation or timeout.

No failure branch publishes a partial `SDDToolKitConfig`, invokes a model,
creates a project directory, writes a cache, or starts F0002. F0001 returns the
typed result; it does not log its own content or invoke logging recursively.

## 8. Explicit non-responsibilities

F0001 does not:

- compile logging, model, path, workflow, command, or state policy;
- canonicalize log levels or choose a logging destination;
- resolve model providers or routes;
- normalize, validate, or authorize configured paths;
- create an ingestion seal or consumer projection;
- persist bootstrap authority or workflow state;
- expose a mutable settings object, generic lookup service, or filesystem
  capability;
- watch or reload the file;
- use the repository example as runtime input or fallback; or
- create, edit, migrate, or repair `.sddtoolkit.json`.

## 9. F0002 boundary

F0002 never reads `.sddtoolkit.json`. During bootstrap, the logging-policy
compiler receives only `*const LogsConfig` from the accepted
`SDDToolKitConfig`, validates/canonicalizes it under its own contract, and
produces the logging policy consumed by F0002.

This creates one authority chain:

```text
.sddtoolkit.json
  -> F0001 SDDToolKitConfig
  -> const LogsConfig view
  -> logging-policy compiler
  -> validated logging policy
  -> F0002 runtime logging
```

F0001 owns JSON structure. The logging compiler owns logging semantics. F0002
owns record processing and sink behavior. None duplicates another owner.

## 10. Acceptance criteria

1. The reader selects only the nearest ancestor's exact
   `.sddtoolkit.json`; no alternate name, source example, packaged asset,
   environment variable, or default document is considered.
2. Discovery, reading, JSON parsing, and structural decoding are separate
   one-responsibility actions with no action-to-action execution.
3. The file is opened read-only, no-follow, beneath the validated project root,
   and read completely under engine hard limits.
4. One successful invocation reads and parses the file exactly once.
5. The decoded value has the closed shape in Section 4 and owns all memory
   reachable through it.
6. Missing, unknown, duplicate, wrong-kind, unsupported-version, malformed,
   trailing, oversized, cancelled, and timed-out inputs fail closed without a
   partial result.
7. The runner owns one immutable `SDDToolKitConfig` for the invocation;
   consumers cannot mutate it or trigger a reread.
8. Each declared consumer receives only its typed const section view.
9. No generic string/JSON-pointer lookup, mutable singleton, service locator,
   or filesystem capability exists.
10. Reader success grants no logging, model, path, command, transaction, or
    workflow authority.
11. Domain semantic validation occurs exactly once at the owning consumer
    boundary and is not duplicated inside F0001.
12. The logging compiler consumes `LogsConfig`; runtime F0002 receives only its
    validated logging policy and never receives a reader or filesystem port.
13. All allocations and descriptors are released exactly once on every
    success, rejection, cancellation, timeout, and operational-failure branch.
14. The packaged executable reads a target project's exact file without access
    to repository examples, the source tree, build cache, or Zig toolchain.

## 11. Verification plan

### 11.1 Discovery and read tests

- exact file in invocation directory and nearest parent;
- nearer/farther candidates proving nearest-first selection;
- missing, wrong-case, alias, symlink, directory, and special resource;
- no-follow/beneath-root enforcement;
- byte, ancestor, time, and cancellation limits;
- short read, replacement during read, and adapter failure;
- one read per successful invocation; and
- filesystem spy proving no mutation operation exists.

### 11.2 JSON and structural tests

- the repository example decoded into the expected owned fields;
- reordered object members and insignificant JSON whitespace;
- malformed JSON, invalid encoding, duplicate keys, and trailing content;
- missing, unknown, and wrong-kind members at every closed record;
- accepted `version: "1.0"` and rejection of every unsupported version;
- dynamic model-slot keys with closed slot values;
- optional `reasoningEffort` present and absent;
- integer boundary cases for `maxResponseLength`; and
- deterministic cleanup after every parse/decode failure point.

### 11.3 Query and architecture tests

- const logging/model/path/version views return the expected information;
- compile-time rejection of mutation through a consumer view;
- consumer fixtures cannot access an undeclared sibling section;
- no generic getter, JSON Pointer, reader singleton, policy compiler, logger,
  transaction, command, or writable filesystem import in F0001;
- logging compiler receives `LogsConfig` while F0002 runtime cannot receive the
  config document; and
- repeated consumer queries cause zero filesystem or parser operations.

### 11.4 Packaging test

Build the native executable and run the reader test fixture from a clean
temporary target directory without the repository examples, source tree, Zig
toolchain, or development cache. The packaged executable must use only the
target's exact `.sddtoolkit.json` and create no cache or fallback file.

## 12. Traceability

| Concern | Governing authority |
| --- | --- |
| Exact filename/project-root discovery | Design Sections 9 and 13.1 |
| Action/runner/composition-root boundaries | Design Sections 5-6 |
| Reader-facing JSON shape | `design/examples/.sddtoolkit.json` and Section 4 |
| Typed query isolation | Design Sections 5-7 and this feature Sections 5-6 |
| Path and filesystem safety | Design Sections 11, 25-26 and `design/paths.md` |
| Logging handoff | Design Sections 13.1, 13.9, 26.5-27 and F0002 |
| Verification and packaging | Design Sections 28, 30-31 |
