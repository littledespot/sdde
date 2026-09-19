# 23. Rendering and editability strategy

Part of the [proposed design](../design.md#23-rendering-and-editability-strategy). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

- The engine, not the LLM, renders persistent artifacts.
- `spec.md` is the only freely editable stage artifact.
- Clarification documents under `clarify/` are controlled input forms: the engine owns their
  filename, identity, question, schema, and revision fields, while the user may change only
  `requestedStatus` and the answer block.
- Every plan/task/reference artifact remains a read-only review/progress view backed by
  canonical state.
- This prevents display edits from changing execution while still giving the user an explicit
  file-based answer channel.

Renderers own:

- fixed mandatory headings and relative order of applicable optional sections;
- front matter/header fields;
- dates and engine-known links;
- `AC/FR/BR/EC` and `TNNN` identifiers;
- the exact F0100 §5.1 heading tree, including `### Acceptance Criteria`
  beneath `## User Scenarios & Testing _(mandatory)_`, and compact title-case
  `Given`, `When`, `Then` labels in that order for every `AC-*` record;
- checkboxes and phase/gate status;
- Markdown table columns and escaping;
- code fences around structured contracts where applicable;
- repo-relative path formatting;
- passive filename/path/URI rendering as inert inline-code text;
- deterministic ordering;
- exact preserved token values;
- clarification filenames and immutable question/schema/revision regions, while preserving only the two declared user-editable fields;
- completion summaries derived from state.

- Renderers have no ambient registry access.
- Each render/validation action receives the canonical wrapper named by the view plus its exact
  `FileRegistryState`, bound `PassiveLiteralRegistryState`, required bound `ReferenceSnapshot`,
  exact `WorkflowArtifactRegistry`, and recorded `RendererContract`.
- `SemanticText` file/source/passive nodes resolve only through those authorities.
- `GeneratedView.stateBinding` records the relevant
  plan/file/reference/passive/workflow-artifact registry identities so restart validation cannot
  accidentally render against a newer global registry.

### 23.1 Canonical byte contract

- Every canonical-state serializer and generated-view renderer executes under an exact
  `rendererContractVersion`, stored in canonical workflow state and in each `GeneratedView`
  binding.
- `renderer/v1` requires strict UTF-8 with no BOM, NFC-normalized ordinary textual scalars, LF
  line endings, no trailing spaces introduced by the renderer, and exactly one final newline.
- Tagged `RawSourceScalar`/verbatim values are the underlying text exception: their validated
  UTF-8 scalar sequence bypasses NFC and is emitted through the versioned deterministic
  Markdown/JSON escape function without altering the represented value.
- `ExactBusinessCopy` can emit such a scalar only after its token ID and citation resolve to the
  same current snapshot scalar; it never carries inline model bytes.
- Opaque copied file bytes are not rendered or Unicode-normalized; their immutable blob contract
  remains byte-exact.

- Canonical JSON additionally sorts object keys by Unicode scalar value, preserves array order
  only where the domain schema declares it meaningful, uses the domain's stable sort key
  everywhere else, applies one fixed JSON string-escape table, emits lowercase
  `true`/`false`/`null`, and emits integers in base 10 with no leading plus or zeroes.
- Policy-bearing decimal values are represented as schema-normalized decimal strings; binary
  floating-point spellings are forbidden in canonical state.
- Markdown uses a versioned escape table for text/table cells, a deterministic fence
  length/language rule, fixed blank-line rules, and renderer-owned path/link formatting.
- A passive literal is emitted as non-link inline code: the delimiter is one backtick longer
  than the longest contiguous run in the value and the fixed CommonMark padding rule is applied.
- The renderer never emits it as a Markdown link, autolink, HTML anchor, or clickable local
  path.
- These rules define bytes, not merely equivalent text.

- Validation regenerates with the version recorded by the state/view and compares exact bytes.
- A fresh invocation must use the recorded renderer contract; it must never substitute the
  host's newest renderer implicitly.
- If the recorded version is unavailable, validation blocks with `RENDERER_VERSION_UNAVAILABLE`.
- A deliberate renderer migration includes new canonical/view revisions in the complete
  validated output and requires renewed plan/task review whenever review-visible bytes change.
- No digest or fingerprint is stored or compared.

- `spec.md` is reparsed and normalized at the plan boundary; its IR must pass the full
  specification gate.
- The parser first captures each semantic field's exact UTF-8 bytes and record key.
- When current provenance marks a leaf as `ExactBusinessCopy`, `RebindExactBusinessCopyAction`
  compares the captured unescaped scalar byte-for-byte with the referenced preserved token and
  reconstructs the typed variant; any difference loses the binding and produces an exact-copy
  diagnostic.
- Every other leaf is deterministically segmented into NFC-normalized `BusinessLiteralText` and
  inert inline-code passive-literal spans.
- A known span resolves by exact `(kind, NFC bytes)` against the registry bound by the
  specification.
- A new user-written filename/path/URI cannot become a model repair or operational path: it
  requires a new engine-assigned passive ID and occurrence tied to the same authenticated
  specification acknowledgement, and the registry/acknowledgement/provenance/spec revisions
  commit together.
- A rejected or failed allocation is retired.

- A user may edit semantic fields and add, remove, or reorder semantic records, but engine-owned
  headings, status/checklist fields, acceptance-criterion labels/order, and existing ID syntax
  remain protected by validation.
- Each acceptance criterion must remain an explicit compact `Given`/`When`/`Then` triplet;
  free-form or partially labeled criteria do not normalize into authority.
- Surviving IDs stay attached to their records; an un-ID'd new record receives the next
  monotonic ID; deleted IDs are not reused.
- A duplicate, malformed, or reassigned ID blocks with targeted guidance.
- Formatting is normalized by deterministic rendering, and that normalized spec plus exact
  passive-registry binding is staged with plan-input state so a crash cannot record a different
  planning input.

- Reference citations are not rendered into the business-only file.
- On reparse, the engine joins the persisted `SpecificationProvenanceState` only when the
  fixed/allocated record key and `BusinessContentIdentity` still equal the entry: ordered
  literal segment bytes plus self-contained passive `(ID, kind, bytes)` identities for
  normalized content, or exact token ID plus exact UTF-8 bytes for source-copy content.
- The containing state's exact registry validator must resolve every passive tuple, but adding
  an unrelated literal in a later registry revision does not change an existing record identity.
- Fixed singleton keys come from their protected structural slots; all repeatable records carry
  their rendered ID label.
- A changed or new record loses inherited provenance and must be re-attributed from the
  persisted `ReferenceSnapshot`, explicitly marked user-authored through a validated
  acknowledgement, or blocked when reference support is mandatory; the next
  passive-registry/provenance/acknowledgement revisions are committed with the normalized
  spec/plan input.
- If the spec is edited after downstream canonical state exists, the next gate invokes
  `CompareSpecificationIRAction` against the exact specification stored in canonical
  `PlanState`.
- A difference invalidates plan/task approvals and requires regeneration from `specified`; this
  is direct typed-state comparison, not fingerprinting.

- `reference-context.md`, `plan.md`, `research.md`, `data-model.md`, contract views,
  `quickstart.md`, and `tasks.md` are never parsed as authoritative execution input.
- The engine loads their canonical IR, renders the expected bytes, and checks the view for exact
  equality.
- A modified generated view produces `GENERATED_VIEW_MODIFIED`; the engine may regenerate the
  view from canonical state, but never imports the edit.
- Review feedback is submitted through the review API/CLI and targeted to IR units.

Golden tests ensure byte-stable output for the same canonical IR. Where supported, generated views may also be marked read-only at the filesystem level, but permissions are only a usability guard; canonical-state authority is the security/correctness boundary.

- Because plan and task Markdown are projections, copying only those files does not preserve
  executable workflow state.
- Portability uses an explicit export/import bundle containing schema-versioned canonical
  reference/plan/task state, approvals when policy permits, and their views; the bundle contains
  no hashes.
- A repository may version-control `<paths.workflows>/features/<featureId>/` under an explicit
  policy.
- CI or a clone without canonical state may validate/display `spec.md`, but cannot execute
  plan/tasks from Markdown alone.

### 23.2 Workflow reruns and protected clarification files

- When any workflow is run again, it MUST completely overwrite all its existing registered
  replaceable output files at the same engine-owned paths with the newly validated output.
- Clarification forms the user has resolved (closed) MUST NOT be overwritten.
- Clarification forms the user has not resolved MUST be completely overwritten from current
  validated clarification state at the same registered paths, retaining their stable subject
  IDs.
- This is the shared engine rule for every workflow execution, including unrelated registered
  workflows; no workflow may opt out.
- Existing output files must not cause an append, merge with old output, skip, filename suffix,
  output-exists failure, or separate overwrite approval.
- Specify therefore overwrites `spec.md` and `reference-context.md`, including prior user edits
  to `spec.md`; it does not delete and recreate the feature directory.
- Validation and predecessor/review gates still apply before commit; blocked or failed
  executions publish no new specification. A clarification pause (`needs_user`)
  publishes the validated incomplete projection authorized by
  [ADR 0017](../decisions/0017-incomplete-specification-publication.md), together with
  current reference context, forms/registry and pending state. It cannot publish
  incomplete content as a completed specification.

- Unresolved-form replacement includes the complete question/schema/revision projection and
  controlled editable regions; an unsubmitted draft answer is not protected from replacement.
- Prepare questions under [§12.7](12-model-boundary.md#127-workflow-defined-model-operations)
  through the existing question/reason fields. The renderer formats prepared context;
  it never classifies source support, policy conflicts or answer equivalence. Its
  controlled-region template remains shared with parsing and protected-history readback.
- An unchanged subject or question is not permission to retain the old form.
- Reusing a clarification means retaining its identity and canonical history, not preserving
  unresolved file bytes.
- Reconcile current inputs first, render all writable forms for the owning workflow's complete
  clarification view set, and completely replace them through the clarification persistence
  exception, including when the execution ends in `needs_user`.
- An authority-resolved or cancelled audit form remains writable under its existing lifecycle;
  only user-closed forms have byte-preservation protection.

- User-closed clarification files under `clarify/` are protected inputs/history, not replaceable
  outputs.
- A controlled user-close submission establishes file protection independently of answer
  acceptance or current applicability.
- Before rendering or writing, capture and validate the registered forms and consume applicable
  validated answers.
- Preserve each user-closed file byte-for-byte, including its question, status, answer, and
  original revision fields.
- Accepting a valid close records the response and canonical lifecycle without rewriting the
  submitted file; canonical answer normalization never changes those file bytes.
- Pending, stale, or invalid close submissions are not permission to regenerate the form:
  reject/block without overwriting them.
- Malformed or unrecognized clarification files also block rather than being removed during
  output replacement.

- Complete clarification view sets include retained user-closed forms; every unprotected member
  is rendered and completely overwritten on rerun.
- Validators distinguish a retained closed submission's original binding from the current
  registry revision and check it against its recorded accepted response, which is the sole
  durable owner of the exact bounded submitted form bytes and original binding.
- The view references that response; it introduces no second byte authority or fingerprint.
- A changed or missing protected file blocks; it is not silently recreated.
- Revalidate retained-file preconditions at commit so a concurrent user close cannot be
  overwritten.

- If a current required subject can no longer use its protected answer, preserve the file and
  response and block for explicit user direction.
- If the subject is no longer required, retain its user closure as history without reopening it.
- A rerun cannot automatically reopen it, replace its question, or allocate a duplicate ID to
  evade protection.
- Clarification refreshes retain their existing same-ID rules; they never make unresolved-form
  replacement optional.

- Replacement covers only the selected workflow's registered replaceable outputs.
- References, principles/configuration, application code, other workflows' outputs,
  selected-feature bindings, record identities, approvals, and immutable history retain their
  own authorization/lifecycle rules.
- Section 25 owns whole-workflow atomic output.
- Interrupted executions are abandoned, not recovered; the next invocation regenerates from the
  beginning and replaces the selected outputs.
- If publication itself fails or is interrupted, already-replaced files may remain under Section
  25.1; no new successful completion is recorded.
