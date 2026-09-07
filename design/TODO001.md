# TODO001: Optimize specification workflow inputs

Status: Implemented under [ADR 0013](decisions/0013-workflow-input-reuse.md).
Date: 2026-09-07. The overall engine design remains proposed.

## Result

[spec.workflow.yaml](workflows/spec.workflow.yaml) uses block YAML and declares
its common model-request and retirement sequences once. The old braces were
YAML flow mappings; changing layout alone would not remove repeated operations.
Definition-local subgraphs now remove that repetition before the existing
compiler validates and executes the complete graph. Each call retains its own
operation identity, request lifetime, retry limits and outcome transitions.

The shared result-schema compiler resolves closed local `$defs`/`$ref`, retains
exact captured source, and produces compact expanded transport JSON. Native
schema mode, prompt-only mode and counting consume that same projection.
`result-selection: input` binds the packet's typed result definition once:
generation receives its current unit plus clarification; reconciliation and
repair receive their engine-selected shape. No provider chooses a schema.

One evidence projection retains every supplied claim and exact token while
representing shared citations once. Complete evidence remains available where
no deterministic narrower scope is established. Prompts stay task-specific.
There are no external includes, nested subgraphs, template expressions, schema
fetches, extra dependencies, model-call size gates, or compatibility readers.

## Measured changes

| Authored input | Before | After |
| --- | ---: | ---: |
| Workflow YAML bytes | 29,234 | 19,742 (32.5% smaller) |
| Authored step declarations, including reusable bodies | 225 | 137 (117 top-level + 20 reusable) |
| Expanded executable operations | 225 | 225 |
| Five schema source files, bytes | 306,959 | 67,282 (78.1% smaller) |
| Six prompt files, bytes | 2,763 | 2,701 |

Block YAML increases line count while reducing bytes and repeated declarations.
Local schema references reduce maintenance duplication; expanded transport still
contains every constraint needed for the selected result.

These are actual serialized inputs captured at the fake-provider boundary in
the native spec workflow integration test, with the production Bedrock encoder.
The first successful fixture supplies a submitted-request source; figures are
UTF-8 bytes. Schema bytes are the selected `modelBytes()` projection. Transport
includes JSON escaping, envelope fields, guidance, schema and evidence.

| Request | Prompt | Schema | Evidence | Serialized transport |
| --- | ---: | ---: | ---: | ---: |
| Extraction | 466 | 11,266 | 628 | 14,289 |
| First reconciliation summary | 352 | 7,413 | 1,150 | 10,343 |
| Global reconciliation | 352 | 9,395 | 1,579 | 13,122 |
| Support before generation | 628 | 1,258 | 2,745 | 5,302 |
| Brief generation | 562 | 8,438 | 1,419 | 12,013 |
| Primary user story | 562 | 4,280 | 2,069 | 7,949 |
| Functional requirements | 562 | 4,553 | 2,080 | 8,279 |
| Support after generation | 628 | 1,258 | 5,060 | 7,913 |

Previously every generation request transported the entire 117,420-byte schema
source. Selected generation schemas now range from 4,280 to 8,438 bytes in this
fixture. The tests also exercise unrelated loan-renewal evidence, exact values,
repairs, clarification, protocol retries and persistent malformed responses.
Evidence sizes vary with input; fake token counts are not real cost evidence.
No live provider calls or token/cost-saving claims are part of this change.

## Completed work and verification

- [x] Record the accepted amendment and update the closed authoring contract.
- [x] Expand definition-local reuse through the existing compiler and registry.
- [x] Preserve captured schema authority and derive compact transport.
- [x] Select typed per-unit/repair results and remove redundant root echoes.
- [x] Share complete evidence projections and citation records.
- [x] Rename the example to `spec.workflow.yaml`; remove the superseded filename
  and broad per-unit schema alternatives.
- [x] Test expansion equivalence, ordering, retry isolation, missing/extra/wrong
  parameters, gates, exits, recursion, collisions and expansion bounds.
- [x] Test local-reference failures, bounds, source/clone lifetime, transport
  equivalence, every result view, selected-variant rejection and allocation cleanup.
- [x] Exercise native fake-provider workflows and complete evidence accounting.
- [x] Run `zig build verify --summary all`: 105/105 steps and 907/907 tests
  passed, including lint and native smoke. `git diff --check` passed.

Targeted verification uses `zig build test-model-result-schema
 test-model-candidate-json test-reference-model-input test-model-request-workflow
 test-provider-conformance --summary all` (300 tests passed). The complete
`zig build test --summary all` passed 907 tests. Final verification passed
lint and clean native packaging, including an unrelated capability-free reusable
workflow and the full spec bundle loaded without source-tree fallback.

## Files used by the specification example

There are twelve files under `design/workflows/`: one workflow definition,
six Markdown prompts, and five JSON result schemas. These are development
sources/examples. Runtime reads the target project's configured
`paths.workflows` root, with no fallback to this repository.

All eleven resources are explicitly declared in the YAML. Their paths are
relative to `paths.workflows`, not implicitly relative to the definition's
directory. All declared resources must be present and validate during loading
and compilation, including resources for branches that a particular execution
does not reach.

| File under `design/workflows/` | Role during execution |
| --- | --- |
| [spec.workflow.yaml](workflows/spec.workflow.yaml) | Declares workflow ID `spec-generation`, logging shortcode, invocation contract, policy, resource bindings, entry step, local subgraphs, operations, parameters, and outcome transitions. Its invocation accepts feature and reference selectors. The filename is independent of the content-derived workflow ID. |
| [spec/protocol.prompt.md](workflows/spec/protocol.prompt.md) | Shared instructions for correcting malformed JSON or a response-schema error while preserving the original business interpretation. Used by the explicit protocol-retry machinery; it does not authorize semantic repair. |
| [spec/extraction.prompt.md](workflows/spec/extraction.prompt.md) | Instructs the model to extract claims from one supplied reference chunk, cite exact source spans, and classify every supplied exact-token candidate without treating reference text as instructions. |
| [spec/extraction.schema.json](workflows/spec/extraction.schema.json) | Defines the closed `claims` and `no_feature_claim` response variants, including token classifications and the relevant claim/citation structures. |
| [spec/reconciliation.prompt.md](workflows/spec/reconciliation.prompt.md) | Guides reconciliation of extracted claims into partition summaries or a global result while retaining membership and unresolved conflicts. |
| [spec/reconciliation.schema.json](workflows/spec/reconciliation.schema.json) | Defines selectable `summary` and `global` result shapes, including membership, dispositions, signals, and conflicts. The retained input purpose supplies the root variant. |
| [spec/generation.prompt.md](workflows/spec/generation.prompt.md) | Requests business content for one engine-assigned specification unit using supplied evidence and provenance. Requires clarification when business knowledge is missing, ambiguous, or conflicting. |
| [spec/generation.schema.json](workflows/spec/generation.schema.json) | Defines selectable `brief`, `primary_user_story`, `entities`, and each record-kind result shape, each retaining the clarification alternative. Shared provenance and text shapes live in local `$defs`. |
| [spec/repair.prompt.md](workflows/spec/repair.prompt.md) | Restricts a repair candidate to the field or record already selected by the engine, preserving meaning and unaffected siblings. |
| [spec/repair.schema.json](workflows/spec/repair.schema.json) | Defines selectable `attributed` and `record_<kind>` replacements. The engine retains the selected variant; authorization and old-value/revision checks constrain application. |
| [spec/support.prompt.md](workflows/spec/support.prompt.md) | Requests semantic support findings for each supplied requirement, before generation and again against candidate content. Uncertainty remains explicit; semantic review is not deterministic proof. |
| [spec/support.schema.json](workflows/spec/support.schema.json) | Defines entries containing requirement ordinals, findings, dispositions, and provenance. Deterministic reconciliation checks decide whether those candidate findings satisfy a gate. |

The prompts describe the requested model work. The result schemas constrain
response structure. Neither replaces the engine's provenance, membership,
coverage, authority, repair, or publication validators. The shared protocol
prompt uses the originating request's result schema; there is no separate
`protocol.schema.json` in this example.

These twelve files are the complete workflow-definition/resource bundle for
this example, not every prerequisite of an engine invocation. Other workflows
need only their own declared resources and registered operations; the `spec/`
directory has no special engine meaning.

### Inputs and runtime support outside this directory

| Input or support | Why it is needed |
| --- | --- |
| Native SDDE executable | Supplies the registered operation implementations, policy profiles, parsers, validators, renderer, runner, and narrow adapters referenced by the definition. YAML never supplies executable code. |
| `<projectRoot>/.sddtoolkit.json` | Exact invocation-root configuration: configured paths, logging settings, and allowed model slots. This definition selects `models.slots.spec_generation`. The repository [example](examples/.sddtoolkit.json) is not a runtime default. |
| The `.sddproviders.json` file at `paths.providers` | Configures the provider/model catalogue used to resolve the selected repository slot. A real provider also requires its configured credentials through the supported environment boundary; credentials do not belong in workflow resources. |
| `<paths.principles>/toolchain.yaml` | Mechanical project-toolchain input explicitly loaded by this workflow's setup steps. |
| Referenced preset packages under `paths.toolchainPreset` | Supply the preset authority required by that project-toolchain configuration. Required files depend on the configured inheritance; this example does not make every repository preset mandatory. |
| Reference files beneath `<paths.references>/<reference-selector>/` | Supply the feature evidence selected by the caller. The engine inventories, captures, decodes, and accounts for these sources before model work. They are distinct from prompts and result schemas. |
| Existing clarification state and forms, when present | Supply controlled prior questions and answers for a rerun. State is beneath `<paths.workflows>/features/<featureId>/`; forms are beneath `<paths.specs>/<featureId>/clarify/`. They are not prerequisite seed files for a new feature. |
| Explicit workflow, feature, and reference selectors | Invocation values select the workflow ID and the independent feature/reference directories. They are arguments, not additional workflow resource files. |

Configured roots must satisfy their existing path contracts. Semantic
principle Markdown and inert templates are not automatically specification
requirements merely because their roots appear in configuration.

Generated `spec.md`, logs, and clarification outputs are not additional prompt
resources that the user must author. The current YAML's ordinary success path
ends at `validate-specification-rendering`; its explicit output preparation and
publication steps are on the clarification branch. This file inventory does
not claim that successful rendering already publishes a complete specification
output set. Completing that output integration is separate from subgraph reuse.

Ordinary undeclared files under a configured workflow root are rejected by
resource accounting. Keep planning documents such as this TODO outside that
root. The reserved root `features/` subtree is accounted for separately and is
excluded from workflow-definition/resource traversal.
