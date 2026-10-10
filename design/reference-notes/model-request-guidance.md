# Model request and response guidance

Companion to the [request-flow diagram](../diagrams/17-model-prompt-response-flow.md).
This summarizes the existing contracts in
[ADR 0006](../decisions/0006-minimal-model-response.md),
[ADR 0011](../decisions/0011-provider-owned-request-limits.md),
[ADR 0012](../decisions/0012-workflow-owned-model-request.md) and
[ADR 0014](../decisions/0014-universal-response-format-guidance.md).

## Input and evidence representation

- Inputs and responses share the `kind` wire codec.
- Evidence projections remove internal validation wrappers.
- Reconciliation distinguishes each claim's representation (`content.kind`) from
  model content's semantic category (`content.model.kind`). The shared
  [native constraint descriptions](../../src/domain/reference_reconciliation_diagnostic.zig)
  supply the matching rules for initial assignments and repairs.
- Semantic summary/signal selections come only from `assignment.claim_ids`; token
  claims remain supporting evidence and native projections. Signal coverage guidance
  concerns retained assigned claims not already covered by accepted signals. Signal
  content preserves the selected claims' conditions, triggers and obligation strength.
  Compatible content categories and subset cardinality derive from the native
  selection owner. Atomic selection repairs instead name `repair.rule.selection`;
  they do not request whole-result coverage. Different signal groups may overlap.
  Reference repair `failed_requirement` describes the rejected candidate; the
  repair target and scoped constraints describe the permitted replacement.
- Summary packets carry one shared `summary_purpose` for generation and scoped
  repair: preserve selected meaning, conditions, triggers and obligation strength;
  original claims and cited sources govern earlier summaries, and incompatible
  meanings remain distinct. Complete-summary assignments require every assigned
  semantic claim ID in the union of statements, with nonempty unique selections
  inside each statement. Combined, split and overlapping expressions are permitted;
  native code adds token statements. This coverage instruction is absent from partial
  repairs and signal assignments. Protocol correction retains the original packet.
  After every statement validates, the native summary projection keeps the first of
  any exact duplicates with the same claim membership and equivalent typed content;
  the raw candidate and repair occurrences remain intact. Different source occurrences
  and paraphrases are not deduplicated by similar display text. Coverage and
  normalization do not prove meaning preservation or enlarge repair authority.
- A non-final, nonempty summary partition with one current validated child and
  unchanged membership/evidence/text dependencies carries its content forward
  natively. Explicit workflow actions check eligibility before any model packet and
  feed the existing summary validation/identity/build path. Stale or altered history
  fails; other summary partitions retain their existing request path. The native
  parent links to the child's retained provenance without claiming a new model call.
- Content references preserved-token IDs; `preserved_tokens` retains exact values
  and citations across reconciliation, generation, review and repair.
- Extraction selects source lines as `{first: {ordinal}, last: {ordinal}}`, with
  inclusive endpoints and original line endings. Separate selections represent
  discontiguous support; exact tokens retain extractor-owned finer spans.
- Extraction content assigns source facts, semantic categories and citations;
  token classification is separate. The shared extraction context distinguishes
  meaningful prose, exact-token-only content and `no_feature_claim`. It prefers
  complete strings while preserving source conditions, obligation strength and
  literal text. Fragment forms and reference IDs come from the existing selected
  schema and supplied evidence, without a second variant list in the context.
  Corrections retain that context; scoped repairs apply it only to selected fields.
- Models supply neither quote bytes nor coordinates. The engine assigns citations
  after validation and rechecks them against captured sources on load.
- Invalid selections retain typed diagnostics and existing replacement authority.
  Diagnostics preserve originating request/attempt even after request release;
  repairing one citation preserves sibling attribution.
- Source selection proves location, not semantic support.
- Authoring dependencies use resolved brief text and entity applicability/basis;
  canonical provenance and fragment bookkeeping stay native. Record purposes and
  selected schema alternatives derive from the same native eligibility decision.
- Source `candidate_omission` separates a required `missing_obligation` from its
  diagnostic `detail`. The existing reviewer states the omitted source requirement
  directly, retaining conditions, negation and obligation strength and selecting
  its source evidence. Other findings and principle reviews forbid the field.
  Native code validates and carries it without synthesizing meaning. Initial
  review, insertion and protocol correction use that same closed shape; selected
  omission-detail correction returns both obligation and explanation under the
  existing bound verdict and source evidence.
- Loss comparison keeps that explicit obligation fixed and assesses native-bound evidence
  collections. `preserved`, `lost` and `uncertain` describe each assigned view;
  no model-selected culprit or repair operation is accepted. Native attribution,
  currentness and permission follow [§22.1](../contracts/22-repair.md).
  Omission admission requires its supporting sources even when claim evidence is
  fixed by the subject; this provides the comparison's original-source premise.
  Original claims selected for authoring remain its meaning input; signal prose is
  supporting evidence. Complete comparison responses retain source/member evidence
  and their own call origin. Stored evidence is rederived without request logs.
  The request exposes one comparison-local member ID, resolved claim meaning and
  source identity. Canonical claim/citation IDs and half-open coordinates stay in
  native evidence; source selections use only the inclusive line catalogue.
  `fixed_finding.missing_obligation` is the single comparison target. The diagnostic
  explanation and target purpose are supporting evidence alongside the already
  deficient subject and resolved producer outputs. They cannot supply a different
  obligation or require upstream collections to resemble the final artifact or
  describe its defect. Equivalent wording and meaning expressed jointly by members
  count as preservation.
  Claim meanings omit extraction-category labels: preservation depends on what the
  collection expresses, not whether a value has a separate member. A bare value
  alone does not establish behavior. Canonical categories, occurrence identities
  and actual classification decisions remain intact; native code does not infer
  semantic equivalence or change role membership.
- `Source.comparisonAssignment` constructs the shared native binding;
  `packetForLoss` resolves its model-facing values. Initial requests and protocol
  corrections use `preservation_comparisons`. Collection, diagnostic admission and
  repair authorization use the same native derivation. Native `invalid_loss` is
  terminal; this change adds no semantic retry or expanded repair permission.
  The retained assignment binds the exact obligation, original explanation,
  selected sources, subject, review revision and current canonical evidence.
  Readback or repair with a changed binding rejects. Source-obligation fidelity
  and loss-attribution quality require live measurement of both existing calls;
  hand-written obligations alone cannot establish the complete handoff's quality.

Native operation causes and expected domain rejections survive into CLI, telemetry
and harness evidence through the closed operation contract. The harness records
the first observed diagnostic and explicit repair/revision/invalidation links;
event order does not prove the initiating semantic cause. Provider-content rejection
survives transport retirement independently of protocol rejection. See the
[retained evidence contract](../harness/e2e.md#retained-results). These observations
grant no retry, repair, continuation or publication authority.

Omission authorization retains each considered target's actual rejection reason,
validated loss location and available target, finding and comparison origins.
Unchecked targets stay explicit when stale or invalid evidence stops admission.
These separate observations do not replace assembled-candidate attribution with
a single culprit call. Target origins follow accepted replacements; absent origins
remain absent. Reporting consumes the authorization trace without repeating its
eligibility checks.

## Guidance by call type

**Every call** receives one shared engine instruction, emitted once by serialization
for every workflow and both response modes:

> Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.

- Workflow resources supply task instructions and the complete compiled result schema.
- The schema defines allowed properties, required fields, types, bounds and variants.
- Universal framing adds no schema, business rules or workflow authority. Templates
  and the evaluator do not supply independent copies.
- Selected reasoning effort and optional output allowance are retained request
  controls, not model-visible task guidance. Corrections and diagnostic replay
  preserve their originating binding under ADR 0011.

**Protocol correction** receives:

- Original task content, selected protocol prompt and complete original schema.
- Exact rejected response as untrusted evidence.
- Latest native validation error in model-visible guidance: decoder reason/position
  and object/key context, or schema reason and JSON Pointer. A terminal/log-only
  diagnostic does not meet this requirement.
- For schema rejection: the candidate JSON Pointer and parent/value scope, an
  exact locator in the single complete schema, and derived immediate fields, child-object required names and
  discriminator values. Alternatives and bounds remain in that schema.

The protocol prompt requires the complete corrected response, preserving unaffected
entries and business meaning. The diagnostic locates the defect; it does not narrow
the response schema. For an atomic repair, that schema is already the selected
replacement, not the whole candidate. Schema and domain validation still apply;
syntax correction cannot recover omitted requirements. No candidate examples or
accumulated correction prompts are added.

In [R45](../../fixes/archive/FIX_001.md#47-brief-schema-exhaustion-despite-child-object-guidance),
both corrections already included `unknown_property` at `/provenance`, required
child `value`/`provenance` fields and the rejected response. The first correction
therefore differed from initial generation; the second correction repeated the
first because the latest error and rejected response were unchanged. Use captured
request/response bytes to establish repetition, rather than temperature alone.

The user-requested [explicit-error guidance](../contracts/22-repair.md#2262-explicit-error-guidance)
is implemented through the same `build-model-protocol-retry` action. The error has
a plain-language explanation; the existing structured outline supplies allowed
fields and child requirements. Together they convey the following for R45
(illustrative wording, not an additional prompt):

```text
The previous response failed schema validation.
Error at /provenance: this property is not allowed on the root object.
Allowed root fields: kind, title, description, primary_goal.
Each title, description and primary_goal object requires value and provenance.
Return the complete corrected response matching the supplied schema.
Correct the reported errors; preserve unaffected entries and meaning.
```

The field names above come from R45's selected schema, not hardcoded prompt rules.
Keep the typed error and schema locator alongside the explanation. Decoder errors
instead explain their parser reason/location; missing answers explicitly request
the absent final response without attaching a body or reasoning.

Confirmed recurrence adds one sentence: “The previous correction still failed this
validation.” The handoff retains the preceding typed rejection with its prepared
correction, verifies the next response's exact association and compares diagnostic
identity before passing the fact to the builder. This adds no allowance, temperature change or
semantic reassessment. Native defects and operational failures retain their owners.

**Atomic repair** receives:

- Shared replacement prompt and validator diagnostic.
- Selected unit, `current_value` for replacements, scoped evidence and selected schema.

When native claim selection fixes the content kind, statement/signal repairs receive
only that payload schema. Native decoding restores the retained kind; the model does
not repeat it. Target/revision ownership, sibling preservation and full validation
remain with the existing repair owners.

**Support review** returns one `decision` with evidence and brief detail. Native
policy supplies fixed applicability; `not_applicable` is a separate permitted
decision only when applicability still needs review. Initial and missing-finding
requests select the same closed shapes. Detail/evidence repairs preserve decisions;
admission and persisted validation share native assembly. Source review assesses
meaning sufficient to derive content, without requiring prewritten spec fields.
Packets replace native ledger tuples with short semantic tasks. The shared review
evidence owner supplies claim minimums, eligible/exact sets and current candidate
provenance to both admission and guidance. Corrections retain the precise failing
rule once, preserving the decision; insertion retains the available choices.
Absent presentation fields are omitted without removing source/extraction evidence.
Collection assignments identify the assessed slot and its resolved records,
including an empty collection. Source review retains the complete business and
source reconstruction context; related prose cannot replace the selected records.
Collection membership comes from the same native lens as evidence aggregation.
Completed entity-applicability review receives the disposition, resolved basis and
business context through the same projection as policy review. Partial source
review and producer localization retain their existing subjects and evidence.

**Entity applicability** uses the shared requirement description for role
selection, generation, source/policy review and authorized basis repair. It defines
both the entity-only disposition and the explanation connecting that decision to
the requirements. A negative entity decision retains the other behavioral
obligations. Review assesses the decision and its basis together; an irrelevant
basis is not evidence that those obligations disappeared. This guidance grants
no additional semantic omission-repair authority.

**Principle review** receives one resolved business `subject`, its semantic `task`
and the complete selected `principles`. Feature fields contain their displayed
text; record fields also contain their fully resolved siblings and business record
ID. Collection subjects identify the assessed slot and selected resolved records;
entity applicability includes its disposition and resolved basis. Every subject
retains the resolved brief, candidate and entity basis as supporting context:
free-text principles may relate different requirements. Exact/passive values use
the same projector as rendering. Native requirement tuples, assignment ordinals and
source-review instructions are not business content. Initial review, correction,
insertion and detail/citation repair reuse this projection; native identity,
currentness, evidence admission and retained verdicts keep their existing owners.

**Specification record meanings** come from the shared
[requirement descriptions](../../src/domain/required_authority_description.zig).
Generation receives eligible family meanings and their fields through its source
assignment; focused source and policy reviews receive the selected family/field
purpose. Records authoring also receives `record_requirements`, projecting the
canonical mandatory families with `assembled_specification` scope. Requiredness
applies across bound source-group batches; optional families need no filler.
The authoring prompt asks the collection to preserve all assigned obligations.
The shared acceptance-criterion field descriptions distinguish the situation
before the trigger, the trigger itself and its observable consequences. They
also reach focused review and repair; those paths have no separate definitions.
Atomic repair omits that aggregate authoring guidance and retains its selected
target. Specification content repair presents its authorized `task` once; active source
assignments retain their claim/signal selections and omit authoring purposes.
Native value and membership repairs describe only the selected field or permitted
families. Completed-unit omission repair retains `source_assignment: null` without
recreating a consumed authoring assignment. Authoring resolves requirement meaning
beside the bound purpose; remaining eligible requirements are context, not another
assignment. These are projections of existing claims, not a new evidence ledger.
Original source bytes remain available. Citation coordinates and extractor/token
bookkeeping stay native; exact choices expose only the eligible occurrence, value
and source. Initial requests use their authoring prompt; native replacements use
the existing repair prompt and authorized task. Prompts own the generation, review
or repair instructions, rather than another copy of the definitions.
These descriptions add no optional-family requirement, semantic rejection or
cross-kind deduplication rule.

The shared generation context describes fragments by their assigned field purpose:
a title names, a basis explains, and behavioral fields express requirements.
Exact-copy/reference fragments insert display values; any required explanation or
behavioral meaning comes from the surrounding text. The shared context directs
authors to insert an exact-copy object instead of retyping a supplied preserved
literal inside prose, with any surrounding prose in separate string fragments.
Its selector fields still come from the selected schema. Literal-only values remain
structurally valid where the selected schema permits them. Schema admission and
valid provenance do not establish that a field fulfils its semantic purpose.
The [authoring-guidance comparison](../../test/calibration/authoring-guidance/README.md)
separates this representation change from record-purpose/collection guidance;
offline conformance is not evidence of semantic improvement.

**Determined exact references** follow ADR 0020. A single eligible occurrence is
constructed by native code: the model returns `{"kind":"exact_copy"}` and must
not echo its determined `claim_id`. Multiple eligible occurrences retain the
explicit selection. The selected schema and response construction use the same
immutable native choice facts; protocol correction keeps that schema. Canonical
segments and persisted lineage retain the occurrence ID. Matching literal text
never reconstructs source identity, and this rule adds no semantic support.

**Authoring-role assessment** remains one initial model call. Its `role_decisions`
map requires one decision for every registered role: `supported` with nonempty
unique eligible signal IDs, or `unsupported` without IDs. Role names and purposes
come from the shared catalogue, not another prompt registry. Native admission
rejects missing/duplicate roles and duplicate/ineligible selections, then derives
positive group-role bindings in native offered-group and role order through the
existing validator. No eligible groups yields an unsupported-only selected schema;
pending decisions are not default negatives. Upstream repairs retire the complete
assessment and derived bindings together. Protocol correction retains the same
immutable packet and complete contract, with the existing allowance. An admitted
unsupported judgment does not trigger semantic reconsideration, establish a user
gap or grant entity `not_applicable` authority. See
[ADR 0020](../decisions/0020-derived-exact-reference-lineage.md#complete-role-decision-amendment-approved-9-october-2026).

**Authoring-role handoff** uses the shared
[source-binding coverage check](../../src/domain/specification_source_binding.zig)
before generation. Complete eligible coverage starts authoring. An incomplete
assignment returns `blocked` with every missing role, the current reference state,
partition and revision, role-selection request origin, and eligible signal/claim
IDs. The existing candidate diagnostic carries this evidence into CLI and harness
reports. Source readiness still establishes structural accounting, not role
completeness. Unsupported decisions contribute no canonical positive roles;
the actual captured response retains the verdict. This result authorizes neither
default assignments, a user clarification nor an automatic correction call.
Canonical readback requires complete coverage through the same check.

**After every response**, the engine independently requires one complete JSON object.
The approved [§22.6 prefix normalization](../contracts/22-repair.md#226-unparseable-output)
is logged and preserves the raw response. It rejects fences, duplicate keys,
trailing text and schema violations. Rejected
bytes remain evidence. Valid shape yields candidate data, not business-quality
proof or publication authority.

## Configured smaller outputs — implemented boundary

[ADR 0016](../decisions/0016-configured-json-response-composition.md) separates
cohesive response parts while retaining relevant input evidence. Each call receives
its configured task and exact derived part schema; correction requests that complete
part. Replace combined-output instructions at each part's initial/correction call
site; a narrowed schema must not accompany a prompt requesting sibling fields.
Native assembly receives admitted values and a compiled structural mapping,
with **no LLM prompt or call**. Existing full validation, native repair and total-token
accounting remain. Extraction separates content from dependent token classifications;
global reconciliation separates dispositions, signals and conflicts. Arrays and
optional containers remain whole. These paths are implemented; the retained runs
do not establish a measured reliability improvement or a completed, scored baseline.

## Proposed conformance improvements — 20 September 2026

The [21 September Bedrock comparisons](../../fixes/archive/JSON_ISSUE.md#11-plain-string-versus-constant--completed-follow-up)
reproduced malformed native-schema output with a minimal constant-constrained field;
the plain-string counterpart passed. This narrows the measured boundary without
isolating native constraints from schema guidance or proving a remedy. Preserve
canonical discriminator constraints, admission and bounded correction. These
diagnostics justify neither more decomposition nor workflow completion authority.

The table distinguishes implemented guidance from remaining assessments; linked
contracts own each boundary. [Chunk 18's historical follow-up](../../fixes/archive/IMP_001.md#r45-follow-up--brief-conformance-after-child-object-guidance)
retains its sequencing and approval record; [FIX01](../../fixes/FIX01.md) tracks
current work. R38 repeated incorrect nested wrappers
despite the correct schema; R39 corrected its JSON and then reached a separate
semantic-review problem. Measure structural compliance and semantic quality separately.

| Improvement to assess | Existing owner and boundary |
| --- | --- |
| Assignment-specific instructions | Request/assignment guidance supplies only relevant generation rules, shared JSON framing and necessary evidence. Remove sibling-unit instructions consistently from initial and correction inputs; do not create parallel prompts for every failure. |
| Precise nested correction guidance | The feasibility review selects [one nonrecursive child-object required-field annotation](../contracts/22-repair.md#2261-child-object-requirements), approved on 20 September 2026. Reuse the shared projection and protocol builder with the same selected schema; no branch selection, evidence relocation or candidate synthesis. |
| Explicit error explanations | [§22.6.2](../contracts/22-repair.md#2262-explicit-error-guidance) is implemented through typed diagnostics and schema projection, with repetition wording only from confirmed prior-correction evidence. [R45 delivery](../../fixes/archive/IMP_001.md#r45-delivery--explicit-correction-errors) records offline verification; live effectiveness remains unproven. |
| Model and response-mode comparison | Reuse existing provider binding, schema projection and request capture. Explicitly compare the configured baseline with native mode or another registered, authorized model; change one factor at a time. No automatic fallback, hidden model escalation or new retry owner. |
| Further response decomposition | Reuse ADR 0016 for measured object-shape difficulties. Array-item decomposition remains deferred until finite assignments, stable identities, unique ownership, coverage/order and dependency renewal have accepted authority. Do not add arbitrary splitting, flattening or another assembler. |
| Native derivation of mechanical fields | Reuse existing native construction where accepted inputs determine the value uniquely. Required evidence selections, relationships and business meaning remain explicit candidate data. Changing a wire shape requires consistent schema, decoding, repair, provenance and persisted-validation changes; a formatter cannot infer missing support. |
| Measured model reliability | Reuse the existing harness and captured requests under [§28.8](../contracts/28-testing.md#288-model-conformance-comparisons). Scripted acceptance/rejection tests establish engine enforcement; controlled live comparisons establish model behavior. |

Start with assignment guidance and the focused nested-shape assessment, then compare
model/mode choices. Further decomposition or native derivation needs evidence of a
remaining problem. Successful parts retain their dependencies and provenance;
shared retries, full validation and global token accounting remain unchanged.
Unresolved JSON/schema rejection ends in error without specification publication,
including when clarification forms are open.

## Nested-correction feasibility

**Feasible within existing owners; model benefit remains unproven.** The latest
[R40 evidence](../../fixes/archive/FIX_001.md#42-brief-wrapper-recurrence-and-correction-feasibility)
repeats R38's misplaced root provenance. The validator reports that first unknown
property before visiting children. Its expected node already identifies the brief
branch; the outline reduces each child object to its type. The complete schema is
present, so the opportunity is visibility of the required nesting, not recovery of
lost schema information or proof that the prompt caused the model failure.

| Boundary | Existing responsibility and proposed effect |
| --- | --- |
| Schema compilation/selection | The canonical compiled schema owns fields and requiredness. Named results, configured parts and narrowed native repairs keep their exact binding. No schema or composition format changes. |
| Schema validation | `model_payload_schema` retains its first diagnostic and selected expected node. No extra candidate traversal, defect collection or inferred union selection is needed. |
| Shape projection | `model_schema_projection` adds required names to immediate object-valued field descriptors under the approved §22.6.1 rule. It reads schema data only. |
| Correction/preparation | `model_protocol_retry` uses the projection; `model_request_preparation` copies rendered guidance from scratch into request-owned memory. Original assignment/input/schema and latest rejected response remain associated. |
| Provider/logging | Existing serialization sends the guidance and single complete acceptance schema; native mode retains its existing derived grammar. Existing request capture records the changed bytes without a new log or debugger contract. |
| Admission/continuation | The existing runner accounts each call, applies the same assignment allowance and revalidates the full response. Native merge/full validation and deterministic composition preserve authorized scope, sibling data, dependencies and provenance. |

For example, the derived descriptor for `title` is now:

```json
{"type":"object","required":["value","provenance"]}
```

This is explanatory output derived from the configured schema, not a hard-coded
brief rule or a candidate template. It does not say which claims support a field
or authorize copying the rejected root provenance into every child. Deeper defects
remain governed by the full schema and subsequent diagnostics; this amendment does
not recursively expand objects or array items. Repeated failure still exhausts.

The [implementation and offline verification record](../../fixes/archive/IMP_001.md#focused-226-decision--child-object-requirements)
cover unrelated shapes, optional fields, exact selected-schema ownership, cleanup,
recovery and exhaustion. Request-size evidence measures overhead, not reliability;
approved controlled calls are still needed to measure model outcomes under §28.8.

## Provider mode and implementation evidence

- The model catalogue’s required `json` boolean selects response mode (ADR 0012).
  With `true`, the shared Bedrock serializer sends Structured Outputs through
  `response_format.type: "json_schema"`, derived from the compiled schema.
- The complete schema remains in system guidance and engine validation.
- Tagged `oneOf` becomes disjoint `anyOf`; unsupported bounds stay engine-enforced.
- Explicit token counting uses the same text input as inference.
- The maintained Specify catalogue now sets `json: true` under the user’s
  21 September direction. Earlier prompt-only runs and native tagged-schema
  failures remain historical evidence; enabling native output is not live
  evidence that those failures have been resolved.

AWS documents [structured-output support for gpt-oss-20b](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-oss-20b.html)
and [schema-constrained InvokeModel output](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
(checked 25 September 2026). Availability does not overturn the
[retained native-mode failures](../../fixes/archive/FIX_001.md#47-native-mode-and-retry-counts-are-not-demonstrated-solutions)
or prove improvement for the configured provider/model/schema combination. A
comparison must record the actual mode and full engine-validation results.

For authoring-role semantics, the development-only
[calibration command and cohort](../../test/calibration/authoring-roles/README.md)
reuse production role packets/schema restrictions, native role admission and the
existing single-request replay adapter. Labels stay outside model content. The
candidate guidance is an experiment. Baseline and intervention comparisons bind
each request schema to its matching diagnostic decoder; historical captures are
immutable and any packet reprojection is explicit. Production has no sparse-wire
compatibility reader. Reports separate structural missing decisions, false
unsupported verdicts and wrong supported selections from semantic omissions;
complete representation is not a quality score. The completed
[focused pilot](../../fixes/Z_FIX01.md#r7--high-focused-role-calibration-complete-broader-calibration-remains-open)
found fewer unsupported assignments but unchanged total omissions and a regression
on the captured production input; it retains production guidance. Neither that
small comparison nor offline tests establish whole-workflow reliability.

The [R7 routing follow-up](../../fixes/Z_FIX01.md#97-r7-routing-calibration-follow-up--9-october-2026)
adds reviewed partial-role, competing-group, source-order and split-role cases,
plus two retained production inputs. Reports identify wrong-basis pairs as a
subset of unsupported assignments, after ordinary protocol/native admission.
All 48 approved live comparisons completed. The candidate reduced unsupported
assignments but increased omissions overall and on captured production inputs;
production semantic guidance is retained. Those results used the prior sparse
response contract and do not establish the effect of complete role decisions.
No genuine post-repair role capture is available, and diagnostic results establish
no completed-spec quality improvement. The complete-decision intervention still
requires comparison of omissions and wrong selections before promotion, followed
by actual live publication, rubric grading and an unchanged repeat under §28.

The [latest captured native-mode run](../../fixes/archive/FIX_001.md#latest-native-json-run--malformed-output-despite-native-schema)
returned malformed JSON on all three attempts despite the native schema and explicit
correction errors. Raw provider text and decoded text match; the engine correctly
exhausted and withheld publication. Before another prompt/schema refactor, isolate
the provider behavior with approved comparisons through existing diagnostic replay:
exact baseline, minimal object, representative tagged union. Keep production
acceptance schemas unchanged during these diagnostic probes. Neither native-mode
availability nor one successful probe establishes reliable model conformance.

| Responsibility | Source |
| --- | --- |
| Workflow selection | [spec.workflow.yaml](../workflows/spec.workflow.yaml) |
| Request preparation | [model_request_workflow.zig](../../src/application/model_request_workflow.zig) |
| Shared framing | [model_controls.zig](../../src/domain/model_controls.zig) |
| Bedrock serialization | [bedrock_request.zig](../../src/adapters/provider/bedrock_request.zig) |
| Protocol retry | [model_protocol_retry.zig](../../src/domain/model_protocol_retry.zig) |
| Strict decoding | [model_envelope.zig](../../src/domain/model_envelope.zig) |
| Schema validation | [model_payload_schema.zig](../../src/domain/model_payload_schema.zig) |
