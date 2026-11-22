# PLAN01 — Plan workflow intent and feasibility

The Plan workflow's intent, a feasibility assessment of building it on the current engine, the
decisions it needs and the phases that would deliver it ([convention](README.md)).
[ADR 0034](../design/decisions/0034-spec-quality-gate.md) "What waits" governs when Plan work
starts; [SPEC01](SPEC01.md) §1 records the gate's status. This record is research: it amends no
contract, and no **Recommended** item below is a decision.

## 1. Intent

> A supported technical approach that satisfies the specification and applicable project
> constraints.

[intent.md](../design/intent.md):35. The statement orients judgment and isn't contract
authority (intent.md:3-9).

**Owners:**

- **Stage design:** design.md §18 and [18-plan.md](../design/contracts/18-plan.md), as amended
  by the accepted ADRs (design.md §32); **Proposed design**.
- **Model and engine split:** design.md §4 (design.md:261-263, 267, 271-272) and
  [21-validation.md](../design/contracts/21-validation.md) §21.3's semantic remainders and
  §21.6 (21-validation.md:121).
- **Delivery:** design.md §30 Increment 3 (design.md:732-742). Its only exit rule is that an
  increment "must be usable with a fake `LLMProviderInterface` before integrating a real
  provider" (design.md:765).
- **Acceptance:** design.md §31, written for the whole engine. Criteria 9, 10, 13, 19, 20, 22,
  23 and 38 name Plan's work (design.md:876-886, :937-938, :962-985, :992-1005, :1089-1092).

## 2. Verdict (22 November 2026)

**Feasible on the current engine, not as §18 stands.**

- **The generic engine takes a second workflow (§3).**
  - Selection, compilation and the runner don't branch on workflow names: the first argument
    names the workflow, and several definitions already run side by side.
  - Shared code already names Plan in four places: the authority registry makes it the owner
    of `design_decision` and `policy_predicate`, clarification IDs and allocation handle `PNN`,
    the request-owner unions declare `plan_unit`, and log events carry a `plan` stage.
  - The request step, repairs, ID restrictions, model slots and the output writer are generic
    too.
  - Below selection it isn't: the data keys, the operation, error and diagnostic sets and the
    outcome association hold only Spec's members, and Spec's field names sit at the model
    boundary. Each changes for a second workflow (§4).
- **Most of what §18 needs doesn't exist.** The engine can't yet:
  - see the target project: discovery, file kinds, path policy, commands (§4);
  - start from a feature directory alone, or publish under any policy but Spec's (§4);
  - read a published `spec.md` in a later invocation;
  - record an approval or authenticate a user.
  - No Plan workflow definition, prompt or schema exists (§4).
  - The §13 catalogue lists every Plan action only as "Proposed, no code" (13-01:442-512,
    13-02:135-151, 13-05:356-518, 13-06:17-35), to be rewritten when Plan design starts
    (design.md:407-409).
- **The design has open conflicts (§5).** Eight decisions block design. They include whether
  plan output gets a model review, how approval happens, whether Plan runs commands and which
  existing files the model sees.
- **Much of the plan could be computed (§6, recommended).** Repository facts, IDs, paths, the
  rows of coverage and quickstart, `data-model.md` applicability and every restated requirement
  could be engine-built, leaving the model the design choices, their rationale and the
  verification methods.
- **Size.** The Spec stage is 17,370 of the engine's 69,913 production Zig lines (22 November
  2026): 7,949 on the generation side (domain, action and application files named for
  specification or specify), 9,140 on the reference side (named for reference or source) and
  281 named for both. The count covers `src/**/*.zig` without `*_test.zig`, `*_test_fixture.zig`
  or `test_fixtures/`, inline tests included; another filter gives a somewhat different figure.
  Plan has no reference side, but needs discovery, file and path policy and its renderers, which
  Spec never had. §4 gives what one new operation costs in shared code. No estimate beyond that
  is made.
- **No way to judge Plan output exists (§8).** There is no Plan case, rubric, report or
  adjudication, and neither development case has a project for Plan to plan against.
- **It can be delivered in phases that are each proven offline (§9, recommended).** Phases 1
  to 6 make no model call, Phases 7 to 9 use a scripted transport, and Phase 10 is the first
  live set.

## 3. What exists and is reusable

| Mechanism | State | Evidence |
| --- | --- | --- |
| Multi-workflow selection, compiler, runner | Generic | `src/actions/workflow/parse_workflow_invocation.zig:14-21`; `test/integration/workflow_tests.zig`, test "unrelated workflows do not load toolchain documents even with a toolchain workflow installed"; no `spec-generation` literal outside tests (one inline test, `src/domain/llm_provider_identity.zig:81`); the definition schema holds no Spec member (`design/schemas/workflow-definition-v1.schema.json`) |
| One `request-model` step per model request (E1) | Generic | Later workflow files copy no request subgraph (ADR 0030:397-398) |
| Model slots | Generic: open configured keys | 09-configuration.md:71, :85-86; the case configuration already holds `design_section_generation` and `implementation` (`test/e2e/wf-001-hello-world/.sddtoolkit.json:10-21`) |
| Integer-choice and exact-member restrictions | Generic; Spec and reference users; a choice set holds at most 1,024 members | 12-model-boundary.md:100, :133, :162 (ADR 0046; ADR 0006); `src/domain/model_result_schema.zig` |
| Generic repair operations and contract variants (E4) | Generic; 12 Specify owners, 28 variants | ADR 0033:106; `src/domain/repair_owner.zig:72-85`. A new owner adds its binding, one `RepairOwner` member with an arm in each owner switch (`repair_owner.zig:104-148`), an arm and a `frozen` row for each generic operation it joins, and its YAML steps (Z_SPEC01 E4; `src/repair_operations_test.zig:215`) |
| Stage actions (E2) | Generic; four Spec stage actions; side effects `none` or `filesystem_read` only | ADR 0031:3-7, :141-143 |
| Required-authority ledger, reconcile, routing, gate | Generic; Plan owns `design_decision` and `policy_predicate`; no Plan seed producer | `src/domain/required_authority.zig:16`, `:59-61`, `:352-356`; seeds only `specification_authority.zig`, `source_preservation.zig` |
| Clarification registry, `PNN` IDs, forms, refresh | Generic for S/P/T; an invalid closed form blocks before any model call (E7 Stage 1); answers rejected for every stage; progress ignores the stage (§4) | `src/domain/clarification_inputs.zig:16`; `src/domain/clarification_refresh.zig:54-59`, `:64-66`, `:105-113`; SPEC01 §5 E7 |
| Toolchain capture and registered policies | Generic; two policies, naming rules only | `src/composition/toolchain_policy_registry.zig:6-22`; `src/domain/toolchain.zig:40-46` |
| Workspace filesystem policy | Resolved at startup | `runInProjectWithRegistry` in `src/composition/root.zig`; `src/adapters/filesystem/workspace_path_policy.zig:1` |
| Principle capture | Generic, persisted, read by the Spec records request only (Z_SPEC01 Q17); bounded by engine constants | `spec.workflow.yaml` step `principles`; 09-configuration.md:337; 13-01:430-432 |
| `spec.md` codec | Renders and parses; used only in Spec publication, on a document projected from run values (PD4) | `src/domain/specification_markdown.zig:14`, `:101`; `validate_specification_rendering.zig:13-20`; `project_specification_document.zig:9` |
| Stored Spec state readback | Validates from the state file, the installed definitions and the Unicode normalizer, with no model request; keeps the reference directory | `specification_state.zig:45-72`, `:74-79`; `src/domain/workflow_registry.zig:28-32`; `src/domain/reference_snapshot.zig:10`; 24-workflow-state.md:64-65 |
| Input stage | Thirteen typed steps; ten read no reference argument | `src/actions/specify/prepare_inputs.zig:154-157`; the three reference steps, `:172-184` |
| Output writer | Generic `publish-workflow-output`: the whole set is validated first, its read preconditions are rechecked before each replacement, and completion state is written last | `src/domain/workflow_output.zig:9-16`, `:33-45`; `src/adapters/filesystem/workflow_output.zig:40-83`; 25-publication.md:28-31, :42 |
| Bounded no-follow directory scan | Root-generic; two users; prunes nothing before descent | `src/adapters/filesystem/directory_inventory.zig:8-35`; users `src/adapters/filesystem/principle_source.zig:7`, `src/adapters/filesystem/reference_corpus_source.zig:42` |
| Request-owner and state ID types | Declared, with `plan_unit` in the owner unions; never built in production | `src/domain/model_request_identity.zig:15-19`, `:53-60`, `:67-88` |
| Log events and the request debugger | Generic; events carry a `plan` stage, and the debugger keys calls by lineage, not by workflow | `src/domain/telemetry.zig:156`; `src/debugger/app.js:6-14` |
| Offline proof of a workflow | Generic: the production composition with a scripted transport, fixture definitions with test operations, and request projection. Non-Spec definitions already run this way; none has model-backed operations of its own | `test/harness/integration/tests.zig`, test "an offline Spec run of each development case reaches publication through the production composition and the harness oracle"; `test/integration/workflow_tests.zig`, the `hello` definition and the `test.propose-extraction` operations; design/harness/e2e.md:741-775 |

## 4. What is missing

Each item has no code; the owner column names where its contract is.

| Missing | Owner | Note |
| --- | --- | --- |
| Repository discovery, project IDs, file registry, repository facts | §10.2, §18.2; 13-01:454-462, 13-06:17-20 | No adapter reads the target project, and no capability permits it (`src/domain/workflow_capability.zig:3-15`). The scan in §3 walks every directory, so a project with `node_modules` reaches its limits; §18.2 prunes before descent (18-plan.md:97-102) |
| File kinds, path-intent options, name transforms, candidates, file grants | §10.3, §11; 13-05:500-503, 13-06:28-35 | Not in the policies (§3), and §10's richer fields aren't accepted YAML (10-toolchain-presets.md:13-17); PD7 |
| Command registry | §10.4; 13-01:464-492 | 13 capabilities, none for processes (`workflow_capability.zig:3-15`); running a command is Implement's (13-07:67); PD14 |
| Plan's required-decision seeds | §18.1 (18-plan.md:30-31, :40-43) | Only Spec's projections produce seeds (§3), and principle prose is never compiled into a validator (09-configuration.md:341); PD12 |
| Reading the published `spec.md` in a later invocation and comparing it with stored state | §18.1, §23.1; 13-05:462-465 | The codec exists (§3), but no later invocation reads `spec.md`, and a Spec rerun overwrites it unread (`src/adapters/filesystem/workflow_output.zig:83`; 23-rendering.md:239-240) |
| Authentication chain and actor-evidence registry | ADR 0025; 13-05:356-448 | Not built (SPEC01 §5 E7); ADR 0025 covers Spec answers only |
| Review, approval and review-decision records | §14.5, §24.5; 13-05:510-518 | No approval type or state |
| Multi-stage workflow state | §24.1; 13-02:140-151 | One `workflow.json` typed as Spec state, stages `specified` and `spec_clarification_pending` only (`src/domain/specification_state.zig:8`, `:54`) |
| Plan entry gate | §14.2, §18.1 | `checkClarifications` checks open `S` only and serves Spec (`specification_state.zig:117-124`). The gate also recaptures the reference and routes a change back to Specify (18-plan.md:261-263, :268; 24-workflow-state.md:152) |
| Plan artifacts and their renderers | §18.5, §23 | Publication targets are Spec's four (`src/domain/workflow_output.zig:6`; `src/domain/workflow_artifact_registry.zig:14`) |
| Research evidence and dependency registries | §18.2 (18-plan.md:151-160); dependencies, 12-model-boundary.md:183-187 | No configuration member (09-configuration.md:57-62) |
| AST parsing and import resolution | §10.5; 18-plan.md:90 | Parser and tree-sitter libraries are a deferred choice (design.md:1189), and a production dependency needs an accepted ADR (AGENTS.md "Zig implementation expectations"); PD7 |
| Plan workflow definition, prompts, schemas and contexts | ADR 0003; ADR 0034 "What waits" | `design/workflows/` holds Spec's only, and none is written before the gate (0034:32-36) |
| Plan invocation contract | §18.1 (18-plan.md:8-11); ADR 0010 | §18.1 names only the feature directory. The registered contracts take a feature and a reference (`specify-invocation`, `src/application/specify_invocation_runner.zig:47-53`; `parse-specify-invocation`, `src/actions/specify/parse_specify_invocation.zig:7`; `src/composition/native_workflow_operations.zig:65-66`) or nothing (`core.empty-invocation`, `src/composition/core_workflow_operations.zig:5`). The stored snapshot keeps the reference directory (§3), where a feature-only contract can read it |

**Shared code closed to Spec today.** A second workflow extends these, so each is a shared-code
change, not a Plan-local one:

| Closed set | Where | A second workflow adds |
| --- | --- | --- |
| Data keys | `src/domain/pipeline.zig:4`; one closed enum by decision (SPEC01 §8, C20) | Its keys |
| Native operations with their ports, bindings and data schemas | `src/composition/native_workflow_operations.zig:61-172`, `:182`, `:330-358`, `:361`; `Runtime`'s wiring in `src/composition/root.zig` | A field and an initializer for each operation, its ports and its schemas: about 8 production files for one operation with one new key (SPEC01 §10.3 C22) |
| Operation errors | `src/domain/operation_error.zig:56-96` | Its error sets |
| Validation diagnostics and repair observations | `src/domain/candidate_validation_diagnostic.zig:9-17`; readers `src/application/candidate_validation_diagnostics.zig:6-59`, `src/application/candidate_repair_observations.zig:8` | A variant and a probe for each validator. Until then a Plan validator's rejection emits no `validation.failed` event (`src/application/workflow_pipeline_runner.zig:823-830`) |
| Outcome association | `src/domain/workflow_outcome_association.zig:274-283`; `src/application/workflow_outcome_binding.zig:199-214` | Readers for its units' routes, and publication permission, which only a clarification subject has |
| Text fields at the model boundary | The 32-tag `text_field_policy.Field` (SPEC01 §10.3 C23) | One enum per owner, built with Plan's first text field (C23, deferred 21 November 2026) |
| Packet guidance | One closed `packet-guidance/v7` whose keys are native enums (ADR 0016:137-143); v8 is decided and unbuilt (SPEC01 §4 Q26) | Its keys |
| Repair owners | `src/domain/repair_owner.zig:72-85`; `src/application/repair_workflow.zig:172-256` | §3 |
| Invocation and inputs | `prepare-inputs` requires the Spec invocation and is the only producer of the feature directory, artifact paths and clarification inputs (`src/actions/specify/prepare_inputs.zig:87-93`), which feature logging requires (`src/application/feature_logging_workflow.zig:16`) | A feature-only invocation and producer (§3) |
| State capture and parser | One `workflow_state` read, bounded by Spec's limit (`src/adapters/filesystem/feature_input_source.zig:33`); the parser accepts two Spec stages (`specification_state.zig:54`) | Its own state read. PD6's recommendation leaves Spec's parser unchanged |
| Publication targets | `src/domain/workflow_output.zig:6`, `:34`; `src/domain/workflow_artifact_registry.zig:14`, `:42-50` | Its artifacts and paths |
| Policy profiles and capabilities | Only `core.specification-output@1` permits `feature-output-write` (`native_workflow_operations.zig:362-365`); a capability derives from a port type through one closed table (`src/application/workflow_operation_binding.zig:73-99`) | A profile and a project-read capability |
| Clarification progress | Reports `needs_user` for an open record of any stage (`clarification_refresh.zig:54-59`). Spec routes that to its pending publication (`design/workflows/spec.workflow.yaml:820-822`), which collects only open `S` records and rejects an empty set (`src/domain/incomplete_specification.zig:26`, `:46`). So with an open `PNN` and no open `S`, a Spec rerun ends `failed` (`spec.workflow.yaml:935-937`), although only an open `S` stops Spec completing (`specification_state.zig:117-124`) and a reference change returns through Specify (18-plan.md:268) | Progress scoped by stage (§9 Phase 1) |
| Feature log retention | A run validates and prunes the feature's prior-run segments by the identity recorded in them, and invalid history blocks it (ADR 0026:60-83; 26-security.md:243-245). Every run so far found only Spec's | A Plan run beside Spec's logs, and a Spec rerun beside Plan's; neither is exercised (§9 Phases 2 and 6) |
| Reserved names | `core.safety@1` reserves Spec's four artifact names (`toolchain_policy_registry.zig:13-16`) | Plan's artifact names |
| Architecture rules | In `src/architecture_test.zig`: stage-module prefixes and their recorded importers (`spec_stage_prefixes`, `generic_importers_of_spec_stages`); the child-bindings list (`child_bindings_files`); a test for each stage action ("the prepare-inputs stage action obeys ADR 0031's stage rules" and its siblings); the toolchain's two readers ("the valid toolchain has one producer and is required only by the two stages that read the toolchain") | Its prefixes and rules; a third toolchain reader (PD7) |
| Packaged smoke test | Installs and runs the Spec definition (`test/packaging/smoke.zig:324-342`) | The Plan definition |
| E2E harness and live-step lists | §8 | §8 |

## 5. Decisions Plan needs

**Blocking: settle before Plan design.**

- **PD1. Model review of plan output.**
  - §18 has one: 18-plan.md:289 and :307. §12.6 offers a generic model operation "if desired"
    (12-model-boundary.md:350-351), and §21.6 lists the judgments that stay model-assisted or
    human-reviewed (21-validation.md:113-126).
  - ADR 0023 removed post-generation review for Spec and says "no other review policy
    exists" (0023:46, :60-62).
  - The 26 October source review caught 1 of 28 defects (Z_SPEC01 "Decisions that changed
    nothing", Link checks).
  - §18's semantic-review wording stays until the gate, because ADR 0034 bars Plan-specific
    design edits (0034:32-36), so it changes only with the ADR that records PD1.
  - **Recommended:** no model review; the semantic remainders rest on the user at plan review
    and on adjudication, as Spec's rest on the reviewer of `spec.md` (ADR 0023:36-40). PD16
    makes deterministic the applicability choice §18.5's review would challenge. Amends
    18-plan.md:289 and :307.
- **PD2. How approval happens.**
  - The review operation "waits" (14-orchestration.md:168-169).
  - But publication ends the run (25-publication.md:35-36; ADR 0018:74-75) with `ok` or
    `needs_user` as its only outcomes (25-publication.md:37-38), and `needs_user` saves no
    continuation (ADR 0009:74). In non-interactive use approval arrives through "an explicit
    API/CLI approval event or a deliberately selected policy profile" (14-orchestration.md:185).
  - No invocation carries an approval, and `plan_review_pending` appears only at
    18-plan.md:345 and :363. §18.7 calls `plan` complete only once the plan state has explicit
    approval (18-plan.md:351, :362).
  - A rerun of the Plan graph regenerates the plan under a new state ID (25-publication.md:53-54;
    18-plan.md:349), and an approval binds to the exact current one (24-workflow-state.md:132),
    so a rerun can't carry an approval.
  - The Tasks gate is a plan approval's first reader (19-tasks.md:8-9; 24-workflow-state.md:132);
    Implement needs it too (invariant 17, design.md:159).
  - **Recommended:** a Plan run publishes and ends at `plan_review_pending` with the outcome
    `ok`; `needs_user` stays the clarification pause (`src/main.zig:35-42`), and "complete" in
    §18.7 describes the stage, not the run. Approval or rejection is a later invocation of a
    separate workflow definition, built with Tasks together with the blocking Tasks gate. Plan's
    first slice then needs no review records, review units or authentication. Moves plan review
    and the Tasks gate from Increment 3 to Increment 4 (design.md:742, :744-749), and amends
    18-plan.md:351-363.
- **PD4. Edited `spec.md`.**
  - §18.1 reads an edit back as authority (18-plan.md:52-79; 24-workflow-state.md:153).
  - A Spec rerun overwrites it (§4), so no edit becomes authority anywhere yet, although
    invariant 16 makes `spec.md` the one editable stage artifact (design.md:158).
  - `spec.md` also prints engine-derived lines, a record's source and related-statement lines,
    which readback compares with what the projection derives (23-rendering.md:152-165).
    **Recommended** when the edit path is built: an edit to such a line is regenerated, never a
    block. SPEC01's Q13 held that as D13.7; the item closed on 22 November 2026 and its record
    is in git history, so it is not cited here as a decision.
  - §18.1 also requires `reference-context.md` (18-plan.md:22), a generated view that renders
    from stored state alone (`src/actions/reference/render_reference_context.zig:5`). A modified
    generated view is `GENERATED_VIEW_MODIFIED` and is never imported (23-rendering.md:203-212),
    and a run replaces only its own workflow's outputs (23-rendering.md:314), so Plan can't
    regenerate it.
  - **Recommended for a first slice:** Plan accepts only an unedited `spec.md`, the "equal
    content" branch (18-plan.md:56-57), and blocks on any edit.
    - The check is byte equality between `spec.md` and a fresh render of the validated stored
      specification through the existing codec (`specification_markdown.zig:14`); it needs no
      parse and is stricter than parsing and comparing. `reference-context.md` takes the same
      check.
    - A renderer change between the two runs also reads as an edit and blocks until Spec reruns
      (PD13's renderer version).
    - The reread before publication (18-plan.md:332-336) is the output writer's read
      precondition on the bytes the gate captured (§3), not a second parse.
    - Any Spec stage but `specified` blocks, which covers ADR 0041's `spec_incomplete` if it is
      built (24-workflow-state.md:81-87).

    That defers the edit path, its change sets and its authentication. The trade-off: a user
    who edits `spec.md`, as invariant 16 invites, is stopped at Plan, and the only way past is
    a Spec rerun, which overwrites the edit (23-rendering.md:239-240). Amends 18-plan.md:21,
    :52-79 and :332-333, 23-rendering.md:104-105, 24-workflow-state.md:125 and
    14-orchestration.md:125; replaces the typed comparison §13 proposes (13-05:462-465); and
    defers invariant 16's edits and criterion 20's round trip (design.md:979-982).
  - **What the render needs.** No code renders `spec.md` from stored state: the document is
    projected from run values (`project_specification_document.zig:9`;
    `specification_projection.zig:222`). The stored snapshot keeps the same inputs, reference
    records and passive records (`reference_snapshot.zig:8-18`; `reference_support.zig:25-31`),
    but not the token grammar that the projection's passive registry carries
    (`src/domain/passive_literals.zig:22-23`). The stored-state projection is new code at that
    owner, with its tests.
- **PD5. What a `PNN` pause persists.**
  - §18.4 publishes a successor input state and ID ledger (18-plan.md:252-257) and enters
    `plan_clarification_pending` (24-workflow-state.md:92-94; 12-model-boundary.md:531-533).
  - The accepted persistence exception covers clarifications and Spec's pending set only (ADR
    0009:67-69; ADR 0017), and "Nothing from the paused execution is reused"
    (24-workflow-state.md:99).
  - The pause ledger guards IDs that reach no authority: a `PNN` can't cite uncommitted
    records (18-plan.md:258-259). Spec's pending state carries its ID ledger because it
    replaces the state that held the ledger (ADR 0017:32-33, :48-50).
  - `clarifications.json` is one registry across executions (24-workflow-state.md:114-115)
    that both workflows publish. A run rewrites only its own workflow's unresolved forms
    (23-rendering.md:260-262).
  - **Recommended:** forms and `clarifications.json` only; Plan is pending while a `P` record
    is open, and no state is written. A plan published earlier stays on disk with its state
    through the pause; the open `P` record is what stops Tasks and approval
    (24-workflow-state.md:105-108). The alternative writes a pending Plan state last, as Spec's
    pause does to revoke its completion (ADR 0017:32-33); that state would have to carry Plan's
    ledgers. Amends 18-plan.md:252-257,
    24-workflow-state.md:92-94 and 12-model-boundary.md:531-533.
- **PD6. State layout.**
  - One `workflow.json` per feature (24-workflow-state.md:15-20) is typed as Spec state today.
  - The specification Plan compared against is stored in `PlanState` according to
    14-orchestration.md:127 and 23-rendering.md:199-200, but in `PlanInputAuthorityState`
    according to 18-plan.md:338-342 and 19-tasks.md:9-10 and :13.
  - The repository-fact registry splits the same way: `PlanInputAuthorityState`
    (18-plan.md:127-129) against `PlanState` (20-implement.md:31).
  - The split lets a pause publish input authority (18-plan.md:252-253), which PD5 removes, and
    gives plan-unit requests an owner before any `PlanState` exists
    (`model_request_identity.zig:53-56`), which an execution-local identity also gives
    (13-01:508-510).
  - §18 adds about ten persisted registries and states (18-plan.md:113-131, :207, :242-244,
    :297; 24-workflow-state.md:173; 13-05:392-393). No version migrates
    (24-workflow-state.md:42-43), and Spec's one state contract moved seven times in two weeks,
    v21 to v28 (ADR 0041:5-17; ADR 0023:164-173); a persisted shape that embeds another
    contract's goes stale with it.
  - **Recommended:** one Plan state document beside Spec's, with its own version, written last.
    - It holds what later gates and later plan revisions read: the specification it planned
      from, the captured principle registry (24-workflow-state.md:155; Spec's state holds its
      own, `specification_state.zig:21-23`), the gate-sensitive fact values, the file registry
      with its ordinals and retired IDs, the file grants, the plan records, the artifact
      decisions, its workflow ID (ADR 0003:114-115) and the plan ID ledger, so no retired ID is
      reused (18-plan.md:113-114, :238-244), as Spec persists its ledger
      (`specification_state.zig:18`).
    - Path candidates and review units are rebuilt each run.
    - Spec's state and parser stay unchanged, and a Spec rerun makes a plan stale by direct
      comparison, with no write to Plan's state. A revision number alone can't, because a
      recreated Spec state restarts at 1 (`specification_state.zig:110`).
    - The cost: the stale plan views stay on disk, unmarked, until Plan reruns, because a run
      replaces only its own workflow's outputs (23-rendering.md:314).

    Amends §24.1, which allows no other layout (24-workflow-state.md:8-10, :19-20);
    24-workflow-state.md:172-175 and 28-testing.md:187-190, which have the changing run write
    its descendants' invalidation; 18-plan.md:227-228 and :242-244 for the candidate and
    review-unit registries; and 18-plan.md:338-342 and 19-tasks.md:13 for the input and output
    split.
- **PD7. Where file kinds, path rules and commands live.**
  - §18 needs file kinds, roots, path-intent options, templates, transforms, commands and the
    raw-fallback switch, and §10's preset fields for them aren't accepted YAML (§4).
  - Under the implemented contract (10-toolchain-presets.md:13-17), package documents define
    no command, path, capability or safety exception, and YAML selects registered policy IDs
    only (F0003:200-201, :259-260). Two policies are registered, the locked `core.safety@1` and
    the selectable `project.zig@1` (`toolchain_policy_registry.zig:6-22`).
  - Without them no planned path can be validated, so the intent's "applicable project
    constraints" (intent.md:35) can't be checked.
  - Four things §10 and §11 require have no owner or conflict with §18:
    - environments and target platforms (09-configuration.md:176-180, :218-223; invariant 4,
      design.md:146), which no accepted schema carries;
    - the semantic name source a name transform consumes (10-toolchain-presets.md:160-163),
      which no section defines;
    - content-reference coverage: §10.5 disables a kind's `create` capability, or fails the
      preset, when a parser or scanner is missing (10-toolchain-presets.md:245-255), while §18
      records a missing parser as a fact (18-plan.md:90, :95) and leaves content checks to
      Implement (18-plan.md:309; 11-path-validation.md:29);
    - invariant 18 allows "a typed `fileId` or a planning-stage `ProjectPathCandidate`"
      (design.md:160), while §18.3 has the model return option, name-source and candidate IDs
      (11-path-validation.md:95).
  - **Recommended:** extend the registered policy descriptors (§3) with typed file kinds, roots,
    placement and command descriptors, selected by policy ID from `toolchain.yaml` as today.
    That adds no YAML schema or merge rule, and the project still supplies no code or
    capability (AGENTS.md:11-12). The cost: a new stack is an engine change, and the development
    cases' stack is the first (§8). The raw fallback stays off, as the hardened default sets it
    (18-plan.md:211-214). For the first slice:
    - one environment, the project root, under the workspace policy startup already resolves
      (§3); a project that needs more blocks with its reason;
    - name sources are typed values the run already holds, the feature ID and the
      specification's entity names; a wider source is decided on a measured set;
    - §10.5's coverage rule moves to Implement: Plan grants `create` from the kind's ceiling and
      registers each content check it can't run as an implementation validator;
    - the three IDs are read as invariant 18's planning-stage candidate reference, and a
      policy-defined command that configuration selects as invariant 13's "preset/config-defined"
      command (design.md:155). The ADR says so or amends the wording.

    Narrows the rule sources of §10.3-10.4 and 09-configuration.md:345-347 to engine policy,
    amends 10-toolchain-presets.md:245-255 for Plan, and for the slice reads invariant 4's
    configured environment as the project root, setting aside 09-configuration.md:176-180 and
    :218-223. `valid_toolchain` gains a third reader (F0003:30-32, :255-257; §4).
- **PD14. Whether Plan runs commands.**
  - §18.2 builds tool availability (18-plan.md:89-90, :95), and §10.4 exposes a command ID to a
    model only after sandbox validation and a probe, disabling an unsupported one with a reason
    (10-toolchain-presets.md:227, :230-231, :235).
  - No process capability exists (§4); Implement rechecks availability before it runs anything
    (20-implement.md:32).
  - **Recommended:** Plan runs no process. "Available" becomes "declared by the selected policy
    and supported by the manifest facts" (an npm script, or the package that provides the
    binary), and Implement proves it runs. Plan then needs no sandbox, process port or probe.
    The trade-off: a tool that is declared but not installed fails at Implement's gate, after
    both approvals, where §10.4's probe would disable it before a model sees its command ID.
    Amends 10-toolchain-presets.md:230-231 and :235 for Plan, and the meaning of "available"
    in 18-plan.md:318-319, 21-validation.md:83 and design.md:261.
- **PD15. Which existing files the model sees.**
  - §18.2 builds "current files near requirement-relevant terms" (18-plan.md:91). Matching
    specification words against file names is a word-list heuristic over prose, which AGENTS.md
    "Model output, prompts and evidence" forbids, and as a filter it can hide a file the plan
    needs.
  - §12 sends no "raw whole-repository listings" (12-model-boundary.md:189) and rejects a
    choice set above 1,024 members before the request (12-model-boundary.md:162).
  - Nothing states discovery's rule for a symlink inside the project or a file that matches no
    kind, and 09-configuration.md:232 rejects an absent discovery limit that the closed
    configuration has no member for (09-configuration.md:57-62). §26 treats only model and
    reference content as untrusted data and redacts only the run's own credentials
    (26-security.md:8-15, :139-144).
  - **Recommended:** send the complete typed file registry of the selected project's source and
    test roots (file IDs, normalized paths, kinds), with protected, generated and dependency
    roots pruned before descent; the model selects files by ID. The decision includes:
    - reading 12-model-boundary.md:189 as not covering that registry, which is typed and
      limited to those roots;
    - no file body in any request: facts carry dependency names and versions and script names.
      §26 then needs no new rule for secrets in project files, and its untrusted-data rule
      extends to the paths and names that are sent. A plan that depends on what an existing
      file contains is beyond the slice;
    - a symlink is never followed, and it and a file of no kind are recorded as rejections and
      left out (18-plan.md:103-104);
    - discovery's limits are engine constants, as principle capture's are (§3);
    - a registry over the 1,024 bound blocks with its reason, and a provider size failure
      follows the workflow's outcome transitions, as for principles (09-configuration.md:337).

    For the development cases it is a few files. Amends 18-plan.md:91 and
    09-configuration.md:232, and fixes the reading of 12-model-boundary.md:189.

**Settle with E7.**

- **PD3. Who authenticates.**
  - Spec edits, `PNN` answers and review decisions all need an authenticated actor
    (18-plan.md:63-67, :269-270; 14-orchestration.md:173-176).
  - ADR 0025 covers Spec answers only (0025:14-15, :180-181), and nothing says how the
    `specification_edit` lease is issued.
  - The authentication chain isn't built, and SPEC01 §5 E7 records recommendations for it,
    none decided.
  - With PD2 and PD4, only `PNN` answers remain in the first slice. Like Spec's, they wait for
    E7 (§7); until then a `PNN` closes only through authority resolution (18-plan.md:269-270).
  - **Recommended:** extend ADR 0025 Decision 1, where the invoking account is the actor, to
    `PNN` answers with E7, and to review decisions when approval is built.

**Settle during Plan design.**

- **PD8. Principles.**
  - 18-plan.md:128-129 says "principle selection" and :152 "selected".
  - ADR 0015:25-26 says any filter needs its own decision, and 09-configuration.md:336-337
    sends every chunk, untruncated.
  - The case principles are 28,067 and 29,399 bytes (each case's `principles/*.md`;
    hello-world's sit under `node-vitest/`), and carrying them added about 5.5k to 6k tokens to
    Spec's records request (Z_SPEC01 Q17).
  - The budget is one total for an execution (ADR 0037:52), 125,000 tokens in the case
    configuration (`test/e2e/wf-001-hello-world/.sddtoolkit.json:6`), so about 20 carrying
    requests use it all before any other input or output. The closing set's whole Spec runs
    used 18.7k to 24.1k tokens (Z_SPEC01 "Closing set"); the twelve runs retained from 22
    November 2026 used 38,397 to 106,828 (`evaluations/e2e/2026-11-22T*/measures.json`,
    `actual_tokens`).
  - **Recommended:** every chunk, to every Plan model request. That holds only while the
    request count stays well under that bound, so it is settled with PD18's split. The
    measured sets report the tokens, and a narrower per-step binding is decided only on a
    measured set. Amends the "selection" wording of 18-plan.md:128-129 and :152.
  - **Open since Spec began carrying principles (Z_SPEC01 Q17):** is a specification generated
    under an older principle registry stale at Plan's gate? Spec's records request reads the
    principles, and Spec state stores the registry it captured
    (`specification_state.zig:21-23`). The design says a changed registry invalidates plan and
    task approvals and doesn't regenerate unchanged business content (09-configuration.md:368-370;
    24-workflow-state.md:155). **Recommended:** not stale. Plan recaptures the registry and
    judges current policy itself (18-plan.md:32-35).
- **PD9. External evidence and dependencies.**
  - Missing research evidence blocks the stage (18-plan.md:156-157), but the same gap routes
    to `PNN` by the shared reconciliation (:184-191).
  - No configuration owns registry adapters, and without one a new dependency's package,
    version and source can't be validated (18-plan.md:173, :314).
  - **Recommended for a first slice:** no adapters and no dependency proposals; an evidence gap
    or a needed dependency blocks with its reason. Each case's project holds only its stack
    (§8), so a story that needs more blocks. Amends 18-plan.md:151-160, :173 and :314 for the
    first slice.
- **PD10. Rejection.**
  - Regenerate the mapped units (18-plan.md:349), or the whole plan (design.md:742;
    25-publication.md:53-54)?
  - Mapping free-text feedback to units needs a model or a per-unit review form
    (14-orchestration.md:179-183).
  - **Recommended:** whole plan, from `start`, with the feedback as input, built with approval
    (PD2); it needs no `PlanReviewUnitRegistry`. It can change parts the user accepted; a
    per-unit review form is the alternative if that matters. Amends 18-plan.md:242-244 and :349,
    14-orchestration.md:179-183 and 23-rendering.md:213.
- **PD11. Startup or graph steps.**
  - Discovery and the command registry are bootstrap work in 10-toolchain-presets.md:130-132
    and :235, and principle capture in 09-configuration.md:358-360. ADR 0003 puts setup beyond
    the startup graph in the selected workflow's graph (ADR 0003:94-96), invariant 27 fixes
    startup at two routines (design.md:176-181), and principle capture is already a graph step
    (§3). F0003 leaves repository discovery and command authorization as separate work
    (F0003:7-8).
  - §14 names orchestrators for the stage gate, authority reconciliation and the clarification
    lifecycle (14-orchestration.md:119-131, :332-334). Spec runs the same work as YAML subgraphs
    (`spec.workflow.yaml`, `authority-gate` and `clarification-output`), as ADR 0005 requires of
    sequencing (ADR 0005:74-77).
  - §27 activates the feature log "after deterministic reference preflight"
    (27-observability.md:39-41), which Plan doesn't have.
  - **Recommended:** graph steps, each deterministic sequence one stage action (ADR 0031), as
    `prepare-toolchain` is; the gate, reconciliation and clarification work are YAML subgraphs,
    as Spec's are; and the feature log activates after the inputs stage and before the gate's
    checks, so a refused entry is logged. Amends 10-toolchain-presets.md:130-132 and :235,
    09-configuration.md:358-360 and 27-observability.md:39-41.
- **PD12. Validators, ledger and required decisions.**
  - §21.3 lists 12 Plan validators and §18.6 lists 24 checks; 21-validation.md:6 calls §21
    normative. Each of the twelve maps to one or more of the 24.
  - The obligation ledger is a Plan input (18-plan.md:25) but a Tasks deliverable
    (design.md:746; 19-tasks.md:20).
  - Nothing says which planning decisions are required (§4). Requiredness is closed: it comes
    "only from a versioned schema, compiler-locked ownership/reconciliation policy, accepted
    canonical record, or explicit obligation" (12-model-boundary.md:692-693).
  - **Recommended:** §18.6 is the complete list, and §21.3 keeps the semantic remainders.
    - The ledger is a function of the specification, built by each stage that needs it and
      persisted by none; Tasks adds the plan's entries (19-tasks.md:20-33).
    - Seeds come only from native projections, as Spec's do (`required_authority.zig:40-41`;
      invariant 19, design.md:161): one slot for each required field of a plan record's schema
      and for each specification obligation.
    - A need the model raises is admitted only as the clarification candidate of its unit's
      slot (18-plan.md:181-185); it never creates a slot, and a gap with no registered slot is
      an administrative block (`required_authority.zig:352-356`).
    - With no review (PD1), a gap becomes a `PNN` through a unit's own need or a descriptor
      question, which serves only a `missing` or `stale` gap (13-05:32-38).
    - Principle compliance stays a cited, model-assisted judgment (09-configuration.md:339)
      that adjudication scores.
    - A new requirement kind brings its schema, ownership entry, reconciliation policy,
      fixtures and stage-gate tests (12-model-boundary.md:747).

    Amends 18-plan.md:25, which makes the ledger a Plan input.
- **PD13. Shared items: upstream rework, repair owners and the renderer version.**
  - Upstream rework is settled, decided 15 November 2026: a gap an earlier stage owns takes
    §24.5's rework route and never becomes a form (Z_SPEC01 "Upstream rework";
    `required_authority.zig:352-356`), so a Spec-owned gap that Plan detects ends the Plan run
    for Spec rework.
  - Plan's repair owner enums are deferred to the gate (ADR 0033:375-376).
  - The renderer version isn't built: Spec state and views record none, and §23.1's version
    rules remain the target (23-rendering.md:47-51, :99-101). ADR 0036 changed the renderer
    without a version because "no Plan or Tasks review exists to renew" (ADR 0036:233-234),
    which stops holding once a plan is published for review.
  - **Recommended:** the renderer version is built with approval (PD2), as a new Plan state
    version; until then PD4's byte check blocks on any renderer change.
- **PD16. Artifact applicability.**
  - The model proposes applicability and a semantic review may challenge it
    (18-plan.md:285-289).
  - `data-model.md`: the specification already lists its entities (ADR 0038 Decision 6), and
    readback validates their membership (`specification_state.zig:89-93`).
    **Recommended:** required exactly when the specification has an entity, which the engine
    computes; the model writes the content. The artifact set then can't vary between runs on
    one specification. The trade-off: a feature whose state isn't a business entity gets
    `not_applicable`. Amends 18-plan.md:285 and :288-289 and the remainder at
    21-validation.md:62.
  - `contracts/`: whether a contract "adds planning value" (18-plan.md:286) is a judgment, and
    neither development case has an interface beyond console output. **Recommended for a first
    slice:** not produced. The disposition's engine reason says the slice produces no
    contracts, which is not a finding that the feature needs none (18-plan.md:290-291). The
    trade-off: a feature with an interface gets no contract view. Amends 18-plan.md:286 and
    :292-299 for the first slice.
- **PD18. The split between engine and model (§6).**
  - §18 leaves open how many quickstart scenarios there are (18-plan.md:317), makes coverage
    mappings and quickstart scenarios separate model units (:177-178), and lets the model
    restate requirement text.
  - The split also sets the request count, which PD8's principle cost multiplies. Of the twelve
    runs retained from 22 November 2026 (`zig-out/e2e-spec/2026-11-22T*`), the six loan-renewal
    specifications each hold five `AC` and one `UO`, with one to three `FR` and one to three
    `BR`; the six hello-world ones hold three `AC` and two or three `FR`. §18.6 covers business
    rules and visible states as well (18-plan.md:320-321), and the count varies between runs on
    one case.
  - **Recommended:** §6's split: one quickstart scenario per acceptance criterion and edge
    case; coverage and quickstart from one model answer per obligation, every row in one
    `exact_members` request; requirement text and the technical context rendered by the engine,
    never written by the model. A request per obligation is the smaller decision the intent
    proposes (intent.md:84-100) at that many times the context, and is decided only on a
    measured set. The decision includes:
    - a missing or repeated row is corrected by resending the whole answer and fails the run
      when the corrections are spent (ADR 0046:58-60, :92-93), so the publication rate per case
      is this split's guard;
    - an ID outside the offered set is rejected at admission (12-model-boundary.md:100-104), and
      Plan's repair owners serve only defects a schema can't state, where criterion 13 expects
      an atomic repair for every invalid selection (design.md:937-938);
    - a later unit receives earlier units only as typed selections and engine-rendered paths,
      never their prose (12-model-boundary.md:189);
    - path-intent requests carry option and candidate IDs with engine-rendered labels and no
      examples (12-model-boundary.md:336-337, against 11-path-validation.md:107);
    - a specification record printed in a plan view goes through `spec.md`'s renderer for that
      record, so its bytes match what the user reviewed (23-rendering.md:75-89 scopes the escape
      table to Spec's views);
    - Plan's prose fields are exact-copy `prohibited`, since requirement text is rendered by
      ID, and name a file only by its file ID (text-field-composition.md:41, :53-70;
      18-plan.md:229-230). C23's per-owner field enum carries those roles (§4), and
      28-testing.md:367 requires the rejected case of an unbound filename in plan prose.

    Amends 18-plan.md:177-178 and :317 and criterion 13 (design.md:937-938), applies ADR 0046's
    whole-answer correction where 12-model-boundary.md:342 bars a full-document retry, and adds
    the rendering rule.

**Settle before the first live Plan run:** PD17 (§8).

## 6. Recommended split between engine and model (not decided; PD18)

The operating rule is "if a validator can answer from typed data or executable evidence, do not
ask the LLM to answer it" (design.md:271). Applied to §18 with the mechanisms that exist:

| Plan content | Engine | Model | Mechanism |
| --- | --- | --- | --- |
| Feature, date, spec link, IDs, headings, status | All of it | Nothing | Invariant 14 (design.md:156); 18-plan.md:305 |
| Technical context: language, runtime, test runner, dependencies, scripts, roots | Rendered from repository and policy facts | Nothing; it cites fact IDs | design.md:261; 18-plan.md:137-140 |
| Existing files a change touches | The registry (PD15) | Selects file IDs | Integer-choice restriction (12-model-boundary.md:100) |
| New files | The path, from the policy's kind, root and placement (PD7) | An option and a name source, never a filename | 18-plan.md:197-209 |
| Coverage: one design and verification record per obligation | Rows listed from the specification's IDs | Each record's content | `exact_members` (12-model-boundary.md:133; ADR 0046): a missing or repeated row is rejected at admission |
| Quickstart scenarios | One per acceptance criterion and edge case, from the same records | Automated (test-file and command IDs) or manual steps | 18-plan.md:317-319 |
| Requirement text in plan views: criteria, exact copy, values | Rendered from the specification record by ID | Never restated | 18-plan.md:236-237, :322; ADR 0047; ADR 0038 Decision 7 |
| `data-model.md` applicability; `contracts/` | Computed (PD16) | The data model's content | ADR 0038 Decision 6 |
| Research decisions | IDs; fact and source links checked | Decision, rationale, alternatives | 18-plan.md:313 |
| Principle consideration | Chunk citations checked | Reasoning and any deviation | 09-configuration.md:339 |
| Approach, minimal change, task-generation approach | Nothing | All of it | 21-validation.md:121 |

- **Restated text is rendered, not generated.** A model that restates a requirement drops or
  weakens part of it, as Spec's edge-case outcomes did (ADR 0038:375-378; Z_SPEC01 "Next 8").
  The levers that held were engine-composed text (ADR 0047) and a link whose target's text is
  printed (ADR 0038 Decision 7). This is not the rejected lever, filling a record from its cited
  source lines (ADR 0038:389-391): Plan prints a linked specification record, never source
  lines.
- **Coverage and quickstart share one answer per obligation,** rendered twice, so they can't
  disagree and no obligation is asked twice.

## 7. Sequencing

What each engine-track item means for Plan; its status is its owner's.

- **E1 (ADR 0030; Z_SPEC01 E1).** Plan's model requests are `request-model` steps.
- **E4 (ADR 0033; Z_SPEC01 E4).** Plan's repairs join the four generic operations as owners
  and variants (ADR 0033:262-264); the Plan owner enums wait for the gate (:375-376).
- **E2 (ADR 0031).** Four stage actions are built, and every other Spec stage is still a run
  of single-step actions until its conversion lands (ADR 0031:3-7). Under PD11 Plan's
  deterministic sequences are stage actions from the start, so none waits for a conversion.
- **E7 (ADR 0025; SPEC01 §5 E7).** It gates `PNN` answers (PD3), not the first slice.
- **E0 (ADR 0041; SPEC01 §5 E0).** If it is built, `spec_incomplete` blocks Plan at its gate
  (PD4).
- **C23 (SPEC01 §10.3).** §9 places it in Phase 7, with Plan's first text field (§4).
- **C42 and C41 (SPEC01 §10.6).** Under §9 Plan's scripted scenarios run through
  `root.Runtime`, its development-case offline runs go through the harness's `invoke.run` as
  well, and a failed hook assertion fails its scenario.
- **Gate.** SPEC01 §1 holds the gate's evidence; the gate stays the user's to declare (ADR
  0034:67-69).
- Nothing in the engine track blocks Plan design; only the gate does.

## 8. Evaluation gap

- **The harness is Spec-only:**
  - case `spec-e2e-case/v3`, which requires a reference and Spec's four artifacts
    (`test/harness/e2e/contracts.zig:6`, `:15`, `:25-28`). The harness passes `--feature` and
    `--reference` (`test/harness/e2e/invoke.zig:61`), its oracle keeps the specification's bytes
    alone (`test/harness/e2e/oracle.zig:46`), and runs are retained under `zig-out/e2e-spec`
    (`test/harness/e2e/cli.zig:5`);
  - report `spec-e2e-report/v25` (`contracts.zig:224-225`): changing a closed member needs a
    new version (SPEC01 §2 rule 12), and earlier runs need their own build (SPEC01 §1, Retained
    runs). **Recommended:** a Plan report of its own, which leaves Spec's decoder unchanged;
  - adjudication `spec-adjudication-record/v1`, which yields `spec-adjudication/v3`
    (`test/harness/adjudication.zig:13`, `:19`);
  - the E2E gate's mechanics, an intact source and provenance join and zero measured admission
    escape (acceptance.md:52-54), which are Spec's;
  - measures, which read Spec's response shapes (`test/harness/e2e/measures.zig:27-49`), and
    stage measures, which count `plan_unit` as `other` (`test/harness/baseline/stages.zig:94`);
  - `e2e-call`, which reads a retained case through the Spec contract
    (`test/harness/call/capture.zig:38`);
  - the evaluation case `evaluation-case/v2`, whose required grading-qualification paths serve
    only the supplied-spec grader (`test/harness/contracts.zig:21-31`; acceptance.md:113-117,
    :144). **Recommended:** a Plan evaluation case names its sources and rubric only;
  - the evaluate-e2e and live-e2e skills, and AGENTS.md, which names only Spec's record,
    `adjudicate-spec` and "published specifications" (AGENTS.md:205-207, :324-325); a Plan
    record extends that policy text;
  - "Plan, Tasks and Implement need their own workflow cases" (design/harness/e2e.md:334).
- **Live steps are listed by name** in `build.zig:967` (the steps no automated step may reach),
  `.claude/settings.json:32-50`, `.claude/hooks/guard-bash.sh:57` and `:67-69`,
  `.claude/hooks/live-e2e-approval.py:24-25`, AGENTS.md:41-43 and CLAUDE.md "Live and billed
  steps". A Plan live step outside those lists runs without a prompt, because `Bash(zig *)` is
  allowed (`settings.json:10`). All but `build.zig` are policy files, changed only when the user
  asks (CLAUDE.md "Claude Code setup").
- **No project to plan against.** Hello-world's case sits under
  `test/e2e/wf-001-hello-world/node-vitest/`, with its rubric at `rubric/spec.json`;
  loan-renewal's is flat. Both select no preset and no policy (`principles/toolchain.yaml`:
  `presets: []`, `policies: []`) and install no project files, yet both cases' principles are
  written for a Node, TypeScript and Vitest project (`architecture.md:6`,
  `project-structure.md:36`). `design/toolchainPresets/node-vitest.yaml` is matching source
  material, never runtime configuration (10-toolchain-presets.md:10-11), and the only selectable
  registered policy is `project.zig@1` (PD7).
  - **Recommended:** one minimal project per case, with no feature code, as case principles never
    anticipate a story (AGENTS.md:317-318): `package.json` with TypeScript and Vitest dev
    dependencies and `build` and `test` scripts, `tsconfig.json`, an empty `src/`, and the
    registered policies for that stack (PD7). Plan then has real facts to select or misstate.
  - Spec must see the same toolchain as Plan. Spec's token grammar reads the compiled naming
    policy (`src/actions/reference/prepare_reference_tokens.zig:49`, `:83-84`), readback
    recomputes token classification (24-workflow-state.md:57-60), and Plan recaptures the
    reference and routes a change back to Specify (18-plan.md:261-263, :268). So the project and
    policies go into each development case for both workflows. For Spec that is an input
    change: it shares a build if the Spec guard (§9) shows its requests unchanged, and is kept
    or reverted like any other if not (SPEC01 §2). As Plan test input it waits for the gate
    (ADR 0034 "What waits").
- **PD17. Plan's input and acceptance bar.** A Plan run needs a published specification, and no
  state version migrates (PD6).
  - **Recommended:** a Plan run names a retained Spec run of the same build and case inputs
    whose adjudication passed, and copies its published feature directory and state; Plan's
    measurements then vary only with Plan. The copied input is a live production run's
    published output, so nothing scripted substitutes (AGENTS.md:322-323). The alternative,
    running Spec inside each Plan case, adds Spec's variance and cost to every Plan measurement.
  - That is pre-seeded feature output, which the Spec case contract rejects
    (design/harness/e2e.md:345-346); the Plan case contract admits exactly this input.
  - State lies outside the feature directory, under
    `<paths.workflows>/features/<featureId>/state/` (`workflow_artifact_registry.zig:46-47`),
    so the copy takes both roots, and the Spec run's logs with them, as a real project holds
    them (§4).
  - The Plan case also installs the Spec definition that published the run: reading stored
    Spec state resolves its extraction contract by workflow ID and rejects a missing or changed
    one (`specification_state.zig:74-79`; 24-workflow-state.md:24-27). Readback also rejects a
    state whose stored claim text predates the build's quote rules (Z_SPEC01 "Refactors that
    leave request bytes unchanged", B7), which is why the input run is of the same build.
  - SPEC01 §5 E7 recommends a fifth registered Spec output and case v4; if taken, the copy and
    the Plan case follow them.
  - **Recommended bar:** Plan's rubrics carry R8's, an 80% aggregate and 3/4 on each critical
    criterion (acceptance.md:9-13), with the adjudication classes below as the critical
    criteria. The bar is the user's to approve, as R8's was, and a rubric without a threshold
    stops the run before generation (design/harness/e2e.md:306-308).
- **Defect classes.** Plan has no published-output defect classes or rubric criteria; AGENTS.md
  requires both before a change can be judged. Candidates from the intent's measures
  (intent.md:159-162), by what catches them:
  - the engine, before publication, counted as rejected attempts: an unknown fact, file or
    command ID; an invalid path; a missing or repeated coverage row;
  - adjudication: a lost or weakened obligation in a design or verification record; an
    unsupported addition (a file, dependency, component or behaviour nothing requires); a
    principle violation, such as a database against loan-renewal's "In-memory only. Do not add
    databases or files." (`test/e2e/wf-002-loan-renewal/principles/architecture.md:31`); a prose
    claim about the project that its facts don't support; a verification that doesn't test its
    criterion.
- §9 Phase 9 builds what a live Plan run needs.

## 9. Phased rollout (recommended; not decided)

Only the user declares the ADR 0034 gate passed and actions Plan; nothing below starts before
that. Increment 3 (design.md:732-742) is Phases 1 to 8, less plan review and the Tasks gate,
which PD2 moves to Increment 4.

**Rules for every phase.**

- **One change set.** A phase lands alone under AGENTS.md "Before editing", "Validation" and
  "Definition of done", owner first and offline first (SPEC01 §2 rule 2). Its proof below is
  in addition to those rules.
- **Offline proof.** Every phase but the last is proven without a model call, as §30 requires
  of an increment (design.md:765). Unit tests sit at the owner. Scenarios run through the
  production composition, `root.Runtime`, with only the transport scripted, and a development
  case's offline run also goes through the harness's `invoke.run`, as Spec's does (§3; SPEC01
  §10.6 C42). A step the shipped Plan definition doesn't reach yet is driven by a fixture
  definition with test operations, as the reference fixtures are (§3).
- **Spec guard.** A phase that touches shared code or `spec.workflow.yaml` shows that a
  request-projection freeze taken before it equals one taken after (design/harness/e2e.md:741-775;
  SPEC01 §2 rule 10), and that the offline Spec run of each development case still publishes.
  A phase that can't show this changes Spec's model input and is a measured Spec change instead
  (SPEC01 §2).
- **Typed cases.** Proofs use typed accepted and rejected cases, never fixed model text
  (AGENTS.md "Testing expectations"), and cover both development cases and one unrelated domain
  wherever a rule reads specification content (SPEC01 §2 rule 2). Each new stage action gets its
  ADR 0031 rule in `src/architecture_test.zig` (§4), and each new test execution is registered
  (`zig build test-build-registration`).
- **What a proof shows.** Phases 1 to 9 show implementation complete and mechanical checks
  passed. Only Phase 10 says anything about output quality (AGENTS.md "Model output, prompts
  and evidence").

**Phase 0. Decisions and design.** No code.

- The user settles the blocking decisions: PD1, PD2, PD4 to PD7, PD14 and PD15. The others are
  settled as the design reaches them: PD9, PD11 to PD13, PD16, PD18 and PD8's staleness
  question with Phases 2 to 6; the rest of PD8 with Phase 7; PD17 with Phase 9; PD3 with E7;
  PD10 with approval.
- One ADR records them with the clauses each amends. The design rewrites Plan's §13 entries
  (design.md:407-409) and writes a Plan feature contract, as F0100 is Spec's.
- **Proof:** none of its own. Each clause is proven by the phase that builds it.

**Phase 1. Clarification progress by stage.** Shared code; no PD.

- **Delivers:** `check-clarification-progress` reports `needs_user` only for an open record of
  the stage its step names, so an open `PNN` no longer fails a Spec rerun (§4). It amends the
  operation's contract (13-05:59-63) and both of Spec's uses of it (`spec.workflow.yaml:821`,
  `:921`).
- **Proof:**
  - the progress rule over registries that mix open and closed `S`, `P` and `T` records;
  - a Spec rerun on a registry with an open `P01` and no open `S` publishes and keeps the open
    `P` record and its form;
  - a Spec rerun with an open `S01` still pauses;
  - the Spec guard.

**Phase 2. Plan entry.** Needs PD4, PD11, PD13 and PD8's staleness answer.

- **Delivers:**
  - a feature-only invocation contract and an inputs stage action, which reuses the ten
    `prepare-inputs` steps that read no reference argument (§3) and takes the reference
    directory from the stored snapshot;
  - the gate: Spec state `specified`, no open `S`, the recaptured reference equal to the
    snapshot's sources, and `spec.md` and `reference-context.md` byte-equal to a render from
    stored state, which needs the stored-state projection (PD4);
  - a Plan policy profile. Toolchain, naming-policy and principle capture reuse the registered
    operations.
- **Proof,** on a feature directory that the offline Spec run published:
  - accepted: the unedited directory passes with no provider request and no artifact, form or
    state written, and the feature log activates beside the Spec run's logs (§4);
  - rejected, each with its typed reason and no artifact, form or state written: one changed
    byte in `spec.md`; a changed `reference-context.md`; an open `S`; a pending Spec state; no
    state; a missing or changed Spec definition; a changed reference file; an invalid closed
    form;
  - for every publication in the scripted Spec matrix, the render from stored state equals the
    published bytes;
  - the Spec guard.

**Phase 3. Policy descriptors.** Needs PD7 and PD14.

- **Delivers:** typed file kinds, roots, placement options, name transforms and declared
  commands on the registered policy descriptors, and the policies for the development cases'
  stack (§8).
- **Proof:**
  - accepted and rejected descriptors, and fixed test vectors for each name transform
    (10-toolchain-presets.md:160-163);
  - path properties (invariants 2, 4 and 12): a normalized path normalizes to itself, a path
    maps to exactly one project and kind, and a case-fold collision or a non-portable name is
    rejected;
  - a candidate built from an option and a name source passes the same chain as an existing
    path;
  - the Spec guard: a project that selects no policy compiles the same naming policy.

**Phase 4. Project discovery, file registry and repository facts.** Needs PD15 and Phases 2
and 3.

- **Delivers:** a project-read capability, port and adapter that evaluates exclusions before
  descent; the file registry with kinds, IDs and retired IDs; manifest and policy facts with
  their gate policy.
- **Proof,** on fixture project trees:
  - a pruned root is never opened, and a tree over the limits is rejected whole;
  - a symlink and a file of no kind are recorded and left out, and every entry joins a file, a
    rejection or a prune record (18-plan.md:103-104);
  - the same tree gives byte-identical registries; with a prior registry, surviving paths keep
    their IDs and no retired ID returns;
  - a definition whose policy lacks the capability is rejected at compilation.

**Phase 5. Plan records, validation and views.** No model. Needs PD9, PD12, PD16 and PD18, and
Phase 4.

- **Delivers:** the plan record types and the plan ID ledger, the §18.6 checks the first slice
  keeps, artifact applicability, and the renderers of `plan.md`, `research.md`, `quickstart.md`
  and `data-model.md`.
- **Proof,** on typed plans built for each development case's offline Spec publication and for
  one unrelated domain:
  - each check has an accepted and a rejected plan: a missing or repeated coverage row; an
    unknown fact, file or command ID; a path outside its kind's root;
  - each view has golden bytes and renders identically twice (invariant 15; 28-testing.md:411);
  - requirement text in a view equals `spec.md`'s rendering of that record;
  - IDs are monotonic, and none is reused across a prior ledger.

**Phase 6. Plan state and publication.** Needs PD2, PD5 and PD6, and Phases 2 and 5.

- **Delivers:** the Plan state document and its parser; publication targets for the four views
  and the state, which is written last; read preconditions on the bytes the gate captured;
  staleness by direct comparison with Spec's state.
- **Proof:**
  - the state contract's accepted, rejected, unknown-field and version-mismatch fixtures;
  - a write that fails at each position records no completion, and `spec.md` changed after the
    gate rejects the publication with nothing written;
  - a fixture definition runs the gate, discovery, a typed plan, validation, rendering and
    publication, ends `ok` at `plan_review_pending`, and a rerun replaces every view;
  - a Spec rerun on that feature directory publishes beside Plan's logs and state, and the
    stored plan then reads as stale;
  - the Spec guard.

**Phase 7. Model units.** Needs PD1, PD8 and PD18, and Phase 6. Builds SPEC01 C23.

- **Delivers:** `plan.workflow.yaml` with its prompts, schemas, contexts and packet guidance;
  one `request-model` step per unit; admission through the integer-choice and `exact_members`
  restrictions; proposals materialized into plan records; Plan's repair owners and variants.
- **Order,** each unit landable alone: approach, research and principle consideration (Plan's
  first text fields, so C23's per-owner field enum lands here); touched files and new-file
  intents; coverage and quickstart; the data model.
- **Proof:**
  - for each unit, a scripted answer is admitted and reaches the next step, and a rejected one
    (an unknown ID, a missing or repeated member, a filename where an option is asked) takes
    its correction or repair, or fails at the retry limit with nothing published;
  - an offline Plan run on each development case's offline Spec publication ends at
    `plan_review_pending`;
  - the request projection records Plan's requests from here on, with the request count PD8
    depends on;
  - the Spec guard, which covers C23: each Spec field serialises under the same name.

**Phase 8. Required decisions and `PNN` forms.** Needs PD5 and PD12, and Phases 1 and 7.

- **Delivers:** Plan's seed producer, the shared reconciliation and gate for its slots, a
  unit's clarification need as a `PNN` need, and the pause output of forms and
  `clarifications.json`.
- **Proof:**
  - a unit that returns a need ends the run `needs_user` with `P01` and the registry written
    and no plan view or state;
  - a rerun with it open asks under the same ID, and an authority resolution closes it;
  - a need with no registered slot blocks administratively, and a Spec-owned gap ends the run
    for Spec rework with no form (PD13);
  - a submitted answer is rejected until E7.

**Phase 9. Evaluation harness.** Needs PD17. Its offline run needs Phase 8.

- **Delivers:** the project and policy selection in both development cases; a Plan case,
  report, measures and adjudication record with their build steps; Plan rubrics; Plan support in
  the evaluate-e2e skill; the live-step lists (§8).
- **Proof:**
  - the contracts' accepted, rejected, unknown-field and version-mismatch fixtures;
  - an offline harness run of each Plan case, fed by an offline Spec publication copied as PD17
    describes, reaches publication through the production composition and the oracle;
  - an input run of another build or another case, or one without a passed adjudication, is
    rejected;
  - `zig build test-build-isolation` rejects an automated step that reaches the Plan live step;
  - the Spec guard, which decides whether the case-input change is a measured Spec change (§8).

**Phase 10. First live Plan set.** Each run needs its own approval (AGENTS.md).

- A Spec set on the Plan build supplies the input runs (PD17) and is the live evidence for the
  case-input change. Three Plan runs of each development case follow (SPEC01 §2 rule 4), each
  adjudicated. Nothing is decided on the reserved qualification features (ADR 0034).
- **Result:** the baseline that later Plan changes are measured against: the publication rate,
  the engine-rejected attempts, §8's defect counts, and the tokens and requests of each run.

**After the first slice.** Approval, rejection and the Tasks gate with Tasks (PD2, PD10); `PNN`
answers with E7 (PD3); each row below when its decision is revisited.

**First slice.** The recommendations leave out the following; each decision names what it
amends.

| Left out | Decision |
| --- | --- |
| Edited `spec.md` as authority, its change sets and leases | PD4 |
| The pause-time input state and ID ledger, and a pending Plan state | PD5 |
| Persisted path-candidate and review-unit registries, and the input and output state split | PD6 |
| Approval, rejection, review units, their authentication and the blocking Tasks gate, until Tasks | PD2, PD10 |
| Model review of plan output | PD1 |
| Command execution, probes and the sandbox, for Plan | PD14 |
| File content in model requests, and a project whose source and test roots hold more than 1,024 files | PD15 |
| Renderer versions in state and views | PD13 |
| More than one environment, and name sources beyond the feature ID and entity names | PD7 |
| Research adapters and dependency proposals | PD9 |
| `contracts/` and its view registry | PD16 |
| AST and import facts, recorded as unavailable (18-plan.md:90, :95), and §10.5's content-reference coverage | PD7; a parser library needs an ADR first (§4) |
| The raw path fallback, off by default (18-plan.md:211) | None |

It keeps the entry gate, discovery, repository facts, typed paths, coverage, rendering,
clarification forms and whole-workflow validation. Whether those decide output quality is
Phase 10's to show.
