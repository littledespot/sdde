# F0002 — LogService

**Status:** Proposed feature design

**Implementation readiness:** Blocked until F0001's sealed projection contract
and the log-level canonicalizer/policy-validator ownership prerequisite in
Section 6.4 are accepted in the governing catalogues.

**Classification:** Core, cross-cutting feature-logging subsystem

**Scope:** SDDE engine development. This document specifies behavior and
boundaries only; it does not authorize running SDDE against a target project.

**Governing authority:** This feature refines, but does not accept, amend, or
supersede, the proposed contracts in [the engine design](../design.md),
especially Sections 5-6, 9, 13.1, 13.9, 14.9-14.10, 26.5, 27-28, 30, and 31.
The existing [feature logging diagram](../diagrams/06-feature-logging.mmd) is an
informative view of the same boundary.

**Required collaborator:** The proposed
[F0001 — SDDToolKitReader](F0001-SDDToolKitReader.md) is the sole logical
feature permitted to ingest `.sddtoolkit.json`. F0001 ends at a validated
logging-settings projection; the specialized compiler and bootstrap-authority
owner remain separate. Runtime F0002 consumes neither the reader projection
nor the transient compiler fragment. It consumes only a validated
`FeatureLogPolicy` reconstructed from persisted authority and an exact
`FeatureLogBinding` constructed by the governing binding actions from that
policy plus current feature, run, and artifact-registry authority.

---

## 1. Purpose

F0002 has one cohesive responsibility: convert accepted runner facts and
separately authorized sanitized prompt records, under one validated
feature/run policy and binding, into safe, ordered, non-authoritative
observability records or a typed fail-closed logging outcome. Every ordinary
feature log follows this boundary. The fixed content-free emergency path is
the explicit non-recursive failure exception, not a second ordinary logger.

`LogService` is only the F0002 feature/documentation label. It is not a Zig
type, singleton, facade, `PipelineNode`, dispatcher, service locator, generic
logger API, or additional authority object. Its implementation is the
runner-owned observer, runner-invoked logging orchestrators, named
single-responsibility actions, and operation-specific private ports. The
composition root alone wires their concrete adapters.

Other services use logging through a minimal typed-fact boundary. They do not
receive a logger, sink, filesystem handle, logging configuration, or a method
that accepts an arbitrary level and message.

## 2. Required outcomes

The feature must provide the following observable outcomes:

1. Every accepted fact follows one common logging pipeline under exactly one
   validated `FeatureLogPolicy` and `FeatureLogBinding` for its feature/run;
   policy, binding, sink state, and records are never global or shared across
   feature authorities.
2. Other services can contribute useful observability facts without gaining
   control of severity, wording, sensitive-field classification, output paths,
   sinks, or persistence.
3. The runtime threshold comes only from the exact persisted bootstrap-
   authority fragment revalidated into the active `FeatureLogPolicy`. That
   fragment ultimately derives from `logs.level` through F0001 and the
   specialized compiler, but F0002 never rereads or consumes configuration.
4. Six canonical levels are supported: `fatal`, `error`, `warning`, `info`,
   `debug`, and `trace`.
5. Every ordinary persisted log is isolated to the validated active feature
   and stored beneath that feature's **feature specification root**
   (`<paths.specs>/<featureId>/`); no shared or global persistent log exists.
6. Mandatory metadata logs are safe, bounded, recoverable, and separate from
   workflow authority.
7. Optional prompt or body capture cannot weaken metadata safety and remains
   off by default.
8. Producer actions remain isolated from log-sink I/O: they return typed facts
   in their ordinary deltas. After applying a delta, the runner invokes the
   logging graph and consumes its standard `Outcome` before crossing the next
   applicable business-node barrier.
9. A logging safety or sink failure is fail-closed and cannot recursively log
   itself.

## 3. Scope

### 3.1 In scope

- trusted runner lifecycle events;
- validated `TelemetryFact` values produced by engine services;
- canonical event definitions and levels;
- enforcement of a validated persisted-authority-derived `FeatureLogPolicy`;
- threshold filtering;
- safe event-field projection and redaction;
- optional, separately protected prompt/body capture;
- console mirroring when enabled by validated policy;
- mandatory feature-bound JSONL event storage beneath the validated feature
  specification root;
- log record identity, ordering, timestamps, serialization, and size limits;
- runner-mediated post-delta fact handoff and terminal logging barriers;
- stream initialization, locking, append, flush, rotation, retention, close,
  restart recovery, and logging-policy transitions;
- fixed, non-recursive emergency reporting and fail-closed control;
- logging-specific verification and architecture tests.

### 3.2 Out of scope

- using logs as approval, completion, rollback, transaction, or workflow-state
  authority;
- a general-purpose `log(level, message, fields)` facility;
- caller-selected severity, message templates, sinks, paths, formats,
  retention, or redaction classifications;
- custom levels or aliases;
- detached fire-and-forget logging, unbounded pending work, silent sampling,
  overwrite, or dropping an admitted mandatory event;
- a background/asynchronous dispatcher, queue, worker, dispatch ordinal,
  capacity pool, backpressure scheduler, or drain-deadline policy; those need a
  separately accepted governing action/type/data-key amendment;
- unrestricted arbitrary text, maps, or binary payloads in metadata events;
- enabling raw content merely because the threshold is `trace`;
- network telemetry export, a log-query UI, or an external logging provider;
- a shared, process-wide, project-wide, working-directory, or otherwise global
  persistent log file;
- choosing a concrete logging library or adding a production dependency;
- defining implementation modules, method signatures, or Zig code in this
  feature document.

## 4. Ownership and encapsulation boundary

### 4.1 Responsibilities owned by LogService

The logging subsystem exclusively owns:

- resolving one fact kind against the supplied immutable event-definition
  registry;
- assigning the registry-defined canonical level and message template;
- projecting only registered, typed fields into a draft record;
- applying registry-owned sensitivity classification;
- omitting or redacting disallowed data;
- comparing the event level with the configured threshold;
- assigning event identity, stream sequence, and trusted timestamps after an
  event survives filtering and redaction;
- validating and serializing one complete safe record;
- proving each record joins the exact validated `FeatureLogBinding` and using
  only its registry-owned collection identity; no logging action derives a
  path;
- controlling stream locks, files, permissions, append, flush, rotation,
  retention, close, and restart recovery;
- completing exactly one below-threshold, successful-persistence, or fail-
  closed branch for each accepted fact through the standard `Outcome` and
  runner-validated composite `NodeDelta` contracts;
- adopting a new logging policy only through a validated authority transition;
- destroying transient raw-content handles on every terminal branch;
- returning only that standard `Outcome` to the runner, which alone validates/
  applies its composite delta and owns business-node scheduling and
  continuation;
- handling its own failure without invoking the normal logging pipeline.

No other boundary may duplicate or bypass any of these responsibilities.

### 4.2 External collaborators

The following owners remain outside the logical logging subsystem:

| Owner | Responsibility |
| --- | --- |
| `SDDToolKitReader` | Exclusively discover, inspect, open, read, parse, and generally validate the one exact, bounded, no-follow project-root `.sddtoolkit.json`; publish only the narrow immutable logging-settings projection and evidence permitted by its closed consumer inventory. Raw bytes, the JSON tree, file handles, and filesystem capabilities remain private. |
| Specialized logging-policy compiler | Consume only F0001's validated logging-settings projection and produce a feature-independent transient compiled fragment without interacting with the file, receiving unrelated fields, persisting authority, or activating runtime logging. The canonicalizer/validator ownership prerequisite in Section 6.4 must be resolved first. |
| Compiler-owned event-definition registry | Solely define and version event kinds and assign one governing canonical level, template, field schema, and sensitivity classification to each. It does not redefine the canonical-level variants or ranks. F0002 receives the resolved immutable registry and never defines or mutates it. |
| Bootstrap-authority owner | Incorporate the validated compiler fragment into compiled engine policy and persist it only through an accepted `BootstrapAuthorityState`; compare/adopt successor authority through the governing transaction route. |
| Workflow-artifact registry owner | Derive and validate the fixed feature event/prompt collection paths and publish their typed collection identities. No F0002 action recalculates them. |
| Producing service | Return only a registered, typed fact describing what occurred. |
| Pipeline runner | Validate/apply node deltas, derive lifecycle facts, establish fact order, seed the logging-internal envelope, invoke the logging child binding, consume its standard `Outcome`/composite delta, and enforce business-node barriers. It performs no definition lookup, redaction, threshold, serialization, or sink work. |
| Transaction recovery | Stabilize a transaction that was already prepared or applying when logging failed. |
| Composition root | Construct concrete adapters and the runner-owned logging graph. |

LogService must not absorb these collaborators into a service locator or a
generic capability bag, and an external collaborator must not take ownership of
logging policy or sink behavior.

There is no alternate `.sddtoolkit.json` access path: no service, action,
orchestrator, model boundary, or adapter outside the `SDDToolKitReader`
ingestion boundary may discover, stat, open, watch, read, parse, or traverse the
file directly.

### 4.3 Encapsulated internal components

The following components are internal to the logical LogService boundary and
are not exposed to ordinary engine services:

| Internal component | Responsibility |
| --- | --- |
| Runner-owned logging observer | Accept only trusted lifecycle facts and contract-accepted telemetry facts from applied deltas, preserve runner-established order, and seed the separate logging-internal envelope. It performs no logging-domain operation. |
| Event-definition lookup actions | Resolve one fact against the externally owned immutable registry and project only the definition-authorized shape. |
| Logging actions | Perform one logging responsibility each under the common node contract. |
| Logging orchestrators | Coordinate runner-owned logging child bindings without receiving filesystem, clock, serializer, redaction, sink, transaction, or logger capabilities. |
| Feature-log operation ports and adapter | Expose separate acquire/release, inspect, create, append/flush, recover/truncate, close, and prune views. A concrete adapter may implement several views, but no action receives the aggregate interface. |
| Trusted time sources | Supply UTC occurrence time and monotonic duration observations without becoming ordering authority. |
| Emergency adapter | Emit the one fixed content-free failure record without invoking the normal sink. |

These internals may exchange only the narrow typed values and capabilities
needed for their individual responsibilities. They must not be collapsed into
a public logger or one capability-heavy operation. Architecture checks prove,
for example, that append cannot prune, recovery cannot create a successor
segment, retention cannot append, and an orchestrator cannot receive any of
those ports.

## 5. Minimal consumer contract

### 5.1 Ordinary engine services

An ordinary action or service does not call `LogService` directly. When it has
an observable fact, it adds a closed, typed `TelemetryFact` to its normal
immutable result. For pipeline nodes, this is the validated
`NodeDelta.telemetryFactsAdded` collection. The runner applies the delta before
its logging observer receives the fact.

A fact may contain only fields declared for its registered kind, such as typed
IDs, enums, counts, durations, diagnostic codes, command IDs, exit codes, and
evidence outcomes. It must not contain a log level, message template, arbitrary
map, caller-defined sensitivity label, raw body, path to a sink, or persistence
instruction.

This is the only ordinary service-produced `TelemetryFact` path. Trusted
runner lifecycle facts use the separate runner-owned path in Section 5.2. Raw
prompt/model/reference/code bodies never enter `TelemetryFact`; the private
prompt-capture route in Section 5.4 is logging-internal and is not an alternate
arbitrary producer API. Any future non-node metadata producer requires an
explicitly approved runner-owned typed-fact integration and no direct logging-
adapter access.

### 5.2 Runner-only operations

The runner-owned observer may submit:

- trusted runner lifecycle facts; and
- contract-accepted telemetry facts from an applied node delta.

The runner receives only the standard `Outcome` and composite `NodeDelta` that
the common runner contract already owns. Ordinary consumers receive no stream
state, sink handle, lock token, configured threshold, event sequence, or
logging evidence that could be reused as workflow authority.

### 5.3 Lifecycle-only operations

Initialization, feature/run binding, policy transition, recovery, flush, and
the design-defined stream-close operations are private lifecycle operations
available only to the composition-root/runner-owned logging graph. They are not
general service APIs.

There is no consumer-facing `isEnabled` query. Producers report the same typed
fact regardless of the configured threshold; only
`EvaluateLogThresholdAction` produces the emit/drop decision.

### 5.4 Private prompt/body capture integration

Prompt/body capture has a separate compiler-locked input route; it never
widens `TelemetryFact`. The governing model/logging actions retain these
responsibilities:

1. `BuildPromptBodyFragmentManifestAction` accounts for every loggable typed
   request/result body field before provider serialization and classifies each
   as exactly one of `ordinary`, `reference_body`, or `code_body`;
2. `BuildPromptLogCandidateAction` applies the validated direction/class
   opt-ins without redacting, truncating, or emitting;
3. `RedactPromptLogContentAction` removes secrets;
4. `TruncatePromptLogContentAction` applies the UTF-8 byte ceiling only after
   redaction; and
5. `ValidatePromptLogContentAction` proves complete accounting, opt-ins,
   ordering evidence, field schemas, and byte bounds, then produces a transient
   logging-internal `SanitizedPromptExchangeLogRecord`.

Only the compiler-registered transient key carrying that sanitized record may
join the safe-record pipeline. It never enters the business envelope, a model
context, durable workflow state, or a producer-defined map. Raw, candidate,
redacted, truncated, and sanitized handles follow their declared last
consumers and are destroyed on every filtered, emitted, rejected, cancelled, or
failed branch.

### 5.5 Runner handoff and terminal barrier

Producer execution is isolated from logging operations. A business action
returns its typed fact in a candidate delta and neither invokes nor waits on a
sink. After the runner validates and applies that delta, the observer accepts
the fact in runner-established order and seeds the separate logging-internal
envelope. The observer performs no definition resolution, projection,
redaction, threshold evaluation, identity/sequence assignment, serialization,
or sink operation.

The runner alone invokes its child binding for the compiler-registered
`FeatureLoggingOrchestrator`. The registered actions own the logical processing
steps in Section 9.
The binding returns only the common `Outcome`; it introduces no logging-
specific terminal-disposition type or data key. For each accepted fact, its
child graph completes exactly one branch:

- below-threshold drop: `EvaluateLogThresholdAction` produces `drop`; the
  orchestrator returns `Outcome.status = ok` with its ordinary composite delta,
  and no event ID, sequence, segment identity, or stream lock was allocated;
- successful persistence: the orchestrator returns `Outcome.status = ok` only
  after the existing append, applicable flush, and lock-release action
  evidence is present in its ordinary composite delta; or
- logging failure: the orchestrator returns `Outcome.status = blocked` with
  the governing `block_new_work` result only after cleanup, emergency-write,
  and any required transaction-stabilization children complete.

The pipeline runner, not F0002, owns business-node scheduling and barrier
enforcement. It does not start the next applicable business node, activate a
successor logging policy, close a stream, or return the run's terminal outcome
until it has consumed the logging graph's standard `Outcome` and validated/
applied its composite delta. Error, fatal, and terminal lifecycle records
include their forced flush before the standard successful `Outcome` may
return.

V1 introduces no general asynchronous dispatcher, queue, worker, admission
state, dispatch ordinal, capacity pool, backpressure scheduler, or drain
deadline. The bounded transition buffer explicitly required by the governing
`FeatureLogPolicyTransitionOrchestrator` is a narrow authority-transition
mechanism, not a reusable dispatch lane. Any broader asynchronous design
requires an accepted amendment to the governing action/type/data-key
catalogues, compiled policy, failure state machine, diagram, and tests before
implementation.

## 6. Incoming authority contract

### 6.1 Fixed authority flow

The sole runtime source of the effective threshold and every other logging
setting is the exact persisted fragment revalidated into the active
`FeatureLogPolicy`. Runtime F0002 never consumes a configured spelling or
transient compiler value.

The ownership flow is fixed:

1. F0001 validates the exact project-root configuration and produces only its
   sealed, schema-valid logging-settings projection/evidence for runner-
   validated application;
2. the specialized compiler consumes that projection, performs the accepted
   canonicalization/policy-validation contracts, and produces one
   feature-independent transient `CompiledFeatureLoggingPolicyFragment`;
3. compiled-engine-policy/bootstrap-authority assembly incorporates the exact
   fragment, and only an accepted transaction persists it in
   `BootstrapAuthorityState`;
4. the workflow-artifact registry owner independently derives and validates the
   feature event/prompt collection identities;
5. feature-policy actions reconstruct and validate `FeatureLogPolicy` from
   the exact persisted current or historical fragment, immutable
   event-definition registry, feature identity, and artifact registry; and
6. binding actions construct and validate a fresh run's
   `FeatureLogBinding` from that policy, the active-feature-directory
   capability, run identity, and the same artifact registry.

Only after those joins pass may the runner seed the logging-internal envelope
with `FeatureLogPolicy`, `FeatureLogBinding`, and the immutable registry.
F0002 receives no `engine.config@1`, F0001 projection, transient compiler key,
raw configured level, bootstrap candidate, arbitrary path, or reader/filesystem
capability.

F0002, the specialized compiler, and every other non-F0001 component are
architecturally unable to discover, stat, open, watch, read, parse, or traverse
`.sddtoolkit.json`. The composition root wires contracts but does not
transport, transform, persist, or activate values.

### 6.2 Invalid or unavailable configuration and startup

Discovery, read, parse, schema, ingestion-seal, projection, canonicalization, or
policy-validation failure blocks bootstrap with no source-example, packaged
file, environment variable, model, caller, or hard-coded threshold fallback.

Before a feature-log binding is active, reporting is limited to bounded,
content-free emergency output. A new target must not create a feature directory
merely to hold a failure log. An existing target never reactivates a prior-run
binding: startup first creates the fresh `runId`, recovers feature ownership,
inventories and finalizes every prior-run binding group, reconstructs policy
from persisted current authority, and validates a fresh current-run
`FeatureLogBinding`. Only failures occurring after that point may use the
current-run feature sink.

### 6.3 Policy immutability and change

A validated `FeatureLogPolicy` is immutable for its bound persisted
bootstrap-authority state. A newly compiled fragment is only a candidate. A
same-run change becomes active only after the successor authority commits and
`FeatureLogPolicyTransitionOrchestrator` completes the exact old/new
transition. The runner owns the pause before later business nodes; the
orchestrator coordinates child bindings and receives no operation port.

Prior-run recovery uses the historical fragment reachable through each prior
binding's persisted authority lineage. It never interprets an existing segment
with a new root configuration or candidate fragment. A fresh run activates the
current persisted policy only after complete prior-run finalization.

### 6.4 Governing catalogue prerequisite

F0001 Section 4.5 identifies a higher-order conflict that F0002 cannot resolve
locally: `CanonicalizeLogLevelAction` owns spelling/alias conversion, while
`ValidateLoggingPolicyAction` does not consume its result/evidence and also
claims alias/threshold semantics. That creates duplicate functionality and an
unrepresented order dependency under governing Section 6.3.

The specialized compiler and F0002 integration remain blocked until the
governing catalogue assigns one canonicalization owner and represents the
dependency in typed inputs. The smallest single-responsibility resolution is
for the canonicalizer to produce canonical level plus alias evidence and for
the policy validator to consume that result while validating only complete
policy invariants. F0002 must not canonicalize configured text, duplicate the
check, depend on incidental graph order, or accept the raw spelling while this
decision is unresolved.

## 7. Canonical level contract

F0002 does not define a second level enum, spelling table, alias map, rank map,
or severity meaning. Governing design Section 26.5 owns the six canonical
variants, their ranks and meanings, and the closed configured-spelling/alias
table. After Section 6.4 is resolved, `CanonicalizeLogLevelAction` is the sole
configured-spelling conversion owner. The immutable
`LogEventDefinitionRegistry` separately owns only the assignment of one of
those canonical variants to each event definition; it does not own or redefine
the variants or ranks.

Runtime F0002 receives only a registry-assigned canonical event level and a
canonical threshold in the validated `FeatureLogPolicy`.
`EvaluateLogThresholdAction` is the sole comparison/emission-decision owner and
emits exactly when the governing rank of the event is at or above the governing
rank of the threshold. Threshold selection changes neither event meaning,
severity, redaction, workflow behavior, nor body-capture authorization.

Persisted records contain only canonical variants; aliases and raw configured
spellings are invalid at the runtime boundary and during recovery. Raw-name,
case, and alias conformance tests belong to the specialized compiler.
F0002 owns the exhaustive canonical-level threshold matrix and rejection of an
alias-bearing persisted record.

## 8. Event-definition authority

The compiler-owned immutable `LogEventDefinitionRegistry` is the sole
event-definition authority. F0002 neither constructs nor mutates it.
`ResolveLogEventDefinitionAction` performs exactly one runtime lookup: every
observable fact kind must resolve to one entry in that exact validated
registry. Each registry definition owns:

- the canonical event kind and level;
- the fixed message template or rendering identity;
- required and optional typed fields;
- the allowed field set;
- sensitivity classification for every field;
- any context-dependent severity rule.

Producers contribute facts, not log records. A producer cannot downgrade a
fatal event to trace, elevate ordinary behavior to error, replace a message
template, add an undeclared field, or declare sensitive data public.

Model output is never a trusted event producer. The runner may emit registered
facts about a model invocation or validated result, but a model cannot create a
log event, choose its level or template, supply its destination, or give its
claims logging or workflow authority.

Context-sensitive severity must be explicit in the registry. For example, a
retryable schema rejection may be `warning`, while exhaustion is `error`; an
expected red test is not an operational error; and an expected rollback may be
`info`, while rollback caused by persistence failure is `error`.

An unregistered fact kind, invalid field type, missing required field, extra
field, or inconsistent context is rejected as a typed instrumentation failure.
It must not be converted into a best-effort free-form record.

## 9. Record processing

The observer performs none of these operations. For one accepted lifecycle or
metadata fact, the runner-invoked graph uses discrete actions to:

1. resolve exactly one event definition;
2. build one bounded definition-shaped draft from typed context/fact fields;
3. omit prohibited fields and apply one-field-at-a-time registry-owned
   redaction;
4. evaluate the canonical event level against the canonical policy threshold;
5. on a below-threshold `drop` decision, destroy applicable transient values
   and return without
   assigning an event ID, sequence, segment identity, or stream lock;
6. on admission, assign the event ID, trusted UTC/monotonic observations, and
   next sequence from matching per-run/per-stream state;
7. validate the complete safe discriminated record against its closed schema
   and encoded-size ceiling;
8. serialize one fixed-order UTF-8 JSON object followed by one line feed;
9. acquire and validate the exact operation-specific stream-lock capability;
10. append to the active segment or invoke the separately authorized
    rotation/retention actions;
11. apply the bound flush policy; and
12. release the exact lock on every success, rejection, failure, or
    cancellation branch before returning the standard `Outcome`.

Optional prompt/body content follows the separate Section 5.4 chain first.
Only its already validated transient `SanitizedPromptExchangeLogRecord` may
join the appropriate discriminated safe-record validation step. Runtime event
processing never selects, classifies, or redacts raw prompt fragments a second
time, and metadata facts never carry them.

The complete frame is encoded before lock acquisition and is never split
across writes. Runner-established per-stream processing order and terminal
barriers prevent a later accepted fact from committing ahead of an earlier
fact. Logging-internal actions and orchestrators are excluded from recursive
observation.

## 10. Event content and privacy

### 10.1 Mandatory metadata stream

The event stream is metadata-only. Registered records may include:

- run, feature, stage, node, parent, and correlation IDs;
- attempt and sequence numbers;
- trusted timestamps and durations;
- registered enums, state transitions, and diagnostic codes;
- model route/profile IDs and token counts;
- command IDs, bounded exit status, and duration;
- repair-unit kinds and evidence outcomes;
- bounded counts and policy/rule IDs.

Metadata records must never contain:

- diagnostic free-form `message`, `actual`, or `expected` bodies;
- credentials, keys, tokens, or environment-variable values;
- arbitrary caller text or maps;
- raw prompts or model responses;
- reference bodies;
- source code, patches, or file contents;
- command output;
- raw paths, path-shaped text, capabilities, opaque handles, or lock tokens.

When location correlation is required, an event definition may admit only the
appropriate registered typed identifier; it cannot admit a caller-supplied
path.

These exclusions apply at every level, including `trace`.

### 10.2 Optional prompt and body stream

Prompt/body logging is a separate stream and defaults to off. It remains off
even when the configured threshold is `trace`.

This subsection states the sanitized record's privacy invariants; the Section
5.4 actions are the sole owners of fragment accounting, selection, redaction,
truncation, and validation behavior.

Enabling it requires independent, validated opt-ins for:

- request bodies;
- response bodies;
- reference-body fragments; and
- code-body fragments.

A direction opt-in is necessary for every selected fragment, and a reference
or code fragment also requires its class-specific opt-in. Opaque whole-body
capture is forbidden.

For every selected fragment, structured secret fields, mandatory credential
detectors, and configured bounded detectors run before truncation. Redaction
uses fixed category markers that reveal neither the original value nor its
length. Truncation then occurs at a UTF-8 scalar boundary, after which the
bounded sanitized record is schema-validated again. All transient fragment
handles are destroyed whether the record is emitted, filtered, rejected, or
fails at the sink.

## 11. Destinations and storage

### 11.1 Registry-owned destinations

For an active feature, the **feature specification root** is the validated
`<paths.specs>/<featureId>/` authority carried by the
`WorkflowArtifactRegistry` and active-feature capability. The registry is the
sole collection-path owner. F0002 neither joins raw path segments nor
recalculates containment.

The governing selector table renders the event and prompt collection shapes
documented in design Section 26.5. These human-readable shapes are conformance
information, not a second path authority:

- mandatory events:
  `<paths.specs>/<featureId>/logs/events/<runId>/<featureLogBindingId>/<segmentOrdinal>.jsonl`;
- optional prompt exchanges:
  `<paths.specs>/<featureId>/logs/prompts/<runId>/<featureLogBindingId>/<segmentOrdinal>.jsonl`.

Before any file access, binding validation proves that the policy, validated
`featureId`, active-feature capability, run, `FeatureLogBinding`, and
registry-owned collection identity all join the same feature specification
root. A missing, stale, foreign, cross-feature, raw, model/config-selected, or
otherwise unregistered binding fails closed. Logging actions receive only the
validated binding and operation-specific port, never a caller-selected path.

The mandatory JSONL event sink cannot be disabled. No record may be written to
another feature specification root or to a shared project, process, user-home,
current-working-directory, or global persistent log. Concurrent features use
distinct bindings, sink states, collection identities, segments, and locks;
records are never merged across those boundaries.

An optional console mirror may reproduce only the validated safe feature-bound
record under validated policy. It is ephemeral presentation, does not replace
the mandatory event sink, and cannot reveal another field.

No ordinary persistent log may exist outside the feature specification root.
Fixed content-free emergency `stderr` is the sole out-of-root reporting path
when no current binding exists or the initialized pipeline/sink fails. It is
not an ordinary log, contains no feature content, and cannot create or
substitute a shared persistent sink.

### 11.2 Permissions and path safety

Feature log directories must be owner-only. Segment files must use owner
read/write permissions, exclusive creation, no-follow regular-file operations,
and validated contained paths. Aliases, escaping paths, symlinks, special
files, collisions, or insecure existing permissions block logging.

Log collections are excluded from editable specifications, generated
plan/task views, stage/task transaction membership, repository/reference
discovery, model context, unexpected-project-change detection, and default
artifact export.

### 11.3 Ordering and concurrency

One exclusive lock capability governs each `(featureId, runId, stream)` while
the adapter inspects, recovers, rotates, appends, prunes, or flushes that
stream. Opaque lock tokens remain runner-held and are never serialized, logged,
or exposed to a model or ordinary service.

Sequence is the ordering authority; trusted UTC timestamps are informational
and monotonic time is used for durations. Each enabled stream in a fresh run
starts at sequence one. A same-run policy transition continues at the prior
binding's final sequence plus one. A sequence is never reused within one
`(featureId, runId, stream)` tuple, a binding-local ordinal is never reused
within its binding, and every complete segment-identity tuple remains distinct.

### 11.4 Flush, rotation, and retention

- `error`, `fatal`, and every terminal stage/task/transaction event force a
  flush.
- Lower levels follow the validated bounded count/time flush policy.
- A record larger than the validated maximum is rejected; it is never split.
- Rotation closes and flushes the active segment before exclusive-creating the
  authorized next segment.
- The hard segment count applies across all policy bindings for the complete
  `(featureId, runId, stream)` lifetime. A policy transition cannot reset it.
- Retention cannot create capacity for an exhausted active-run ordinal and
  cannot authorize identity reuse.
- Retention may remove only explicitly authorized closed segments, oldest
  first by the validated retention order, and never the active segment.
- Pruning is the only permitted destructive log operation.

When a record cannot fit and the lifetime segment cap is exhausted, the
runner-invoked graph must return the typed logging failure and enter the fail-
closed path. It must not drop the admitted record silently or exceed the cap.

### 11.5 Restart recovery

Before a fresh current-run sink is initialized, the runner-invoked startup
graph coordinates discrete actions that inventory every bounded prior-run
binding group in deterministic order and resolve its exact historical logging
authority. The relevant actions acquire the prior stream lock, then validate
an already-closed tail or recover an active tail and close it durably.

Recovery may truncate only bytes after the last complete, valid,
line-feed-terminated final record. Interior malformed JSON, wrong run, binding,
or stream, sequence regression, a persisted alias instead of a canonical
level, insecure permissions, incomplete inventory, or missing release evidence
blocks recovery. Corrupt records are never skipped.

Current-policy construction, `run.started`, and normal work remain unreachable
until complete prior-run finalization and lock-release evidence validates.

## 12. Failure semantics

Logs are observability only. They never establish that a task, stage,
transaction, approval, recovery, or workflow succeeded, failed, committed, or
rolled back. Their absence cannot be used to infer any such outcome.

Transaction events are submitted only after the corresponding durable
transition. In particular, a transaction cannot be logged as committed before
its commit marker is durable.

Configuration discovery, reading, parsing, canonicalization, or policy
validation failure follows the preactivation rules in Section 6.2. It fails
bootstrap and does not invoke an initialized feature-sink failure flow that may
not yet exist.

If an initialized logging pipeline's safety validation, locking,
serialization, append, flush, rotation, retention, recovery, policy transition,
or sink operation fails, the subsystem must:

1. release or terminalize every acquired logging capability and destroy every
   transient content handle;
2. emit exactly one fixed, bounded, content-free emergency record to the
   emergency `stderr` adapter without invoking the failed sink;
3. when a workflow transaction is already prepared or applying, invoke the
   existing transaction-recovery boundary to restore or finish it to a stable
   state while preserving a durable commit;
4. return the common `Outcome` with `status = blocked` and
   `BuildLoggingBlockedControlAction`'s typed `block_new_work` result in its
   composite delta before the runner starts the next business node.

The logging failure path is excluded from normal logging observation. It must
never recursively log itself, claim recovery that did not occur, downgrade the
failure, silently drop an admitted mandatory event, or continue with an
obsolete or partially switched policy.

`FeatureLoggingFailureOrchestrator` owns only this child ordering and typed
branching. `DestroyRawPromptLogHandlesAction` owns transient cleanup,
`EmitEmergencyLogFailureRecordAction` owns the one emergency write,
`TransactionRecoveryOrchestrator` owns transaction stabilization, and
`BuildLoggingBlockedControlAction` owns construction of the blocked result.
The failure orchestrator receives no sink, filesystem, journal, transaction,
or workflow-state port.

## 13. Acceptance criteria

This feature is acceptable only when all of the following are true:

1. Every trusted lifecycle fact and applied-delta `TelemetryFact` follows one
   runner-invoked logging graph under exactly one current validated
   `FeatureLogPolicy` and `FeatureLogBinding`.
2. `LogService` is not implemented as a facade, singleton, generic logger,
   `PipelineNode`, dispatcher, or authority object. `NodeRuntime` remains
   capability-free; orchestrators receive only child bindings; each action
   receives only its one operation-specific port.
3. An unrelated action fixture proves facts can be returned only through a
   candidate delta that the runner validates/applies. Observer tests prove it
   only accepts/orders facts and seeds the logging envelope; definition lookup,
   projection, redaction, thresholding, sequencing, serialization, and sink
   work remain discrete actions.
4. F0001 is the sole `.sddtoolkit.json` ingestion boundary. The compiler
   consumes only F0001's sealed logging projection; only the bootstrap-
   authority transaction owner persists a state incorporating the transient
   compiled fragment; runtime F0002 rejects raw config, the reader projection,
   the transient compiler key, and an unpersisted bootstrap candidate.
5. Before the logging compiler/F0002 seam is implemented, the governing action
   catalogue resolves Section 6.4's duplicate canonicalization ownership and
   represents the result/evidence dependency. No local duplicate, hidden order,
   or raw-spelling shortcut is permitted.
6. Runtime receives the one compiler-owned immutable
   `LogEventDefinitionRegistry`; F0002 cannot construct or mutate it, and one
   `ResolveLogEventDefinitionAction` lookup determines each fact's canonical
   level, template, allowed/required fields, and sensitivity.
7. An exhaustive canonical-level threshold matrix proves
   `EvaluateLogThresholdAction` admits exactly events at or above the active
   canonical threshold. A filtered fact consumes no event ID, sequence,
   segment identity, or stream lock.
8. Unknown facts, arbitrary messages/maps, extra fields, wrong field types,
   producer-selected levels/templates/sensitivity, and model-created events
   fail closed.
9. Raw prompt/model/reference/code bodies never enter `TelemetryFact`.
   Only the Section 5.4 action chain may produce the transient
   `SanitizedPromptExchangeLogRecord` used by safe-record validation.
10. The workflow-artifact registry is the sole log-collection path authority.
    Every file operation requires a current validated binding joining the exact
    feature, run, persisted policy, active-feature capability, and registered
    collection; no F0002 action derives a path.
11. Metadata remains free of prohibited content at every canonical threshold,
    including `trace`.
12. Prompt/body capture is off by default and remains unavailable until all
    direction/class opt-ins, complete fragment accounting, redaction-before-
    truncation evidence, UTF-8/size validation, retention, and sink protections
    pass. Every transient handle is destroyed after its last consumer on every
    terminal branch.
13. Concurrent process writers preserve exclusive stream ownership and
    monotonic sequence. Every terminal branch releases or safely terminalizes
    its exact lock, and operation-port tests prove append cannot prune,
    recovery cannot create a successor, and retention cannot append.
14. Flush, rotation, retention, lifetime segment caps, permissions, and record
    size limits remain bounded and permit neither silent loss nor identity
    reuse.
15. Restart recovery covers active, already-closed, mixed, duplicate, missing,
    wrong-binding, corrupt, and insecure prior-run groups. Only an incomplete
    final frame may be truncated; interior corruption blocks.
16. A same-run policy transition occurs only after the successor authority
    commits, uses the governing bounded transition buffer, switches all streams
    atomically, continues sequence correctly, and cannot reset lifetime caps.
17. Historical recovery uses each persisted historical fragment and never
    reinterprets a segment with current root configuration or a candidate
    fragment.
18. Every initialized-pipeline failure invokes the non-recursive failure graph
    once, releases/terminalizes capabilities and transient handles, emits one
    content-free emergency record, stabilizes an already prepared/applying
    transaction through `TransactionRecoveryOrchestrator`, preserves a
    durable commit, and returns the common `Outcome` with `status = blocked`
    and the governing `block_new_work` result.
19. Missing, filtered, deleted, or tampered logs cannot satisfy or alter any
    workflow transition, approval, evidence predicate, recovery result, or
    completion state.
20. Producer execution and delta return perform no logging operation. After
    delta application the runner consumes the common `Outcome` and validates/
    applies its ordinary composite delta: `ok` contains either the governing
    threshold `drop` decision or the applicable append/flush/release evidence,
    while `blocked` contains the governing `block_new_work` result. This occurs
    before the next applicable business-node barrier. No background
    dispatcher, queue, worker, capacity pool, backpressure policy, or drain
    deadline exists in v1.
21. Two concurrently active features retain distinct policies, bindings, sink
    states, feature specification roots, segments, locks, records, and failure
    outcomes; neither can write into or reuse the other's authority.
22. Before a fresh current-run binding is valid, startup failures use only
    bounded content-free emergency output. A prior-run binding is never
    reactivated; feature logging begins only after ownership recovery,
    historical finalization, persisted-policy reconstruction, and fresh-binding
    validation.
23. The packaged native executable proves the same authority, isolation,
    recovery, and no-source-tree behavior without examples, development assets,
    a Zig toolchain, or build cache.

## 14. Verification plan

Implementation work derived from this feature must provide the following
evidence at the owning boundaries.

### 14.1 Authority and architecture tests

- one shared seam fixture proving the specialized compiler accepts exactly
  F0001's sealed logging projection/evidence, while runtime F0002 accepts only a
  persisted-authority-derived `FeatureLogPolicy`, exact
  `FeatureLogBinding`, and immutable event-definition registry;
- rejection of raw configuration, F0001 private/projection keys, transient
  compiler fragments, unpersisted bootstrap candidates, and every direct
  `.sddtoolkit.json` discovery/read/watch/reread capability outside F0001;
- a governing-catalogue conformance check proving Section 6.4 has one
  canonicalization owner and an explicit typed dependency before the compiler
  integration is enabled;
- compiler-owned tests (referenced, not duplicated here) for configured name,
  case, alias, canonicalization, invalid type/value, and no-fallback behavior;
- complete F0002 canonical-level threshold matrix plus rejection of aliases in
  runtime values and persisted records;
- event-definition lookup and required/extra/wrong-field rejection, including
  producer/model attempts to select severity, template, path, or sensitivity;
- architecture tests proving no logger capability in `NodeRuntime` or domain
  services, no operation port in orchestrators, no aggregate feature-log port
  in an action, and only responsibility-specific port views; and
- observer/runner tests proving the observer only accepts/orders facts and
  seeds the logging envelope, while the runner alone invokes child bindings,
  validates/applies deltas, enforces barriers, and branches on the common
  `Outcome` plus existing action results/evidence.

### 14.2 Content and prompt security tests

- prohibited metadata fields at every canonical level;
- prompt logging disabled by default and at `trace`;
- proof raw bodies cannot inhabit `TelemetryFact` or the business envelope;
- complete fragment-manifest accounting and every direction/class opt-in
  combination, including missing, duplicate, and multiply classified
  fragments;
- secret detection and fixed-marker replacement before UTF-8-safe truncation;
- acceptance of only the compiler-locked transient
  `SanitizedPromptExchangeLogRecord` at the safe-record join;
- transient-handle destruction after every last consumer on filtered,
  persisted, rejected, cancelled, and failed paths; and
- raw, escaping, aliased, symlinked, special-file, and insecure-permission
  rejection before file access.

### 14.3 Storage, concurrency, and recovery tests

- exact registry-owned event/prompt collection identities and rendered shapes,
  with proof no logging action derives a path;
- simultaneous runs for two features proving distinct feature specification
  roots, policies, bindings, sink states, segments, locks, records, and failure
  outcomes with no cross-feature write;
- missing, foreign, stale, raw, and cross-feature identity/binding rejection
  before file access, plus proof no global persistent log is created;
- operation-port negative tests: append cannot prune, recovery cannot create or
  rotate a successor, retention cannot append, and lock acquisition cannot
  inspect/write;
- complete-frame fixed-order JSONL serialization;
- concurrent-process append ordering and exact lock release/terminalization on
  success, rejection, failure, and cancellation;
- forced flush for `error`, `fatal`, and terminal lifecycle events;
- record/segment bounds, rotation, retention, and lifetime-cap exhaustion;
- incomplete final-frame recovery and rejection of interior corruption,
  binding/stream mismatch, persisted aliases, and sequence regression;
- prior-run active, closed, mixed, duplicate, missing-release, wrong-binding,
  and orphan-release cases; and
- same-run policy transition and historical-policy reconstruction.

### 14.4 Runner handoff and barrier tests

- a delayed fake sink proving producer execution/delta return performs no
  logging work, nothing starts before delta application, and the runner does
  not cross the next applicable barrier before consuming the common `Outcome`
  and validating/applying its composite delta;
- `ok` with below-threshold `drop`, `ok` with successful append/flush/release,
  and `blocked` with `block_new_work` branch tests, including forced-flush
  completion before the successful `Outcome` returns;
- observer-spy tests proving definition resolution, redaction, thresholding,
  identity/sequence assignment, serialization, and file operations occur only
  in their named actions;
- next-node, policy-transition, stream-close, and terminal-run barriers;
- architecture rejection of a background dispatcher, queue/worker, dispatch
  ordinal, capacity/backpressure state, or drain-deadline data key/policy;
- proof the runner-owned transition buffer exists only while the governing
  `FeatureLogPolicyTransitionOrchestrator` route is active, is not an operation
  capability exposed to that orchestrator or its actions, and cannot become a
  normal dispatch lane; and
- ownership cleanup for every logging-internal delta value and prompt handle.

### 14.5 Failure and end-to-end tests

- definition, redaction, threshold, identity, serialization, lock, append,
  flush, rotation, retention, recovery, and transition failures;
- exactly one emergency record and no recursion for each initialized-pipeline
  failure;
- spy-child proof that `FeatureLoggingFailureOrchestrator` owns only ordering
  and has no sink/filesystem/journal/state port;
- new-target and pre-fresh-binding emergency-only behavior, followed by
  existing-target feature logging only after historical finalization and fresh
  current-binding validation;
- prepared/applying transaction stabilization and preservation of durable
  commits;
- proof normal work cannot proceed after `block_new_work`;
- fake-model end-to-end runs covering canonical thresholds, exact feature
  bindings, event/prompt crash points, recovery, transitions, and
  non-authoritative logs; and
- clean native-executable coverage proving runtime logging does not depend on
  source examples, source tree, build cache, Zig toolchain, or development-only
  assets.

## 15. Traceability

| Feature concern | Governing design authority |
| --- | --- |
| Engine ownership and trust boundary | Sections 1, 3, and 4 |
| Dependency direction and capability-free nodes | Sections 5 and 6 |
| Exclusive `.sddtoolkit.json` ingestion and persisted-policy authority flow | [F0001 — SDDToolKitReader](F0001-SDDToolKitReader.md), plus Sections 9, 13.1-13.2, and 15 |
| Discrete logging actions | Section 13.9 |
| Separate sanitized prompt-record route | Section 13.4 |
| Failure and policy-transition orchestration | Sections 14.9 and 14.10 |
| Levels, privacy, sinks, durability, and recovery | Section 26.5 |
| Feature specification root and registry-owned storage isolation | Sections 9.1, 13.2, and 26.5 |
| Runner handoff, common `Outcome`/delta contract, and v1 no-dispatcher boundary | Sections 6, 13.9, 14.9-14.10, and 27-28 |
| Runner-owned observability | Section 27 |
| Required tests | Section 28 |
| Delivery ordering | Section 30, Increment 1 |
| Production-evaluation criteria | Section 31, especially criteria 5-8, 34, and 35 |
