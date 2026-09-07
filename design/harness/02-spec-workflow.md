# Spec workflow dependencies

[Backlog index](README.md). These are production-engine dependencies for the
**run-workflow-and-evaluate** path. They are not prerequisites for evaluating an
already supplied specification through H-003–H-006.

Production validation and the external rubric have different purposes. A rubric
can judge a readable specification without a complete parser; it cannot grant
the engine permission to bypass its current safety/publication contracts.

The current task excludes human evaluator calibration and live API verification.
Production authority, clarification protection and output-safety contracts are
not waived by that exclusion.

## H-007 — Align the existing specification contract

**Status:** Native content contract and mechanical Markdown codec implemented;
the shared authority boundary is implemented in H-008, generation/identity in
H-010, and publication integration remains H-012.
**Owner:** F0100 and
canonical specification types. **Dependencies:** none; independent of H-001.

The user approved the minimal record/entity/modality/required-content contract.
[F0100 §5.6](../features/F0100-SpecWorkflow.md#56-native-content-and-view-contract)
records it; `src/domain/specification.zig` owns native candidate shapes and IDs,
and `specification_markdown.zig` owns view rendering/parsing. Captured Markdown
is not validated business authority. Entity section presence/absence cannot
manufacture applicability evidence. Provenance resolution, monotonic identity
allocation, registered pipeline bindings and publication remain production
integration work; no complete Specify execution is claimed.

`zig build test-specification-contract` covers every record family, empty
optional content, exact display spans, canonical round trips, invalid labels/
IDs, new unnumbered edits, closed JSON and allocation failures. The evaluator
and specification reuse the same closed JSON decoder; the evaluator-local
wire-kind validator is removed.

Current targeted verification: `zig build test-specification-contract
test-rubric-evaluator test-typed-text --summary all` passed 76 tests (12 contract,
29 evaluator, 35 shared typed-text tests). `git diff --check` is clean.

Final combined verification: `zig build test-specification-contract
test-rubric-evaluator test-typed-text verify --summary all` passed all 853 test
executions and 93 build steps, including lint, architecture checks and native
engine/evaluator packaging smoke tests. No human or live API evaluation ran.

Work:

- Align the governing design and illustrative IR with F0100's already-approved
  section hierarchy and prohibition on inline clarification/open-question
  content. Do not ask for those decisions again or retain conflicting samples.
- Record the concrete record grammar and entity-applicability representation
  needed by the renderer/parser. Resolve duplicate ownership of requirement
  modality between structured data and rendering.
- Identify actual schema-required fields separately from optional collections.
  No universal catalogue of business requirements, invented minimum section
  population or fixture-specific exception is authorized.
- Mark genuinely unsettled production policies explicitly. They affect the
  relevant engine operation, not whether the external rubric may judge a spec.

Acceptance:

- [x] One production schema/renderer/parser contract owns structure and IDs.
- [x] Optional empty content cannot be turned into fabricated requirements.
- [x] Semantic adequacy remains a model-assisted/human judgment, not a claimed
  consequence of schema or Markdown validity.
- [x] F0100/design/code examples agree; no legacy `OQ-*` route emits questions
  into `spec.md`.

Targets: [F0100 §5](../features/F0100-SpecWorkflow.md#5-specmd-projection-contract),
Design §§7/17/23 and their schema/render samples. This ticket does not create
an exact semantic expected `spec.md` for the harness.

## H-008 — Implement the shared required-authority boundary

**Status:** Implemented and offline-tested. **Owner:** shared domain/actions;
Specify contributes evidence.
**Dependencies:** H-007 for concrete Specify registrations, not for all generic
mechanics. Governing source: Design §12.8 and acceptance criteria 36–40.

`src/domain/required_authority.zig` owns the closed policies, structural ledger,
current support checks, reconciliation and earliest-owner routing.
`specification_authority.zig` derives Specify requirements from the native
content schema and accounted references; it does not decide continuation.
The shared gate rejects stale source lineage as well as directly replaced
inputs, using the runner's existing generation metadata.

Five capability-free operations are registered in the normal YAML registry;
see [F0100 §3.10](../features/F0100-SpecWorkflow.md#310-shared-required-authority-boundary).
Observations can reference engine-supplied evidence and candidates, but cannot
create requiredness, choose ownership, mint supporting evidence or submit an
overall success/score. Directly equivalent resolutions retain every member's
evidence; semantic findings remain explicitly model-assisted.

`zig build test-required-authority` covers schema-derived Specify fields,
reference conflicts/preservation, unrelated policy/decomposition kinds,
closed scripted observations, YAML gate bypasses, staleness and allocation
failures. H-009/H-010 now supply the production semantic evidence producers;
H-011 consumes the typed gaps, and H-012/H-013 integrate publication and the
complete workflow. This ticket does not claim those workflows execute yet.

Verification: `zig build test-required-authority verify --summary all` passed
103/103 build steps and 927/927 test executions (83 in the targeted authority
suite), including lint, architecture checks and clean native-package smoke
tests. `git diff --check` passed. No live provider calls were made.

Work:

- Build the execution-local required-slot projection only from registered
  schemas, policies, obligations and current authorities. Register the initial
  Specify slots/policies explicitly; do not invent requiredness from model text.
- Produce/validate one closed resolution or gap per entry, including permitted
  non-applicability/exception outcomes only when their rules are registered.
- Feed current reference signals/conflicts into the shared contract using
  existing validators. Citations and reconciled membership are not automatic
  proof of semantic support for a specification field.
- Route gaps through the compiler-owned earliest-stage mapping. Unknown policy
  blocks; downstream discovery cannot move a business gap to Plan.
- Expose operations through generic YAML and rebuild evidence when inputs
  change. No persisted authority ledger or separate recovery subsystem.

Acceptance:

- [x] Missing, duplicate, foreign, stale, unsupported and conflicting support
  cannot pass a gate or enter ordinary repair as invented content.
- [x] Tests exercise the same mechanics across unrelated requirement kinds;
  implementing the full Plan/Tasks workflows is not required for those tests.
- [x] Signals/conflicts have one validation owner and complete provenance.
- [x] The external judge's score is not a candidate resolution or gate token.

## H-009 — Connect reference operations to model execution

**Status:** Implemented; final offline verification is recorded below. **Owner:** registered reference/model
operations. **Dependencies:** reuse current generic request lifecycle work;
H-008 is required at applicable production authority gates.

Implemented: engine-owned packets and exact result association, sequential
extraction and hierarchical reconciliation, concise workflow-owned resources,
explicit transport retirement, bounded protocol correction and H-008 evidence
integration. The generation-only [YAML](../workflows/spec-generation.workflow.yaml)
runs through the ordinary compiler/registry/runner and existing provider port.
The production provider integration remains the configured Bedrock adapter;
OpenAI judging is a separate harness concern.

Final response-contract alignment uses the accepted ADR 0006 `kind` alternatives
in workflow schemas and one shared native candidate codec. Malformed root or
nested variants reject before request closure and use the existing YAML retry;
no permissive one-key union schema or legacy model reader remains.

Native captured values retain their immutable evidence and current domain
dependencies. Retiring a request does not invalidate accepted evidence; changing
an underlying reference or candidate still invalidates dependent gates.
Runner bookkeeping is not semantic authority. No persisted snapshot,
transaction directory, recovery mechanism or source-tree fallback was added.

Work:

- Reuse ingestion, extraction, exact-value and hierarchical reconciliation
  contracts already implemented in F0100 §§3.1–3.9.
- Connect engine-built chunk/reconciliation packets and accepted response
  bodies to the existing generic model-request operations. Replace test-only
  producers in the production path, not the production validators.
- Supply concise workflow-owned prompts/result schemas and explicitly bounded
  iteration/retry transitions. Preserve all claim/citation/token membership.
- Integrate an approved live generation provider behind the production port.
  OpenAI is required for judging, not implicitly chosen for generation; record
  the generation provider/model separately and do not force AWS infrastructure.

Acceptance:

- [x] Fake provider responses traverse the same domain pipeline as live ones.
- [x] Production generation/reconciliation does not depend on a fixture-name
  branch, source-tree fallback or hidden built-in workflow graph.
- [x] Protocol failures, budget exhaustion and semantic conflicts retain their
  distinct outcomes. No failed chunk or unresolved conflict disappears.
- [x] Source-preserved `Hello, World!` reaches downstream data unchanged.

Targets: native model/reference operation bindings, F0006 and F0100; reuse the
existing targeted extraction/reconciliation/provider tests before extending them.

## H-010 — Generate and validate specification content

**Status:** Implemented; final offline verification is recorded below.
**Owner:** registered specification actions and typed IR.
**Dependencies:** H-007–H-009.

Implemented: registered brief/story/applicability/record-family generation,
engine-owned IDs, retained-claim/citation joins, typed text and exact copies,
total claim/token coverage, full assembled-candidate validation and model-assisted
evidence through the shared required-authority gate. Brief description and
primary goal are required review slots alongside title, story and applicability.
Optional families may be empty; entities follow the evidence-backed decision.

Repair replaces one engine-selected field or record after exact owner,
revision and old-value checks. YAML bounds attempts; each merge repeats the
owning validator and assembly repeats full-candidate validation. Unsupported
knowledge remains a typed need/gap, not a repaired guess.

Protocol examples now pass both the workflow schema and native decoding. Tests
cover empty/mixed/nested-invalid responses, unchanged request identity on retry,
successful correction and exhaustion across extraction, reconciliation,
generation, repair and support. JSON integer decoding reuses the schema
validator's exact arithmetic; equivalent numeric spellings do not create a
second schema/native mismatch. Native content/storage and semantic gates are unchanged.

H-011 still owns applicable-answer consumption and protected forms. H-012
owns rendering/publication; this generation-only definition writes no artifacts
and does not mark a feature specified. Live generation and rubric scoring
are not claimed by offline tests.

Work:

- Build reference-grounded feature brief and specification-unit inputs; generate
  business-facing records through YAML-declared model operations.
- Assign IDs in engine code and retain source/claim/clarification provenance.
  Preserve exact-copy obligations without duplicating display text authority.
- Implement structural, citation, typed-text and coverage-accounting checks;
  label semantic review honestly. Do not claim these checks prove correctness.
- Reuse request accounting and implement only authorized unit-level repair,
  revalidation and explicit exhaustion; unresolved domain knowledge uses H-011.

Acceptance:

- [x] Typed output covers the approved section families without invented filler.
- [x] Generator-supplied IDs, operational paths, unsupported source claims and
  forged completion assertions cannot enter accepted workflow output.
- [x] Semantic principles/Node/Vitest preferences cannot invent business
  requirements. The generation packet follows Specify's business boundary.
- [x] Fake tests cover supported content, malformed output, semantic uncertainty,
  preservation and failed repair without fixture-specific success rules.

Offline verification (2026-09-07):

- `zig build test-model-candidate-json test-specification-generation test-reference-extraction test-reference-reconciliation test-structured-tokens --summary all`
  — 15/15 steps, 226/226 test executions passed.
- `zig build verify --summary all` — 104/104 steps, 889/889 tests passed,
  including architecture/lint and native packaging. The packaged generation
  definition/resources load from configured roots; absent credentials fail
  closed without a live call. Fake-provider tests execute generation, repair and
  the response-correction/exhaustion paths (24 scripted workflow scenarios).
- `git diff HEAD --check` — passed.

These checks do not grade business quality; that remains the LLM rubric
evaluator. They do not claim H-011/H-012 publication or H-013 completion.

## H-011 — Complete specification clarification handling

**Status:** Partial — subject-keyed refresh, form replacement and protected-input
checks are implemented; authenticated answer application is not. **Owner:** shared
clarification lifecycle with Specify registrations. **Dependencies:** H-008;
H-010 supplies unit needs. Coordinate output handling with H-012.

The trusted authentication mechanism for accepting new user submissions still
needs selection. No concrete provider is implemented; read-only form validation
does not authenticate the editor or invocation. User-close protection remains
independent of that decision and of answer acceptance.

Implemented: generation-unit needs use engine subjects and `SNN` IDs; the shared
refresh/renderer supports all three stages and replaces open drafts completely.
The generation YAML publishes forms plus `clarification-state/v2` through the
registered output writer before ending `needs_user`. No spec is published on
that branch. Recorded closed forms remain retained inputs, not write targets;
pending submissions block acceptance without a trusted authentication provider.

Remaining: authenticated acceptance, current answer/authority applicability and
generation provenance, forms for all shared-gate/brief gaps, and complete pause
state/log evidence. These are not supplied by read-only validation or by file
existence. The complete H-011 acceptance list below remains the completion gate.

Work:

- Build/reuse stable subject-keyed `SNN` needs and controlled forms under
  `<paths.specs>/<feature>/clarify/`; never insert questions into `spec.md`.
- Completely overwrite unresolved forms from current validated state on every
  rerun at the same IDs/paths, including unsubmitted answer drafts. Reuse the
  subject identity, not the old form bytes. This is the shared rule for all
  workflow executions in Design §23.2 and ADR 0009.
- Accept only current applicable authenticated answers/authority resolutions
  through the existing clarification contract, not a score or model assertion.
- Preserve every user-closed form byte-for-byte, including stale or invalid
  closures. Those require user direction, not automatic rewriting/reopening.
- End `needs_user` runs and start subsequent invocations at the workflow's
  beginning with current inputs; do not add a saved continuation.

Acceptance:

- [ ] Repeated detection does not create duplicate subject IDs. Unresolved forms
  are completely overwritten at the same paths, including unchanged questions
  and unsubmitted drafts; a shorter replacement leaves no old trailing bytes.
- [ ] A user-resolved form and its answer remain byte-identical. An applicable
  validated response is reused on a fresh run.
- [ ] Pending/stale/invalid closure and concurrent-close cases cannot overwrite
  the protected file or publish partial successful specification output.
- [ ] The harness observes clarification separately from generation failure and
  never invents answers to obtain a scoreable specification.
- [ ] Unchanged prior `spec.md` after a blocked rerun is not labelled new output.

## H-012 — Render and publish the complete workflow output

**Status:** Partial. **Owner:** production renderers/parser and publication boundary.
**Dependencies:** H-007/H-010; H-011 protection on clarification branches.

The authority-checked specification projection, existing Markdown codec and
normalized round-trip check are connected to generation. A shared registered
writer publishes prepared clarification output with exact captured-input
rechecks and complete replacement. Successful specification publication remains
unfinished: reference-context rendering, canonical reference/provenance/workflow
state joins and feature-log evidence are not yet assembled into a complete set.
The replacement rule is accepted in ADR 0009 and Design
§23.2: every workflow completely overwrites its registered replaceable outputs
and unresolved clarification forms, preserving user-resolved forms unchanged.
The publication failure rule is now approved in ADR 0009 and Design §25:
validate the complete output set before writing; a failed/interrupted write
sequence may leave already-replaced files, but must not report success or record
new successful completion. A fresh rerun replaces outputs from the beginning.
User-closed forms remain protected; no rollback/recovery subsystem is permitted.

The writer has no raw destination parameter, journal or recovery directory.
It rejects duplicate targets, changed captures, unsafe filesystem aliases and
completion state ordered before other files. Current tests cover normal
clarification reruns, shorter replacements, concurrent closes and a failed
ordinary output write. Exhaustive interruption/failpoint and whole-output rerun
evidence remains open. An interrupted clarification write can leave forms and
registry inconsistent; current strict input validation blocks that condition
rather than resetting state or inventing recovery authority.

Work:

- Render `spec.md` and required `reference-context.md` from validated typed
  data; implement editable-spec parsing and normalized round-trip checks.
- Assemble the required canonical reference/provenance/workflow state and
  feature-log evidence using existing path/identity owners.
- Publish only complete successful workflow output. Preserve the explicit
  clarification persistence exception and abandon unsuccessful candidates.
- Completely overwrite all registered replaceable workflow outputs at the same
  paths on success, including previously edited specs. Completely overwrite
  unresolved clarification forms on their publication branch at the same
  IDs/paths; never overwrite user-resolved forms. Apply the shared rule to every
  workflow execution, without append, merge, skip, suffix or extra approval.

Acceptance:

- [ ] The same accepted structured payload renders byte-stably. Different valid
  model-generated specifications are not required to be byte-identical.
- [ ] Required sidecar/state joins, round-trip checks and write authorization
  pass before publication; failed runs do not expose partial success.
- [ ] Rerun, interruption, write failure and protected-closure tests cover the
  whole output boundary without a transaction directory/WAL/checkpoint layer.
  Fail each publication write: already-replaced files may remain, but no new
  successful completion is recorded; a fresh rerun replaces all outputs.
- [ ] Specify and an unrelated registered workflow prove complete replacement,
  including unresolved forms and shorter output, while user-resolved forms
  remain byte-identical. Clarification pauses replace unresolved forms without
  exposing partial successful specification output.
- [ ] Configured `paths.specs` supplies the root; neither caller nor model
  repeats/hard-codes `specs/` or chooses artifact paths.

### H-011/H-012 implementation checks

- `zig build test-specification-generation --global-cache-dir .zig-cache/global --summary all`
  — 52 tests passed (projection, exact/passive values and generation contracts).
- `zig build verify --global-cache-dir .zig-cache/global --summary all`
  — 104/104 steps and 898/898 tests passed, including lint, architecture and
  packaged execution checks. Two fake-provider knowledge-gap scenarios persist
  forms without a spec; filesystem tests exercise all three clarification stages.
- `git diff --check` — passed.

These checks verify the implemented increment, not all unchecked acceptance
criteria or live/human evaluation. H-011/H-012 remain partial.

## H-013 — Supply the executable Spec workflow definition

**Status:** Open. **Owner:** ordinary YAML workflow/resources.
**Dependencies:** H-008–H-012 for referenced contracts; definition drafting can
track implementation. H-007 fixes the production projection contract.

Work:

- Create a complete `spec.workflow.yaml` using registered operations, explicit
  model slots, concise resource aliases, typed outcomes and bounded retries.
- Include required invocation, reference, generation, validation, clarification,
  rendering and publication paths. No placeholders or disconnected steps.
- Run it through the normal compiler/registry/runner; the harness supplies it
  under the temporary project's configured `paths.workflows` root.

Acceptance:

- [ ] Happy and non-success paths execute through production bindings with fakes
  before live calls; no special `specify` or `wf-001` engine dispatch is added.
- [ ] The compiler rejects skipped gates, undeclared inputs/resources, missing
  outcomes and unbounded loops.
- [ ] Prompt/schema content has one workflow resource owner, not repeated
  boilerplate or hidden engine defaults.
- [ ] Packaged execution works without loading workflows/resources from `design/`
  or another source-tree fallback.
