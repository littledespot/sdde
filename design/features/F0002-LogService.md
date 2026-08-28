# F0002 — LogService

**Status:** Proposed feature design

**Implementation readiness:** Ready for the bounded initial implementation.
The workflow-owned `WorkflowLog` producer contract supplies
`WorkflowShortcode`, the F0001 v2 logging shape supplies every configurable
user choice, and all operational policy plus the two `feature-log/v2`
pipe-delimited schemas are compiler-locked
constants. The event registry, scalar row encodings, and operational limits in
this document are complete for the proof of concept.

**Compatibility:** None. This is a pre-release proof of concept with no
deployed predecessor. `feature-log/v2`, its two column schemas, and config
`2.0` are updated in place; the implementation MUST NOT contain migrations,
aliases, dual readers/writers, historical conversion, or compatibility
fallbacks. Recovery accepts only the exact current headings and contracts.
After a contract is explicitly accepted for release, subsequent incompatible
changes require a new version.

**Classification:** Core, cross-cutting feature logging

**Scope:** SDDE engine development. This document does not authorize running
SDDE against a target project.

**Governing authority:** [Engine design](../design.md), especially Sections
5-6, 9, 13.9, 14.9-14.10, 26.5, and 27-31; [F0001 —
SDDToolKitReader](F0001-SDDToolKitReader.md); and the
[feature logging diagram](../diagrams/06-feature-logging.mmd).

---

## 1. Responsibility

F0002 gives each workflow one simple producer binding, `WorkflowLog`, whose
`workflowLog.log(delta, TelemetryFact)` operation adds one attributed closed
typed fact to an action's candidate delta; it does not write, filter, format,
or flush a record.
After the runner validates and applies that delta, F0002 converts the fact, or
a separately sanitized prompt exchange, under one validated feature/run
logging policy and binding into a safe non-authoritative record. An input is
either filtered, persisted successfully, or produces a typed fail-closed
outcome.

Every F0002 input originates from a workflow-owned producer binding. Every
emitted record carries the mandatory four-character shortcode supplied by that
calling workflow.

F0002 is not a general logger. Producers cannot choose a level, message, path,
sink, format, or redaction rule, and they never receive a filesystem or logger
capability.

## 2. Minimal runtime contract

The runner invokes the logging graph with:

- one trusted runner lifecycle fact attributed through the active workflow's
  `WorkflowLog`, validated `WorkflowTelemetryFact` from an applied node delta,
  or validated transient `SanitizedPromptExchangeLogRecord` from the separate
  optional-content sanitization pipeline;
- the active validated `FeatureLogPolicy`;
- the exact `FeatureLogBinding`; and
- the immutable compiler-owned `LogEventDefinitionRegistry`.

The graph returns the existing common `Outcome` and composite `NodeDelta`:

| Result | Required meaning |
| --- | --- |
| `ok` with drop evidence | The event is below threshold; no event identity, sequence, lock, or write is created. |
| `ok` with persistence evidence | The complete safe record was appended, any required flush completed, and the stream lock was released. |
| `blocked` | Logging failed; cleanup, emergency reporting, and required transaction stabilization completed before new work was blocked. |

There is no logging-specific public response type or direct producer-to-sink
call. `WorkflowLog.log` returns only candidate-delta construction success or
failure; the runner-owned logging graph owns the later drop, persistence, or
blocked outcome.

## 3. Authority and single ownership

### 3.1 Configuration flow

F0002 never reads `.sddtoolkit.json` and never receives `SDDToolKitConfig` or
`LogsConfig` at runtime:

```text
F0001 immutable config
  -> logging-policy compiler reads config.logs
  -> compiled fragment enters persisted bootstrap authority
  -> active FeatureLogPolicy and FeatureLogBinding
  -> F0002
```

`CanonicalizeLogLevelAction` alone converts configured case and aliases into a
canonical level. `ValidateLoggingPolicyAction` consumes that canonical result
and validates the remaining logging policy; it does not canonicalize the level
again. F0002 receives only the validated result.

The accepted v2 `LogsConfig` has exactly three values:

- `level`: the emission threshold spelling;
- `console`: whether an additional pipe-delimited data-row mirror is enabled;
  it never controls the mandatory file sink; and
- `promptCapture`: a unique list drawn from `request`, `response`,
  `reference_body`, and `code_body`; `[]` disables body capture.

F0001's direct typed decoder enforces the closed contract published as
`design/schemas/sddtoolkit-config-v2.schema.json`; no generic JSON tree or
runtime schema dependency is required. The logging-policy compiler owns all
value semantics and injects every operational constant in Section 6.4. Paths,
levels on individual events, timestamp/format/limits, retention, flush,
redaction, failure behavior, prompt byte limits, lock policy, and delimited
columns/headings are deliberately absent from configuration.

Configuration read, decode, canonicalization, validation, persistence, and
runtime logging therefore each have one owner and one direction of flow.

### 3.2 Workflow shortcode flow

The shortcode originates from the workflow that calls the producer API:

```text
workflow constructs WorkflowLog("IMPL") once
  -> WorkflowLog validates and retains WorkflowShortcode
  -> workflow calls workflowLog.log(delta, TelemetryFact)
  -> WorkflowTelemetryFact in the candidate delta
  -> runner validates and applies the delta
  -> F0002 record
```

`WorkflowLog.init` accepts exactly four case-sensitive ASCII alphanumeric
characters and constructs the typed `WorkflowShortcode`. A workflow normally
constructs this binding once and reuses it for all its calls. The shortcode is
not read from `*.workflow.yaml`, configuration, a model response, or stored log
data. It is observability metadata, not workflow identity or authority.

Illustrative workflow-owned bindings are:

```zig
const specify_log = try WorkflowLog.init("SPEC");
const plan_log = try WorkflowLog.init("PLAN");
const tasks_log = try WorkflowLog.init("TASK");
const implement_log = try WorkflowLog.init("IMPL");
const audit_log = try WorkflowLog.init("AUDT");
const drift_log = try WorkflowLog.init("DRFT");
const initialise_log = try WorkflowLog.init("INIT");
```

These values are examples, not a registry. Each workflow owns its selected
value.

The workflow roles currently being considered are:

1. `specify`;
2. `plan`;
3. `tasks`;
4. `implement`;
5. `audit`;
6. `drift`; and
7. `initialise`.

This is a consideration list, not an accepted role registry. The governing v1
workflow remains `specify -> plan -> tasks -> implement`; accepting `audit`,
`drift`, or `initialise` requires the corresponding governing workflow design,
graph, gate, and acceptance-test changes. Any implemented workflow must supply
its own valid shortcode whenever it produces a log fact.

### 3.3 Other authorities

| Authority | Sole owner |
| --- | --- |
| Event level, template, field schema, and sensitivity | `LogEventDefinitionRegistry` |
| Four-character workflow shortcode source and validation | Calling workflow through `WorkflowLog.init` |
| Workflow-shortcode/fact binding | `WorkflowLog.log` and delta validation |
| Emit/drop comparison | `EvaluateLogThresholdAction` |
| Feature log collection paths | `WorkflowArtifactRegistry` and validated `FeatureLogBinding` |
| Fact ordering and business-node barriers | Pipeline runner |
| Transaction stabilization | `TransactionRecoveryOrchestrator` |
| Concrete adapters and child graph construction | Composition root |

F0002 does not recreate any of these decisions. The actions in governing
Section 13.9 remain the canonical responsibility catalogue; this feature does
not define a parallel action list.

## 4. Producer contract

Each workflow constructs one pure producer binding and its actions report
observability through that binding:

```zig
const workflow_log = try WorkflowLog.init("IMPL");

pub fn log(
    self: WorkflowLog,
    delta: *NodeDelta,
    fact: TelemetryFact,
) !void;
```

The call is delta construction, not direct logging I/O. It appends the fact to
`NodeDelta.telemetryFactsAdded` together with `self.workflow_shortcode` as one
`WorkflowTelemetryFact`; it grants no sink, filesystem, clock, or runner
capability. The runner validates and applies the complete delta before handing
the attributed fact to the logging graph. The calling workflow, not a workflow
YAML document or the runner, supplies the shortcode.

The call shape is intentionally concise:

```zig
try workflow_log.log(delta, .{
    .task_started = .{
        .task_id = task_id,
    },
});

try workflow_log.log(delta, .{
    .task_completed = .{
        .task_id = task_id,
        .outcome = .completed,
        .duration_ms = duration_ms,
    },
});

try workflow_log.log(delta, .{
    .validation_failed = .{
        .validator_id = validator_id,
        .diagnostic_code = diagnostic_code,
        .outcome = .rejected,
    },
});
```

These examples define the public shape. Each accepted `TelemetryFact` variant
maps to exactly one event in the closed proof-of-concept registry in Section
6.2. The registry, rather than the caller, supplies its canonical level,
message-template ID, fields, and sensitivity.

A fact may contain registered typed IDs, enums, counts, durations, diagnostic
codes, command IDs, exit codes, and evidence outcomes. It cannot contain:

- a level or message;
- another shortcode inside the fact payload;
- an arbitrary text/map payload;
- a caller-selected sensitivity label;
- raw prompt, response, reference, code, patch, or command-output content; or
- a path, sink, or persistence instruction.

Runner lifecycle facts use the same logging graph. A model response is never a
trusted fact or event definition.

## 5. Record processing

For an accepted fact, the runner-invoked graph performs the discrete actions
defined in governing Section 13.9:

1. require the exact-four-character `WorkflowShortcode` carried by the
   workflow-produced `WorkflowTelemetryFact`;
2. resolve the one registered event definition;
3. project only its allowed typed fields and apply required redaction;
4. evaluate the definition's canonical level against the canonical threshold;
5. if admitted, assign the workflow shortcode, the same canonical level,
   trusted time, event identity, and sequence to the record;
6. validate and serialize one bounded fixed-column pipe-delimited data row;
7. append and flush/rotate as required under the exact stream lock; and
8. release the lock before returning the common outcome.

The steps remain separate action responsibilities. Their orchestrator receives
runner-owned child bindings and no filesystem, clock, serializer, redaction,
or sink capability.

Filtering occurs before event identity, sequence, segment, or lock allocation.
Logging-internal nodes are not recursively observed.

## 6. Levels and content safety

### 6.1 Mandatory workflow attribution

Every serialized log record MUST contain exactly one `workflow_shortcode`
value. In a delimited row it occupies the `workflow_shortcode` column; in the emergency
record it occupies the `workflow` field. It MUST be the typed shortcode
supplied by the workflow that produced the fact and MUST contain exactly four
case-sensitive ASCII
alphanumeric characters. This applies to mandatory event records, optional
sanitized prompt-fragment records, console-mirrored records, and the fixed
emergency record.

`WorkflowLog.init` is the single shortcode validator. F0002 accepts only the
resulting typed value; it does not truncate, pad, normalize, infer, or replace a
missing value. Raw shortcode text inside a fact, model output, configuration,
workflow YAML, or stored log record is never accepted. Missing or malformed
values fail before the fact enters an applied delta; a missing or invalid typed
binding at the runtime boundary fails closed before serialization.

### 6.2 Levels and content safety

The canonical levels, ranks, aliases, meanings, and threshold rule are defined
once in governing Section 26.5. F0002 uses those types and does not define a
second enum or alias table. The registry owns an event's level; the configured
level is the emission threshold. A producer supplies neither value.

Every serialized log record MUST contain one canonical `level` value from
Section 26.5. Delimited records use the `level` column and the emergency record uses
the `level` field. This applies to mandatory event records,
optional sanitized prompt-fragment records, console-mirrored records, and the
fixed emergency record. A missing, aliased, unknown, or caller-supplied level
is rejected before serialization or emission. A fact filtered below the
threshold creates no record and therefore is not a log record missing a level.

The following is the complete proof-of-concept event registry. Event names are
closed and case-sensitive. For every row, `message_template_id` is exactly
`<event_type>/v1`; this identifier is the complete template contract and there
is no rendered or free-text message. “Required” and “optional”
refer to event-specific columns in addition to the common record identity,
time, workflow, run, feature, and context. Every event/prompt data row requires
`record_kind`, schema/stream/policy/binding/segment identity,
`workflow_shortcode`, `event_id`, `sequence`, `occurred_at_utc`,
`monotonic_offset`, `level`, `event_type`, `message_template_id`, `run_id`, and
`feature_id`. Event rows may additionally use the common optional
`stage`, `node_id`, `parent_event_id`, `correlation_id`, `attempt`, and
`evidence_status` fields. Prompt rows may use optional `stage` and `node_id`;
their other fields are listed by `model.prompt_fragment`. A field is permitted
only when it is common or listed for that event below; every other column is
`\N`. Every metadata field is
classified `public_metadata`; arbitrary strings and unregistered fields are
forbidden.

Field types are closed: all `*_id` values are their corresponding validated
opaque identifier types; `diagnostic_code`, `stage`, `outcome`,
`evidence_status`, `repair_unit_kind`, `direction`, and `body_class` are closed
enums; `attempt`, `duration_ms`, token counts, `retained_bytes`, and `count` are
non-negative bounded integers serialized as canonical decimal ASCII;
`exit_code` is a bounded signed integer; booleans are lowercase `true` or
`false`; time/offset use the canonical trusted-clock representations; and
`content` is bounded sanitized UTF-8. No generic string, map, or list field is
registered.

| Event type | Level | Required fields | Optional fields |
| --- | --- | --- | --- |
| `run.started` | `info` | — | — |
| `run.completed` | `info` | `outcome` | `duration_ms` |
| `run.blocked` | `error` | `diagnostic_code`, `outcome` | — |
| `run.failed` | `error` | `diagnostic_code`, `outcome` | — |
| `run.cancelled` | `info` | `outcome` | — |
| `stage.started` | `info` | — | — |
| `stage.completed` | `info` | `outcome` | `duration_ms` |
| `stage.blocked` | `error` | `diagnostic_code`, `outcome` | — |
| `stage.failed` | `error` | `diagnostic_code`, `outcome` | `duration_ms` |
| `stage.clarification_pending` | `info` | `outcome` | — |
| `action.started` | `debug` | — | — |
| `action.completed` | `debug` | `outcome` | `duration_ms` |
| `action.invalid` | `warning` | `diagnostic_code`, `outcome` | — |
| `action.failed` | `error` | `diagnostic_code`, `outcome` | `duration_ms` |
| `model.requested` | `debug` | `model_route_id`, `model_profile_id` | — |
| `model.completed` | `debug` | `model_route_id`, `model_profile_id`, `outcome` | `input_tokens`, `output_tokens`, `duration_ms` |
| `model.protocol_failed` | `warning` | `model_route_id`, `model_profile_id`, `diagnostic_code`, `outcome` | — |
| `model.schema_failed` | `warning` | `model_route_id`, `model_profile_id`, `diagnostic_code`, `outcome` | — |
| `validation.completed` | `debug` | `validator_id`, `outcome` | `count`, `duration_ms` |
| `validation.failed` | `warning` | `validator_id`, `diagnostic_code`, `outcome` | `count` |
| `repair.requested` | `debug` | `repair_unit_kind` | — |
| `repair.applied` | `info` | `repair_unit_kind`, `outcome` | — |
| `repair.rejected` | `warning` | `repair_unit_kind`, `diagnostic_code`, `outcome` | — |
| `repair.exhausted` | `error` | `repair_unit_kind`, `diagnostic_code`, `outcome` | — |
| `review.requested` | `info` | — | — |
| `review.approved` | `info` | `outcome` | — |
| `review.rejected` | `warning` | `outcome` | — |
| `transaction.prepared` | `debug` | `transaction_id`, `count` | — |
| `transaction.applying` | `debug` | `transaction_id`, `count` | — |
| `transaction.committed` | `info` | `transaction_id`, `count`, `outcome` | — |
| `transaction.rolled_back` | `warning` | `transaction_id`, `diagnostic_code`, `outcome` | `count` |
| `transaction.recovered` | `warning` | `transaction_id`, `outcome` | `count` |
| `command.started` | `debug` | `command_id` | — |
| `command.completed` | `debug` | `command_id`, `outcome` | `exit_code`, `duration_ms` |
| `command.failed` | `error` | `command_id`, `diagnostic_code`, `outcome` | `exit_code`, `duration_ms` |
| `task.started` | `info` | `task_id` | — |
| `task.completed` | `info` | `task_id`, `outcome` | `duration_ms` |
| `task.blocked` | `warning` | `task_id`, `diagnostic_code`, `outcome` | — |
| `task.failed` | `error` | `task_id`, `diagnostic_code`, `outcome` | `duration_ms` |
| `security.denied` | `warning` | `rule_id`, `diagnostic_code`, `outcome` | — |
| `model.prompt_fragment` | `debug` | `attempt`, `request_id`, `route_id`, `model_profile_id`, `fragment_id`, `direction`, `body_class`, `content`, `retained_bytes`, `truncated`, `redacted` | — |

`model.prompt_fragment` exists only in the optional prompt stream. Its
`content` field is classified `sanitized_content`, never public metadata, and
is accepted only from the validated sanitization pipeline. All other events
exist only in the event stream. A fact/event not present in this table is
rejected; adding one is a design change to this closed registry.

### 6.3 Fixed-header pipe-delimited format

`feature-log/v2` uses a deterministic fixed-header pipe-delimited format to avoid
repeating field names in every record. The initial F0002 implementation embeds
exactly two schemas as compiler constants: `event-columns/v2` and
`prompt-columns/v2`. It does not generate columns from the event registry or
read headings/schema IDs from configuration, workflow files, persisted data,
or plugins. The first row of each segment is exactly one matching
stream-specific column heading. The second row is one
`segment_header` control row under that heading. It binds the schema, stream,
policy/binding, column-schema, segment, and creation facts. Zero or more event
or prompt rows follow; a normally closed segment ends with one
`segment_trailer` control row. Control rows are storage metadata, not logs.

The hard-coded headings are:

```text
record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|parent_event_id|correlation_id|attempt|task_id|duration_ms|diagnostic_code|validator_id|transaction_id|rule_id|model_route_id|model_profile_id|input_tokens|output_tokens|repair_unit_kind|command_id|exit_code|evidence_status|outcome|count
record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|attempt|request_id|route_id|model_profile_id|fragment_id|direction|body_class|content|retained_bytes|truncated|redacted
```

The first is the 38-column event heading; the second is the 30-column prompt
heading. Every prompt data row represents exactly one sanitized fragment. The
prompt pipeline sorts selected fragments by canonical `promptBodyFragmentId`
and emits one row per fragment in that order. It emits no prompt row when no
fragment is selected; the ordinary metadata event remains available in the
event stream.

Prompt columns are scalar: `direction` is `request` or `response`;
`body_class` is `ordinary`, `reference_body`, or `code_body`; `retained_bytes`
is canonical unsigned decimal ASCII; and `truncated` and `redacted` are
lowercase `true` or `false`. `content` is only the redacted, then
UTF-8-boundary-truncated fragment and uses the escaping below.
Request/response metadata is represented by event-stream model events and is
not duplicated. Redaction/truncation evidence IDs remain internal validation
evidence and are not serialized. There is no JSON, list delimiter, nested row,
or other composite-cell grammar.

`record_kind` is one of `segment_header`, `event`, `prompt`, or
`segment_trailer`. Adding or reordering a column is an implementation contract
change. During this pre-release proof of concept that contract is edited in
place and old headings are rejected rather than migrated.

Every control/event/prompt row has exactly the same cell count and order as its
segment heading.
Required cells cannot be absent; an absent optional value uses the reserved
`\N` cell, while an empty string remains empty. The canonical dialect is UTF-8
without BOM, uses ASCII `|` as its delimiter, is unquoted, and has one LF per
physical row.
Within a value, encode backslash first as `\\`, pipe as `\|`, CR as `\r`, and
LF as `\n`. Because literal backslashes are escaped first, literal content
cannot alias the reserved absent value. A decoder scans left to right, treats
only an unescaped `|` as a cell boundary, checks the complete encoded cell for
the reserved `\N`, and then decodes only `\\`, `\|`, `\r`, and `\n`. An unknown
or dangling escape fails closed. For example, the value `plan|audit` is written
as `plan\|audit` in one cell. Repeated, missing, reordered, duplicate, or
unknown headings and extra or missing row cells fail closed.

For example, the registered `task.started` event at `info` can produce this
segment:

```text
record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|parent_event_id|correlation_id|attempt|task_id|duration_ms|diagnostic_code|validator_id|transaction_id|rule_id|model_route_id|model_profile_id|input_tokens|output_tokens|repair_unit_kind|command_id|exit_code|evidence_status|outcome|count
segment_header|feature-log/v2|event|event-columns/v2|LOGPOL-001|LOGBIND-001|1|\N|\N|\N|2026-08-28T10:15:00Z|\N|\N|\N|\N|RUN-001|F0002|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N
event|feature-log/v2|event|event-columns/v2|LOGPOL-001|LOGBIND-001|1|IMPL|EVENT-0042|42|2026-08-28T10:15:30Z|1205|info|task.started|task.started/v1|RUN-001|F0002|implement|\N|\N|\N|\N|TASK-001|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N
```

`IMPL` is illustrative only; the workflow that produced the fact supplies the
actual shortcode through its `WorkflowLog` binding.

When prompt capture is explicitly enabled, one sanitized fragment is one row:

```text
record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|attempt|request_id|route_id|model_profile_id|fragment_id|direction|body_class|content|retained_bytes|truncated|redacted
segment_header|feature-log/v2|prompt|prompt-columns/v2|LOGPOL-001|LOGBIND-001|1|\N|\N|\N|2026-08-28T10:15:00Z|\N|\N|\N|\N|RUN-001|F0002|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N|\N
prompt|feature-log/v2|prompt|prompt-columns/v2|LOGPOL-001|LOGBIND-001|1|IMPL|EVENT-0043|43|2026-08-28T10:15:31Z|1206|debug|model.prompt_fragment|model.prompt_fragment/v1|RUN-001|F0002|implement|\N|1|REQ-001|ROUTE-001|PROFILE-001|FRAG-001|request|ordinary|Create plan with [REDACTED_SECRET]|34|false|true
```

The console mirror, when enabled, displays only the applicable `event|...` or
`prompt|...` data line above, byte-for-byte. It does not display either heading
or `segment_header` row.

With a configured threshold of `warning`, that `info` fact is filtered and no
data row is created. With a threshold of `info` or below, the emitted row's
`level` cell is `info` regardless of configured threshold spelling.

The mandatory event stream is metadata-only. At every level, including
`trace`, it excludes credentials, environment values, diagnostic free text,
raw paths, arbitrary caller text, prompts/responses, references, source code,
patches, file content, and command output.

Optional prompt/body capture remains a separate, default-off sanitization
pipeline governed by Sections 13.4 and 26.5. F0002 accepts only its validated
transient sanitized fragment records; it never receives or sanitizes raw bodies
a second time. Direction/class opt-ins, redaction-before-truncation,
UTF-8/size validation, canonical fragment ordering, and transient-handle
cleanup remain owned by that pipeline.

### 6.4 Proof-of-concept policy constants

These values are compiler constants, not defaults and not user-tunable
configuration. A change edits the PoC contract in place. The logging-policy
compiler injects them only after validating the three user choices.

| Concern | Exact proof-of-concept contract |
| --- | --- |
| Timestamp | `timestamp` is exactly `true` |
| File | always enabled; every admitted event/prompt record must be durably appended to its bound `.log` segment before logging returns success |
| Console | optional additional mirror only; delimiter is exactly `|`; when enabled, write the already-serialized data row plus its existing LF to `stderr`, with no heading, color, or prefix; console success never substitutes for file success |
| Record | `maxRecordBytes = 65,536`, including encoded cells and final LF |
| Segment | `maxSegmentBytes = 8,388,608`, including heading and control rows |
| Segment count | `maxSegments = 16` per feature/run/stream lifetime |
| Retention | `retentionDays = 14`; a closed segment becomes eligible 1,209,600,000 ms after `closed_at_utc` |
| Flush level | `flushAtOrAbove` is exactly `error`; `error`, `fatal`, and terminal stage/task/transaction events force flush |
| Lower-level flush | flush after 32 records or 1,000 monotonic ms since the last successful flush, whichever occurs first |
| Failure mode | exactly `block_new_work` |
| Redaction policy | exactly `redaction/default-v1`; mandatory built-in detectors only, with no configured patterns |
| Prompt switches | `promptCapture=[]` disables body capture; a non-empty list must contain `request` or `response`; `reference_body`/`code_body` only refine selected directions |
| Prompt content | `maxContentBytes = 5,000` per sanitized fragment |
| Stream lock | compiler constant 2,000 ms from first acquisition attempt; one attempt, no retry or backoff |
| Emergency write | one direct `stderr` write attempt, maximum 128 ASCII bytes, no allocation from failed record content and no recursive logging |

The emergency line is exactly:

```text
SDDE_LOG_FAILURE workflow=IMPL level=fatal code=LOG_SINK_FAILURE
```

The terminating byte is LF. `IMPL` is replaced only by the exact typed
four-character shortcode. `code` is one of `LOG_LOCK_TIMEOUT`,
`LOG_SERIALIZATION_FAILURE`, `LOG_SINK_FAILURE`, `LOG_FLUSH_FAILURE`, or
`LOG_RELEASE_FAILURE`. No message, path, content, identifier, or additional
field is permitted. Failure to perform this single emergency write does not
retry and does not prevent the required fail-closed result.

## 7. Storage and lifecycle

The artifact registry owns the fixed destinations:

- events:
  `<paths.specs>/<featureId>/logs/events/<runId>/<featureLogBindingId>/<segmentOrdinal>.log`;
- optional prompt fragments:
  `<paths.specs>/<featureId>/logs/prompts/<runId>/<featureLogBindingId>/<segmentOrdinal>.log`.

These shapes are conformance information, not configurable paths. F0002 uses
only the validated binding and operation-specific storage ports. It never
joins raw path strings. There is no shared or global persistent log.

The fixed-header pipe-delimited file sink is mandatory and has no disable
switch. Every newly created or rotated segment durably writes its canonical
column heading as the first row and
its `segment_header` control row as the second before accepting event/prompt
rows. A validated optional console mirror may display only the already-safe
data row using the exact delimited bytes defined in Section 6.4. File permissions,
exclusive locking, sequence, flush, rotation,
retention, prior-tail recovery, and policy transition behavior are governed
once by Sections 13.9, 14.10, and 26.5 and are not redefined here.

The initial implementation processes each fact through the runner-owned
logging barrier before the next applicable business node. It has no background
dispatcher, public queue, or fire-and-forget path. The bounded policy-transition
buffer required by Section 14.10 is not a general logging queue.

Logs are never workflow authority and are not stage/task transaction members.
Their presence, absence, or content cannot prove approval, completion,
rollback, recovery, or commit. A transaction event is eligible only after the
corresponding durable transition.

## 8. Failure contract

Configuration discovery/decode or logging-policy compilation failure blocks
bootstrap before F0002 is active. No example, packaged config, environment
value, caller value, or hard-coded threshold is used as fallback.

An initialized logging failure follows the governing
`FeatureLoggingFailureOrchestrator` exactly:

1. release/terminalize logging resources and transient content;
2. make one direct `stderr` attempt using the exact bounded ASCII emergency
   line in Section 6.4, containing the exact workflow shortcode, canonical
   `fatal` level, and one closed failure code, without invoking the failed sink;
3. stabilize an already prepared/applying transaction through the existing
   transaction-recovery boundary; and
4. return `blocked` before the runner starts new work.

The failure path is not logged through F0002 and cannot recurse. A durable
commit remains committed; an uncommitted transaction reaches a stable boundary
before blocking.

Before a current feature binding exists, the bounded content-free emergency
path is available only after the calling workflow's validated `WorkflowLog`
binding exists. Without that attribution F0002 emits no log record; bootstrap
uses its non-logging diagnostic path and blocks. Restart and same-run policy
changes use the historical/current authority rules in Sections 14.10 and 26.5;
F0002 never reinterprets stored records with raw or candidate configuration.

## 9. Explicit non-responsibilities

F0002 does not:

- read, decode, cache, or expose configuration;
- canonicalize configured log-level text;
- infer, pad, truncate, normalize, or repair a workflow shortcode after
  `WorkflowLog.init` validation;
- allow a producer, workflow, model, plugin, or configuration value to define
  event severities, templates, fields, or sensitivity outside the closed
  Section 6.2 registry;
- accept configured, workflow-supplied, registry-generated, or plugin-supplied
  delimited columns/headings;
- provide `log(level, message, fields)` or caller-selected destinations;
  `workflowLog.log(delta, TelemetryFact)` is the only producer convenience
  operation;
- derive paths or treat logs as workflow evidence;
- expose raw-content capture through `TelemetryFact`;
- add network export, a query UI, asynchronous dispatch, or a production
  dependency;
- implement compatibility parsing or migration for any earlier logging or delimited
  shape; or
- duplicate the detailed action, recovery, and storage contracts already
  governed by the engine design.

## 10. Acceptance criteria

1. F0001 is the only `.sddtoolkit.json` reader; F0002 runtime receives an
   attributed `WorkflowTelemetryFact`, validated policy, binding, and
   event-definition registry, never raw configuration or unvalidated shortcode
   text.
2. F0001 structurally decodes the closed v2 logging shape; the logging-policy
   compiler alone validates its three choices and injects all operational
   constants, and configured level conversion has one owner.
3. Each calling workflow constructs a `WorkflowLog` from exactly four
   case-sensitive ASCII alphanumeric characters; no `*.workflow.yaml` or
   workflow-definition schema supplies logging attribution.
4. `WorkflowLog.log` binds that shortcode to exactly one `TelemetryFact` as a
   `WorkflowTelemetryFact` before it enters the candidate delta.
5. Producers use only `workflowLog.log(delta, TelemetryFact)`; the operation
   performs no I/O, and producers cannot select a level, message, path, format,
   sensitivity, or sink capability.
6. Every fact reaches exactly one drop, persisted, or blocked outcome through
   the common runner contract.
7. Event definition, threshold decision, workflow attribution, path binding,
   and runner scheduling each retain their single governing owner.
8. Every serialized event, prompt-fragment, console-mirror, and emergency
   record contains exactly one workflow attribution equal to the calling
   workflow's validated four-character value; delimited rows use
   `workflow_shortcode`, emergency output uses `workflow`, and missing or
   malformed values are rejected.
9. Every serialized event, prompt-fragment, console-mirror, and emergency
   record contains exactly one canonical `level` value resolved from
   engine-owned authority; delimited rows use the `level` column, emergency output uses
   the `level` field, and missing, aliased, unknown, or caller-supplied levels
   are rejected.
10. Every persisted segment starts with the exact `feature-log/v2` stream
    heading embedded in F0002 once, followed by one matching `segment_header`
    control row; configuration cannot select or change the heading, and every
    control/event/prompt row has that heading's exact column count and order,
    and malformed, repeated, missing, reordered, duplicate, or unknown headings
    or control rows and row-width mismatches fail closed.
11. Metadata remains free of prohibited content at every threshold; optional
    body capture is default-off and emits one scalar-only row per separately
    sanitized fragment in canonical fragment-ID order, with no composite cell
    encoding.
12. Every persistent record uses the exact feature/run binding and registered
   feature-log collection; no shared persistent sink exists, console output
   never substitutes for it, and success is impossible without the required
   file append/flush result.
13. Filtering allocates no record identity, sequence, segment, or lock.
14. Storage/recovery follows the governing lock, ordering, rotation, retention,
   restart, and policy-transition contracts without a second implementation.
15. Logging failure cleans up, reports once without recursion, stabilizes any
   in-flight transaction, and blocks before new work.
16. Logs cannot affect workflow state, approval, evidence, or completion.
17. The packaged executable has no dependency on source examples, the source
    tree, build cache, or Zig toolchain.
18. The closed event table in Section 6.2 is exhaustive and every event maps to
    exactly one level, `<event_type>/v1` template, field set, and sensitivity;
    unregistered events and fields fail closed.
19. Configuration contains only `level`, `console`, and `promptCapture`; the
    compiled policy injects every fixed behavior in Section 6.4, including the
    2,000 ms one-attempt lock deadline, exact pipe-delimited console mirror, and exact
    bounded emergency-line grammar.
20. Only the current proof-of-concept v2 headings and contracts are accepted;
    no compatibility or migration branch exists.

## 11. Verification

Tests should prove the shared boundaries with representative positive and
negative cases:

- authority: three-value config-to-compiler-to-runtime handoff, rejection of
  every removed tuning key, one level canonicalizer,
  workflow-owned `WorkflowLog` construction, exact shortcode/fact binding, and
  rejection of raw config/path/message/shortcode inputs or runtime file
  rereads;
- processing: `workflowLog.log` appends exactly one attributed typed fact and
  performs no I/O; rejection of missing, shorter, longer, or malformed workflow
  shortcodes at binding construction and runtime validation; exhaustive
  six-level threshold matrix; rejection of missing, aliased, unknown,
  mismatched, or caller-supplied record levels; typed field validation;
  redaction; drop-before-allocation; exhaustive event-registry mapping and
  rejected unregistered events/fields; exact-once fixed headings;
  deterministic delimiter escaping/null encoding, including embedded pipe,
  backslash, CR, and LF cases; byte-for-byte checks of both built-in headings;
  rejection of unknown and dangling escapes and of any
  configured/dynamic heading; heading/control-row/row-width corruption; fixed
  pipe-delimited serialization; one scalar row per prompt fragment in canonical order;
  zero-fragment behavior; and runner barrier behavior;
- privacy: prohibited metadata, default-off prompt capture, sanitization
  handoff, and transient cleanup;
- storage: exact per-feature bindings, cross-feature isolation, permissions,
  the exact 2,000 ms no-retry lock deadline, fixed size/retention/flush
  constants, rotation/limits, exact pipe-delimited console
  bytes, and representative clean-tail versus corrupt-tail recovery;
- failure: each operation class reaches the one non-recursive emergency/block
  route, the emergency line is byte-exact and at most 128 ASCII bytes, a failed
  emergency write is not retried, and transaction durability is preserved; and
- packaging: a clean native-executable run with no source-tree fallback.

Detailed fault matrices remain owned by governing Section 28 and are referenced
rather than copied into this feature document.

## 12. Traceability

| Concern | Authority |
| --- | --- |
| Config read/decode and handoff | F0001; Design Sections 9 and 13.1 |
| Workflow shortcode source, syntax, validation, and fact binding | Calling workflow; `WorkflowLog.init` and `WorkflowLog.log` |
| Action and orchestrator boundaries | Design Sections 5-6, 13.9, and 14.9-14.10 |
| Levels, privacy, paths, storage, and recovery | Design Section 26.5 |
| Runner-owned observability | Design Section 27 |
| Verification and delivery | Design Sections 28, 30-31 |
