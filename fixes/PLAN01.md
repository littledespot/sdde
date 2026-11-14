# PLAN01 — Plan workflow intent and feasibility

The Plan workflow's intent, a feasibility assessment of building it on the current engine, and
the decisions it needs ([convention](README.md)).
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
- **Model and engine split:** design.md §4 (design.md:256-258, 262, 266-267) and
  [21-validation.md](../design/contracts/21-validation.md) §21.3's semantic remainders and
  §21.6 (21-validation.md:121).
- **Delivery:** design.md §30 Increment 3 (design.md:726-736).

## 2. Verdict (14 November 2026)

**Feasible on the current engine, not as §18 stands.**

- **The generic engine takes a second workflow.**
  - Selection, compilation and the runner don't branch on workflow names, and several
    definitions already run side by side (`test/integration/workflow_tests.zig:341-366`).
  - Shared code already names Plan in three places:
    - the authority registry makes Plan the owner of `design_decision` and `policy_predicate`
      (`src/domain/required_authority.zig:57-59`);
    - clarification IDs and allocation handle `PNN` (`src/domain/clarification_inputs.zig:16`;
      `src/domain/clarification_refresh.zig:105-113`);
    - the request-owner unions declare `plan_unit` (`src/domain/model_request_identity.zig:75-96`).
  - The model path is generic too: requests, repairs and ID restrictions (§3).
- **Most of what §18 needs doesn't exist.** The engine can't yet:
  - see the target project: discovery, file kinds, path policy, commands (§4);
  - read a published `spec.md` in a later invocation;
  - record an approval or authenticate a user.
  - The §13 catalogue lists every Plan action only as "Proposed, no code" (13-01:466-535,
    13-02:133-149, 13-05:316-478, 13-06:17-35), to be rewritten when Plan design starts
    (design.md:402-404).
- **The design has open conflicts (§5).** Eight block design. They include whether plan output
  gets a model review, how approval happens, whether Plan runs commands and which existing
  files the model sees.
- **Much of the plan could be computed (§6, recommended).** Repository facts, IDs, paths, the
  rows of coverage and quickstart, `data-model.md` applicability and every restated requirement
  could be engine-built, leaving the model the design choices, their rationale and the
  verification methods.
- **Size.** The Spec stage is 17,188 of the engine's 66,493 production Zig lines (14 November
  2026): 8,014 on the generation side (domain, action and application files named for
  specification or specify), 8,901 on the reference side (named for reference or source) and
  273 named for both. The count covers `src/**/*.zig` without `*_test.zig`, `*_test_fixture.zig`
  or `test_fixtures/`, inline tests included; another filter gives a somewhat different figure.
  Plan has no reference side, but needs discovery, file and path policy and its renderers, which
  Spec never had. No estimate beyond that is made.
- **No way to judge Plan output exists (§8).** There is no Plan case, rubric, report or
  adjudication, and neither development case has a project for Plan to plan against.

## 3. What exists and is reusable

| Mechanism | State | Evidence |
| --- | --- | --- |
| Multi-workflow selection, compiler, runner | Generic | `workflow_tests.zig:341-366`; no `spec-generation` literal in production code |
| One `request-model` step per model request (E1) | Generic | Later workflow files copy no request subgraph (ADR 0030:388-389) |
| Integer-choice and exact-member restrictions | Generic; Spec and reference users | 12-model-boundary.md:100, :118 (ADR 0046); `src/domain/model_result_schema.zig` |
| Generic repair operations and contract variants (E4) | Generic; 13 Specify owners, 29 variants | A new owner adds its binding, one `RepairOwner` arm, one arm per generic operation it joins, one `frozen` row and its YAML steps (Z_SPEC01 E4); `atomic_repair.zig:81` |
| Stage actions (E2) | Generic; four Spec stage actions | ADR 0031 |
| Required-authority ledger, reconcile, routing, gate | Generic; Plan kinds declared; no Plan seed producer | `required_authority.zig:14`, `:57-59`, `:357-361`; seeds only `specification_authority.zig`, `source_preservation.zig` |
| Clarification registry, `PNN` IDs, forms, refresh | Generic for S/P/T; answers rejected for every stage | `clarification_inputs.zig:16`; `clarification_refresh.zig:64-66`, `:105-113` |
| Toolchain capture and registered policies | Generic; policies hold naming rules only | `src/composition/toolchain_policy_registry.zig:6-22` |
| Principle capture | Generic, persisted, read by no model call | `spec.workflow.yaml` step `principles`; 09-configuration.md:337 |
| `spec.md` codec | Renders and parses; used only in Spec publication | `src/domain/specification_markdown.zig:14`, `:84`; `validate_specification_rendering.zig:13-20` |
| Bounded no-follow directory scan | Root-generic; two users; prunes nothing before descent | `src/adapters/filesystem/directory_inventory.zig:8-34`; users `src/adapters/filesystem/principle_source.zig:7`, `src/adapters/filesystem/reference_corpus_source.zig:37` |
| Request-owner and state ID types | Declared, never built in production | `model_request_identity.zig:15-19`, `:61-68` |

## 4. What is missing

Each item has no code; the owner column names where its contract is.

| Missing | Owner | Note |
| --- | --- | --- |
| Repository discovery, project IDs, file registry, repository facts | §10.2, §18.2; 13-01:478-486, 13-06:17-20 | No adapter reads the target project. The scan in §3 walks every directory, so a project with `node_modules` reaches its limits; §18.2 prunes before descent (18-plan.md:97-102) |
| File kinds, path-intent options, name transforms, candidates, file grants | §10.3, §11; 13-05:460-463, 13-06:28-35 | Not in the policies (§3), and §10's richer fields aren't accepted YAML (10-toolchain-presets.md:13-17); PD7 |
| Command registry | §10.4; 13-01:488-516 | 13 capabilities, none for processes (`src/domain/workflow_capability.zig:3-15`); running a command is Implement's (13-07:67); PD14 |
| Plan's required-decision seeds | §18.1 (18-plan.md:30-31, :40-43) | Only Spec's projections produce seeds (§3), and principle prose can't (09-configuration.md:341); PD12 |
| Reading the published `spec.md` in a later invocation and comparing it with stored state | §18.1, §23.1; 13-05:422-425 | The codec exists (§3), but no later invocation reads `spec.md`, and a Spec rerun overwrites it unread (`src/adapters/filesystem/workflow_output.zig:72`; 23-rendering.md:224-225) |
| Authentication chain and actor-evidence registry | ADR 0025; 13-05:316-408 | Not implemented (SPEC01 E7); Spec answers only |
| Review, approval and review-decision records | §14.5, §24.5; 13-05:470-478 | No approval type or state |
| Multi-stage workflow state | §24.1; 13-02:138-149 | One `workflow.json` typed as Spec state, stages `specified` and `spec_clarification_pending` only (`src/domain/specification_state.zig:8`, `:52`) |
| Plan entry gate | §14.2, §18.1 | `checkClarifications` checks open `S` only and serves Spec (`specification_state.zig:115-122`) |
| Plan artifacts and their renderers | §18.5, §23 | Publication targets are Spec's four (`src/domain/workflow_output.zig:6`; `src/domain/workflow_artifact_registry.zig:14`) |
| Research evidence and dependency registries | §18.2; 12-model-boundary.md:159-163 | No configuration member (09-configuration.md:56-59) |
| AST parsing and import resolution | §10.5; 18-plan.md:90 | Parser and tree-sitter libraries are a deferred choice (design.md:1184), and a production dependency needs an accepted ADR (AGENTS.md "Zig implementation expectations") |

**Shared code closed to Spec today.** A second workflow extends these, so each is a shared-code
change, not a Plan-local one:

- publication targets and artifact paths (above);
- publication permission, which only a clarification subject has
  (`src/domain/workflow_outcome_association.zig:205-214`);
- the feature-directory chain and the published-state capture, which start from the Spec
  invocation (`src/actions/specify/prepare_inputs.zig:126`, `:159-166`);
- the state parser, which accepts two Spec stages (`specification_state.zig:52`); PD6's
  recommendation leaves it unchanged;
- packet guidance, one closed `packet-guidance/v6` keyed by Spec registries (ADR 0016:144-149);
- the E2E harness (§8).

## 5. Decisions Plan needs

**Blocking: settle before Plan design.**

- **PD1. Model review of plan output.**
  - §18 has one: 18-plan.md:289 and :307. §12.6 and §21.6 describe only a generic, optional
    review mechanism (12-model-boundary.md:326-328; 21-validation.md:126).
  - ADR 0023 removed post-generation review for Spec and says "no other review policy
    exists" (0023:46, :60-62).
  - On the configured model, the 26 October source review caught 1 of 28 defects by unconfirmed
    labels (SPEC01 Q13, "Reopening link checks").
  - SPEC01 §8 removed the no-invention replacement from the design text (14 November 2026) and
    kept this semantic-review wording for Plan to decide, here.
  - **Recommended:** no model review; the semantic remainders rest on the user at plan review
    and on adjudication, as Spec's rest on the reviewer of `spec.md` (ADR 0023:36-40). PD16
    makes deterministic the applicability choice §18.5's review would challenge. Amends
    18-plan.md:289 and :307.
- **PD2. How approval happens.**
  - The review operation "waits" (14-orchestration.md:174-175).
  - But publication ends the run (25-publication.md:35-36; ADR 0018:74-75), and `needs_user`
    saves no continuation (ADR 0009:74). In non-interactive use approval arrives through "an
    explicit API/CLI approval event or a deliberately selected policy profile"
    (14-orchestration.md:191).
  - No invocation carries an approval, and `plan_review_pending` appears only at
    18-plan.md:345 and :363.
  - The Tasks gate is a plan approval's first reader (19-tasks.md:8-9; 24-workflow-state.md:129);
    Implement needs it too (invariant 17, design.md:159).
  - **Recommended:** a Plan run publishes and ends at `plan_review_pending`; approval or
    rejection is a later, separate invocation, built with Tasks. Plan's first slice then needs
    no review records, review units or authentication. Moves plan review from Increment 3 to
    Increment 4 (design.md:736, :738-743).
- **PD4. Edited `spec.md`.**
  - §18.1 reads an edit back as authority (18-plan.md:52-79; 24-workflow-state.md:150).
  - A Spec rerun overwrites it (§4), so no edit becomes authority anywhere yet, although
    invariant 16 makes `spec.md` the one editable stage artifact (design.md:158).
  - SPEC01 Q13 D13.7 is open for edited derived lines.
  - **Recommended for a first slice:** Plan accepts only an unedited `spec.md`, the "equal
    content" branch (18-plan.md:56-57), and blocks on any edit. The check is byte equality
    between `spec.md` and a fresh render of the validated stored specification through the
    existing codec (`specification_markdown.zig:14`); it needs no parse and is stricter than
    parsing and comparing. A renderer change between the two runs also reads as an edit and
    blocks until Spec reruns (PD13's renderer version). That defers the edit path, its change
    sets and its authentication. Amends 18-plan.md:21, :52-79 and :332-333 and
    23-rendering.md:103-104, and defers invariant 16's edits.
- **PD5. What a `PNN` pause persists.**
  - §18.4 publishes a successor input state and ID ledger (18-plan.md:252-257).
  - The accepted persistence exception covers clarifications and Spec's pending set only (ADR
    0009:67-69; ADR 0017), and "Nothing from the paused execution is reused"
    (24-workflow-state.md:96).
  - The pause ledger guards IDs that reach no authority: a `PNN` can't cite uncommitted
    records (18-plan.md:258-259).
  - **Recommended:** forms and `clarifications.json` only; Plan is pending while a `P` record
    is open. Amends 18-plan.md:252-257.
- **PD6. State layout.**
  - One `workflow.json` per feature (24-workflow-state.md:15-20) is typed as Spec state today.
  - The specification Plan compared against is stored in `PlanState` according to
    14-orchestration.md:127 and 23-rendering.md:184-185, but in `PlanInputAuthorityState`
    according to 18-plan.md:338-342 and 19-tasks.md:13.
  - The repository-fact registry splits the same way: `PlanInputAuthorityState`
    (18-plan.md:127-129) against `PlanState` (20-implement.md:31).
  - The split lets a pause publish input authority (18-plan.md:252-253), which PD5 removes, and
    gives plan-unit requests an owner before any `PlanState` exists
    (`model_request_identity.zig:61-64`), which an execution-local identity also gives
    (13-01:531-533).
  - §18 adds about ten persisted registries and states (18-plan.md:113-131, :207, :242-244,
    :297; 24-workflow-state.md:170; 13-05:352-353). No version migrates
    (24-workflow-state.md:41-42), and Spec's one state contract moved five times within a week,
    v21 to v26, the last with E1 (ADR 0023:162-166; ADR 0015:16-22; Z_SPEC01 E1); a persisted
    shape that embeds another contract's goes stale with it.
  - **Recommended:** one Plan state document beside Spec's, with its own version, written last.
    It holds what later gates and later plan revisions read: the specification it planned from,
    the gate-sensitive fact values, the file registry with its ordinals and retired IDs, the
    file grants, the plan records, the artifact decisions and the plan ID ledger, so no retired
    ID is reused (18-plan.md:113-114, :238-244), as Spec persists its ledger
    (`specification_state.zig:18`).
    Path candidates and review units are rebuilt each run. Spec's state and parser stay
    unchanged, and a Spec rerun makes a plan stale by direct comparison, with no write to Plan's
    state; a revision number alone can't, because a recreated Spec state restarts at 1
    (`specification_state.zig:108`). Amends §24.1, which allows no other layout
    (24-workflow-state.md:19-20); 18-plan.md:227-228 and :242-244 for the candidate and
    review-unit registries; and 18-plan.md:338-342 and 19-tasks.md:13 for the input and output
    split.
- **PD7. Where file kinds, path rules and commands live.**
  - §18 needs file kinds, roots, path-intent options, templates, transforms, commands and the
    raw-fallback switch, and §10's preset fields for them aren't accepted YAML (§4).
  - Under the implemented contract, package documents define no command, path, capability or
    safety exception, and YAML selects registered policy IDs only (F0003:200-201, :262-263).
  - Without them no planned path can be validated, so the intent's "applicable project
    constraints" (intent.md:35) can't be checked.
  - **Recommended:** extend the registered policy descriptors (§3) with typed file kinds, roots,
    placement and command descriptors, selected by policy ID from `toolchain.yaml` as today.
    That adds no YAML schema or merge rule, and the project supplies no command or capability
    (AGENTS.md:10-11). The cost: a new stack is an engine change. The raw fallback stays off, as
    the hardened default sets it (18-plan.md:211-214). Narrows the rule sources of §10.3-10.4
    and 09-configuration.md:345-347 to engine policy.
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
    both approvals, where §10.4 would disable it at Plan. Amends 10-toolchain-presets.md:230-231
    and :235 for Plan, and the meaning of "available" in 18-plan.md:318-319 and
    21-validation.md:83.
- **PD15. Which existing files the model sees.**
  - §18.2 builds "current files near requirement-relevant terms" (18-plan.md:91). Matching
    specification words against file names is a word-list heuristic over prose, which AGENTS.md
    "Model output, prompts and evidence" forbids, and as a filter it can hide a file the plan
    needs.
  - §12 sends no "raw whole-repository listings" (12-model-boundary.md:165).
  - **Recommended:** send the complete typed file registry of the selected project's source and
    test roots (file IDs, normalized paths, kinds), with protected, generated and dependency
    roots pruned before descent; the model selects files by ID. The decision includes reading
    12-model-boundary.md:165 as not covering that registry, which is typed and limited to those
    roots. A provider size failure follows the workflow's outcome transitions, as for
    principles (09-configuration.md:337). For the development cases it is a few files. Amends
    18-plan.md:91.

**Settle with E7.**

- **PD3. Who authenticates.**
  - Spec edits, `PNN` answers and review decisions all need an authenticated actor
    (18-plan.md:63-67, :269-270; 14-orchestration.md:179-182).
  - ADR 0025 covers Spec answers only (0025:14-15, :175-176), and nothing says how the
    `specification_edit` lease is issued.
  - With PD2 and PD4, only `PNN` answers remain in the first slice. Like Spec's, they wait for
    E7 (§7); until then a `PNN` closes only through authority resolution (18-plan.md:269-270).
  - **Recommended:** extend ADR 0025 Decision 1, where the invoking account is the actor, to
    `PNN` answers with E7, and to review decisions when approval is built.

**Settle during Plan design.**

- **PD8. Principles.**
  - 18-plan.md:128-129 and :152 say "selection".
  - ADR 0015:22-23 says any filter needs its own decision, and 09-configuration.md:336-337
    sends every chunk, untruncated.
  - The case principles are 28,067 and 29,399 bytes, about 7k tokens (SPEC01 Q17). Each
    Plan request that carries them adds that much against the 125,000-token workflow budget;
    the HEAD set's Spec runs used 12,971 to 17,037 tokens and the highest measured run 67,448
    (SPEC01 §3, Robustness track).
  - **Recommended:** every chunk, to every Plan model request; the measured sets report the
    tokens, and a narrower per-step binding is decided only on a measured set.
- **PD9. External evidence and dependencies.**
  - Missing research evidence blocks the stage (18-plan.md:156-157), but the same gap routes
    to `PNN` by the shared reconciliation (:184-191).
  - No configuration owns registry adapters, and without one a new dependency's package,
    version and source can't be validated (18-plan.md:173, :314).
  - **Recommended for a first slice:** no adapters and no dependency proposals; an evidence gap
    or a needed dependency blocks with its reason. Each case's project would hold what its
    stories need (§8). Amends 18-plan.md:151-160, :173 and :314 for the first slice.
- **PD10. Rejection.**
  - Regenerate the mapped units (18-plan.md:349), or the whole plan (design.md:736;
    25-publication.md:53-54)?
  - Mapping free-text feedback to units needs a model or a per-unit review form
    (14-orchestration.md:185-189).
  - **Recommended:** whole plan, from `start`, with the feedback as input, built with approval
    (PD2); it needs no `PlanReviewUnitRegistry`. It can change parts the user accepted; a
    per-unit review form is the alternative if that matters. Amends 18-plan.md:242-244 and :349
    and 14-orchestration.md:185-189.
- **PD11. Startup or graph steps.** Discovery, the command registry and principle capture are
  bootstrap work in 10-toolchain-presets.md:130-132, :235 and 09-configuration.md:357, but
  selected-workflow setup in 15-bootstrap.md:28 and F0003:12. **Recommended:** graph steps
  (ADR 0003), each deterministic sequence one stage action (ADR 0031), as `prepare-toolchain`
  is.
- **PD12. Validators, ledger and required decisions.**
  - §21.3 lists 12 Plan validators and §18.6 lists 24 checks; 21-validation.md:6 calls §21
    normative. Each of the twelve maps to one or more of the 24.
  - The obligation ledger is a Plan input (18-plan.md:25) but a Tasks deliverable
    (design.md:740; 19-tasks.md:20).
  - Nothing says which planning decisions are required (§4).
  - **Recommended:** §18.6 is the complete list, and §21.3 keeps the semantic remainders. The
    ledger is a function of the specification, built by each stage that needs it and persisted
    by none; Tasks adds the plan's entries (19-tasks.md:20-33). Seeds come only from native
    projections, as Spec's do (`required_authority.zig:38-39`; invariant 19, design.md:161),
    for example one design-decision slot per plan unit the workflow declares. A need the model
    raises is admitted only as the clarification candidate of its unit's slot
    (18-plan.md:181-185); it never creates a slot, and a gap with no registered slot is an
    administrative block (`required_authority.zig:357-361`). Principle compliance stays a cited,
    model-assisted judgment (09-configuration.md:339) that adjudication scores.
- **PD13. Shared items SPEC01 and the ADRs already list:**
  - upstream rework as a form, to settle before a downstream stage detects gaps
    (SPEC01 §8, Design–code conflicts);
  - the renderer version (SPEC01 §8, Design–code conflicts; 23-rendering.md:46-50, :98-100); until it exists,
    PD4's byte check blocks on any renderer change;
  - Plan repair owner enums, deferred to the gate (ADR 0033:359-360).
- **PD16. Artifact applicability.**
  - The model proposes applicability and a semantic review may challenge it
    (18-plan.md:285-289).
  - `data-model.md`: the specification already lists its entities (ADR 0038 Decision 6).
    **Recommended:** required exactly when the specification has an entity, which the engine
    computes; the model writes the content. The artifact set then can't vary between runs on
    one specification. The trade-off: a feature whose state isn't a business entity gets
    `not_applicable`. Amends 18-plan.md:285 and :288-289.
  - `contracts/`: whether a contract "adds planning value" (18-plan.md:286) is a judgment, and
    neither development case has an interface beyond console output. **Recommended for a first
    slice:** not produced, an explicit `not_applicable` with an engine reason. Amends
    18-plan.md:286 and :292-299 for the first slice.
- **PD18. The split between engine and model (§6).**
  - §18 leaves open how many quickstart scenarios there are (18-plan.md:317), makes coverage
    mappings and quickstart scenarios separate model units (:177-178), and lets the model
    restate requirement text.
  - **Recommended:** §6's split: one quickstart scenario per acceptance criterion and edge
    case; coverage and quickstart from one model answer per obligation; requirement text and the
    technical context rendered by the engine, never written by the model. Amends
    18-plan.md:177-178 and :317, and adds the rendering rule.

**Settle before the first live Plan run:** PD17 (§8).

## 6. Recommended split between engine and model (not decided; PD18)

The operating rule is "if a validator can answer from typed data or executable evidence, do not
ask the LLM to answer it" (design.md:266). Applied to §18 with the mechanisms that exist:

| Plan content | Engine | Model | Mechanism |
| --- | --- | --- | --- |
| Feature, date, spec link, IDs, headings, status | All of it | Nothing | Invariant 14 (design.md:156); 18-plan.md:305 |
| Technical context: language, runtime, test runner, dependencies, scripts, roots | Rendered from repository and policy facts | Nothing; it cites fact IDs | design.md:256; 18-plan.md:137-140 |
| Existing files a change touches | The registry (PD15) | Selects file IDs | Integer-choice restriction (12-model-boundary.md:100) |
| New files | The path, from the policy's kind, root and placement (PD7) | An option and a name source, never a filename | 18-plan.md:197-209 |
| Coverage: one design and verification record per obligation | Rows listed from the specification's IDs | Each record's content | `exact_members` (12-model-boundary.md:118; ADR 0046): a missing or repeated row is rejected at admission |
| Quickstart scenarios | One per acceptance criterion and edge case, from the same records | Automated (test-file and command IDs) or manual steps | 18-plan.md:317-319 |
| Requirement text in plan views: criteria, exact copy, values | Rendered from the specification record by ID | Never restated | 18-plan.md:236-237, :322; ADR 0047; ADR 0038 Decision 7 |
| `data-model.md` applicability; `contracts/` | Computed (PD16) | The data model's content | ADR 0038 Decision 6 |
| Research decisions | IDs; fact and source links checked | Decision, rationale, alternatives | 18-plan.md:313 |
| Principle consideration | Chunk citations checked | Reasoning and any deviation | 09-configuration.md:339 |
| Approach, minimal change, task-generation approach | Nothing | All of it | 21-validation.md:121 |

- **Restated text is rendered, not generated.** A model that restates a requirement drops or
  weakens part of it, Spec's open "lossy repeats" problem (SPEC01 §3, "Lossy repeats"); the levers that held
  were engine-composed text (ADR 0047) and a link whose target's text is printed (ADR 0038
  Decision 7). This is not the rejected lever, filling a record from its cited source lines
  (SPEC01 §3, "Lossy repeats", edge-case outcomes): Plan prints a linked specification record, never source
  lines.
- **Coverage and quickstart share one answer per obligation,** rendered twice, so they can't
  disagree and no obligation is asked twice.

## 7. Sequencing

- **E1 (ADR 0030): implemented and kept** (SPEC01 §3, Engine track; Z_SPEC01 E1). Plan's model requests are
  `request-model` steps.
- **E4 (ADR 0033): implemented and kept 14 November 2026** (Z_SPEC01 E4); its live set was taken
  the same day (Z_SPEC01 E4). Plan's repairs join the
  four generic operations as owners and variants (ADR 0033:248-250); the Plan owner enums wait
  for the gate (:359-360).
- **E2 (ADR 0031): stops at the three preparation stages, now four stage actions** (decided 14
  November 2026, "Revisit when Plan work begins", SPEC01 E2). Plan's deterministic
  sequences are stage actions from the start (PD11), so none waits for a conversion.
- **E7 (ADR 0025): last** (SPEC01 §3, Engine track; E7). It gates `PNN` answers (PD3), not the first
  slice.
- **Gate re-run decided 14 November 2026** (SPEC01 §1): one closing set on the build after
  E1–E4 land and the output-track changes are each kept or reverted (SPEC01 §3, Set order), so the
  evidence comes from the build Plan work would start from (ADR 0034:89, :93-95, :103-104).
- Nothing in E1–E5 blocks Plan design any longer; the closing set comes first under ADR 0034.

## 8. Evaluation gap

- **The harness is Spec-only:**
  - case `spec-e2e-case/v3`, which requires Spec's four artifacts
    (`test/harness/e2e/contracts.zig:4`, `:23-26`);
  - report `spec-e2e-report/v19` (`:161`): changing a closed member needs a new version
    (SPEC01 §2 rule 12), and earlier runs need their own build (SPEC01 §1, Retained runs). **Recommended:** a Plan
    report of its own, which leaves Spec's decoder unchanged;
  - adjudication `spec-adjudication-record/v1` (`test/harness/adjudication.zig:13`, `:69`);
  - stage measures, which count `plan_unit` as `other` (`test/harness/baseline/stages.zig:94`);
  - AGENTS.md names only Spec's record, `adjudicate-spec` and "published specifications"
    (AGENTS.md:205-207, :324-325); a Plan record extends that policy text.
  - "Plan, Tasks and Implement need their own workflow cases" (design/harness/e2e.md:328).
- **No project to plan against.** Both development cases select no preset
  (`principles/toolchain.yaml`: `presets: []`) and install no project files, yet both cases'
  principles are written for a Node, TypeScript and Vitest project (`architecture.md:6`,
  `project-structure.md:36`), and `design/toolchainPresets/node-vitest.yaml` is matching source
  material, never runtime configuration (10-toolchain-presets.md:10-11).
  - **Recommended:** one minimal project per case, with no feature code, as case principles never
    anticipate a story (AGENTS.md:317-318): `package.json` with TypeScript and Vitest dev
    dependencies and `build` and `test` scripts, `tsconfig.json`, an empty `src/`, and the
    registered policies for that stack (PD7). Plan then has real facts to select or misstate.
  - Spec must see the same toolchain as Plan. Spec's token grammar reads the compiled naming
    policy (`src/actions/reference/prepare_reference_tokens.zig:49`, `:83-84`), readback
    recomputes token classification (24-workflow-state.md:56-59), and Plan recaptures the
    reference and routes a change back to Specify (18-plan.md:261-263, :268). So the project and
    policies go into each development case for both workflows. For Spec that is an input
    change, kept or reverted like any other (SPEC01 §2); as Plan test input it waits for the
    gate (ADR 0034 "What waits").
- **PD17. Plan's input.** A Plan run needs a published specification, and no state version
  migrates (PD6). **Recommended:** a Plan run names a retained Spec run of the same build and
  case inputs whose adjudication passed, and copies its published feature directory and state;
  Plan's measurements then vary only with Plan. The copied input is a live production run's
  published output, so nothing scripted substitutes (AGENTS.md:322-323). The alternative,
  running Spec inside each Plan case, adds Spec's variance and cost to every Plan measurement.
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
- **Needed before the first live Plan run:**
  - the projects and policies above, and PD17;
  - Plan rubrics, from the classes above;
  - a Plan case, report and adjudication record, and Plan support in the evaluate-e2e skill;
  - decisions on both cases, never on the reserved qualification features (ADR 0034).

## 9. Recommended path (not decided)

0. Only the user declares the ADR 0034 gate passed and actions Plan; nothing below starts
   before that.
1. The user settles the blocking decisions: PD1, PD2, PD4 to PD7, PD14 and PD15.
2. The design writes Plan's §13 entries and a Plan feature contract, scoped by those decisions
   and the first slice below.
3. Shared prerequisites, each with tests at its owner:
   - Plan's own state document and publication targets (PD6);
   - file kinds, roots, placement and command descriptors on the registered policies (PD7);
   - repository discovery with pruning before descent, and the file registry (PD15);
   - the Plan entry gate: no open `S` and an unedited `spec.md` (PD4).
4. Plan generation, rendering and publication to `plan_review_pending`, split as PD18 decides.
5. Before the first live run, the §8 evaluation pieces exist on both development cases.
6. Approval and rejection with Tasks (PD2, PD10); `PNN` answers with E7 (PD3).

**First slice.** The recommendations leave out the following; each decision names what it
amends.

| Left out | Decision |
| --- | --- |
| Edited `spec.md` as authority, its change sets and leases | PD4 |
| The pause-time input state and ID ledger | PD5 |
| Persisted path-candidate and review-unit registries, and the input and output state split | PD6 |
| Approval, rejection, review units and their authentication, until Tasks | PD2, PD10 |
| Model review of plan output | PD1 |
| Command execution, probes and the sandbox, for Plan | PD14 |
| Research adapters and dependency proposals | PD9 |
| `contracts/` and its view registry | PD16 |
| AST and import facts, recorded as unavailable (18-plan.md:95) | None; a parser library needs an ADR first (§4) |
| The raw path fallback, off by default (18-plan.md:211) | None |

It keeps what decides output quality: the entry gate, discovery, repository facts, typed paths,
coverage, rendering, clarification forms and whole-workflow validation.
