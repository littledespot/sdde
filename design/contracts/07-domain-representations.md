# 7. Core domain representations

Part of the [proposed design](../design.md#7-core-domain-representations). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

Markdown is a presentation format, not the internal source of truth while a stage is running. The engine uses typed intermediate representations (IRs) and renders Markdown only after validation.

### 7.1 Shared types

[View the Shared domain types sample](../code.md#shared-domain-types).

#### Approved typed-content amendment — 25 September 2026

The user approved implementation of the shared typed-content recommendations. This
amends invariant 18 and the prose restrictions in §§11, 12, 16, 17, 22 and 23; it does
not change operational path authorization or the overall Proposed design status.

- Content separates ordinary prose, exact source values and explicit references.
  Prose is normalized inert text; punctuation alone establishes neither reference
  identity nor intent. Semantic grounding remains with existing review owners.
- Business values are ordered segments: prose strings, `passive` registry IDs and
  `exact_copy` token/citation pairs. Exact copies can appear within a sentence.
  The former whole-value exact-copy union is removed, without a dual reader.
- Exact selections resolve through the current source evidence and the field's
  fixed provenance. They carry no model-authored replacement bytes. Passive
  references retain filename/path/URI kinds and source occurrences in their
  existing registry. Source references keep their separate source identity.
- Source markup supplies structure, not semantic approval: inline code, fenced
  blocks and explicit link destinations retain source coordinates and raw values
  under registered extractors. Existing classification decides relevance. A code
  example is not an executable capability or automatic permission to publish code
  in a business specification.
- Renderers own formatting. Persisted selections and editable-view comparisons
  preserve exact bytes and reference bindings; formatting alone cannot mint them.
- Literal text never supplies a filesystem path, command, import or fetch to an
  adapter. Operational fields continue through existing IDs, scope, containment
  and operation authorization. This boundary applies across workflows, not by
  workflow name. Source scanning remains a discovery mechanism, not a prose gate.

- `PassiveLiteralRegistryState` is a feature-scoped immutable revision authority.
- The engine scans decoded mandatory-reference spans, reference manifest labels, and
  authenticated editable-spec additions, classifies candidates using the closed precedence
  `external_uri > display_path > display_filename`, and assigns monotonic IDs to unique `(kind,
  NFC bytes)` tuples.
- Model-derived brief/spec text is never a minting source.
- Existing ID/kind/value cores can never change; later revisions only append records/occurrences
  and retire failed allocations.
- Every occurrence resolves exact trusted bytes.
- Models receive only unit-allowlisted `{passiveLiteralId, kind, displayValue, nonOperational:
  true}` choices.
- There is deliberately no passive-to-operational conversion action.

`isOrganizer` does not reduce authority. It records that a file such as `README.md` helps describe the corpus; any requirements it contains remain peer authoritative with requirements in sibling files.

- `sourceId`, `blockId`, and claim IDs are stable within a persisted feature-scoped
  `ReferenceSnapshot`, including across process restarts.
- They are derived from normalized source position and snapshot-local ordinal, not content
  hashes, and are not stale-artifact fingerprints.
- A changed reference corpus creates a new snapshot identity and invalidates provenance that
  names the prior snapshot.

- State identities are engine identifiers, not content digests.
- Plan approval targets `planStateId`; task approval targets immutable `taskDefinitionStateId`.
- Execution changes only a monotonic `taskRuntimeRevision`, so completing one task does not
  invalidate approval of the unchanged task graph.
- These states are persisted beneath the reserved `<paths.workflows>/features/` child; their
  Markdown files are review views only.
- The specification remains authoritative as editable Markdown and is reparsed into
  `SpecificationIR` at the plan boundary.

### 7.2 Stage IRs

Execution-local information occurrences use the common envelope contract in
[§6](06-pipeline-nodes.md#execution-local-information-stack): native scope and
producer occurrence plus a registered typed key, retaining the canonical immutable
value and origin. These are neither persisted artifact IDs nor new domain authority.
Historical information cannot satisfy current authority by its presence alone.

#### Specification IR

The LLM returns `SpecificationContentProposal` semantic fields with no IDs or status. The engine assigns canonical record identifiers from the persisted `SpecificationIdLedger` and constructs `SpecificationIR`:

[View the Specification IR sample](../code.md#specification-ir).

The two singleton fields have fixed provenance keys `spec.display_name` and `spec.primary_user_story`; their engine-owned structural slots survive reparse without an allocated ordinal. Every repeatable editable/provenance-bearing record uses a monotonic prefix:

| Record kind | Prefix |
| --- | --- |
| Acceptance criterion | `AC` |
| User-visible outcome | `UO` |
| Edge case | `EC` |
| Functional requirement | `FR` |
| Business rule | `BR` |
| Assumption | `AS` |
| Non-goal | `NG` |
| Prohibited behavior | `PB` |
| Entity | `EN` |

- The renderer emits the ID as an engine-owned visible list/heading label in a fixed grammar,
  for example `**UO-001**`, and the parser requires/preserves it.
- `SpecificationIdLedger.nextOrdinalByKind` and tombstones cover every prefix; surviving IDs
  stay with normalized records across reorder, new unlabelled items receive the next ordinal,
  and removed IDs are never reused.
- The renderer also owns dates, headings, checklist state, and execution state.
- The model cannot forge a “passed” checklist.

- [F0100 §5](../features/F0100-SpecWorkflow.md#5-specmd-projection-contract) owns the approved
  heading hierarchy and clarification separation.
- Specification unknowns are `ClarificationNeedProposal` results routed to `clarify/SNN.md`,
  never specification records or an `Open Questions` section.
- Reference-context question signals remain separate.
- Fixed headings do not require invented records in optional collections, and structural
  validity does not prove semantic adequacy.

- The approved native content contract uses one closed `records` collection of typed record
  variants, not a parallel field list.
- `MUST`/`MUST NOT` are part of functional-requirement text, without a duplicate modality field.
- The entity decision is `required | not_applicable` with attributed supporting rationale; the
  shared gate must validate it before publication.
- The mechanical view codec captures only section presence/absence and never manufactures that
  authority.
- See [F0100 §5.6](../features/F0100-SpecWorkflow.md#56-native-content-and-view-contract).

#### Reference-context IR

[View the Reference-context IR sample](../code.md#reference-context-ir).

- Every `PreservedToken` contains a tagged `RawSourceScalar` and citation.
- That scalar points to the exact validated UTF-8 source bytes and bypasses ordinary text
  normalization.
- Structured readers can create tokens directly from CSS declarations and JSON/YAML/XML leaves.
- The LLM classifies relevance but cannot rewrite the value.
- This creates a deterministic propagation ledger for values that the current workflow says must
  never be lost.

#### Plan IR

[View the Plan IR sample](../code.md#plan-ir).

- Nested plan values are closed too: principle-consideration records, implementation units,
  data-model entities, contracts, quickstart steps, and coverage entries have explicit schemas.
- A contract body is admitted only under an exact registered closed schema whose string leaves
  are typed as identifiers, `BusinessText`, `SemanticText`, `FileReference`, or
  `SourceReference`; it is not arbitrary JSON.
- Repository fact selections return registry value IDs rather than model-authored copies of fact
  values.

`ArtifactDecision` is explicit:

[View the Artifact decision sample](../code.md#artifact-decision).

#### Task IR

The model does not assign task IDs, checkbox syntax, or `[P]` markers:

[View the Task IR sample](../code.md#task-ir).

After graph validation, the engine topologically assigns `T001...`, calculates safe parallel markers, and renders checkboxes. A task may be semantically atomic while changing multiple tightly coupled files, but every file, shared resource, command, manual scenario, and completion-evidence predicate must be declared.

#### Implementation IR

[View the Implementation IR sample](../code.md#implementation-ir).

- `CreateFile` requires an absent destination.
- `ReplaceFile` requires an explicit whole-file capability and a present regular-file
  destination, then replaces its complete contents.
- `CopyFile` performs a byte-exact copy from an engine-resolved, immutable-revision
  `CopySource`; it never accepts a raw source path, and source/destination cannot be the same
  file.
- Target state and revisions are derived and bound by the engine, never asserted by the model.
- If copied code needs adaptation, the copy completes first in the operation savepoint and a
  separately authorized `UpdateFile` or `ReplaceFile` operation performs the adaptation.
- Deletion is disabled by default and requires both task authorization and engine policy.
- The model never returns a raw shell command.

---

### 7.3 Canonical state and model-request identity

- The explicitly selected, validated feature directory identifies every feature-scoped
  authority.
- `featureId` in shared contracts is its lossless `paths.specs`-relative directory key, not a
  generated slug or separate ownership record.
- The only project-level identity exception is the self-validating `BootstrapRootRegistry`
  tuple.
- Validate state and approvals against the selected directory before reuse; file existence alone
  proves no authority.
- Owner-local record identities remain scoped to their governing principle, preset, reference,
  specification, clarification, plan or task contracts.
- There is no feature-identity registry, project state-ID ledger, or project-wide ownership
  inventory.

- State identity remains engine-owned and revision-validated.
- Allocation and candidate ledger changes belong to the current workflow execution; accepted
  state and its identity metadata are published with the complete workflow output.
- No durable reservation/retirement transaction or checkpoint is required before a model or
  command call.
- Clarification identity follows its separate preservation contract.
- Models never assign state IDs.

- Logical model requests follow [ADR 0012](../decisions/0012-workflow-owned-model-request.md): one
  process-local execution identity, originating compiled YAML step and request ordinal identify
  a generic request without inventing SDD ownership.
- `BuildInitialModelRequestIdentityLedgerAction` creates the fresh epoch and sole run-local
  ledger.
- `AssignModelRequestIdAction` returns the next ordinal and immutable successor.
- The originating step selects slot, controls and resources once; separate validation,
  preparation and consumer steps retain the exact request association through typed pipeline
  data rather than rebinding to their own step.
- `BuildImmutableUnitOwnerIdAction` still validates the required canonical SDD owner tuple for
  SDD-specific work; generic ownership grants no repair, semantic-review or clarification
  authority.
- Protocol-format retries retain the same logical request ID and advance its attempt count only
  through that retry operation instance's explicit limit.
- A new repair, semantic review, clarification resolution, or context follow-up receives a
  distinct purpose-bound request ID.
- It cannot reset either an operation instance's local retry counter or the workflow execution's
  total-token ledger.
