# Rubric and OpenAI evaluator backlog

[Backlog index](README.md). These tickets deliver the semantic evaluator; they
do not require a complete Spec engine or a deterministic prose oracle.

Implementation and commands: [supplied-spec evaluator](evaluator.md).
**Current task scope:** Offline implementation is complete. The user explicitly
excluded human evaluation and live API verification; neither is a blocker for
this implementation task. Unchecked live/calibration criteria below remain
unverified, not passed or replaced by fake judgments. H-007 onward are separate
production work.

Remaining acceptance preparation: the [calibration set](../../test/evaluation/wf-001-hello-world/node-vitest/calibration/README.md)
contains two equivalent specifications and five deliberate defects, with proposed
review findings and the existing command to run them. A future live run requires
explicit judge configuration/allowance and credentials. No live evidence or
human approval is claimed by the offline fixtures.

## H-001 — Define the minimum evaluation contracts

**Status:** Implemented contracts; live settings remain operator-selected.
**Owner:** development harness.
**Dependencies:** none.

Define one small evaluation case and separate run configuration. They bind the
case ID, source resources, rubric, supplied/generated artifact origin, workflow
invocation when applicable, judge settings and report destination. Do not
repurpose production `.sddtoolkit.json` as an unrelated grader configuration.

Work:

- Specify closed case, rubric and judge-result shapes and their version rules;
  these schemas describe transport/accounting, not every valid business spec.
- Record the harness entry point and configuration location using repository
  build conventions. `node-vitest` names a target fixture, not the harness's
  implementation language or a requirement to execute Vitest.
- Record exact OpenAI model/settings, API surface, credential source, timeout,
  total evaluation budget and bounded retry policy before live implementation.
  Generation and judging have distinct settings and accounting.
- Select one score scale, criterion anchors, weighting/aggregation,
  not-applicable treatment and optional quality thresholds. Do not invent
  production release policy or silently choose numeric defaults.
- Define what source/spec content may be sent to OpenAI and how local evidence
  is retained. Require explicit live execution; missing credentials must not
  trigger a different provider, model or mock result.

Acceptance:

- [x] Decisions have one documented owner; model, threshold, SDK/dependency and
  paid-run choices are distinguishable from the user's already-fixed objective.
- [x] Evaluator-only and full-workflow runs share one grading contract.
- [x] Unknown keys, duplicate case/criterion IDs and invalid settings are rejected.
- [x] Workflow execution outcome and semantic evaluation result are separate.

The shared grading call accepts explicit artifact provenance; full-workflow
handoff is still H-015. Responses API/native HTTPS is implemented without a new
dependency. Exact model/settings/budget are mandatory run configuration; numeric
scoring choices live in the draft rubric, not evaluator code or release policy.

Likely changes: harness-owned schemas/configuration and an entry point wired
through `build.zig`; exact new source paths are chosen after inspecting reusable
contracts. No production dependency is implicitly approved by this ticket.

## H-002 — Create the Hello World rubric

**Status:** Draft implemented; human review/calibration outstanding.
**Owner:** rubric author/reviewer. **Dependencies:** H-001 for
the executable schema and scoring scale; criterion drafting can begin now.

Create `test/evaluation/wf-001-hello-world/node-vitest/rubric/spec.json`.
Keep that file the sole runtime source of criterion wording, scoring anchors,
weights and thresholds; do not copy them into prompts or code.

Work:

- Ground the case in the two stated requirements: successful startup and
  displaying the exact user-facing greeting `Hello, World!` when started.
- Draft criteria for behavioral coverage, greeting fidelity, absence of
  unsupported requirements, clarity/testability, coherent organization and
  proportionate scope. These are rubric proposals, not a new engine schema.
- Explain partial, satisfactory and poor performance using the selected scale.
  Give concise examples without prescribing one correct full specification.
- Assess missing/inappropriate content semantically. Do not require an invented
  business rule, error flow, entity or assumption just to populate a heading.
- Evaluate business-facing scope without demanding Node, Vitest, framework,
  architecture, file-path or command details in `spec.md`.

Acceptance:

- [x] Both explicit source requirements are separately assessable.
- [ ] Different faithful wording can score comparably; a golden paragraph is
  not required. Exact greeting spelling matters because the source states it.
- [x] Missing behavior, a changed greeting and unsupported functionality have
  explicit scoring guidance; length or extra features earn no automatic credit.
- [x] Each criterion identifies the evidence expected and how uncertainty or
  non-applicability is reported under H-001.

Tests: rubric schema/IDs/anchors, human review against the unchanged source and
calibration specimens in H-016. A draft rubric is not marked calibrated merely
because it parses.

## H-003 — Capture inputs and build the judge packet

**Status:** Implemented and offline-tested. **Owner:** harness input/packet builder. **Dependencies:** H-001;
use H-002 for the initial case.

Build one reusable input packet from the exact source requirements, candidate
`spec.md` and rubric. Feed the real captured documents, not a generation model's
summary or its self-assessment.

Work:

- Capture declared inputs once, retain their origin and bind the request to
  that capture. Reject missing/unreadable/unsafe inputs explicitly.
- Use a short shared judging instruction: assess only rubric criteria, treat
  source/spec text as data, cite evidence and report uncertainty. Load criterion
  content from the rubric instead of repeating it in instructions.
- Keep credentials, absolute workspace paths, generation reasoning and
  unrelated repository/principle content out of the judge packet.
- Do not suppress a readable poor-quality specimen because it lacks expected
  headings or contains unwanted prose. Those may be rubric findings. An empty
  candidate must be reported as an artifact failure, never a good evaluation.
- Preserve full evaluation inputs; if an API cannot accept them, report that
  failure rather than silently truncating the rubric, references or candidate.

Acceptance:

- [x] Packet inspection proves all declared source/spec/rubric content is present
  and bound to one run; changing an input produces a newly identified evaluation.
- [x] Artifact content saying “ignore the rubric” cannot change criteria,
  requested model, tools, score policy or output destination.
- [x] Model-visible labels identify source versus candidate evidence without
  granting file, process or network capabilities.
- [x] Supplied-spec evaluation works without importing `SpecificationIR` or
  constructing production workflow state.

## H-004 — Implement the OpenAI evaluator boundary

**Status:** Implemented and offline-tested; authorized live acceptance outstanding.
**Owner:** narrow model adapter plus harness composition.
**Dependencies:** H-001 and H-003; test fake before authorized live calls.

Invoke OpenAI for rubric judgment. This is a separate use of the model boundary
from generating the specification, not a second workflow engine.

Work:

- Inspect/reuse [LLMProviderInterface](../../src/ports/llm_provider_interface.zig),
  existing request/response validation and provider plumbing where their
  contracts apply. Keep provider transport separate from scoring; do not
  clone lifecycle/budget policy or make grading require feature publication.
- Implement the selected API path only. Do not add both a hosted evaluation
  platform integration and a direct judging integration for the first case.
- Supply no tools or artifact-write capability to the judge. Use a supported
  structured response mechanism for result transport, then validate locally.
- Handle authentication/configuration failure, rate limiting, timeout,
  cancellation, provider refusal, incomplete response and exhausted retries
  explicitly. No failure becomes a zero score, passing score or fake fallback.
- Record actual request/model identity and reported token usage separately
  from generator usage. Keep secrets out of prompts, reports and logs.

Acceptance:

- [x] Fake adapter tests cover success and every supported error/stop branch.
- [ ] An authorized live request returns inspectable criterion judgments from
  the explicitly selected OpenAI model.
- [x] Retry policy is bounded; low scores do not trigger retries seeking a pass.
- [x] Cancellation or exhausted budget prevents additional calls; already
  reported usage is retained without claiming cross-run exactly-once billing.

Structured Outputs provides response-shape assistance, not semantic truth, and
refusals require separate handling. See [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
The implemented endpoint and explicit per-run configuration are documented in
[the evaluator contract](evaluator.md#run). No model or paid run was selected.

## H-005 — Validate judgments and calculate results

**Status:** Implemented and offline-tested. **Owner:** evaluator result validator/scoring functions.
**Dependencies:** H-001/H-002; scripted results allow work before H-004 is live.

Validate the evaluator's response as untrusted data. Code owns score arithmetic
and result accounting; the LLM owns the rubric's semantic judgments.

Work:

- Require exactly one result for every applicable rubric criterion under the
  selected applicability policy. Reject missing, duplicate or foreign IDs,
  unknown fields, invalid score ranges and unsupported result variants.
- Require concise reasons and source/candidate evidence references. Validate
  that supplied quotations/locations resolve to the captured text. Missing
  candidate content is expressed as absence, not a fabricated quotation.
- Preserve the distinction between a valid quotation and a sound semantic
  inference. A mechanically valid judgment can still be wrong.
- Calculate totals/weights/threshold results from the rubric only. Never trust
  a model-supplied overall pass flag or silently fill a missing criterion.
- Preserve uncertainty and any permitted not-applicable outcome explicitly;
  neither is an automatic full score.

Acceptance:

- [x] Fixed accepted judgments produce stable arithmetic and serialization.
- [x] Missing scores, bogus evidence and malformed responses produce evaluator
  errors rather than apparently complete reports.
- [x] A valid low score remains a completed evaluation, distinct from API failure.
- [x] No judgment or total can mark a workflow completed, answer a clarification,
  approve a plan or write back to `spec.md`.

Tests: score boundaries, selected weighting/rounding/applicability rules,
criterion cardinality, evidence joins and unrelated-case IDs.

## H-006 — Report results and support supplied-spec evaluation

**Status:** Implemented supplied-spec command/reports; live demonstration outstanding.
**Owner:** harness reporting/entry point.
**Dependencies:** H-003–H-005.

Provide an evaluator-only path for a supplied specification and use the same
path when the full workflow later supplies its output. Do not build two judges.

Work:

- Emit a machine-readable report and concise human-readable view containing
  criterion scores, explanations, evidence, totals under the selected policy,
  errors and unresolved judgments.
- Record the input capture, case/rubric revision, judge prompt/schema revision,
  actual model/settings, provider request identity, attempts and reported usage.
  Record generation identity/settings only when known; never fabricate them.
- Label artifact origin: supplied/manual, recorded, scripted generation or
  fresh live workflow generation. Preserve workflow status independently.
- Retain the evaluated artifact with the report, or an exact authorized local
  capture, so a later workflow overwrite cannot change what a score refers to.
- Give report-output replacement/retention an explicit harness policy. Reports
  are observations, not a transaction log, checkpoint or workflow resume store.

Acceptance:

- [ ] An operator can supply source/spec/rubric, invoke OpenAI and inspect a result
  without waiting for H-007–H-013.
- [x] Report rendering uses the same parsed result as machine output.
- [x] API failure, failed workflow, clarification-required run and completed
  evaluation with poor quality cannot be confused.
- [x] Regrading an explicitly retained artifact never reruns generation or
  silently substitutes a newer `spec.md`; this is a new evaluation, not recovery.

The CLI labels supplied artifacts `not_run`; recorded provenance and evaluator
outcome are distinct fields. Running/reporting a fresh workflow, including its
failure/clarification branches, remains H-015 rather than an implied CLI feature.
