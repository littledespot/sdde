# 17. Specify stage design

Part of the [proposed design](../design.md#17-specify-stage-design), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

### 17.1 Inputs

```text
sdde <workflow-id> --feature <feature-directory> --reference <relative-selector>
```

- The workflow ID is the selected definition's `id`; the supplied [Spec
  definition](../workflows/spec.workflow.yaml) uses `spec-generation`.
- The API requires `featureDirectory` and `referenceSelector`.
- `--feature` and `featureDirectory` are relative to `paths.specs` from `.sddtoolkit.json`, not
  the project root.
- `--feature hello-world` resolves to `<paths.specs>/hello-world/`; its specification is
  `<paths.specs>/hello-world/spec.md`.
- The caller does not include the configured specs root, and the engine never hard-codes
  `specs/` or strips a presumed prefix.
- Exclude `paths.specsArchive` after resolution.

`--reference` independently selects a readable descendant directory beneath
`paths.references`. Reject missing, empty, duplicate, unknown or positional
arguments. These are registered Specify invocation rules, not hard-coded
arguments of the generic workflow engine.

- The feature directory is the identity ([ADR
  0010](../decisions/0010-explicit-feature-directory.md)).
- The same directory selects the same feature even when the reference input changes.
- There is no slug generation, `max-length`, ownership registration, selector-to-owner mapping,
  or scan of other active/archived features.
- The human title, description and goal still come from validated reference content, not the
  directory name.

### 17.2 Deterministic preflight

1. The fixed startup validates project configuration and workflow definitions.
   The selected YAML's registered invocation operation validates both inputs.
2. Normalize the supplied relative feature directory through the shared path
   policy and resolve it against the validated `.sddtoolkit.json` `paths.specs`.
   Enforce configured-root containment, archive exclusion,
   no-follow traversal and unambiguous filesystem identity. A missing target
   may be prepared for authorized output creation; an existing directory is
   not an ownership conflict and requires no overwrite approval.
3. Resolve the selected feature's fixed artifact/state paths. Read and validate
   only the existing state, approvals and clarification files required by the
   selected workflow. Do not trust completion from file existence, and do not
   reset invalid state or read an ownership registry to authorize writes.
4. Load current clarification forms before generation. Preserve every user-closed
   file byte-for-byte, including stale/invalid submissions; reuse applicable
   validated answers and route unresolved requirements through the existing
   clarification contract. Each execution starts at the graph's `start`, not
   a persisted step or task ([ADR 0009](../decisions/0009-atomic-workflow-execution.md)).
5. Validate the independent reference selector, perform bounded no-follow corpus
   inventory/capture/decoding, and require complete supported-source accounting.
   Run only the bootstrap, toolchain and principle operations selected by YAML.
   Reference changes follow normal reconciliation and downstream invalidation;
   they never change the feature directory or mint a second feature.
6. Build and validate reference authority, the reference-grounded feature brief,
   specification units, the principle assessment in §17.3.1 and complete rendered/state
   candidates. Keep candidates private to the execution. Missing business authority
   creates a clarification and a validated incomplete `spec.md` under
   [ADR 0017](../decisions/0017-incomplete-specification-publication.md). It never
   creates completed specification authority from unresolved content.
7. At successful workflow completion, publish only the complete validated output
   set to the same registered paths, completely replacing existing outputs.
   The clarification branch publishes the incomplete specification, current reference
   context and pending workflow state, and completely replaces unresolved forms at
   their existing IDs/paths. Recheck containment and user-closed
   clarification protection immediately before writes. Clarification persistence
   is the explicit exception in ADR 0009; failure is never `specified`.

Path selection establishes the target, not the validity of its contents or an
unrestricted filesystem capability. No feature-name reservation, ownership
append, activation registry, transaction directory or recovery scan precedes it.

### 17.3 LLM work

The [field-composition contract](text-field-composition.md) owns the complete native
text-field inventory, prose requirements and insertion roles. The same policy
drives presentation, admission, repair, exact coverage and stored readback.
Structurally invalid values stop before semantic review; legitimate exact
insertions retain lineage. Prose presence never certifies business meaning.

The LLM performs these semantic activities:

1. reference claim extraction and bounded hierarchical reconciliation;
2. one reference-grounded feature brief containing the human title, description, and primary goal;
3. specification content generation from original sources, the validated brief and
   currently retained claim selections.
4. focused requirement–principle consistency assessment under §17.3.1.

Typed content covers these concerns; each concern does not require a separate call:

- display title;
- primary story;
- observable outcomes;
- acceptance-criteria candidates;
- functional-requirement candidates;
- business rules;
- assumptions and scope boundaries;
- explicit non-goals;
- prohibited behaviors;
- entities, only if business data is involved;
- semantic ambiguity/open-question review.

- The LLM does not assign the feature ID, IDs, headings, paths, dates, status, checklist state,
  passive-literal values, clarification lifecycle, or execution status.
- Every initial brief/spec record has eligible effective reference claims from
  explicit selections or exact segments, one or more current resolved
  clarification-response IDs, or an allowed combination.
- Source selections remain explicit under their own contract. Under
  [ADR 0020](../decisions/0020-derived-exact-reference-lineage.md#native-exact-value-recognition),
  the model types exact values in meaningful prose and never returns `exact_copy`.
  Native code recognizes unambiguous raw-byte occurrences within the current
  request's eligible scope and contextual delimiters, retaining canonical handles.
  Recognized `E` may extend unchanged selected support `S`; it neither chooses a
  source group nor proves semantic use. A reference alone describes no behavior.
- The engine assigns canonical IDs, validates current authority and selection
  joins, and derives effective claims and their citation union from explicit
  support plus exact segments through the shared reference owner.
- The model does not reproduce that determined union; user answers never receive fabricated
  reference citations.
- Semantic entailment of arbitrary prose is model-assisted and ultimately user-reviewed; it is
  never misrepresented as deterministic proof.
- For explicit path/filename/URI references the model may select a unit-allowlisted
  passive ID. Native recognition admits exact values in prose under ADR 0020. Ordinary
  prose punctuation is not a reference.
- A valid display reference proves neither business meaning nor source preservation.
  Existing source review must distinguish a path-valued requirement from a filename
  substituted for the behavior described in that file. After generation the
  judgment remains advice; independent native defects retain their typed routes.
- **Post-generation assessment:**
  [ADR 0023](../decisions/0023-advisory-post-generation-review.md) governs source
  and principle review. Source review assesses one whole canonical unit, record
  family or complete collection per call: the brief, story, entity applicability,
  all fields/relationship members of every record of one kind (a record family,
  each member carrying its own record), or an independently assigned
  collection/reference subject. A family stops atomically under one
  protocol-correction allowance; narrow finding correction keeps its per-target
  allowance. Principle review assesses the complete generated
  requirement set together, carrying the selected principle corpus once. Native
  ownership defines each complete member set; a model cannot choose a subset.
  Each closed assignment response contains exactly one finding per assigned
  requirement. Missing, duplicate, foreign or partial membership rejects at
  response admission, before any member is appended. The existing bounded protocol
  correction resubmits the complete assignment. Assignments exist only under
  advisory policy, so on exhaustion that assignment's advice closes as incomplete
  (ADR 0023, 18 October 2026). An assignment also withholds any positive verdict
  to which no claim set can be bound, such as `supported` for a coverage subject
  whose collection has no records; one in a response rejects at admission in the
  same way (ADR 0023, 20 October 2026). Canonical ledger order, per-member evidence, origins,
  current candidate revision and full assignment context remain bound. Initial
  admission cannot fall back to a singleton response for a required batch.
  Narrow finding correction preserves the verdict and every sibling.
  Retention must compare the complete current assignment and dependencies;
  reuse creates neither a new call nor semantic proof.
  All inference, including post-generation review and correction, counts once
  against the single 100,000-token workflow budget (ADR 0011). Global exhaustion, overshoot or unavailable
  usage prohibits all later model calls. A global budget rejection ends the workflow
  with `WorkflowTokenBudgetExceeded`, including during advice; it cannot publish or
  become incomplete advice. Eligible provider stops, exhausted protocol correction
  or genuinely missing usage may record `assessment_incomplete`, with the exact
  unassessed member set and native stop evidence. Only a fully admitted assignment contributes
  findings. This is no assessment success or semantic support, and it cannot fail an
  otherwise valid workflow. Native defects, invalid trusted associations, cancellation, deadlines
  and security/logging/operational failures retain their ordinary blocking routes.
  Inspectable retained findings and the incomplete status are published together
  with the same current candidate binding; stale or forged stop evidence rejects.
- Registered source-readiness and preservation projections require native
  pre-generation phase facts. Generation sessions cannot be treated as readiness
  merely because no brief has been produced yet. Late required-review projection
  attempts reject; complete generated content selects the advisory projection.
  Generation initialization requires the canonical required-authority projection
  set to be retired and no active native repair permit, preventing earlier
  required review or dependent repair validation from surviving into generation.
- Every admitted post-generation semantic finding retains its original type,
  explanation, selected evidence, subject and origin as advice. Native
  `assessment_complete` records complete current assessment without declaring
  the content supported. A model's positive or negative finding cannot create,
  discharge or repair a native defect, create a mandatory Plan obligation, or
  manufacture a clarification. Native requiredness, provenance, exact coverage,
  authority currentness, citation/selection validity and publication gates remain
  independently mandatory. A genuinely unresolved required decision uses the
  existing native clarification owner; model uncertainty alone establishes none.
- Source findings keep their closed evidence contract, including a nonblank
  `missing_obligation` for `candidate_omission`, distinct from its explanation.
  Source selection and field purpose bind the observation without proving its
  meaning. Collection review assesses complete selected-member coverage; record
  fields may jointly express conditions and results. Original sources establish
  obligations, while claims/groups remain derived evidence. Exact/passive
  references resolve through the canonical projector, not from display equality.
- Pre-generation source-readiness and optional preservation review retain their
  existing required semantics and bound loss-comparison contract in §22.1.
  A source repair pins its original required review purpose in the native retry
  scope. Becoming generation-ready cannot skip that review; the matching pending
  validation remains required even when the optional preservation scan is disabled.
  Before authoring, a positive readiness source-purpose finding requires explicit
  nonempty original source IDs and empty canonical claims/citations/clarification
  selections, under the approved §12 rule. It retains model-assisted source
  authority without creating a candidate binding or authored association.
  Post-generation advice triggers no paid localization/comparison or automatic
  omission repair. An upstream finding retains its producer/evidence in a typed
  outcome or an independently justified clarification; it never restarts
  extraction, reconciliation and generation. Independently detected native
  generation/coverage defects retain their authorized repair or blocked outcome.
- There is no unreferenced command description to use as provenance.
- The model returns typed business content rather than Markdown.
- Each acceptance-criterion proposal contains exactly one nonempty typed `given`, `when`, and
  `then` value; the model does not supply Markdown labels or combine the three values into
  free-form prose.

[ADR 0020](../decisions/0020-derived-exact-reference-lineage.md#authored-associations)
couples semantic support selection with the existing authoring assignments. There
is no independent presentation-role classifier or mandatory role-prebinding gate.
A current complete reconciled reference state with a nonempty retained group
catalogue admits generation; missing or stale authority is an engine rejection,
not a human information gap.

Each initial attributed value returns nonempty unique `signal_ids` with its
`BusinessValue`. Native admission resolves the selected canonical group
occurrences into required `source_group_ids`, their complete ordered claim union
`S`, exact dependencies and citations. Joint support and legitimate overlaps are
permitted; repeated, foreign, mixed-inactive or stale groups reject. A larger
catalogue is availability, not semantic support. Positive associations cannot map
open questions; initial clarification questions have a separate native eligibility
scope and select only their actual evidence. Existing missing/ambiguous/conflicting
reasons and inconclusive outcomes remain. A question does not establish a genuine
user gap merely by having valid IDs. Shared field purposes describe derivation
from source-backed behavior, not a demand for prewritten titles, goals or stories.
Do not invent an actor, benefit or entity to fill a field.

Record authoring binds one complete retained group containing at least one
non-token claim and may return multiple records
or none. Responses remain content-only; every admitted record inherits that group's
complete selection and exactly one group occurrence. The shared finite native
iteration contract in §6 fixes the population at three narrative assignments plus
the native record-authoring group count and advances once per admitted assignment, even
for an empty record array. It grants traversal only for committed progress and
does not enlarge retry limits. Existing aggregate required families, entity
membership, claim mapping, exact-token coverage and semantic review still apply.
An empty collection contributes no positive coverage.
All-preserved-token groups have no record batch, but remain in general source
catalogues and exact evidence. Zero authorable groups returns a typed binding
rejection. Mixed groups retain every original member and occurrence identity.
The model-facing `record_requirements` projects those same native assembly rules:
AC and FR are required across the assembled non-entity record batches. Entity
records are owned by the single feature-wide entities unit, which returns the
applicability decision, its basis and the complete entity collection together.
A `required` decision requires at least one entity; `not_applicable` requires an
empty collection. Each entity record explicitly selects its own eligible source
groups, independently of the decision basis. Native code derives its full support
and citations through the shared source association and exact-recognition owners.
A record batch cannot author an entity: the closed schema, native admission,
canonical revalidation and repair boundary enforce the same ownership rule.
The feature collection participates once in canonical IDs, coverage, review and
stored readback; its fields and records retain their actual producing origins.
The batch presentation's scope remains `assembled_specification`; an individual
group may remain empty, including after earlier groups have satisfied a family.
This presentation introduces no per-group minimum or per-family cardinality cap.

Initial brief/story/entity responses and clarification questions select groups;
fixed value and record repairs do not. Protocol correction preserves the initial
catalogue and schema. Value-only repair preserves the existing authored association,
`S`, effective evidence bounds, siblings, revision and retry identity. Changing
group membership requires separately authorized authored-unit rebuilding, which
does not exist. An unresolved association blocks; it cannot be
rerouted to extraction, grouping or a removed role producer. A missing required
entity may be inserted only in the feature entities unit,
using the existing applicability basis's exact selected association; it cannot
choose a new group or borrow a writable record batch. Contradictory entities under
`not_applicable` are removed from that collection; they are never converted into
another content family. Coupled entity correction preserves the fixed association,
its native effective evidence bound, siblings and retry identity.
Upstream changes invalidate affected groups, authored associations and dependent
review/attribution evidence. Canonical readback recomputes projections from captured
groups and rejects inconsistency; no parallel binding store or legacy reader applies.
Native shape and membership checks do not establish semantic adequacy. Generation,
source review and repair responses contain no `provenance`.
Completed
`reference-context.md` displays each generated record ID with its effective
claim-to-citation occurrence edges and captured source spans. This read-only
view adds no selection or stored authority; pending output has no generated
record links. Original requirement IDs appear only when captured as validated
source associations, never inferred from headings or claim ordinals.

For each feature-brief or specification unit, the declared model operation returns content, an identifiable clarification need, or an inconclusive interpretation. Inconclusive interpretation fails; it is not missing user information. The engine accepts neither hedged invented content nor a magic placeholder such as “TBD.” Mechanically invalid output uses atomic repair/retry; missing domain knowledge does not.

- **Consolidated generation:** the shipped workflow requests brief, primary story, feature entities and
  source-group records as four sequential task types through one shared
  generation subgraph. Narrative, applicability and record drafting receive their
  purpose-specific configured authoring prompts. Native repairs receive the
  configured repair prompt and the selected field/record purpose from the existing
  repair task. Protocol correction retains that active assignment and its schema.
  The primary story has its own concise prompt and uses the canonical story purpose.
  Generation and native unit repair share static text
  guidance from `spec/generation.context.json`: ordered fragments form one field
  value, prose expresses its meaning and types required exact values verbatim.
  Native recognition owns exact occurrence bookkeeping; supplied passive/source
  references retain their allowed forms. Schemas remain the sole response-shape authority. Initial and native
  repair packets include earlier drafts only for dependent units: entities receive
  the brief, records receive the brief and entity decision. Brief and story requests
  receive neither sibling draft. Dependent drafts are resolved business text and
  applicability; their canonical provenance, fragment wrappers and display-span
  bookkeeping remain native. Record-family purposes and response alternatives
  use the same native unit ownership; entity applicability and records are decided
  together in the feature entities unit. Batch records always exclude entities.
  Source evidence and native repair dependencies
  remain complete; packet presentation does not change semantic review or retry policy.
  Authoring packets resolve offered complete group requirements beside field
  purposes; initial values select their support while drafting. Record packets
  retain their fixed group and separate remaining context without repeating assigned claims.
  Shared guidance names `source_assignment.requirements` as the batch's duties;
  `context_requirements` and prior drafts help interpret them without substituting
  another group's independent obligation or changing fixed repair evidence.
  A preserved-token occurrence retains its cited source context, including the
  source-required use and conditions of that value. Token membership alone neither
  establishes semantic entailment nor requires an empty batch. It does not assign
  every other duty in the source to that group. Under ADR 0024, only groups whose
  complete membership is preserved tokens are omitted from record scheduling;
  this adds no context prohibition. Semantic support remains subject to original-source
  review. Original sources remain available; citation
  coordinates, extractor metadata and redundant token IDs remain native.
  Exact-value guidance exposes authorized literal/source context through one
  reference-owned projection; immutable native metadata retains occurrence identity
  and current snapshot/request eligibility. Multiple same-span eligible identities
  are ambiguity, never a model choice or catalogue-order tie breaker. Repair and
  correction retain their original narrower scope.
  The canonical story purpose identifies an actor or system supported by the
  source, rather than requiring an invented user persona or prewritten story.
  Functional requirements express behavior and obligation; acceptance criteria
  express precondition, triggering action and observable outcome. A rejected
  candidate may omit intent: repair preserves source meaning and correct surrounding
  content within its authorized scope, not the rejected value's omissions. Literal
  values alone do not replace the behavior involving them. This guidance is not a
  deterministic semantic validator or authority to widen a repair target.
  Record kinds remain closed schema variants; an optional family has no dedicated
  call or required filler. Assumptions must be
  supported premises, non-goals supported exclusions, and prohibited behaviors
  forbidden actions. Positive requirements cannot satisfy those meanings merely
  by having valid citations. Semantic assessment remains with the existing review.
  Per-field validation, atomic repair, request identities and total-token accounting
  retain their existing owners. Request grouping grants no semantic repair authority.
  Original candidate indices/origins survive canonical section-order projection;
  native repair resolves canonical IDs back to those original indices.
  A record clarification must name its closed `record_kind`; other generation
  units prohibit that field. The existing clarification builder uses that family
  as its subject, preserving identities across reruns instead of merging all record
  questions into a new generic subject. This changes no clarification admission rule.

- **Draft-first sequencing:** complete validated references with a nonempty selectable retained group catalogue admit
  execution-local section generation without a
  model review of specification fields that do not yet exist. The existing source
  review/repair route still handles blocked references or absence of selectable
  positive evidence before generation. The native readiness check reuses the
  provenance owner's eligibility rule; it cannot certify source meaning or create
  a clarification.
  Generation and its selected repairs receive original sources through the shared
  evidence projection, retained claims/citations and exact tokens; the native group catalogue exposes selectable complete members without
  adding a second semantic authority. Original text is context, not a new
  provenance selection or permission to cite a discarded claim.
- [ADR 0021](../decisions/0021-optional-source-preservation-review.md) adds the
  opt-in `validation.sourcePreservationCheck` before generation-ready sources
  proceed. One obligation per captured source checks meaning preserved by
  extraction/reconciliation, including sources with no claims. Source-only loss
  goes through the shared localization, authorized repair, dependent rebuilding
  and re-review path. The extra check is skipped when disabled or omitted; it
  never replaces the mandatory review below. Authorized candidate repairs use
  the separate configured `repair` model slot; protocol retries retain their
  original binding.
- Assemble and validate the generated sections, then build the complete
  specification-owned requirement ledger and perform source-preservation and
  principle assessment through the existing review owners. The shared authority
  gate remains mandatory for rendering, state construction and publication.
  Explicit regeneration after actual input changes retires prior assessment
  projections. A review finding cannot initiate upstream rebuilding. Drafts
  confer no completion or downstream authority.
- A current required business choice genuinely missing or ambiguous in the source
  produces an `SNN` only after shared [§12.8.1 admission](12-model-boundary.md#1281-clarification-admission-and-candidate-failure-precedence).
  Uncertain interpretation, missing extraction or an unverified conflict label does
  not establish a user decision. Neither a gap nor a candidate defect may be hidden
  in assumptions, non-goals, context or technical-stage decisions to complete Spec.
- Entries owned by later technical stages are carried as cited context/obligations without
  asking principles to invent business intent.

Source review must distinguish a source conflict from a false conflict introduced
by extraction/reconciliation, following [§16.4](16-reference-ingestion.md#164-semantic-extraction-flow).
Supported content stranded behind an incorrect disposition is candidate loss, not
missing user knowledge. Review receives the original source and must assess that
meaning even when current eligible signals contain only a preserved token. A
validated conflict label alone cannot justify an `SNN`. Shared clarification
preparation in §12.7 requires a concrete missing decision. Before generation,
correcting an unsafe upstream candidate requires an authorized target and complete
rebuilding. Post-generation semantic findings retain advisory status under
[ADR 0023](../decisions/0023-advisory-post-generation-review.md).

### 17.3.1 Requirement–principle consistency review

Governed by [ADR 0015](../decisions/0015-specification-principle-review.md) as
amended by [ADR 0023](../decisions/0023-advisory-post-generation-review.md).

After references and applicable validated answers establish business intent, compare
that intent with the current principle selection from
[§9.4](09-configuration.md#94-project-principle-resolution). Reassess affected business
units after source/answer changes, generation or repair; require current complete
evidence before publication. Reuse the existing semantic-assessment request, admission and authority
owners with a distinct typed assessment purpose; do not create a second policy
validator, source loader or summary model. YAML declares the calls and typed exits;
actions retain one responsibility and the runner owns execution.

Guidance must distinguish the business assignment being assessed from the principle
chunk and source-line range cited as evidence. Assignment ordinals do not identify
policy chunks. Source-preservation and principle-consistency instructions stay
specific to their existing typed purposes; the same shared review orchestration
and each purpose's guidance serve initial review, insertion and selected repair.
A policy finding explains the relation between business behavior and a cited policy
passage. A source-comparison concern alone does not establish a policy conflict,
and a citation's existence does not prove semantic support.

- Source-preservation review remains independent: it distinguishes missing source
  authority from extraction/reconciliation loss. Principles are policy evidence,
  never reference claims, source citations or sufficient positive business support.
- The assessment receives assigned business units supported by references or current
  validated answers, plus the exact selected principle spans once, with their existing
  typed IDs and citations.
  Native checks establish assignment coverage, citation membership, current source,
  answer and principle bindings, and closed findings. Compatibility remains
  model-assisted; a structurally valid no-conflict result is not deterministic proof.
- A clear business requirement with a model-reported policy conflict remains
  intact. Retain the cited finding and affected identities as advice under
  ADR 0023. It alone creates no mandatory Plan obligation or Spec clarification.
  Do not force a user to restate known intent or create a `PNN` during Specify,
  before Plan's predecessor and `PlanInputAuthorityState` exist.
- A genuine business-choice gap uses the existing `SNN` route. Changing or waiving
  project policy belongs to Plan/project approval. Neither the model nor an ordinary
  clarification answer may silently amend principles or business requirements.
- No open Spec clarification may be relabelled a deferred policy obligation. Plan
  remains prohibited until every Spec clarification is resolved under the existing
  answer/authority contract; Tasks remains prohibited while any Spec or Plan
  clarification is open.
- Completed Spec publication requires current native assessment bindings and
  all native business/authority checks. Advice may be completely assessed or
  explicitly `assessment_incomplete` with the exact unassessed set and an
  admissible native stop. Neither disposition certifies semantic compatibility. Plan validates current project policy and
  its own required decisions independently; a semantic finding alone cannot
  choose that requiredness or resolve policy.

Persist the assessment's provenance, exact principle selection/revision and
advisory findings through the existing canonical evidence/context owners; render
the cited advice in `reference-context.md`. That view is not authority. Add no
parallel summary store, copied principle registry or new fixed artifact. Fresh
readback must recover the same associations. A principle change invalidates the
dependent assessment; the consuming gate rebuilds it under §24.5 without rewriting
unchanged business intent. An earlier no-conflict finding cannot certify Plan's
current policy compliance.

Capturing principle files is not performing the assessment. A source-authority gap
may pause before policy assessment; the incomplete view is then unassessed, never
policy-approved. Existing execution evidence/reporting must distinguish captured
inputs from an executed assessment. Principles cannot repair a false negative in
source review by becoming business authority. Assess supported intent through the
existing policy path once its prerequisites hold; retain its cited advice.

### 17.4 Specification clarification behavior

- Both need producers follow [shared clarification preparation](12-model-boundary.md#127-workflow-defined-model-operations)
  after §12.8.1 admission and before refresh/render/publication. A genuine gap beside
  an unresolved candidate defect cannot bypass the shared precedence rule.
- Source review assesses meaning, not whether references already contain separate
  stories, acceptance criteria or requirement headings. Known behavior must not be
  requested again merely to fill those categories. Genuine missing actors, outcomes
  or choices must be identified precisely. Post-generation omission findings
  remain advice; independently detected native defects retain their owning path.
- A valid specification need is deduplicated by its engine-built subject tuple.
- If it is new, the engine allocates the next `S01` through `S99` identity and derives
  `<paths.specs>/<featureId>/clarify/SNN.md`; otherwise it reuses the existing ID and path.
- It commits the registry/form/workflow pause together in `spec_clarification_pending`.
- Source, generation, post-generation and residual open-registry pauses all use the
  existing shared incomplete-specification publication path in ADR 0017. A validated
  current reference snapshot is required. The output includes `spec.md`, reference
  context and linked forms, but grants no completed or downstream authority.
- Unrepaired JSON/schema failure follows §22.6 and takes precedence over open forms;
  it cannot be reclassified as a user clarification to obtain publication.
- The model is idle while the engine waits.

- On the next specify run, the engine first parses the exact registered form against the last
  committed clarification/reference binding.
- A user closes it by changing only `requestedStatus` and the answer region.
- The submission must name the current state/record revisions, match the configured select-one
  or bounded-text schema, and be associated with an authenticated actor.
- [ADR 0025](../decisions/0025-clarification-answer-authentication.md) defines that actor as the
  operating-system account that runs the engine; running Specify with valid closed forms
  accepts them. If any closed form is invalid, the run accepts none of them, makes no model
  call and reports a typed reason for each failing form. Not yet implemented.
- An empty close is invalid; `defer` remains open; `cancel` cancels the run.
- Path-shaped answer text is scanned into the inert passive registry under the assigned response
  ID, and that complete clarification response is published before refresh.

- The engine then refreshes the selected reference directory and tests still-open `SNN` records
  against the new claims/citations.
- A current, non-conflicting authority resolution may close the record after deterministic join
  validation and, where semantic interpretation is required, a bounded workflow-declared
  clarification-resolution proposal.
- If the reference snapshot is directly unchanged, the current-reference resolution variant may
  retain current provenance and may adopt only a specification-contract bootstrap successor.
- If refresh constructs a successor reference snapshot or adopts a reference-ingestion bootstrap
  successor, the reference-revision resolution variant atomically includes the regenerated
  reference view and the complete descendant/runtime/evidence invalidation mutation; it clears
  feature-request/provenance/plan/task pointers and cannot carry a stale provenance state.
- Thus no clarification registry can point to an uncommitted snapshot and no changed reference
  can bypass the ordinary rework contract.

Preserve accepted clarification responses under Section 23.2. A new Specify execution starts at its beginning and regenerates every unit from current validated inputs; no resumed workflow state is committed before generation.

### 17.5 Deterministic specification validation

The engine validates:

- workflow-declared operation result schema and source references;
- nonempty mandatory IR fields;
- fixed singleton provenance keys plus engine-assigned, unique, well-formed `AC/UO/EC/FR/BR/AS/NG/PB/EN-*` identifiers; initial generation is gap-free per prefix, while edits preserve surviving IDs, allocate new monotonically increasing IDs, and never reuse deleted IDs;
- exactly one nonempty `given`, `when`, and `then` field for each acceptance criterion; combined free-form, unlabeled, missing, duplicated, or reordered acceptance-condition content is invalid;
- duplicate or byte-identical requirements;
- typed clarification state rather than fragile substring matching;
- citation validity and reference-file accounting;
- for every spec record, each authority is either a resolvable reference-claim/citation set, a current resolved clarification response, or an allowed combination; reference citations equal the stable unique union derived under ADR 0020 from explicit support and exact dependencies, while user answers never receive fabricated citations;
- every retained reference claim has exactly one closed specification disposition: mapped to one or more fixed/allocated spec record keys, context-only signal IDs (including reference-context question signals), a blocking conflict, a specification clarification need bound to its `SNN` record, or an explicit non-spec reason; no claim disappears between the snapshot and specification, and no question becomes a specification content record;
- derived-feature-brief records cite the reference claims from which they were generated; a later user-authored record requires its explicit acknowledgement provenance;
- exact user-facing copy obligations;
- exact preserved-token propagation in `reference-context.md`, with visual/style kinds additionally requiring visual checks;
- presence of separate observable flows when claims explicitly distinguish success, invalid, empty, error, or terminal outcomes;
- absence of template placeholders and model-authored checklist state;
- artifact boundary: `spec.md` has no `Reference Context` heading or reference metadata;
- unsupported technical content: existing semantic review assesses whether code, filenames, paths, framework identifiers and implementation details belong in business requirements. Lexical shape alone is not a semantic rejection; explicit references and exact values still require native evidence validation under §7.1;
- mandatory `reference-context.md` existence, complete section set, and exact binding to the current reference snapshot;
- equality between the reference inventory and the sidecar's rendered file inventory;
- unresolved specification-owned conflicts and blocking open questions;
- current principle-assessment bindings under §17.3.1, either complete findings
  or a validated incomplete-advice disposition; policy findings cannot erase
  source requirements or create downstream mandatory obligations;
- complete successful authority reconciliation for every specification-owned required field/decision, with no warning-only, assumed, approximate, or later-stage substitute;
- workflow artifact paths and complete output-set membership.

The technical-leakage validator is a strong lexical/static lint, not a complete semantic proof. A separate semantic-review action decides nuanced cases and labels them model-assisted.

### 17.6 Rendering and commit

After validation:

1. assign requirement IDs;
2. render `spec.md` from `SpecificationIR` and the canonical template contract;
3. render the mandatory `reference-context.md`, including completed requirement-to-source occurrence links;
4. serialize the immutable reference-derived feature-request state, exact passive-literal registry revision, specification ID ledger, initial/next specification-acknowledgement and clarification-registry states, clarification views, specification-provenance state revision, canonical reference snapshot, and §17.3.1 evidence/advice within their existing canonical owners;
5. reparse `spec.md` and compare its normalized IR to the validated source IR;
6. compare the read-only reference-context view with deterministic rendering from its canonical IR;
7. stage the complete artifact set, exact workflow-artifact registry, bootstrap-authority state, feature-request state, passive-literal registry state, specification ID ledger, acknowledgement and clarification-registry states, writable clarification forms plus preservation preconditions for retained user-closed forms, specification-provenance state, canonical reference state, and next workflow-state record as one candidate output set;
8. validate the complete set and all captured-input/preservation preconditions;
9. publish registered outputs, writing canonical workflow state last; on write failure report no new successful completion (§25);
10. report engine-known paths and readiness for user spec editing/validation, then `plan`.

The document follows the exact hierarchy in
[F0100 §5.1](../features/F0100-SpecWorkflow.md#51-ownership-and-hierarchy): its H1
is the display name, and the mandatory parents are `User Scenarios & Testing`
and `Requirements`. The acceptance-criteria subsection is nested beneath the
first parent and is always rendered in this form:

```markdown
### Acceptance Criteria

- **AC-001**: **Given** <nonempty business precondition>, **When** <nonempty business event or action>, **Then** <nonempty observable business outcome>
```

- Every criterion has one engine-owned `AC-*` identity followed by the compact `Given`, `When`,
  `Then` triplet.
- The renderer owns labels, casing, separators, order and structure.
- The editable parser rejects missing, duplicated, reordered or foreign labels and the
  superseded multiline uppercase form.
- Exact code spans may contain label-shaped text without becoming structure.

- The H1 uses the `Feature Specification:` title prefix, and inapplicable sections are
  omitted.
- Mandatory parents, primary story, acceptance criteria and functional requirements remain
  present; optional empty families and an empty scope parent are omitted.
- The shared required-authority projection requires supported acceptance criteria, functional
  requirements and complete scenario coverage.
- Missing mandatory record families in an assembled candidate force a `missing` gap through that
  gate; positive model evidence cannot override absence.
- Scenario coverage remains model-assisted, requiring comparison with source claims/citations,
  including triggers, outcomes and exact copy.
- The persisted specification-state validator also enforces the canonical required-family
  contract.
- Display omission never proves non-applicability or removes a source obligation.

- The initial acknowledgement state is present even when its `entries` array is empty.
- Its ID, the feature-request-state ID, passive-literal-registry ID, and their engine-derived
  paths are stored in workflow metadata and bound by `SpecificationIR`,
  `SpecificationProvenanceState`, and any reference snapshot; stage gates and fresh invocations
  load and validate all authorities before model selection, provenance acceptance, or rendering.
- No fingerprint is written.
- If the engine process is restarted, later stages reload and revalidate the current artifacts.

### 17.7 Specify gate

`specify` succeeds only when:

- the specification IR and rendered `spec.md` pass all blocking rules;
- every reference file is accounted for;
- the sidecar exists and passes when required;
- no behavior-changing reference conflict remains unresolved;
- no specification clarification record remains open;
- the current §17.3.1 advisory assessment, its native bindings, and required
  principle authority validate;
- all required output writes succeeded and current canonical state records completion;
- workflow state recorded `specified` after the commit.

### Shared authoring and diagnosis

Model-assisted review distinguishes invalid additions from missing original
meaning using the source-only finding in §12. A mixed source gap remains visible
alongside invalid candidate content. Under ADR 0023, post-generation judgments
alone authorize neither clarification nor content repair. Native diagnostics bind the assessed subject,
purpose, original evidence and permitted correction scope; models never select a
repair producer or turn candidate assertions into source requirements.

Authoring and content repair use the shared typed-text wire representation in
§7.1. Prose does not require manual segmentation. Native recognition constructs
eligible exact occurrences from complete values in prose; explicit composition
retains authorized passive references. Native code converts and renders admitted
segments without adding separators or inventing an occurrence identity.

Native record assembly presents required, present and unmet structural families
from its existing policy and admitted state, without copying previous drafts into
the request. These facts apply to the assembled specification; an individual
group may return an empty batch. Presence does not establish semantic coverage.
An aggregate defect does not acquire an owner from the last dispatched group.
Repair must retain its evidence and current authorized unit; unsupported ownership
produces an explicit diagnostic rather than an invented association. Alternative
authoring units are evaluated under FIX05 B5; none is adopted here.
