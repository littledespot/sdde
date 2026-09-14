# 26. Security and safety

Part of the [proposed design](../design.md#26-security-and-safety). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 26.1 LLM trust boundary

Model and reference content are untrusted data:

- reference text is delimited and labeled as data, never concatenated into system instructions;
- instruction-like content in a reference cannot alter response schema, available tools, paths, or policy;
- the model has no filesystem or shell capability;
- model path/context requests use validated IDs;
- model-returned status, executable text, or validation assertions outside the compiled operation's allowed typed semantic payload are schema-rejected and never acted upon;
- provider output is size-bounded and schema-validated.

### 26.2 Filesystem safety

- reject absolute, drive, UNC, URI, traversal, NUL, and control-character paths;
- use real-path containment and segment-aware root matching;
- reject symlink escapes for reads and writes, then repeat target/ancestor identity checks at commit with descriptor-relative/no-follow operations or the supported platform equivalent;
- deny VCS/engine/cache/generated roots by default;
- separate create/update/replace/copy/delete semantics and validate expected target state;
- require explicit delete policy and task authorization;
- reruns MUST overwrite their existing registered output files under Section
  23.2 and MUST NOT overwrite user-closed clarification files or files outside
  the selected workflow's authorized path set;
- enforce the whole-workflow output boundary in Section 25 without introducing transaction/recovery machinery.

### 26.3 Command safety

- no shell interpolation;
- no raw model commands;
- registered executable and argv templates only;
- typed placeholders only;
- contained working directory;
- environment-variable allowlist and secret redaction;
- time, output, concurrency, network, and mutability limits;
- mandatory OS/container filesystem namespace, process-tree confinement, and inherited descendant restrictions;
- per-operation write mediation/audit that fails even transient unauthorized writes before they can influence command evidence;
- in-flight command quotas for created entries, cumulative/current bytes, per-file bytes, and private temporary storage;
- no mutating command when the platform adapter cannot enforce its declared sandbox contract;
- persistent command effects limited to the intersection of task-approved file IDs and command-authorized path policy plus the engine-derived per-file create/modify/delete capability, with special-file rejection and post-promotion revalidation;
- validate command capability against actual project manifests;
- isolate dependency mutations;
- refuse externally irreversible operations by default.

### 26.4 Reference safety

- bounded per-file and total corpus size;
- MIME sniffing rather than extension trust alone;
- archive depth/file-count/compression-ratio limits if archive readers are enabled;
- encrypted/corrupt content diagnostics;
- sandboxed document/image parsers where feasible;
- no macro execution;
- no scripts embedded in reference content;
- deterministic hidden-file and symlink policy;
- explicit account for every discovered file.

### 26.5 Secrets and logging

- The effective threshold is always compiled from v2 `.sddtoolkit.json` `logs.level`; neither a
  prompt, model response, action, nor orchestrator may override it.
- File logging is always enabled and cannot be configured away.
- The only other logging inputs are the optional `logs.console` mirror boolean and unique
  `logs.promptCapture` selector list.
- Console output never substitutes for a successful file append.
- Configuration supplies no path, file-enable switch, timestamp, format, size, retention, flush,
  failure, redaction, prompt byte limit, lock value, per-event level, column-schema ID, or
  heading.
- The example's lowercase `debug` is valid input.
- Configuration is case-normalized, `CRITICAL` is the input alias of canonical `fatal`, and
  `WARN` is the input alias of canonical `warning`.
- No other aliases or custom levels exist.

| Accepted configured spelling | Canonical level/rank | Fixed meaning |
| --- | ---: | --- |
| `FATAL`, `CRITICAL` | `fatal` / 60 | The process cannot continue safely, or a vital invariant/recovery/log-safety subsystem failed and needs immediate correction. |
| `ERROR` | `error` / 50 | An operation, task, required command, stage, or durable write failed while the engine remains in a known stable state; the affected feature is broken/blocked. |
| `WARNING`, `WARN` | `warning` / 40 | An unexpected, rejected, stale, or retryable condition occurred and the engine recovered or safely blocked it, but it needs attention. |
| `INFO` | `info` / 30 | Normal run/stage/task/review lifecycle and publication outcomes. |
| `DEBUG` | `debug` / 20 | Developer detail such as node lifecycle, validator summary, operation/slot/token counts, and output entry counts. |
| `TRACE` | `trace` / 10 | The most verbose step/branch/scheduling, typed-key/ID, rule-ID, and bounded count detail. It never enables raw content or weakens redaction. |

- An event is emitted iff `rank(event) >= rank(configured threshold)`.
- The closed proof-of-concept `LogEventDefinitionRegistry` is exactly the table in F0002 Section
  6.2 and owns every event's canonical level, `<event_type>/v1` template, field types, required
  fields, and sensitivity classification.
- Producers return typed facts without a level or message, so they cannot relabel an event or
  mark secret-bearing text public.
- An event or field absent from that table is rejected; no caller, plugin, model, or
  configuration may extend it.

Every activated run writes beneath the spec being run, never into the editable specification itself:

- events: `<paths.specs>/<featureId>/logs/events/<runId>/<featureLogBindingId>/<segmentOrdinal>.log`;
- prompt exchanges, only when enabled: `<paths.specs>/<featureId>/logs/prompts/<runId>/<featureLogBindingId>/<segmentOrdinal>.log`.

- These collection roots are fixed entries in the exact `WorkflowArtifactRegistry`; the engine
  renders the binding tuple to one registered portable path token, so no user/model/config path
  chooses a child.
- The binding layer prevents a same-run policy transition's ordinal-one successor segment from
  colliding with the historical binding.
- They use a separate append-only workflow access class and are excluded from `spec.md`,
  generated views, workflow output-set membership, repository/reference discovery, model
  context, unexpected-project-change detection, and default artifact export.
- A new run buffers bounded metadata during deterministic reference preactivation; only after a
  new target's feature root is activated is that buffer flushed into its feature log.
- A **new-target** preactivation failure has no feature/spec directory and therefore uses only
  the process/emergency engine sink.
- An existing-target rerun already has its validated active feature directory and current log
  authority, so its preactivation failure remains feature-logged under that existing binding as
  defined by the startup flow.

- The event stream is metadata-only.
- It may contain only the registered IDs, enums, counts, durations, diagnostic codes, workflow
  model-operation/model-slot identities and token counts, command IDs/exit codes, and outcomes
  in F0002 Section 6.2.
- It never contains diagnostic `message`/`actual`/`expected`, environment-variable values,
  credentials, raw prompts, reference bodies, source code, patches, command output, or arbitrary
  maps.
- Prompt/body logging defaults off even when the threshold is `trace`.
- Enabling it requires independent request, response, reference-body, and code-body opt-ins.
- The engine builds a complete fragment manifest from the typed workflow operation
  request/result before provider serialization; every body field is exactly one `ordinary`,
  `reference_body`, or `code_body` fragment.
- A request/response direction opt-in is necessary for every fragment in that direction, and
  reference/code fragments additionally require their class opt-in.
- Opaque whole-body capture is forbidden, so disabling reference/code capture cannot leak those
  bytes inside an enabled request.
- Structured secret fields, mandatory credential/key detectors, and configured bounded RE2
  detectors run first per selected fragment; replacement uses a fixed category marker that
  reveals neither value nor original length.
- Truncation happens only afterward at a UTF-8 scalar boundary.
- Selected sanitized fragments are sorted by `promptBodyFragmentId` and each becomes one
  scalar-only prompt pipe-delimited row; metadata and evidence vectors are not packed into
  composite cells.
- Zero selected fragments produce zero prompt rows.
- Every transient fragment handle is destroyed whether its row is emitted or filtered out.

- `feature-log/v2` is the only feature-file format.
- The first bytes of every segment are exactly one canonical pipe-delimited column-header row
  for that stream.
- The second row is exactly one `segment_header` control row under the same heading; it binds
  the schema version, stream, policy/binding IDs, column-schema ID, segment ordinal, and
  creation facts formerly carried by the durable segment metadata header.
- A normally closed segment ends with exactly one `segment_trailer` control row under the same
  heading; active tails have none.
- `event`, `prompt`, `segment_header`, and `segment_trailer` are the closed `record_kind`
  variants.
- Control rows are storage metadata, not log events, and their event-only cells are absent.

- The initial F0002 implementation contains exactly two compiler-locked column schemas:
  `event-columns/v2` and `prompt-columns/v2`, with the exact ordered headings specified by F0002
  Section 6.3 and implemented by `src/domain/feature_log_format.zig`.
- The schemas are constants, not generated from the event registry and not supplied by config, a
  workflow, stored data, or a plugin.
- Every control or event/prompt row has its stream schema's exact column count and order.
- The `workflow_shortcode` and `level` columns are required on every `event` or `prompt` row and
  absent on control rows.
- Other required fields are enforced by row kind.
- An absent value is encoded as the reserved `\N` cell; an empty string remains an empty cell,
  and a literal backslash is escaped before the reserved-null check, so absence and content
  cannot alias.
- Unknown, duplicate, missing, or reordered headings and extra/missing row cells fail closed.
- This pre-release proof of concept updates v2 in place and rejects all obsolete headings; it
  has no migration, compatibility reader, dual writer, or historical conversion.
- After release acceptance, adding or reordering a column requires a new contract version.

- The exact PoC constants are F0002 Section 6.4: timestamp enabled; pipe-delimited file and
  optional console output; 65,536-byte records; 8,388,608-byte segments; 16 segments per
  feature/run/stream; 14-day retention; lower-level flush after 32 records or 1,000 monotonic
  ms; 5,000-byte sanitized prompt fragments; built-in `redaction/default-v1` detectors with no
  configured additions; `error` forced-flush threshold; and `block_new_work`.
- These are compiler-owned constants rather than configurable values or defaults.

- The canonical dialect is UTF-8 without BOM, ASCII `|` delimiter, no quoting, and one LF after
  every heading, control, event, or prompt row.
- Values are encoded in order: backslash as `\\`, pipe as `\|`, CR as `\r`, and LF as `\n`, so
  one logical record is always one physical row.
- A decoder scans for unescaped `|` boundaries, then decodes only those four escape sequences;
  an unknown or dangling escape fails closed.
- No locale-dependent formatting, optional whitespace, alternate delimiter, comments, multiline
  row, or repeated heading is accepted.

- Feature log directories use owner-only directory permissions and segments use owner
  read/write, exclusive-create, no-follow regular-file opens; aliases and insecure permissions
  block.
- One validated exclusive lock capability exists per `(featureId, runId, stream)` while a writer
  is inspecting, recovering, rotating, appending, pruning, or flushing.
- Each acquisition makes one attempt with the compiler-fixed 2,000 ms deadline and no retry or
  backoff.
- Sequence is assigned after threshold/redaction and is ordering authority; a same-run binding
  transition continues at the historical final sequence plus one, while a fresh run begins at
  one.
- Timestamps are informational.
- A complete bounded pipe-delimited event/prompt row plus LF is encoded before lock acquisition
  and is never split.
- Segment capacity includes the one pipe-delimited column-heading row and required control rows;
  every newly created or rotated segment must durably contain its heading and `segment_header`
  row before accepting an event/prompt row.
- Before overflow the adapter fsyncs/closes the current segment with its `segment_trailer` row
  and creates the next zero-padded binding-local ordinal only while the total number of segments
  across **all** bindings for `(featureId, runId, stream)` remains within
  `rotation.maxSegments`.
- Thus a policy transition cannot reset the lifetime cap; retention cannot make room and
  identities/ordinals are never reused within a binding.
- If the active segment cannot fit the record at the cap, `EvaluateFeatureLogRotationNeedAction`
  returns `LOG_SEGMENT_LIMIT_EXHAUSTED`; no segment identity or rotation authorization is
  created, and the sink follows the ordinary fail-closed logging-failure flow before any next
  business node rather than dropping the record or exceeding the cap.
- Every terminal branch releases the capability; after process death the adapter/OS releases
  ownership and recovery must reacquire before inspecting bytes.
- A later new run starts its own ordinal-one binding/sequence.
- Error/fatal and every terminal stage/task/workflow event force a flush; lower levels use the
  validated count/time policy.

- On restart, recovery first validates the exact first pipe-delimited column-heading row and
  second `segment_header` control row, then may truncate only bytes after the last complete
  valid LF-delimited event/prompt row of an active tail.
- A missing, duplicate, malformed, or schema-mismatched heading/control row; misplaced or
  duplicate trailer; an interior malformed pipe-delimited row; wrong column count, run, stream,
  or workflow shortcode; sequence regression; alias; or permission failure is never skipped.
- Retention runs after recovery and rotation; a single-use authorization selects closed segments
  oldest-first by `(closedAtUtc, runId, ordinal)`, never the current segment.
- This is the only authorized destructive log operation.

Logs are observations, not workflow authority. Their presence, absence or content cannot prove completion or resume an execution. A logging failure abandons the current workflow candidate; no transaction stabilization or recovery is invoked.
