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
- **Delivery:** design.md §30 Increment 3 (design.md:725-735).

## 2. Verdict (10 November 2026)

**Feasible on the current engine architecture, not as §18 stands.**

- **The generic engine takes a second workflow.**
  - Selection, compilation and the runner don't branch on workflow names, and several
    definitions already run side by side (`test/integration/workflow_tests.zig:344-369`).
  - Shared code already names Plan in three places:
    - the authority registry makes Plan the owner of `design_decision` and `policy_predicate`
      (`src/domain/required_authority.zig:57-59`);
    - clarification IDs and allocation handle `PNN` (`src/domain/clarification_refresh.zig:105-113`);
    - the request-owner unions declare `plan_unit` (`src/domain/model_request_identity.zig:75-96`).
  - The repair contract is generic (`src/domain/atomic_repair.zig:81`).
- **Most of what §18 needs doesn't exist.** The engine can't yet:
  - see the target project: discovery, file kinds, path policy, commands (§4);
  - read an edited `spec.md`;
  - record an approval or authenticate a user.
  - The §13 catalogue lists every Plan action only as "Proposed, no code"
    (13-05:541-574, 13-06:17-35, 13-01:496-543, 13-02:108-124), to be rewritten when Plan
    design starts (design.md:402-403).
- **The design has open conflicts (§5).** Seven block design. They include whether plan
  output gets a model review, how approval happens, and who authenticates whom.
- **Size.** The Spec stage is about 16,000 of the engine's 72,446 production Zig lines (domain,
  action and application files named for specification, reference, source and specify; counted
  10 November 2026). §18 needs more new mechanisms than Spec did, so expect at least that
  much; no estimate beyond that is made. The count is a file-name filter, so another filter
  gives a somewhat different figure.
- **No way to judge Plan output exists (§7).** There is no Plan case, rubric, report or
  adjudication, and neither development case has a project for Plan to plan against.

## 3. What exists and is reusable

| Mechanism | State | Evidence |
| --- | --- | --- |
| Multi-workflow selection, compiler, runner | Generic | `workflow_tests.zig:344-369`; no `spec-generation` literal in production code |
| Required-authority ledger, reconcile, routing, gate | Generic; Plan kinds declared; no Plan seed producer | `required_authority.zig:14`, `:57-59`, `:357-361`; seeds only `specification_authority.zig`, `source_preservation.zig` |
| Clarification registry, `PNN` IDs, forms, refresh | Generic for S/P/T; answers rejected for every stage | `clarification_refresh.zig:64-66`, `:105-113` |
| Atomic repair contract and retry state | Generic core; all 7 instances Spec or reference | `atomic_repair.zig:81`; ADR 0033:237-240 |
| Toolchain capture, inheritance, safety | Generic; holds package IDs and naming rules only | `src/composition/toolchain_policy_registry.zig:6-22`; F0003:208-209 |
| Principle capture | Generic, persisted, read by no model call | `spec.workflow.yaml` step `principles`; 09-configuration.md:336-337 |
| Bounded no-follow directory scan | Root-generic; two users | `src/adapters/filesystem/directory_inventory.zig:8-34` |
| Request-owner and state ID types | Declared, never built in production | `model_request_identity.zig:15-19`, `:61-68` |

## 4. What is missing

Each item has no code; the owner column names where its contract is.

| Missing | Owner | Note |
| --- | --- | --- |
| Repository discovery, project IDs, file registry, repository facts | §10.2, §18.2, 13-01:496-504 | No adapter reads the target project |
| File kinds, path-intent options, name transforms, candidates, file grants | §10.3, §11, 13-06:28-35 | Not in the implemented preset shape (10-toolchain-presets.md:13-17) |
| Command registry and command execution | §10.4, 13-01:506-534 | 13 capabilities, none for processes (`src/domain/workflow_capability.zig:3-15`) |
| Reading an edited `spec.md` back and comparing it with stored state | §18.1, §23.1, 13-05:518-521 | A Spec rerun overwrites `spec.md` unread (`src/adapters/filesystem/workflow_output.zig:72`) |
| Authentication chain and actor-evidence registry | ADR 0025; 13-05:412-504 | Not implemented (SPEC01 E7); Spec answers only |
| Review, approval and review-decision records | §14.5, §24.5 | No approval type or state |
| Multi-stage workflow state | §24.1, 13-02:113-124 | One `workflow.json` typed as Spec state, stages `specified` and `spec_clarification_pending` only (`src/domain/specification_state.zig:8`, `:52`) |
| Plan entry gate | §14.2, §18.1 | `checkClarifications` checks open `S` only and serves Spec (`specification_state.zig:115-122`) |
| Plan artifacts and their renderers | §18.5, §23 | Publication targets are Spec's four (`src/domain/workflow_output.zig:6`; `src/domain/workflow_artifact_registry.zig:14`) |
| Research evidence and dependency registries | §18.2; 12-model-boundary.md:160-161 | No configuration member (09-configuration.md:57-59) |

**Shared code closed to Spec today.** A second workflow extends these, so each is a shared-code
change, not a Plan-local one:

- publication targets and artifact paths (above);
- publication permission, which only a clarification subject has
  (`src/domain/workflow_outcome_association.zig:206-215`);
- the feature-directory chain, which starts from the Spec invocation
  (`src/actions/specify/prepare_inputs.zig:126`);
- the state parser, which accepts two Spec stages (`specification_state.zig:52`);
- packet guidance, one closed `packet-guidance/v6` keyed by Spec registries (ADR 0016:144-149).

## 5. Decisions Plan needs

**Blocking: settle before Plan design.**

1. **PD1. Model review of plan output.**
   - §18 has one: 18-plan.md:289 and :307. §12.6 and §21.6 describe only a generic, optional
     review mechanism (12-model-boundary.md:327-328; 21-validation.md:126).
   - ADR 0023 removed post-generation review for Spec and says "no other review policy
     exists" (0023:46, :60-62).
   - Related open Decision: SPEC01 "Semantic-review and no-invention branches"
     (SPEC01:946-952).
   - **Recommended:** no model review; the semantic remainders rest on the user at plan review,
     as Spec's rest on the reviewer of `spec.md` (ADR 0023:36-40).
2. **PD2. How approval happens.**
   - The review operation "waits" (14-orchestration.md:173-174).
   - But publication ends the run (25-publication.md:35-36; ADR 0018:74-75), and `needs_user`
     saves no continuation (ADR 0009:74).
   - No invocation carries an approval, and `plan_review_pending` appears only at
     18-plan.md:345 and :363.
   - **Recommended:** a Plan run publishes and ends; approval or rejection is a later, separate
     invocation.
3. **PD3. Who authenticates.**
   - Spec edits, `PNN` answers and review decisions all need an authenticated actor
     (18-plan.md:63-67, :269-270; 14-orchestration.md:179).
   - ADR 0025 covers Spec answers only (0025:14-15, :175-176), and nothing says how the
     `specification_edit` lease is issued.
   - **Recommended:** extend ADR 0025 Decision 1, where the invoking account is the actor, to
     all three, after E7.
4. **PD4. Edited `spec.md`.**
   - §18.1 reads an edit back as authority (18-plan.md:52-79; 24-workflow-state.md:150).
   - Today a Spec rerun overwrites it (23-rendering.md:224-225).
   - SPEC01 D13.7 (SPEC01:403-410) is open for edited derived lines.
   - **Recommended for a first slice:** Plan accepts only an unedited `spec.md`, the "equal
     content" branch (18-plan.md:56-57), and blocks on any edit. That defers the edit path and
     its authentication.
5. **PD5. What a `PNN` pause persists.**
   - §18.4 publishes a successor input state and ID ledger (18-plan.md:252-257).
   - The accepted persistence exception covers clarifications and Spec's pending set only (ADR
     0009:67-69; ADR 0017), and "Nothing from the paused execution is reused"
     (24-workflow-state.md:96).
   - **Recommended:** forms and `clarifications.json` only.
6. **PD6. State layout.**
   - One `workflow.json` per feature (24-workflow-state.md:15-18) is typed as Spec state today.
   - The specification Plan compared against is stored in `PlanState` according to
     14-orchestration.md:127 and 23-rendering.md:185, but in `PlanInputAuthorityState`
     according to 18-plan.md:338-342 and 19-tasks.md:9-13.
   - The repository-fact registry splits the same way: `PlanInputAuthorityState`
     (18-plan.md:127-129) against `PlanState` (20-implement.md:31).
   - Decide one multi-stage state contract and one owner for each value.
7. **PD7. Preset fields.**
   - §18 needs file kinds, roots, path-intent options, templates, transforms, commands and the
     raw-fallback switch.
   - The implemented preset has package references and policy IDs only (F0003:165-173,
     :208-209).
   - Without these fields no planned path can be validated, so the intent's "applicable project
     constraints" (intent.md:35) can't be checked.

**Settle during Plan design.**

8. **PD8. Principles.**
   - 18-plan.md:128-129 and :152 say "selection".
   - ADR 0015:22-23 says any filter needs its own decision, and 09-configuration.md:336 sends
     every chunk.
   - **Recommended:** every chunk, 28–29 KB per case (SPEC01 Q17).
9. **PD9. External evidence.**
   - Missing research evidence blocks the stage (18-plan.md:156-157), but the same gap routes
     to `PNN` by the shared reconciliation (:184-191).
   - No configuration owns registry adapters.
   - **Recommended for a first slice:** no adapters; an evidence gap blocks.
10. **PD10. Rejection.**
    - Regenerate the mapped units (18-plan.md:349), or the whole plan (design.md:735;
      25-publication.md:53-54)?
    - **Recommended:** whole plan, from `start`, with the feedback as input.
11. **PD11. Startup or graph steps.** Discovery, the command registry and principle capture
    are bootstrap work in 10-toolchain-presets.md:130-132, :235 and 09-configuration.md:357,
    but selected-workflow setup in 15-bootstrap.md:27 and F0003:12. **Recommended:** graph
    steps (ADR 0003).
12. **PD12. Validators and ledger.**
    - §21.3 lists 12 Plan validators and §18.6 lists 24 checks; 21-validation.md:6 calls §21
      normative.
    - The obligation ledger is a Plan input (18-plan.md:25) but a Tasks deliverable
      (design.md:739; 19-tasks.md:20).
    - Decide which list is complete and who owns the ledger.
13. **PD13. Shared items SPEC01 and the ADRs already list:**
    - upstream rework as a form, to settle before a downstream stage detects gaps
      (SPEC01:963-971);
    - the renderer version (SPEC01:972-977; 23-rendering.md:45-49, :99-100);
    - semantic-review and no-invention branches (SPEC01:946-952; see PD1);
    - Plan repair owner enums, deferred to the gate (ADR 0033:347-348).

## 6. Sequencing

- **E1 (ADR 0030).** Later workflow files don't copy the request subgraphs (0030:97-98,
  :382-384). A Plan definition written first would copy the 16-step request body, and E1
  would then convert two definitions.
- **E4 (ADR 0033).** Plan repair joins the generic mechanism as new owners (0033:237-240). A
  Plan written first would add per-owner repair operations for E4 to remove.
- **E2 (ADR 0031).** Every single-step action costs about six coordinated pieces, and Plan
  "would multiply this cost" (0031:50-63).
- **Recommended:** E1, E2's first measure and E4 land before Plan code.
- **Gate evidence.** ADR 0034 wants gate evidence from the build Plan work starts from (:89,
  :103-104), and recommends re-running the gate after those conversions land (:93-95). The
  user decides whether to re-run it.

## 7. Evaluation gap

- **The harness is Spec-only:**
  - case `spec-e2e-case/v3`, which requires Spec's four artifacts
    (`test/harness/e2e/contracts.zig:4`, `:23-26`);
  - report `spec-e2e-report/v17` (`:140`);
  - adjudication `spec-adjudication-record/v1` (`test/harness/adjudication.zig:13`, `:50`);
  - stage measures, which count `plan_unit` as `other` (`test/harness/baseline/stages.zig:94`).
  - "Plan, Tasks and Implement need their own workflow cases" (design/harness/e2e.md:328).
- **No project to plan against.** Both development cases select no preset
  (`principles/toolchain.yaml`: `presets: []`) and install no project files. Plan's repository
  facts would be empty.
- **No defect classes.** Plan has no published-output defect classes or rubric criteria;
  AGENTS.md requires both before a change can be judged. The intent's measures
  (intent.md:159-162) could seed them.
- **Needed before the first live Plan run:**
  - a target project and preset for each development case;
  - Plan rubrics;
  - a Plan case, report and adjudication record;
  - decisions on both cases, never on the reserved qualification features (ADR 0034).

## 8. Recommended path (not decided)

0. Only the user declares the ADR 0034 gate passed and actions Plan; nothing below starts
   before that.
1. The user settles PD1–PD7.
2. E1, E2's first measure and E4 land (§6), with gate evidence from that build.
3. The design writes Plan's §13 entries and a Plan feature contract, scoped by PD1–PD7.
4. Shared prerequisites, each with tests at its owner:
   - multi-stage state and generic publication targets;
   - preset file-kind and path policy;
   - repository discovery;
   - the Plan entry gate.
5. Plan generation units, rendering and publication, then the review invocation. PD3's
   authentication follows E7.
6. Before the first live run, the §7 evaluation pieces exist on both development cases.

A first slice that takes the recommended cuts in PD4 (unedited `spec.md` only) and PD9 (no
research adapters) removes the spec-edit path, its authentication and the registry adapters.
Each cut amends §18, so each is a **Decision**.
