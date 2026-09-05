# F0100 — SpecWorkflow

**Status:** Proposed feature design

**Implementation readiness:** The generic concise YAML, declared-resource,
compiler, registry, and transition-runner boundaries are implemented by F0005
and ADR 0005. The logical Specify flow, `spec.md` section hierarchy, and
clarification separation are defined below. Invocation and read-only selector
preflight are implemented in Section 3.1; generation, activation, persistence,
and the complete executable definition remain unfinished.

**Transport:** `spec.workflow.yaml` uses F0005's generic YAML 1.2
workflow-definition boundary; F0100 adds no reader or Specify-specific media
rule.

**Classification:** Initial SDD workflow definition

**Scope:** SDDE engine development. This feature defines declarative topology
and the business-facing `spec.md` projection. It defines no executable code or
model capability.

**Governing authority:** [Engine design](../design.md), especially Sections 1,
3-7, 12-14, 17, and 21-25; accepted [ADR
0003](../decisions/0003-generic-workflow-engine.md); accepted [ADR 0005 —
workflow-defined operations](../decisions/0005-workflow-defined-operations.md);
and the closed
workflow-definition field and graph shape in [F0005](F0005-WorkflowDefinitionRegistryService.md).
F0005 owns YAML discovery, decoding, schema validation, and compilation.

---

## 1. Responsibility

`spec.workflow.yaml` is one ordinary definition beneath `paths.workflows`. It
declares the `specify` workflow's identity and graph topology using registered
`PipelineNode` contracts. The generic workflow engine selects it by validated
content-derived `WorkflowId` and follows its compiled typed transitions through
runner-owned bindings; it contains no `specify` name branch.

YAML-selected registered operations in the selected graph build and validate `SpecificationIR`,
render and reparse `spec.md`, render `reference-context.md`, and commit the
complete artifact/state transaction. The generic workflow engine performs none
of that Specify-specific work. The YAML explicitly selects every operation,
model slot, prompt/schema resource, and outcome transition. It contains no raw
operational output path, command, adapter, capability, or executable payload.

## 2. Closed YAML shape

The root contains exactly:

| Field | Meaning |
| --- | --- |
| `schema` | Closed `workflow/v1` schema identity. |
| `id` | `specify`; identity comes from content, not the filename. |
| `version` | Positive workflow-definition version. |
| `shortcode` | Validated unique four-character logging shortcode. |
| `invoke` | Exact registered Specify invocation operation. |
| `policy` | Exact registered workflow policy profile. |
| `start` | Definition-local entry-step ID. |
| `resources` | Concise aliases for bounded workflow-owned prompts, schemas, and examples. |
| `steps` | Local step map selecting registered generic operations, native scalar parameters, and outcomes. |

Each step contains `use`, optional `with`, and `on`. `with` uses native YAML
scalars whose types and allowed values come from the selected operation
contract; it does not repeat tagged parameter wrappers. `on` explicitly maps
every declared outcome to another local step or a matching `end.*` terminal.

Each YAML transition uses one of `ok`, `needs-user`, `invalid`, `blocked`,
`failed`, or `cancelled`, and targets either another local step or the matching
`end.*` terminal. The compiler rejects missing or duplicate outcome
transitions, unbounded cycles, unreachable steps, invalid typed data flow, gate
weakening, and capability escalation. A retry or repair cycle is accepted only
when it crosses a registered monotonic budget operation with a finite ceiling.

## 3. Structural outline

The remaining placeholders are deliberate: generation and completion contracts
are not yet fixed. The implemented invocation contract is explicit.

```yaml
schema: workflow/v1
id: specify
version: <positive-u32>
shortcode: "<validated-unique-four-character-shortcode>"
invoke: specify-invocation@1
policy: "<registered-ref@version>"
start: generate

resources:
  spec-prompt: "<workflow-resource>"
  spec-result: "<workflow-resource>"

steps:
  generate:
    use: model.generate@1
    with:
      slot: spec-generation
      prompt: spec-prompt
      result-schema: spec-result
    on: { ok: validate, invalid: repair, failed: end.failed, cancelled: end.cancelled }
```

This is a shape outline, not an executable fixture. A concrete definition is
valid only after every placeholder is replaced by a registered or captured
workflow-owned value and every selected operation outcome has exactly one
mapping. `validate` and `repair` are illustrative local steps and must also be
declared in a complete definition.

### 3.1 Registered invocation and read-only identity preflight

These native contracts use the existing runner, owned value envelope, and
registry. Any workflow may select them. Only identity derivation takes a YAML
parameter: the required `max-length` integer described below.

| Contract | Kind | Input → output |
| --- | --- | --- |
| `specify-invocation@1` | Invocation | Remaining arguments → validated `specify_invocation` |
| `parse-specify-invocation@1` | Invocation | Remaining arguments → `parsed_specify_invocation` |
| `validate-specify-arguments@1` | Step | Parsed invocation → validated invocation |
| `normalize-reference-selector@1` | Step | Validated invocation → `normalized_reference_selector` |
| `validate-reference-selector@1` | Step | Normalized candidate → `relative_reference_selector` |
| `inspect-reference-directory@1` | Step | Relative selector → read-only `reference_directory` observation |
| `derive-feature-identity@1` | Step | Relative selector + `max-length` → `feature_identity_seed` |

`specify-invocation@1` atomically coordinates the same parser and validator
through runner-owned child bindings; only its validated result leaves that
boundary. Invocation accepts exactly `--reference <non-empty-value>`; removed,
unknown, duplicate, positional, missing, and `--` forms fail. Invocation success
is `ok`; rejection uses the existing operation-failure boundary. Steps declare
`ok` and `failed`; runner cancellation remains `cancelled`.

Selector policy `reference-selector/v1` bounds raw and normalized UTF-8 to
4,096 bytes and each normalized segment to 255 bytes. The shared
[ADR 0007](../decisions/0007-unicode-normalization.md) adapter performs NFC.
Normalization maps literal backslashes to `/` and removes only literal `.`
segments. Validation rejects empty/dot-only, absolute/drive/UNC/URI, traversal,
encoded dot/separator, controls/NUL, empty segments, trailing separators, and
portable-invalid segment names. Unicode remains supported; configured-root
ASCII policy is unchanged. Bounds are engine contracts, not YAML overrides.

Only directory inspection carries `reference-read`; the other operations are
capability-free. `core.reference-read@1` permits that read capability and
`ok`/`failed`/`cancelled` terminals; it authorizes no provider or write.
The inspector rechecks the bound configured-root identity and opens each
descendant component without following symlinks. It requires a readable
directory and publishes repository-relative metadata and physical identities,
not a reusable filesystem capability. Future readers must revalidate them.

Identity derivation follows [ADR 0008](../decisions/0008-feature-naming-policy.md).
`with: { max-length: 64 }` is an explicit example, not a default; the closed
parameter accepts integers 1–255. The operation folds the full selector with
the pinned Unicode naming policy, constructs and truncates a portable ASCII
kebab-case ID, and rejects empty/invalid results. The seed retains the exact
selector, policy version, maximum length, and prospective ID; it is neither
an availability claim nor feature ownership. No reference prose or model title
participates. Identity derivation itself is capability-free and need not read
a directory; the full Specify preflight separately requires inspection.

The [preflight fixture](../../src/test_fixtures/reference-preflight.workflow.yaml)
proves these operations without claiming `specified`. It reads no reference
contents and creates no feature, log, clarification, transaction, or artifact.
Collision/ownership checks, recovery/activation, and complete corpus validation
remain later work; an identity seed alone cannot authorize them.

Feature activation uses validated fixed-path writes under Design Section 25.1.
There is no project-level transaction directory, WAL, ledger, or lock prerequisite.
Existing project-owner ledger code is superseded and requires removal, not
persistence implementation (F0050 Section 5.2). Feature-owned stage/task
transactions remain separate from activation.

Reruns MUST overwrite the selected workflow's known output files at the same
registered paths without separate overwrite approval. User-closed clarification
files remain byte-for-byte unchanged; reuse applicable validated answers and
recheck protection before writing (Design Section 23.2).

## 4. Required logical coverage

The compiled registered contracts collectively cover:

1. parse and validate only `sdd specify --reference <relative-selector>`;
2. perform deterministic feature, recovery, and reference preflight;
3. ingest and reconcile the complete supported reference corpus;
4. generate a reference-grounded feature brief and the typed units mapped in
   Section 5;
5. send missing, unsupported, ambiguous, or conflicting specification
   authority to an `SNN` clarification transaction without persisting a partial
   `SpecificationIR` or `spec.md`;
6. atomically repair only engine-authorized invalid candidate units, then rerun
   impacted and complete validation;
7. assign engine-owned record IDs and build and validate the complete
   `SpecificationIR`;
8. render the exact Section 5 hierarchy and `reference-context.md`, reparse
   `spec.md`, and compare normalized IR; and
9. atomically commit the complete artifact/state set before entering
   `specified`.

Exact grouping into definition-visible steps follows the registered operation
contracts; this feature does not invent their IDs.

## 5. `spec.md` projection contract

### 5.1 Ownership and hierarchy

`spec.md` is a business-facing renderer projection, never a model-authored
Markdown response. To preserve the existing fixed `displayName` field and a
valid heading tree, the renderer emits the display name as the document H1,
then these sections in exact order:

```markdown
# <display name>

## User Scenarios & Testing *(mandatory)*

### Primary User Story

### Acceptance Criteria

### User-Visible Outcomes

### Edge Cases

## Requirements *(mandatory)*

### Functional Requirements

### Business Rules

### Assumptions & Scope Boundaries

#### Assumptions

#### Explicit Non-Goals

#### Prohibited Behaviors

### Key Entities *(include if feature involves data)*
```

The angle-bracketed display-name token above documents the renderer slot; it is
not emitted literally. `User Scenarios & Testing` and `Requirements` are always
present. `Key Entities` is present only after a validated applicability decision
establishes that the feature involves business data.

### 5.2 Typed content mapping

| Section | `SpecificationIR` content | Purpose |
| --- | --- | --- |
| Document H1 | `displayName` | Reference-grounded human feature name. |
| Primary User Story | `primaryUserStory` | Main user journey in plain business language. |
| Acceptance Criteria | `acceptanceCriteria` / `AC-*` | Testable initial state, action, and expected outcome. |
| User-Visible Outcomes | `userVisibleOutcomes` / `UO-*` | Results, validation, confirmation, or terminal responses a user can directly observe. |
| Edge Cases | `edgeCases` / `EC-*` | Boundary/error condition and expected business response. |
| Functional Requirements | `functionalRequirements` / `FR-*` | Required system or user capability in business terms. |
| Business Rules | `businessRules` / `BR-*` | Constraint, validation rule, or policy controlling behavior. |
| Assumptions | `assumptions` / `AS-*` | Supported assumption that keeps the feature bounded. |
| Explicit Non-Goals | `nonGoals` / `NG-*` | Supported adjacent behavior deliberately outside scope. |
| Prohibited Behaviors | `prohibitedBehaviors` / `PB-*` | Behavior the feature must not perform. |
| Key Entities | validated applicability plus `entities` / `EN-*` | Business data concepts and relationships, without implementation detail. |

The engine assigns and preserves record IDs; the model supplies neither IDs nor
Markdown. The historical template's unnumbered example bullets do not permit
anonymous persisted records.

### 5.3 Acceptance-criterion rendering

The historical inline `Given`/`When`/`Then` example describes semantic fields.
The canonical engine-rendered form retains the governing uppercase triplet and
nests it under the restored section hierarchy:

```markdown
### Acceptance Criteria

**AC-001**
- **GIVEN** <nonempty business precondition>
- **WHEN** <nonempty business event or action>
- **THEN** <nonempty observable business outcome>
```

Every criterion contains exactly one nonempty value for each label in that
order. The renderer owns the heading, identity, labels, casing, order, and
Markdown structure.

### 5.4 Empty and conditional collections

The hierarchy does not authorize invented filler:

- `displayName`, `primaryUserStory`, and every contract-required record must be
  supported by current reference or resolved clarification authority;
- a repeatable collection with zero supported records renders its fixed heading
  with no bullet, placeholder, or synthetic `None` entry unless its registered
  requiredness policy requires content;
- if required content is absent, the workflow takes the clarification path in
  Section 5.5 rather than rendering an empty successful specification; and
- `Key Entities` is omitted only from a validated `not_applicable` decision. An
  empty `entities` collection alone cannot prove that the feature involves no
  business data.

The registered Specify contract must expose the closed Key Entities
applicability decision before implementation; its exact contract is not yet
defined.

### 5.5 Clarification is not specification content

`spec.md` never contains `[CLARIFICATION]`, `[CLAFIFICATION]`,
`[NEEDS CLARIFICATION: ...]`, `TBD`, unresolved template instructions, or an
inline clarification question. Every bracketed phrase in the historical
template is authoring metasyntax and is never emitted or accepted as authority.

When required specification knowledge is missing, ambiguous, unsupported, or
conflicting, the engine:

1. returns the typed `clarification_needed` operation outcome;
2. allocates or reuses the engine-owned `SNN` identity;
3. renders the controlled form only beneath `<featureDir>/clarify/SNN.md`;
4. atomically commits the clarification registry, form, required current
   authorities, and `spec_clarification_pending` workflow state;
5. returns terminal `needs_user` with no partial `SpecificationIR` or `spec.md`;
   and
6. after a current authenticated answer or authority resolution commits,
   regenerates every specification unit before validation and rendering.

On a Specify rerun, the engine MUST overwrite existing `spec.md` and
`reference-context.md` with the newly validated output at the same paths,
including prior edits to `spec.md`. It must not skip existing output, require
separate overwrite approval, or add a filename suffix. This uses the shared
rerun rule in Design Section 23.2; it never deletes the feature directory or
its clarification history.

The engine MUST NOT overwrite user-closed `clarify/SNN.md` files. Retain them
byte-for-byte and consume applicable validated answers before generation.
Accept a valid close into canonical state without rewriting its submitted form. A pending,
stale, or invalid close is not overwritten; an inapplicable protected answer
blocks for user direction rather than automatic reopening or a duplicate ID.
The complete clarification view set includes these retained files, not writes
to them. Transaction validation rechecks their preservation preconditions.

There is no committed `Open Questions` section in `spec.md`. Specification-owned
unknowns use the clarification lifecycle above; reference-context questions
remain in their separate sidecar authority. The proposed `OQ-*` specification
record shown elsewhere in the design must therefore be removed or narrowed
before implementation so render/reparse remains lossless.

### 5.6 Remaining renderer/parser decisions

The user-approved hierarchy and clarification boundary are fixed here. Before
implementation, the registered renderer/parser contract must additionally fix:

- synchronization of the proposed Design Sections 17.6 and 23 and the
  illustrative SpecificationIR renderer sample from the old standalone
  `## Acceptance Criteria` heading to Section 5.1's nested hierarchy;
- exact Markdown grammar for non-acceptance repeatable records;
- the closed Key Entities applicability value and its provenance;
- exact visible identity grammar for entity records while retaining `EN-*`;
- whether functional-requirement modality is renderer-owned or part of validated
  semantic text; and
- removal or narrowing of the proposed specification `openQuestions`/`OQ-*`
  field in accordance with Section 5.5.

These decisions cannot be inferred from historical placeholder text.

## 6. Diagrams

- [Specify workflow logical topology](../diagrams/10-spec-workflow.md) shows
  selection, typed generation, clarification, rendering, and commit.
- [`spec.md` projection structure](../diagrams/11-spec-document-structure.md)
  shows the fixed heading hierarchy and conditional entities section.
- [Reference ingestion and Specify completion](../diagrams/05-reference-ingestion.md)
  owns the detailed reference/generation transaction flow.
- [Clarification lifecycle](../diagrams/07-clarification-lifecycle.md) owns the
  durable `SNN` pause and later full regeneration path.

The diagrams are behavior and artifact views, not substitutes for the closed
YAML definition.

## 7. Acceptance criteria

1. `spec.workflow.yaml` is discovered, decoded, validated, compiled, selected,
   and executed through the same generic YAML workflow-definition path as every
   other definition, and has `id: specify`.
2. Every invocation, operation, parameter, resource, policy, outcome, gate, and capability
   reference resolves exactly through an engine registry.
3. The graph is fully reachable, terminal-reachable, data-compatible,
   outcome-complete, and policy-bounded; every cycle has a compiler-validated
   finite monotonic guard.
4. YAML explicitly selects model slots and bounded prompt/schema/example
   resources through compiled aliases. No YAML value selects a raw operational
   artifact path, command, implementation, adapter, capability, provider, model,
   or executable payload, and no packaged resource is substituted implicitly.
5. YAML-selected registered operations—not the generic workflow engine or a
   workflow-name branch—own Specify content, validation, rendering,
   transaction, and state work; no workflow operation is inaccessible from the
   definition.
6. A model returns typed candidate content only; the engine owns IDs, paths,
   headings, validation, rendering, repair scope, persistence, and completion.
7. `spec.md` renders the exact Section 5.1 hierarchy, with both mandatory parent
   sections and a policy-validated conditional Key Entities section.
8. `spec.md` contains no template placeholder, inline clarification marker, or
   unresolved specification question; all such needs use `clarify/SNN.md` and
   terminal `needs_user` with no partial specification.
9. `needs_user`, `invalid`, `blocked`, `failed`, and `cancelled` cannot be
   relabelled as `ok`.
10. Success requires a committed valid specification, complete reference
   accounting, valid `reference-context.md`, no open `SNN`, and workflow state
   `specified`.
11. Adding any other correctly configured workflow YAML composed only from
    registered generic operations requires no workflow-name branch, hidden
    operation, or engine rebuild.
12. A Specify rerun MUST overwrite its existing registered output files at the
    same paths under Design Section 23.2, without skipping, renaming, or separate
    overwrite approval. It MUST NOT overwrite user-closed clarification files;
    they remain byte-identical through generation, reference refresh,
    failed/cancelled runs, and commit; applicable validated
    answers are reused and no duplicate question bypasses that protection.

## 8. Verification

- closed YAML fixtures reject missing, unknown, duplicate, and wrong-kind
  fields and every prohibited operational value;
- compiler tests cover exact reference resolution, complete outcomes, graph
  closure, typed data flow, preserved gates, and capability limits;
- fake-model tests cover valid generation, `SNN` clarification, atomic repair
  and exhaustion, malformed output, and failure propagation;
- renderer/parser fixtures cover exact heading order, missing mandatory groups,
  zero-record collections without filler, data-required entities, validated
  non-data omission, and render/parse equality;
- negative fixtures reject every placeholder spelling, inline clarification,
  unresolved question, malformed/reordered record ID, and invalid acceptance
  triplet; and
- golden tests prove byte-stable `spec.md`, mandatory sidecar generation, and
  atomic commit before `specified`.
- rerun tests prove existing outputs are overwritten at the same paths without
  skipping, renaming, or separate overwrite approval, while preserving pending
  and accepted user-closed forms, including when another question is opened;
  stale/invalid submissions and changed answer applicability block without rewriting, and
  a user close concurrent with commit cannot be lost.

## 9. Traceability

| Concern | Authority |
| --- | --- |
| Generic declarative workflow execution | ADR 0003; Design Sections 5-6 and 14 |
| Closed definition and transition shape | F0005 Sections 3 and 7 |
| Specify behavior and success gate | Design Section 17 |
| Validation, repair, and no invention | Design Sections 21-22 |
| Engine-owned rendering and editability | Design Section 23; F0100 Section 5 |
| Clarification pause and full regeneration | Design Sections 17.4 and 24; diagram 07 |
| Atomic specification commit | Design Section 25; diagram 09 |
