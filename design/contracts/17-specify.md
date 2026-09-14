# 17. Specify stage design

Part of the [proposed design](../design.md#17-specify-stage-design). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

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
   specification units and complete rendered/state candidates. Keep candidates
   private to the execution. Missing business authority creates a clarification,
   not a partial `spec.md`.
7. At successful workflow completion, publish only the complete validated output
   set to the same registered paths, completely replacing existing outputs.
   The clarification branch likewise completely replaces unresolved forms at
   their existing IDs/paths. Recheck containment and user-closed
   clarification protection immediately before writes. Clarification persistence
   is the explicit exception in ADR 0009; failure is never `specified`.

Path selection establishes the target, not the validity of its contents or an
unrestricted filesystem capability. No feature-name reservation, ownership
append, activation registry, transaction directory or recovery scan precedes it.

### 17.3 LLM work

The LLM performs three semantic activities:

1. reference claim extraction and bounded hierarchical reconciliation;
2. one reference-grounded feature brief containing the human title, description, and primary goal;
3. specification content generation from the validated brief and complete reconciled claims.

Calls are split into typed units:

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
- Every initial brief/spec record selects real claim IDs, one or more exact resolved
  clarification-response IDs, or an allowed combination.
- Meaningful exact-copy and source selections remain explicit.
- The engine assigns canonical IDs, validates current authority and selection joins, and
  constructs reference citation lists as the stable unique union of the selected claims'
  canonical citations.
- The model does not reproduce that determined union; user answers never receive fabricated
  reference citations.
- Semantic entailment of arbitrary prose is model-assisted and ultimately user-reviewed; it is
  never misrepresented as deterministic proof.
- For path/filename/URI display text the model may select only a unit-allowlisted passive ID
  from the exact registry.
- There is no unreferenced command description to use as provenance.
- The model returns typed business content rather than Markdown.
- Each acceptance-criterion proposal contains exactly one nonempty typed `given`, `when`, and
  `then` value; the model does not supply Markdown labels or combine the three values into
  free-form prose.

For each feature-brief or specification unit, the declared model operation returns either content or a clarification need. The engine accepts neither hedged invented content nor a magic placeholder such as “TBD.” Mechanically invalid output uses atomic repair/retry; missing domain knowledge does not.

- Before each declared specification model operation and again over the assembled specification
  candidate, `AuthorityReconciliationOrchestrator` builds the complete specification-owned
  requirement set from the reconciled reference claims, required specification fields,
  preservation descriptors, and conflict/open-question rules.
- Feature intent or reference meaning that has zero current support, multiple non-equivalent
  interpretations, missing required detail, unresolved conflict, or uncertain semantic support
  produces an `SNN`; it cannot be downgraded to an assumption, non-goal, context-only signal,
  generic prose, or technical-stage decision merely to complete the specification.
- Entries owned by later technical stages are carried as cited context/obligations without
  asking principles to invent business intent.

### 17.4 Specification clarification behavior

- A valid specification need is deduplicated by its engine-built subject tuple.
- If it is new, the engine allocates the next `S01` through `S99` identity and derives
  `<paths.specs>/<featureId>/clarify/SNN.md`; otherwise it reuses the existing ID and path.
- It commits the registry/form/workflow pause together in `spec_clarification_pending`.
- The model is idle while the engine waits.

- On the next specify run, the engine first parses the exact registered form against the last
  committed clarification/reference binding.
- A user closes it by changing only `requestedStatus` and the answer region.
- The submission must name the current state/record revisions, match the configured select-one
  or bounded-text schema, and be associated with an authenticated actor.
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
- for every spec record, each authority is either a resolvable claim/citation set, a current resolved clarification response, or an allowed combination; reference citations equal the stable unique union of selected claim citations, while user answers never receive fabricated citations;
- every retained reference claim has exactly one closed specification disposition: mapped to one or more fixed/allocated spec record keys, context-only signal IDs (including reference-context question signals), a blocking conflict, a specification clarification need bound to its `SNN` record, or an explicit non-spec reason; no claim disappears between the snapshot and specification, and no question becomes a specification content record;
- derived-feature-brief records cite the reference claims from which they were generated; a later user-authored record requires its explicit acknowledgement provenance;
- exact user-facing copy obligations;
- exact preserved-token propagation in `reference-context.md`, with visual/style kinds additionally requiring visual checks;
- presence of separate observable flows when claims explicitly distinguish success, invalid, empty, error, or terminal outcomes;
- absence of template placeholders and model-authored checklist state;
- artifact boundary: `spec.md` has no `Reference Context` heading or reference metadata;
- unbound or operational technical leakage: foreign absolute paths, fenced code, stylesheet declarations, inline known source-file paths/extensions, known framework/package identifiers, and implementation-only handles; an exact validated passive display node is inert but remains subject to semantic business-relevance review;
- mandatory `reference-context.md` existence, complete section set, and exact binding to the current reference snapshot;
- equality between the reference inventory and the sidecar's rendered file inventory;
- unresolved authoritative conflicts and blocking open questions;
- complete successful authority reconciliation for every specification-owned required field/decision, with no warning-only, assumed, approximate, or later-stage substitute;
- workflow artifact paths and complete output-set membership.

The technical-leakage validator is a strong lexical/static lint, not a complete semantic proof. A separate semantic-review action decides nuanced cases and labels them model-assisted.

### 17.6 Rendering and commit

After validation:

1. assign requirement IDs;
2. render `spec.md` from `SpecificationIR` and the canonical template contract;
3. render the mandatory `reference-context.md`;
4. serialize the immutable reference-derived feature-request state, exact passive-literal registry revision, specification ID ledger, initial/next specification-acknowledgement and clarification-registry states, clarification views, specification-provenance state revision, and canonical reference snapshot;
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

- The user-approved 2026-09-11 amendment restores the original template's `Feature
  Specification:` title prefix and omission of inapplicable sections.
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
- all required output writes succeeded and current canonical state records completion;
- workflow state recorded `specified` after the commit.
