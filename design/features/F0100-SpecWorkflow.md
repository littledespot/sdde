# F0100 — SpecWorkflow

**Status:** Proposed feature design

**Implementation readiness:** The generic concise YAML, declared-resource,
compiler, registry, and transition-runner boundaries are implemented by F0005
and ADR 0005. The logical Specify flow, `spec.md` section hierarchy, and
clarification separation are defined below. The explicit feature/reference
invocation, shared directory preflight, read-only clarification inputs, Markdown
ingestion, citable reference preparation, typed text, Markdown exact-value
preservation and scripted extraction accounting in Sections 3.1–3.8 are implemented.
Generated-name code is removed; semantic extraction/reconciliation, generation,
output publication and the complete definition remain unfinished.

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
complete atomic workflow output. The generic workflow engine performs none
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
invoke: specify-invocation
policy: "<registered-ref@version>"
start: generate

resources:
  spec-prompt: "<workflow-resource>"
  spec-result: "<workflow-resource>"

steps:
  generate:
    use: model.generate
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

### 3.1 Explicit feature directory and reference preflight

[ADR 0010](../decisions/0010-explicit-feature-directory.md) replaces generated
feature names and ownership registration with the exact supplied directory:

```text
sdd specify --feature <feature-directory> --reference <relative-selector>
```

The registered invocation requires `featureDirectory` and `referenceSelector`.
`--feature` and the API's `featureDirectory` are relative to `.sddtoolkit.json`'s
`paths.specs`, not the project root. For example, `--feature hello-world` writes
`<paths.specs>/hello-world/spec.md`. Do not repeat or hard-code the specs root;
resolve from configuration and exclude `paths.specsArchive`.

`--reference` independently selects the source directory beneath `paths.references`.
Missing, duplicate, empty, unknown and positional inputs fail. Unrelated workflows
keep their own registered invocation contracts; the generic engine has no Specify
argument branch.

Use shared path normalization, containment, portability and no-follow validation
for the target. Resolve its registered artifact paths directly and validate only
the existing state needed by the selected workflow. The same directory is the
same feature, including when reference input changes. No slug, `max-length`,
identity seed, owner registry, active/archive ownership scan, or registration
write is required. An existing directory is not a collision requiring approval.

The existing reusable reference operations remain:

| Contract | Input → output |
| --- | --- |
| `normalize-reference-selector` | Validated reference input → normalized candidate |
| `validate-reference-selector` | Normalized candidate → relative selector |
| `inspect-reference-directory` | Relative selector → read-only directory observation |

The shared ADR 0007 adapter owns NFC. Reference policy retains its 4,096-byte
raw/normalized limit, 255-byte segment limit, separator/dot normalization, and
rejection of traversal, absolute paths, encoded separators, controls and invalid
portable names. Inspection alone carries `reference-read`; it rechecks root
identity, follows no symlinks, requires a readable directory, and grants no write
capability. Reference inspection does not read or reconcile the corpus.

**Implemented preflight:** `specify-invocation` requires both inputs.
`normalize-feature-directory`, `validate-feature-directory` and
`inspect-feature-directory` reuse shared path policy and the runner/value
envelope. Inspection carries only `feature-read`; `core.directory-read@1`
permits feature/reference inspection. The fixture selects these steps through
ordinary YAML, accepts absent targets without creation, and rejects archive
targets, aliases and symlinks. Generated-name code and parameters are removed.
The next read-only input steps are implemented below; generation and output
replacement remain unimplemented.

Specify follows [ADR 0009](../decisions/0009-atomic-workflow-execution.md): each
execution starts at `start`; no transaction/checkpoint/recovery prerequisite.
Successful reruns overwrite the selected workflow's known outputs at the same
paths without separate approval. User-closed clarification files remain
byte-for-byte unchanged, including stale/invalid submissions; reuse applicable
validated answers and recheck protection immediately before writing (§23.2).

### 3.2 Read-only artifact and clarification inputs

The shared artifact-path owner resolves the selected feature's `spec.md`,
`reference-context.md`, `clarify/` and log paths under `paths.specs`, plus
`state/workflow.json` and `state/clarifications.json` under
`<paths.workflows>/features/<feature-directory>/`. These are derived paths,
not configurable filenames, an ownership registry or write permission.

Five registered operations compose through ordinary YAML:
`resolve-feature-artifact-paths`, `capture-clarification-inputs`,
`parse-clarification-state`, `validate-clarification-state` and
`validate-clarification-forms`. Only capture carries `feature-input-read`;
`core.feature-input-read@1` explicitly permits that capability alongside
feature/reference inspection. Existing inspection-only profiles are unchanged.
The executable test definition is
[`feature-input-preflight.workflow.yaml`](../../src/test_fixtures/feature-input-preflight.workflow.yaml),
not the complete Specify workflow.

The single native persisted schema is
[`clarification_inputs.State`](../../src/domain/clarification_inputs.zig):
strict JSON tagged `clarification-state/v1`, bound to the selected feature,
with registry/record revisions, stage ID counters, stable subjects, authority
bindings, bounded answer schemas and recorded responses. A response owns its
original form bytes and revision binding. No second persisted byte copy or
compatibility reader exists. The
[canonical form renderer](../../src/domain/clarification_form.zig) owns all
Markdown except `requestedStatus` and the answer region.

Capture reads only this state file and the registered `SNN.md`, `PNN.md` and
`TNN.md` forms: at most 297 forms of 16 KiB each and 8 MiB of state.
It does not create directories or read generated views, unrelated features or
`workflow.json`. Missing state with no forms represents fresh inputs.
Orphan, malformed, unknown, stale, changed or missing protected forms fail
without modifying anything. Recorded closures use their original revision
binding and must match the response's exact saved bytes.

The result distinguishes new submissions from recorded responses and retains
closed bytes unchanged. Structural validation is not actor authentication or
current-authority/applicability validation. Response acceptance, source
reconciliation, clarification transitions/writes and publication-time
protection checks remain later work; no stage completion is inferred.

### 3.3 Read-only Markdown ingestion

Five registered operations cover the physical source boundary:
`inventory-reference-sources`, `validate-reference-inventory`,
`capture-reference-sources`, `decode-reference-markdown` and
`validate-reference-accounting`. They use the configured `paths.references`
root and independent selector. Every encountered entry, including hidden files,
directories and non-followed symlinks, is accounted; unsupported, unreadable,
changed, malformed or over-limit inputs fail without output writes.

The native `markdown_source_v1` reader retains lossless UTF-8 source ranges,
not a semantic Markdown AST. Inventory/capture/decoding enforce 1,024 entries,
depth 16, 1 MiB per source, 8 MiB source/decoded corpus budgets, 1,024 blocks per
file, 16 KiB blocks and 5-second phase checks. Blocks normally break at 64 lines;
they never split a Unicode scalar, CRLF or eligible exact-value span (§3.8).
A span may defer the line break but cannot exceed the byte ceiling. These are source-reader limits, not model
request-size estimates. Decoding never reopens captured source bodies.

Additional formats and the full multi-reader probe/rank registry remain future
work; this initial reader does not claim support for arbitrary reference bytes.

### 3.4 Citable reference inputs

Four registered operations extend that boundary:

| Operation | Contract |
| --- | --- |
| `assign-reference-identities` | Validated reference inputs and selected feature → identified corpus and total provisional-to-canonical mappings. |
| `build-reference-chunks` | Identified corpus → state-bound chunks; `source_blocks_v1` uses one chunk per existing source block. |
| `validate-reference-chunks` | Original inputs, feature, corpus and chunks → validated citable inputs; reject omissions, duplicates, changed bytes, wrong mappings or foreign state/feature bindings. |
| `validate-source-citations` | Citable inputs and engine-scoped typed proposals → validated source citations. |

The [reference identity owner](../../src/domain/reference_identity.zig) supplies
the same state/chunk types used by model-request owners. Each corpus receives a
fresh 128-bit system-random namespace, formatted as `reference-<hex>`; entropy
failure fails the operation. Only identity assignment has `reference-identity`,
explicitly allowed by `core.reference-ingestion@1`. There is no persisted ID
counter, reservation, hash or journal. Files keep normalized source order;
source, state-global block and chunk ordinals are deterministic within the state.
These values remain execution candidates until later complete publication.

Chunks reference captured source ranges instead of owning a second body.
Locations use zero-based byte offsets, one-based Unicode-scalar line/column
coordinates, exclusive ends and CRLF as one newline. The citation validator
checks the engine-supplied state/chunk scope, exact source/block joins and
nonempty in-chunk locations. Optional verbatim text must equal the entire cited
range byte-for-byte; validated text comes from the captured source, without NFC
normalization. This proves location/quotation integrity, not semantic support.
Models cannot choose the call scope or assign citation IDs.

[`reference-ingestion.workflow.yaml`](../../src/test_fixtures/reference-ingestion.workflow.yaml)
is an executable **test fixture**, ending at validated chunk preparation. Tests
also inject typed citation proposals to exercise the registered validator through
the native runner. Section 3.5 extends those tests with scripted extraction
results. No production proposal producer, model call, persistent snapshot,
clarification acceptance or `spec.md` publication is added.
The complete Specify YAML will compose these same operations, not invoke a
second required user workflow. Closed clarification files remain untouched.

### 3.5 Extraction-candidate accounting

These operations, together with §3.8's preservation operations, keep extraction
explicit in the selected YAML:

| Operation | Contract |
| --- | --- |
| `parse-reference-extraction-results` | Engine-scoped raw observations → closed parsed candidates. |
| `validate-reference-extraction-text` | Parsed candidates, current toolchain, citable inputs and source-backed literal registry → text-validated candidates (§3.7). |
| `validate-reference-claims` | Citable inputs and prepared model/preserved-token claims → structurally validated claims. Reuses the same citation validator as §3.4. |
| `assign-reference-claim-identities` | Validated candidates → state-local claim/citation ordinals; no model-selected IDs. |
| `build-reference-extraction-ledger` | Assigned identities → in-memory claims, citations and chunk outcomes; binds preserved tokens to their assigned citation IDs. |
| `validate-reference-extraction-accounting` | Citable inputs, preserved-token assignments and ledger → exact total chunk/claim/citation/token coverage, with explicit `ok` or `blocked`; malformed coverage fails. |

The current lossless-Markdown candidate body is exactly one JSON object:
`{kind: claims, claims: [...], token_classifications: [...]}` or
`{kind: no_feature_claim, reason: ReferenceSemanticText, token_classifications: [...]}`.
These are shape descriptions, not literal JSON examples. Each claim has only
`content: {kind, text}` and a nonempty `citations` collection using §3.4's typed
proposal shape. Content kinds are `business`, `design`, `technical`,
`validation`, `implementation_assumption`, `open_question` and `scope_guard`.
`business` and `scope_guard` use `BusinessText`; other kinds use
`ReferenceSemanticText`. Text validation establishes syntax and permitted
references, **not accepted meaning or requirements**. Unknown/duplicate fields,
unsupported kinds, forged IDs, missing fields and legacy raw strings are
rejected. Each supplied exact-value candidate needs one classification (§3.8).

State/chunk scope and `blocked: extraction_failed` are engine observations,
never model body fields. Every supplied chunk needs exactly one claims,
positive `no_feature_claim`, or engine-blocked result. Positive empty requires
no model or preserved-token claims; `claims: []` is valid only when preservation
produces at least one deterministic claim. Missing/duplicate/foreign
chunks fail; any blocked chunk makes total accounting blocked, even when other
chunks contain claims. `source_blocks_v1` has one chunk per block, so exact chunk
coverage also proves block coverage. Claim/citation IDs start at one in each
fresh reference state and follow chunk/claim/citation order; response arrival
order cannot change them. No ID counters or ledgers are persisted.

This is not the complete `result.reference-claims/v1` production contract:
semantic support, business-boundary review, reconciliation and publication
are still required before these candidates can become reference authority.
Markdown inline-code candidates are implemented; other format extractors remain
future work. There is no live
model producer or hidden prompt/schema resource. Native values own their data
and retain only execution-local predecessors; they impose no model-call byte
ceiling. The test-only YAML path runs these operations with scripted results
and does not write artifacts, accept clarifications or mark a stage complete.

### 3.6 Shared naming-policy and path-token grammar

The shared `BusinessText` / `ReferenceSemanticText` and passive-literal
contracts follow Design §7.1. Their
inline-literal validator must use §11's `SupersetPathTokenGrammar`, compiled
from all resolved environment naming/extension rules, reserved/manifest names
and current reference basenames. A unit allowlist cannot narrow that detector.

The initial native boundary is implemented through three pure registered
operations:

| Operation | Required inputs → output |
| --- | --- |
| `compile-naming-policy` | `valid_toolchain` → `compiled_naming_policy` |
| `build-superset-path-token-grammar` | Compiled naming policy, current toolchain and citable reference inputs → `path_token_grammar` |
| `scan-path-tokens` | Grammar, current toolchain, citable inputs and required `text` data-resource parameter → `path_token_scan` |

[F0003 §3.5](F0003-ToolChainService.md#35-registered-lexical-naming-rules) owns
the registered rule contract. Grammar construction includes every selected rule
and captured reference basename, with exact toolchain, feature and reference
bindings; omitted, altered or stale inputs fail. The shared lexer detects
path/drive/UNC/URI forms, encoded separators/dots and policy/reference filename
tokens. Unicode punctuation separates lexemes while path/URI punctuation stays
internal. Matches retain end-exclusive byte spans into the owned original text;
NFC/case folding never changes those offsets. No unit allowlist narrows scanning.
Exact registered/reference names containing spaces or punctuation are also
detected in full; directory tokens ending in a separator remain path-shaped.

`ok` means scanning succeeded, **not** that matched text is valid or any path is
authorized. The YAML registry remains generic. `core.reference-ingestion@1`
permits the existing toolchain read/parser operations so selected YAML can
compose these prerequisites; unused operations perform no reads. Tests compose
the existing toolchain and ingestion fixtures, without a required extra user
workflow, model calls or artifact writes.

This is the native registered-rule lexical slice, not the full proposed
environment/repository-bound grammar: RE2 rules and repository discovery remain
unimplemented. Source examples cannot supply missing runtime authority.
Scanning alone does not validate text or permit specification publication;
§3.7 owns the implemented text gate.

### 3.7 Typed reference text and source-backed display literals

Three pure YAML operations prepare the execution-local literal registry:

| Operation | Required inputs → output |
| --- | --- |
| `scan-reference-passive-literals` | Current grammar/toolchain and citable inputs → ordered source-name/block-span candidates |
| `assign-passive-literal-identities` | Candidates → source-ordered IDs, deduplicated by `(kind, NFC bytes)` |
| `validate-reference-passive-literals` | Assigned candidates and current inputs → `reference_passive_literals` |

Validation reuses the shared detector to prove complete exact origins, values
and allocations. Models and workflow data resources cannot register literals.
The initial registry is an immutable in-memory reference candidate, not a
persisted `PassiveLiteralRegistryState`; authenticated edits/answers and
append-only persisted revisions remain outside this read-only increment.

The native JSON text shapes are closed:

```json
{"segments":[{"literal":{"value":"Display "}},{"passive":{"passive_literal_id":{"ordinal":1}}}]}
```

`BusinessText` uses `segments` and permits only `literal` and `passive`.
`ReferenceSemanticText` uses `nodes` and additionally permits
`{"source":{"source_id":{"ordinal":1}}}`. Neither permits a project-file
node. A passive node contains only its ID, never model-provided display bytes.

`validate-reference-extraction-text` normalizes literal runs to NFC and rejects
empty/control-invalid text and inline path/filename/URI matches. Adjacent literal
segments are joined before scanning so splitting a token cannot bypass it.
Passive IDs require an occurrence inside the exact chunk, or that chunk's source
manifest name; source IDs must identify that same source. Unknown, stale and
cross-unit references fail. Claim text and no-feature-claim reasons share this
gate. Citation validation and total accounting remain separate responsibilities.

The raw-string format is removed, with no dual reader. No file/network grant,
model call, output write, clarification modification or completion transition is
introduced. Semantic review, reconciliation and publication remain required.

### 3.8 Exact-value preservation

Design §16.3's approved `markdown_inline_code_v1` descriptor makes parsed
Markdown inline-code spans eligible. Prose, quotation-marked text and fenced
code blocks do not qualify through this extractor. Equal-length backtick runs
identify the exact interior source bytes; escaped/unmatched delimiters do not
create invented spans. Code-block/HTML regions are not inline code. Candidate
values keep source whitespace, line endings and Unicode scalar sequences,
without Markdown-rendering transformations or NFC normalization. The source
reader and fact extractor share this parser; reader boundaries do not split a
value, and an over-limit value fails explicitly.

| Operation | Contract |
| --- | --- |
| `extract-structured-reference-facts` | Current captured sources → source-ordered, citation-validated exact facts from registered extractors. |
| `assign-structured-token-candidate-identities` | Current sources and verified complete facts → transient `(source_id, extractor_id, ordinal)` candidates. Ordinals are source/extractor-local. |
| `validate-preserved-token-classifications` | Current candidates and text-validated responses → exactly one current chunk-local `preserve` or `irrelevant` decision per candidate. Engine-blocked chunks retain blocked candidate dispositions. |
| `assign-preserved-token-identities` | Validated decisions → state-local token ordinals in source order; irrelevant/blocked candidates allocate none. |
| `build-preserved-token-claims` | Token assignments → prepared deterministic claims alongside unchanged model claims, before common citation validation, claim-ID assignment and ledger construction. |

The closed model classifications are:

```json
{"token_candidate_id":{"source_id":{"ordinal":1},"extractor_id":"markdown_inline_code_v1","ordinal":1},"decision":"preserve","kind":"business_exact_string"}
```

or the same candidate ID with `"decision":"irrelevant"` and **no `kind`
field**. The model never supplies scalar bytes, citations, canonical token IDs
or obligation IDs. Unknown, duplicate, omitted, stale and cross-chunk candidates
fail. An empty classification collection is valid only for a response whose
chunk has no candidates. `no_feature_claim` may classify candidates irrelevant,
but cannot preserve any.

Each preserved value produces one claim through the ordinary claim/citation
pipeline. The final ledger binds its exact scalar to its citation ID and derives
the downstream obligation identity from the token identity. Final accounting
checks one-to-one preservation and unchanged bytes, kind, source, citation and
obligation joins. Eligibility and relevance are not semantic proof, and token
values grant no file, path, command or network authority. Everything remains
execution-local: no registry persistence, artifact publication or clarification
write is added.

## 4. Required logical coverage

The compiled registered contracts collectively cover:

1. validate the explicit feature directory and independent reference selector under Section 3.1;
2. validate the selected directory, required existing state and reference corpus without an ownership registry or cross-feature scan;
3. ingest and reconcile the complete supported reference corpus;
4. generate a reference-grounded feature brief and the typed units mapped in
   Section 5;
5. send missing, unsupported, ambiguous, or conflicting specification
   authority to the persistent `SNN` clarification registry without publishing a partial
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
12. The supplied directory identifies the feature; reference changes do not select
    another directory or require an ownership lookup. A Specify rerun MUST overwrite its existing registered output files at the
    same paths under Design Section 23.2, without skipping, renaming, or separate
    overwrite approval. It MUST NOT overwrite user-closed clarification files;
    they remain byte-identical through generation, reference refresh,
    failed/cancelled runs, and commit; applicable validated
    answers are reused and no duplicate question bypasses that protection.

## 8. Verification

- `zig build test-structured-tokens` covers inline-code eligibility, exact
  Unicode/whitespace, multiline and size-boundary citations, closed and total
  classifications, source/identity forgery, preserved-claim conservation and
  allocation failures. `zig build verify` also proves the generic YAML gates,
  protected closed-clarification bytes, and clean packaged candidate extraction;
- `zig build test-reference-ingestion test-reference-evidence test-reference-extraction` covers source
  accounting, deterministic identity mappings, complete chunks, Unicode/CRLF,
  exact quotations, foreign scopes, closed extraction bodies, engine IDs,
  total chunk/claim/citation joins, blocked results and allocation/ownership
  failures. `zig build verify` additionally covers native YAML dependencies,
  rejection before continuation, cancellation and the packaged read-only
  ingestion path;
- `zig build test-path-tokens` covers closed naming rules, selected-policy
  coverage, NFC/case folding, original-byte spans, stale bindings, ownership
  and allocation failures. `zig build verify` also exercises these operations
  through renamed YAML and the packaged executable, without artifact writes;
- `zig build test-typed-text test-reference-extraction` covers exact passive
  origins, deduplication, stale/cross-chunk IDs, closed node shapes, legacy-string
  rejection, split-token bypasses and allocation cleanup. Native YAML tests
  prove the text gate cannot be skipped and preserve closed clarification bytes
  on accepted and rejected candidates;
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
