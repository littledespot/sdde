# F0100 — SpecWorkflow

**Status:** Proposed feature design

**Implementation readiness:** The generic concise YAML, declared-resource,
compiler, registry, and transition-runner boundaries are implemented by F0005
and ADR 0005. The logical Specify flow, `spec.md` section hierarchy, and
clarification separation are defined below. The explicit feature/reference
invocation, shared directory preflight, read-only clarification inputs, Markdown
ingestion, citable reference preparation, typed text, Markdown exact-value
preservation, scripted extraction accounting and reconciliation in Sections
3.1–3.9 are implemented. Model-connected extraction/reconciliation (§3.11) and
in-memory specification generation/validation/repair (§5.7) are implemented
through ordinary YAML. Generation needs now refresh and publish controlled
clarification forms (§3.12); validated specification content renders, reparses
and publishes alongside its reference sidecar and canonical state. Answer
application, feature-log integration and remaining clarification routes are
unfinished. Generated-name code is removed.
The native content schema and mechanical specification Markdown codec in §5.6
are implemented. The shared required-authority boundary and Specify projection
in §3.10 are connected to model-assisted generation and publication evidence.

**E2E evaluation:** The [development harness](../harness/e2e.md) invokes the
configured production LLM and grades the exact published specification through
a separate live rubric evaluator. Generation/publication evidence and semantic
scores remain separate; neither offline integration tests nor supplied-spec
grading establish a successful live workflow.

**Transport:** `spec.workflow.yaml` uses F0005's generic YAML 1.2
workflow-definition boundary; F0100 adds no reader or Specify-specific media
rule.

**Input optimization:** [ADR 0013](../decisions/0013-workflow-input-reuse.md) is
implemented. `spec.workflow.yaml` declares local request/retirement subgraphs;
the compiler expands their operations through the existing validators.
Schemas share local definitions and select the current generation unit,
reconciliation purpose or authorized repair shape. Model inputs share citation
records and preserve their complete supplied evidence. The
[file guide and measurements](../TODO001.md) describe the twelve-file bundle.

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
render and reparse `spec.md`, render `reference-context.md`, and publish the
complete validated workflow output under Design §25. The generic workflow engine performs none
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

This is a structural outline of the eventual complete workflow, not an
executable definition. The implemented generation-only definition is linked in
§3.11; §3.12 adds clarification persistence, not successful Specify completion.

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
Input, generation and clarification replacement steps are implemented below;
complete specification output remains H-012.

Specify follows [ADR 0009](../decisions/0009-atomic-workflow-execution.md): each
execution starts at `start`; no transaction/checkpoint/recovery prerequisite.
Successful reruns completely overwrite the selected workflow's registered
replaceable outputs at the same paths without separate approval. Unresolved
clarification forms are completely overwritten on their publication branch at
the same IDs/paths under the shared rule for every workflow. User-closed files
remain byte-for-byte unchanged, including stale/invalid submissions; reuse applicable
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
strict JSON tagged `clarification-state/v2`, bound to the selected feature,
with registry/record revisions, stage ID counters, stable subjects, authority
bindings, bounded answer schemas and recorded responses. Reference authority
uses the real reference state identity; other authorities use the shared
canonical kind/ordinal/revision contract. A response owns its
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
current-authority/applicability validation. Response acceptance and applicability
remain open. §3.12 implements refresh, rendering and write-time protection;
no stage completion is inferred.

H-011 also requires selection and implementation of the trusted authentication
mechanism for accepting submitted answers. Merely editing a form or loading an
actor/evidence ID is not authentication. This does not affect user-close file
protection, which applies even when acceptance is blocked.

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
| `validate-reference-claims` | Citable inputs and prepared claims → validated canonical citations or typed `invalid` selection diagnostics. Exact-token citations retain §3.4 validation. |
| `assign-reference-claim-identities` | Validated candidates → state-local claim/citation ordinals; no model-selected IDs. |
| `build-reference-extraction-ledger` | Assigned identities → in-memory claims, citations and chunk outcomes; binds preserved tokens to their assigned citation IDs. |
| `validate-reference-extraction-accounting` | Citable inputs, preserved-token assignments and ledger → exact total chunk/claim/citation/token coverage, with explicit `ok` or `blocked`; malformed coverage fails. |

The current lossless-Markdown candidate body is exactly one JSON object:
`{kind: claims, claims: [...], token_classifications: [...]}` or
`{kind: no_feature_claim, reason: ReferenceSemanticText, token_classifications: [...]}`.
These are shape descriptions, not literal JSON examples. Each claim has only
typed `content` and a `citations` collection of inclusive `{first, last}`
source-line IDs supplied in the request. Missing citations are a typed repairable
rejection. The engine reconstructs exact bytes and coordinates; no quotation or
coordinate echo is accepted. Content kinds are `business`, `design`, `technical`,
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

These candidates require the later reconciliation and required-authority gates;
the extraction validator alone does not establish semantic support.
Markdown inline-code candidates are implemented; other format extractors remain
future work. Model/resource/gate integration is described in §3.11. Native values own their data
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
introduced. Semantic review, live reconciliation and publication remain required.

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
| `validate-reference-selections` | Current candidates and text-validated responses → complete chunk-local token classifications and valid scoped citation selections, or typed rejection. Engine-blocked chunks retain blocked candidate dispositions. |
| `assign-preserved-token-identities` | Validated decisions → state-local token ordinals in source order; irrelevant/blocked candidates allocate none. |
| `build-preserved-token-claims` | Token assignments → prepared deterministic claims alongside unchanged model claims, before common citation validation, claim-ID assignment and ledger construction. |

The closed model classifications are:

```json
{"kind":"preserve","preserve":{"token_candidate_id":{"source_id":{"ordinal":1},"extractor_id":"markdown_inline_code_v1","ordinal":1},"kind":"business_exact_string"}}
```

or `{"kind":"irrelevant","source_id":{"ordinal":1},"extractor_id":"markdown_inline_code_v1","ordinal":1}`.
The discriminator follows ADR 0006; the preserved token's classification remains
a separate domain field. The model never supplies scalar bytes, citations, canonical token IDs
or obligation IDs. Unknown, duplicate, omitted, stale and cross-chunk candidates
fail. An empty classification collection is valid only for a response whose
chunk has no candidates. `no_feature_claim` may classify candidates irrelevant,
but cannot preserve any.

Compiled graphs retain a fixed 512-step capacity, including expanded subgraph
instances; the Specify definition uses 264 steps with both repair paths. This
capacity is independent of operation retry limits and the workflow token budget.

The reference-ingestion policy permits a distinct `invalid` terminal outcome.
The validator publishes `invalid` with the chunk scope, candidate revision,
`token_classifications` field and all missing, duplicate, unknown or forbidden
candidate IDs. Invalid source authority remains a failure. A repair authorization
selects that chunk's classification collection, one invalid citation selection,
or an empty claim-citation collection. The model cannot change claim meaning,
source bytes, other selections/chunks or the target. The selected replacement schema reuses the corresponding generation definition:
`classification_replacement`, `source_selection_replacement`, or
`citation_replacement`. Citation requests also include the unchanged claim. After compare-and-swap
merge, the shared reference-selection validation runs again before token and
claim construction and full ledger checks. The text-validated candidate and
selection result use captured retention,
like specification repair: descendants retain candidate evidence while current
source/policy generations remain in their authority lineage. Retiring an old
repair slot cannot invalidate its retained evidence, and changing source authority
still blocks later gates. This is an in-memory candidate repair, not a source correction.

Each preserved value produces one claim through the ordinary claim/citation
pipeline. The final ledger binds its exact scalar to its citation ID and derives
the downstream obligation identity from the token identity. Final accounting
checks one-to-one preservation and unchanged bytes, kind, source, citation and
obligation joins. Eligibility and relevance are not semantic proof, and token
values grant no file, path, command or network authority. Everything remains
execution-local: no registry persistence, artifact publication or clarification
write is added.

### 3.9 Reference-reconciliation boundary

Design §16.4's approved input contract retains existing typed claims, canonical
citations, source/block/chunk identities and preserved-token references. It adds
no inferred modality or subject/object IDs. The selected reference directory is
the complete related-document set; filenames confer no precedence.

The explicit YAML parameter `group-size` is an integer of at least two. The
engine partitions claims within each source in source/claim order, groups those
summaries across sources, then recursively groups global summaries until one
global partition remains. The bound counts immediate members, not request bytes
or tokens. Every partition keeps its complete original-claim map and provenance;
its input includes unchanged original payloads and accepted child summaries.
An empty accounted claim set has one empty global partition. Blocked extraction
cannot enter reconciliation.

All operations are pure and individually registered in the generic YAML registry:

| Responsibility | Operations |
| --- | --- |
| Inputs and grouping | `build-reference-reconciliation-items`, `partition-reference-reconciliation-items` (`with: { group-size: 16 }`), `assign-reference-reconciliation-partitions`, `validate-reference-reconciliation-partitions` |
| Each partition | `build-reference-reconciliation-input`, `parse-reference-reconciliation-result` |
| Non-final summaries | `validate-reference-reconciliation-summary`, `assign-reference-summary-identities`, `build-reference-reconciliation-summary` |
| Global proposal | `validate-reference-claim-dispositions`, `validate-reference-signal-proposals`, `validate-reference-conflict-proposals` |
| Identified result | `assign-reference-reconciliation-identities`, `build-reference-reconciliation-records`, `validate-reference-reconciliation-completeness` |

The closed native response is either `{"summary": {...}}` or
`{"global": {...}}`; the engine binds the response to its current partition.
A summary contains `member_claim_ids`, `member_summary_ids` and `statements`
with positive unique `local_key`, `claim_ids` and typed `content`. Membership
must match exactly, and statements represent every member claim exactly once.
Summary IDs are allocated only after validation; partition planning contains
local group links, not future canonical summary IDs. Statement IDs follow sorted
local keys. Accepted summaries retain their lineage
in immutable execution-local history; advancing clears the consumed candidate
keys rather than retaining stale parallel candidates.

A global proposal contains `claim_dispositions`, `signals` and `conflicts`:

- Exactly one disposition per original claim: `retained` has no related IDs;
  `duplicate` has one; `superseded` and `conflicting` have one or more.
  Related IDs must be current, unique and non-self. Duplicate/supersession
  edges are acyclic and terminate at retained claims; conflict relationships
  are symmetric and must be represented by conflicts.
- Signal content is either `{"model": {"business": {"segments": [...]}}}`
  (or another existing extraction kind), or
  `{"preserved_token": {"token_id": {"ordinal": 1}}}`. Kind, claim and token
  joins must agree; citations are the exact union for the selected claims.
  Every retained claim is covered. Every non-conflicting preserved token retains
  its own reference and obligation, including when its claim is superseded or
  duplicate. Different exact scalars cannot be declared duplicates.
- Conflicts name at least two current conflicting claims, exact citations,
  a closed conflict kind, typed `summary`, and `resolution: "unresolved"`.
  Overlapping conflicts retain all relationship coverage; duplicate conflict
  groups of the same kind fail. Conflicting claims cannot be projected as
  resolved signals. No source-precedence authority is currently registered,
  so model-proposed precedence or user resolution is rejected.

All text uses §3.7's shared validator with the explicit contributing-claim
scope set; cross-source scope never becomes corpus-wide permission. Models
cannot supply canonical signal, conflict or statement IDs, scalar replacements,
paths or completion status. The final validator checks hierarchy and record
joins and returns `blocked` whenever unresolved conflicts exist, otherwise
`ok`. This is candidate accounting, not semantic proof or permission to publish.

The scripted YAML fixture explicitly sequences these operations. Live model
iteration/repair, shared authority-reconciliation integration, persisted
snapshot/conflict continuity, clarification creation and specification rendering
remain separate work. No new prompt, provider call, persistence or artifact
write is introduced; user-closed clarification files remain unchanged.

### 3.10 Shared required-authority boundary

H-008 implements Design §12.8 through one shared native contract, not a
specification-quality oracle. `src/domain/required_authority.zig` owns the
closed requiredness/ownership policies, current support checks and outcomes.
`specification_authority.zig` contributes the schema-derived Specify projection.

The projection includes the display name, primary story and evidence-backed
entity decision; each field of an existing identified content record; every
accounted reference signal/conflict; and each exact-preservation obligation.
Optional collections add no minimum record count. The gate rebuilds this
projection to reject omitted/invented entries. Signals retain the existing
claim/citation/token lineage and unresolved conflicts force a gap; neither a
citation nor reconciliation membership supplies semantic support by itself.

| Registered YAML operation | Responsibility |
| --- | --- |
| `build-specification-authority-requirements` | Project native content/reference facts into shared requirements. |
| `build-required-authority-ledger` | Validate and canonically order registered requirements/current inputs. |
| `parse-required-authority-observations` | Parse the closed observation shape using the shared strict JSON decoder. |
| `reconcile-required-authorities` | Account for every supplied evidence member and derive one resolution or gap per requirement. |
| `validate-required-authority-reconciliation` | Rebuild against current inputs and issue accepted/rejected gate evidence. |

Observations contain only requirement references, the complete inspected
authority set and supplied evidence IDs. Native evidence keeps current
authority identities, scoped candidate revisions, provenance and whether its
finding is deterministic or model-assisted. The model cannot mint evidence,
choose ownership, remove requirements or set workflow success. Only direct
identity/revision equality collapses equivalent candidates, retaining all member
evidence. Entity non-applicability requires supported `no_business_data` evidence;
exceptions are permitted only by the shared registered exact-scope policy and
current authenticated authority, not by an arbitrary flag.

The shared owner mapping routes business/reference gaps to spec, design/policy
gaps to plan and decomposition gaps to tasks. Downstream detection produces
explicit upstream rework; unknown ownership/policy blocks. Structural
accounting errors block instead of entering model repair. Gap records are
execution-local inputs to H-011, not inline questions or persisted forms.

The registered `required-authority@1` gate binds its sole issuer to the current
input, observation and result generations. The existing runner also checks
source lineage, so refreshing a reference, candidate or support source requires
explicit projection/reconciliation/validation again. Protected operations
declare that gate in their native contract; YAML cannot bypass it or supply
an alternative issuer. There is no persisted authority ledger, new prompt,
fingerprint or recovery mechanism.

`zig build test-required-authority` covers scripted outcomes, unrelated kinds,
all Specify record families, missing/foreign/duplicate/stale support, permitted
and prohibited dispositions, scoped exceptions, source preservation and YAML
gate bypasses. The production reference fixture reaches the Specify projection;
H-009/H-010 now supply model-assisted evidence and generation. H-011–H-013
still own applicable answers, protected forms, publication and the complete definition.

### 3.11 Native reference/model execution (H-009)

Registered operations now build immutable domain packets and collect bodies
accepted by the existing provider-observation, envelope and result-schema
validators:

- `initialize-reference-extraction`, `check-reference-extraction-progress`,
  `build-reference-extraction-model-input`,
  `collect-reference-extraction-result`, `build-reference-extraction-results`.
- `build-reference-reconciliation-model-input`,
  `check-reference-reconciliation-purpose`,
  `collect-reference-reconciliation-result`.

Each extraction packet contains the complete captured chunk as lossless
`source_lines` with request-local IDs, scoped passive choices and token candidates. Reconciliation packets retain all
partition claim/summary membership and exact-token references. Collection checks
the immutable request/packet association; models cannot select another chunk or
partition. Existing domain validators still own interpretation/accounting.

`assign-model-request-id` accepts either a native `model_input_packet` or
the declared static input resource, never both. The packet supplies an
engine-owned unit/purpose, not a prompt, result schema or provider selection.
Initial generation, semantic review and authorized atomic repair have native producers.
A new logical request gets an initial attempt; it does not reset the YAML
operation's execution/retry ceiling. `more` exposes bounded collection progress
without reusing failure outcomes.

The ordinary [generation-only definition](../workflows/spec.workflow.yaml)
connects these operations, workflow-owned resources and H-008 review.
`retire-model-input` and `retire-model-request` explicitly release completed
transport slots. Native captured evidence keeps its current domain-source
lineage, not the replaceable transport slot; source changes and mixed-generation
joins still reject. The request ledger is runner-validated execution control,
not business authority. All storage is execution-local.

`build-model-protocol-retry` retains the original request identity, schema,
unit and provider binding. It uses the originating assignment's optional
`protocol-prompt`, decoder/schema diagnostic and minimum schema example.
It rebuilds from the retained original inputs and latest rejection, without
accumulating correction history. YAML checks the logical request phase before
reusing the normal provider-operation lifecycle and accounting. The accounting
step's configured limit and total token budget own exhaustion; the correction
builder has no separate counter or limit (Design §22.6).

Workflow schemas and the shared `model_candidate_json.zig` decoder use ADR
0006's closed `kind` alternatives, including nested typed values. Empty, mixed
or incomplete alternatives reject at payload validation, before request closure,
and take the existing bounded protocol-correction path. Schema examples are
checked against native decoding; integer spelling uses the payload validator's
exact arithmetic. Native/persisted JSON is unchanged; no legacy model reader
or schema-profile extension is introduced.

`test-reference-model-input` checks packets, exact values, scope membership and
allocation failures; `test-model-request-workflow` checks native packet transport
through the fake provider and rejects packet substitution/schema rejection.
The fake-provider generation test covers complete read/generate/review paths,
two business examples, protocol correction/exhaustion and semantic uncertainty.
This is not artifact publication or an end-to-end Specify completion claim.

### 3.12 Clarification refresh and registered publication

The generation definition now routes validated unit needs through
`build-specification-clarification-need`, `refresh-clarifications`,
`render-clarification-forms`, `prepare-clarification-output`,
`publish-workflow-output` and `check-clarification-progress`. The shared refresh
retains subject IDs across invocations and replaces open drafts, including when
the question is unchanged. New submitted answers remain blocked pending trusted
authentication and applicability validation; loading a response is not acceptance.

Preparation joins the complete rendered form set to validated registry state,
retains protected bytes and serializes canonical JSON. The writer has only a
`feature-output-write` capability and registered destinations, never model paths.
It rechecks the complete captured clarification input set before replacement,
uses no-follow file access, rejects hard links, truncates shorter output and
verifies written bytes. User-closed files are not replacement candidates. No
transaction directory, append/merge path or recovery subsystem is introduced.

The YAML's successful content branch projects current-authority-checked typed
content through the existing Markdown codec and reparses it. It renders
`reference-context.md` from an accepted reference snapshot, refreshes the
clarification registry through the shared refresh operation, and prepares all
four registered outputs before the writer runs. `workflow.json` is written last.

The native closed `specification-state/v1` singleton contains the feature key,
revision, `specified` stage, captured reference sources/chunks/claims/citations,
reconciliation and passive-literal records, accepted brief/content/provenance,
coverage, record-ID counters, clarification state/revision and required-authority
review evidence. Model-assisted support retains that label. The snapshot contains
no raw model response, filesystem handle, runner state or saved continuation.
`capture-workflow-state` and `parse-specification-state` validate this singleton
before generation; reruns reuse only the canonical record-ID counters, increment
the publication revision and regenerate the candidate from current inputs.
Malformed or foreign state blocks before model calls. Generated Markdown is not
imported as authority. Specification request owners use the same lossless
`FeatureId` directory contract for generation, review and repair.

Publication checks exact captured workflow-state bytes as well as clarification
inputs; stale captures reject. Every write failure prevents new completion, and
a fresh invocation starts from the beginning. Feature-log integration and
[remaining clarification work](../harness/02-spec-workflow.md#h-011--complete-specification-clarification-handling)
remain open. A clarification publication ending in `needs_user` still does not
claim a completed Specify workflow.

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

The 2026-09-11 user-approved presentation amendment restores the business
layout of the original `ai_base/.specify/templates/spec-template.md`. The
original is design source material, not a runtime template dependency.

`spec.md` is a business-facing renderer projection, never a model-authored
Markdown response. To preserve the existing fixed `displayName` field and a
valid heading tree, the renderer emits the display name as the document H1,
then applicable sections in this exact relative order:

```markdown
# Feature Specification: <display name>

## User Scenarios & Testing _(mandatory)_

### Primary User Story

### Acceptance Criteria

### User-Visible Outcomes

### Edge Cases

## Requirements _(mandatory)_

### Functional Requirements

### Business Rules

### Assumptions & Scope Boundaries

#### Assumptions

#### Explicit Non-Goals

#### Prohibited Behaviors

### Key Entities _(include if feature involves data)_
```

The angle-bracketed display-name token above documents the renderer slot; it is
not emitted literally. `User Scenarios & Testing` and `Requirements` are always
present. Primary User Story, Acceptance Criteria and Functional Requirements
are mandatory. Other record families appear only when they contain supported
content. The scope parent appears only when at least one of its children is
present. `Key Entities` additionally requires the validated business-data
applicability decision.

The original template's execution flow and generation guidelines are workflow
instructions, not specification content. Review checklist and execution status
are represented by actual validation evidence and workflow state; this view
never invents checked boxes. Branch, creation date, draft status and original
command metadata are not fields in the current content contract and are not
fabricated or inferred from the feature title. The feature directory remains
the identity; the human title is reference-grounded.

### 5.2 Typed content mapping

| Section | Native content field / record kind | Purpose |
| --- | --- | --- |
| Document H1 | `display_name` | Reference-grounded human feature name. |
| Primary User Story | `primary_user_story` | Main user journey in plain business language. |
| Acceptance Criteria | `acceptance_criterion` / `AC-*` | Testable initial state, action, and expected outcome. |
| User-Visible Outcomes | `user_visible_outcome` / `UO-*` | Results, validation, confirmation, or terminal responses a user can directly observe. |
| Edge Cases | `edge_case` / `EC-*` | Boundary/error condition and expected business response. |
| Functional Requirements | `functional_requirement` / `FR-*` | Required system or user capability in business terms. |
| Business Rules | `business_rule` / `BR-*` | Constraint, validation rule, or policy controlling behavior. |
| Assumptions | `assumption` / `AS-*` | Supported assumption that keeps the feature bounded. |
| Explicit Non-Goals | `non_goal` / `NG-*` | Supported adjacent behavior deliberately outside scope. |
| Prohibited Behaviors | `prohibited_behavior` / `PB-*` | Behavior the feature must not perform. |
| Key Entities | `entities` applicability plus `entity` / `EN-*` | Business data concepts and relationships, without implementation detail. |

The engine assigns and preserves record IDs; the model supplies neither IDs nor
Markdown. The historical template's unnumbered example bullets do not permit
anonymous persisted records.

### 5.3 Acceptance-criterion rendering

The renderer restores the original compact acceptance-criterion form while
retaining three separate typed values and engine-assigned identities:

```markdown
### Acceptance Criteria

- **AC-001**: **Given** <precondition>, **When** <action>, **Then** <observable outcome>
```

The labels, casing, separators and order are canonical. Missing, duplicate,
reordered or foreign labels reject; label-shaped bytes inside exact Markdown
code spans remain inert content. Multiline exact values retain the shared
continuation encoding. No legacy multiline uppercase reader is retained.

### 5.4 Empty and conditional collections

The hierarchy does not authorize invented filler:

- `displayName`, `primaryUserStory`, and every contract-required record must be
  supported by current reference or resolved clarification authority;
- acceptance criteria and functional requirements each require supported
  records before successful publication; their headings remain mandatory;
- other empty collections render no heading, bullet, placeholder or synthetic
  `None` entry; an empty scope group is omitted with its children;
- if required content is absent, the workflow takes the clarification path in
  Section 5.5 rather than rendering an empty successful specification; and
- `Key Entities` is omitted only from a validated `not_applicable` decision. An
  empty `entities` collection alone cannot prove that the feature involves no
  business data.

The approved native contract requires `entities.disposition` as `required` or
`not_applicable`, plus an attributed business-text `basis`. That is a candidate
decision: the shared authority gate must validate its support. Parsing a missing
entity section captures only `omitted`, never a supported non-applicability fact.

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

Unresolved `clarify/SNN.md` forms MUST also be completely overwritten from
current validated state at the same paths on rerun, including their editable
regions and any unsubmitted draft answer. Reuse the same subject ID, not the
old form bytes, even when the question is unchanged. This replacement also
applies to a clarification publication ending in `needs_user`; it does not
publish a partial specification. Design Section 23.2 applies this rule to all
workflow executions and every registered clarification family.

The engine MUST NOT overwrite user-closed `clarify/SNN.md` files. Retain them
byte-for-byte and consume applicable validated answers before generation.
Accept a valid close into canonical state without rewriting its submitted form. A pending,
stale, or invalid close is not overwritten; an inapplicable protected answer
blocks for user direction rather than automatic reopening or a duplicate ID.
The complete clarification view set includes these retained files, not writes
to them. Transaction validation rechecks their preservation preconditions.

There is no committed `Open Questions` section in `spec.md`. Specification-owned
unknowns use the clarification lifecycle above; reference-context questions
remain in their separate sidecar authority. Specification content/IR samples
have no question collection or `OQ-*` identity prefix; `clarification_needed`
is an operation result, not a specification content unit.

### 5.6 Native content and view contract

The user approved the following minimal contract. Native shapes and ID syntax
are owned by [specification.zig](../../src/domain/specification.zig); the
mechanical codec is [specification_markdown.zig](../../src/domain/specification_markdown.zig).

- Simple records use `- **FR-001**: <text>` with the applicable prefix.
- Edge cases use `**EC-001**`, then `- **CONDITION** <text>` and
  `- **EXPECTED OUTCOME** <text>`.
- Entities use `**EN-001**`, then `- **NAME** <text>`,
  `- **BUSINESS MEANING** <text>` and zero or more
  `- **RELATIONSHIP** <text>` lines.
- IDs have a positive ordinal, padded to at least three digits, without
  surplus leading zeroes. New editable records may use the kind label without
  an ordinal, such as `**AC**` or `- **FR**: <text>`; they require engine
  allocation before canonical rendering. Existing malformed/duplicate IDs reject.
- `MUST`/`MUST NOT` remain semantic text. There is no second `modality` field
  or renderer-inserted requirement wording.
- Title/story, the entity decision, acceptance criteria and functional
  requirements are required. Other record families have no minimum population.
  Schema presence never proves support, completeness or testability.
- The Specify authority projection always includes acceptance-criteria,
  functional-requirement and scenario-coverage obligations. On an assembled
  candidate, missing mandatory records produce engine-owned `missing` gaps
  through the shared authority gate even if model evidence says `supported`.
  The scenario-coverage obligation requires model-assisted comparison of the
  complete candidate with source claims/citations, including distinct observable
  flows and their triggers/results. Missing behavior cannot be satisfied by
  citation presence or a title. Canonical-state parsing rejects missing mandatory
  families through the same specification required-family contract.

Native proposals contain attributed title/story, `records` with one closed
content-kind variant and provenance per record, and the entity decision/basis.
They contain no generated IDs, paths, questions or completion fields. Ordinary
business values use the existing typed-text shape; exact copies carry token and
citation references, never a second copy of source bytes.

The view codec receives already projected text and separated, non-overlapping
exact inline-code spans (adjacent delimiter runs cannot preserve two identities);
it escapes punctuation and literal control whitespace, uses deterministic
backtick delimiters/padding, LF structural lines and one final newline. Code
continuation lines have two structural indentation spaces, removed on parse.
Record order is section order, preserving order within each family. The shared
Markdown scanner owns code-span recognition. Parsing captures text/spans, not
NFC normalization, provenance, applicability, semantic adequacy or stage success.
H-008/H-010 connect the shared gate and generation validation; H-012 still owns publication.

### 5.7 Generation, coverage and repair (H-010)

The native generation candidate is a closed content-or-clarification union.
Content units are a feature brief (title, description, primary goal), primary
story, entity applicability, or one registered record family. Native validation
normalizes typed text, rejects the wrong family and identical normalized records,
and keeps questions outside specification content.

The model's `kind` selects `brief`, `primary_user_story`, `entities`, `records`
or `clarification`, with that variant's fields directly, without the IR's `content`
wrapper. Repair uses the same compact codec, and its expected-value guidance
uses the response wire shape. Existing provenance, repair and gate validators
remain the owners of meaning and authority.

The initial reference-only provenance join requires retained current claims and
their stable unique citation union. Exact copies contain only a valid token and
citation reference, never replacement display bytes. Arbitrary loaded
clarification-response IDs are rejected; applicable-answer integration remains
with H-011. Engine code allocates monotonic per-family record IDs; no model
identity, completion, approval or artifact-path field is accepted.

Registered actions generate units sequentially through the generic model path.
Every retained business claim maps to native content keys; non-spec context
remains in identified reference signals. Every retained exact business token
has an exact-copy target. Coverage is mechanical accounting, not semantic proof.
Model review supplies scoped evidence for the shared gate before generation and
after assembly, including the brief description/goal and every record field.

An invalid mechanically repairable candidate authorizes one field or record in
stable diagnostic order. The engine retains its owner, revision and old value;
the model returns only the replacement. Merge preserves siblings, increments
revision and repeats unit validation. Assembly revalidates all units, checks
conditional entities and assigns IDs before coverage and final authority review.
Classification collections and specification fields/records use the same
`atomic_repair.Contract`: immutable authorization IDs bind owner, revision,
target, expected value and validator rule; response parsing verifies the exact
repair packet, and merge checks the old value before incrementing the revision.
Native domain actions only select and apply their typed units. Both paths use
the existing `model-request` subgraph and one replacement prompt. JSON/schema
protocol retry remains separate from semantic repair.
YAML's repair operations each have an explicit bounded ceiling; exhaustion fails.
Only the workflow's cumulative actual token budget limits model tokens.
No missing knowledge is replaced with a default or treated as deterministic proof.

`test-specification-generation` and configured-root fake-provider tests cover
these paths and negative cases. Section 3.12 connects canonical persistence and
publication. Applicable answers and remaining workflow integration stay with
H-011/H-012; reruns regenerate views using the persisted record-ID counters.

## 6. Diagrams

- [Specify workflow logical topology](../diagrams/10-spec-workflow.md) shows
  selection, typed generation, clarification, rendering, and commit.
- [`spec.md` projection structure](../diagrams/11-spec-document-structure.md)
  shows the mandatory hierarchy, optional sections and conditional entities.
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
7. `spec.md` renders the Section 5.1 hierarchy, omits empty optional sections,
   retains mandatory parent/content sections and validates conditional entities.
   Empty mandatory content cannot pass the shared authority gate or state load.
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
    overwrite approval. Unresolved clarification forms MUST be completely
    overwritten at the same IDs/paths, including open answer drafts. It MUST NOT
    overwrite user-resolved clarification files;
    they remain byte-identical through generation, reference refresh,
    failed/cancelled runs, and commit; applicable validated
    answers are reused and no duplicate question bypasses that protection.

## 8. Verification

- `zig build test-reference-reconciliation` covers hierarchical/recursive
  grouping, exact original membership, all claim kinds, preserved tokens,
  closed proposals, invalid/acyclic relationships, overlapping blocking
  conflicts, scoped text, canonical record joins and allocation/lifetime
  failures. `zig build verify` also exercises the native YAML path, rejects
  missing prerequisites and invalid group sizes, preserves user-closed forms,
  and runs the clean-environment native packaging smoke suite;
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
- renderer/parser fixtures cover applicable heading order, omitted/empty optional
  groups, compact criteria with exact-code delimiters, missing mandatory groups,
  zero-record collections without filler, data-required entities, validated
  non-data omission, and render/parse equality;
- negative fixtures reject every placeholder spelling, inline clarification,
  unresolved question, malformed/reordered record ID, and invalid acceptance
  triplet; and
- golden tests prove byte-stable `spec.md`, mandatory sidecar generation, and
  atomic commit before `specified`.
- rerun tests prove all registered replaceable outputs and unresolved forms are
  completely overwritten at the same paths without append, merge, skipping,
  renaming, or separate overwrite approval. Cover unchanged questions, open
  answer drafts, shorter replacements with no retained trailing bytes, and
  stable subject IDs, while preserving pending and accepted user-closed forms,
  including when another question is opened;
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
