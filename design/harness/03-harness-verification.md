# Workflow harness, verification and delivery

[Backlog index](README.md). The delivery test joins actual Spec generation to
the selected-provider rubric evaluator. Mechanical tests and live semantic calibration
are separate evidence classes; both are needed, and neither replaces the other.

## H-014 — Assemble the isolated Hello World project

**Status:** Implemented with mechanical verification. **Owner:** generic harness fixture builder.
**Dependencies:** H-001 case mapping; consume H-013 when the workflow is ready.

The [live E2E harness](e2e.md) copies explicit resources into a retained dated
project and verifies source preservation. Source/rubric/settings snapshots are
retained before network calls. Mechanical tests exercise unrelated references,
configured models, path safety and one-to-one engine/judge source mapping.

Work:

- Build a temporary target from declared fixture resources. Supply exact
  `.sddtoolkit.json`, required configured roots, workflow resources and valid
  mechanical toolchain/preset inputs through their production contracts.
- Copy the sibling `reference/stories.md` beneath a configured descendant
  reference directory; pass a contained selector, never `../reference`.
- Resolve `--feature hello-world` beneath configured `paths.specs`; no feature
  ownership inventory and no hard-coded output-root assumptions.
- Keep source fixtures immutable and generated output isolated. Only fixture
  data changes between cases; the builder must not branch on `wf-001` or Vitest.
- Include the existing principle files only through the ordinary applicable
  setup contract. Do not feed them to the judge as unstated business authority.

Acceptance:

- [ ] The source stories and principles remain byte-identical after each run.
- [ ] The synthetic project passes ordinary config/workflow/toolchain preflight
  without source-example fallback, credentials in Git or Node execution.
- [ ] A second unrelated case can use the same builder by changing its data.
- [ ] Invalid mappings, traversal/symlinks and writes outside the declared
  temporary/report roots fail before execution or data transmission.

Use the current user-authored source verbatim, including later requirement
changes. Do not enrich or trim it to make the engine or judge pass.

## H-015 — Run the workflow and evaluate its actual output

**Status:** Implemented; live evidence is recorded per execution. **Owner:** harness coordinator and production invocation adapter.
**Dependencies:** H-006/H-013/H-014. Offline tests verify mechanical boundaries only.

The [E2E command](e2e.md) uses real production model binding, authorization and
HTTPS transport. Successful publication hands exact captured output to the live
evaluator, with execution identity and each generation slot/provider/model.
Reports retain failures and inputs; stale or replaced output cannot be graded
as fresh generation. Remaining H-012 production work is separate.

Work:

- Invoke the ordinary selected workflow with explicit feature/reference inputs.
  Reuse production compilation, bindings, validators and output handling.
- Observe the execution's terminal result and collect only its registered
  published output. Bind the evaluated artifact to the generating execution;
  mere existence of `spec.md` is insufficient after a failed rerun.
- On completed generation, call H-003–H-006 with the unchanged source, rubric
  and that exact artifact. Generation and evaluation have separate identities,
  provider settings, usage and failure records.
- On failure, cancellation or `needs_user`, report that state and any existing
  clarification references; do not grade stale output as a fresh success or
  automatically answer forms. Regrading a supplied artifact is explicit.
- Preserve readable poor-quality generated output for evaluation. Do not add a
  harness semantic prefilter that excludes the failures the rubric should find.

Acceptance:

- [ ] One selected case produces a joined generation/evaluation report with
  traceable input and artifact identity.
- [ ] Changing `spec.md` before collection cannot attach a grade to an unrelated
  artifact; retained evaluation input stays stable across subsequent reruns.
- [ ] Missing expected output after reported success is an execution/artifact
  error; evaluator failure after generation leaves the generated output intact.
- [ ] A score does not modify workflow state, emit a success transition or
  bypass production validation. There is no judge-driven regeneration loop.

## H-016 — Test and calibrate the evaluator

**Status:** Open. **Owner:** evaluator tests and human rubric reviewer.
**Dependencies:** H-002/H-005/H-006; independent of full Specify completion.

Work:

- Add offline tests for packet construction, response parsing, criterion/evidence
  accounting, aggregation, reporting and all provider failures. Use deterministic
  fake responses only to test those mechanical boundaries.
- Create explicitly labelled calibration specimens: faithful concise content,
  faithful paraphrasing, missing startup behavior, missing/altered greeting,
  invented features, technical leakage and excessive unsupported detail.
- Include prompt-injection content in a candidate and a semantically wrong
  candidate with perfect formatting. Include equivalent meanings expressed
  differently. Assess robustness instead of declaring the judge infallible.
- Have a human review the expected qualitative findings, then perform authorized
  live judgments. Inspect disagreement and adjust rubric/prompt only with
  explicit recorded revisions, never by hiding low-scoring cases.
- Record repeated judgments where needed to understand variability. Do not
  require identical live scores or retry until a desired score appears.

Acceptance:

- [ ] Mechanical regression tests include missing/duplicate/foreign criteria,
  invalid score bounds, bogus quotes, refusal, incomplete output and API errors.
- [ ] Live reports distinguish meaning/coverage from wording and do not reward
  invented functionality or obey instructions embedded in candidate text.
- [ ] Human disagreement/uncertainty is visible; a single model score is never
  described as deterministic proof of specification quality.
- [ ] Calibration uses more than the one Hello World happy path without making
  additional application workflows implementation prerequisites.

OpenAI's [evaluation guidance](https://developers.openai.com/api/docs/guides/evaluation-best-practices)
explains why variable model outputs need evaluation beyond traditional tests.
The calibration set and acceptance decisions here remain project-owned.

## H-017 — Prove the complete Spec evaluation case

**Status:** Open. **Owner:** end-to-end tests and live evaluation evidence.

Live execution now reaches the configured Bedrock model. The latest run passed
extraction, then failed with `InvalidModelEnvelope` at reconciliation;
generation plus live grading
remains unmet. See [retained run evidence](e2e.md#live-evidence--2026-09-11).
**Dependencies:** H-015/H-016; reuse H-011/H-012 negative-path tests.

Work:

- First exercise the ordinary full workflow and evaluator handoff with fake
  providers. Then, with explicit credentials/network/spend approval, generate
  the original Hello World spec using the selected real generation provider
  and grade it with the selected OpenAI or Bedrock judge and checked-in rubric.
- Capture the generated `spec.md`, sidecar, relevant workflow outcome and
  evaluator report. Do not substitute a hand-authored spec, fake generation or
  a preselected best run in the live milestone's evidence.
- Exercise success, malformed generation, real missing/conflicting authority,
  clarification handling, cancelled/failed execution and judge failure. Use
  separate negative fixtures rather than silently modifying `stories.md`.
- Prove complete rerun replacement of registered replaceable outputs and
  unresolved clarification forms at the same IDs/paths, byte-identical
  user-resolved form preservation, and rejection of stale-artifact evaluation
  after a failed/blocked rerun. Include shorter replacements, unsubmitted
  drafts and an unrelated registered workflow in the shared-boundary tests.

Acceptance:

- [ ] Actual live generation followed by the selected provider's rubric judgment completes for
  the unchanged Hello World case; report all findings, including low scores.
- [ ] A clarification-required result is reported honestly but does not stand
  in for the requested successful-generation-and-evaluation milestone.
- [ ] Correct source behaviors and unsupported additions are assessed through
  the rubric, not full-document string equality.
- [ ] Any chosen quality threshold is reported separately from whether the
  harness successfully executed; failed attempts remain available for review.
- [ ] Tests prove no fixture mutation, no unrelated target access and no
  unauthorized writes/commands or external judge influence on engine authority.

## H-018 — Add build wiring and correct the documentation

**Status:** Build wiring and documentation implemented; acceptance evidence below. **Owner:** repository build/test entry points and documentation.
**Dependencies:** H-001 for command decisions; deliver alongside H-006/H-015,
complete after H-017. Documentation correction can start immediately.

Work:

- Add repository-owned development harness entry points using `build.zig`
  conventions, with explicit case selection and offline mechanical checks
  separate from live E2E execution. The E2E executable has no mock mode.
  Settle command names once; do not document invented commands as available.
- Keep ordinary verification offline. Live evaluation/generation runs are explicit
  opt-in, have approved credentials/spend settings and never silently run in CI.
  Any release-gating/CI policy change needs its own approval.
- Update F0050 to remove its conformance-only goal and deferred-rubric claims.
  Correct stale implementation findings and references to absent
  `TEST_HARNESS.md`; link to one current harness design/backlog entry point.
- Update F0100 and relevant overview/diagram links for the generation/evaluation
  separation. Do not put evaluation scores inside the production completion
  contract or restore removed transaction/ownership machinery.
- Document fixture setup, rubric editing, supplied-spec grading, full-workflow
  evaluation, credentials, costs/usage, report interpretation and failure states.
  Keep judge instructions concise and criterion wording in the rubric file.

Acceptance:

- [ ] Documented commands exist and are exercised; they identify the case,
  generation mode and judge mode without relying on the shell's ambient project.
- [ ] Harness resources/development tools are excluded from native production
  packaging; production runtime changes pass the clean-environment smoke suite.
- [ ] Relevant targeted/schema/architecture tests and `zig build verify` pass
  for implementation changes, with exact commands/results recorded.
- [ ] Documentation agrees that live LLM rubric evaluation is the goal, while
  mocks/goldens serve only their explicitly limited regression-test purposes.
- [ ] Removed/obsolete documentation and code have no competing fallback,
  compatibility shim, unused entry point or duplicate rubric authority.

Current harness commands are `e2e-spec`, `evaluate-spec`, `test-e2e-harness`,
`test-rubric-evaluator`, `build-e2e-harness`, `build-rubric-evaluator`,
`smoke-e2e-harness` and `smoke-rubric-evaluator`. `zig build verify` includes
the offline mechanical and smoke checks. Live commands are explicit and retain
results separately; see [E2E instructions](e2e.md).
