# FIX02 — Phased rollout of independently configured assessments

**Date:** 10 October 2026.

**Status:** Proposed rollout. No implementation phase or semantic acceptance is
complete by creation of this document.

**Scope:** The supplied “Assessment actions and independent model configuration”
handoff: route existing semantic assessments through `models.slots.assessment`
while generation and authorized repair retain their existing bindings.

[FIX01](FIX01.md) remains the active reliability backlog. This document details
the proposed assessment-routing work and its verification gates; it does not
replace that backlog, accept the overall **Proposed design**, amend an accepted
ADR, authorize implementation, or authorize live calls. Existing working-tree
changes and historical experiment records must be preserved.

## Outcome and boundaries

An operator can select a supported provider, model and reasoning effort for
assessment independently of generation and repair in the existing
`.sddtoolkit.json`. The selected workflow explicitly chooses the slot. Native
code continues to own subject identity, revisions, source selections, admission,
repair permissions, transitions, accounting and publication.

The causal problem is shared configuration: the supplied Spec workflow currently
uses `spec_generation` for authoring, source/principle review and loss attribution.
A correct omission finding can be followed by incorrect upstream attribution,
unnecessary regeneration and recurrence. Independent selection permits controlled
measurement of those judgments; it does not establish that a different model or
higher reasoning effort will improve them.

Assessment is a semantic role of an existing action, not a new pipeline-node kind
or execution subsystem. Each assignment asks one question about one bound subject
or explicitly assigned collection. Output assessment and defect attribution remain
separate assignments with their existing purpose-specific closed findings and
evidence contracts. There is no additional universal pass/fail, score or confidence
contract. A valid shape or citation is not proof of semantic correctness.

Keep evidence preparation, one model invocation, response admission and evidence
application separate. No action invokes another action, owns a hidden review
loop, selects its successor or gains publication capability. The generic engine
contains no Spec-specific assessment routing.

This rollout adds no assessment calls, second judge, voting, fallback,
retry-until-approved behavior, new repair permission, verdict reassessment,
provider implementation or production dependency. It does not implement
[FIX01-01](FIX01-01.md)'s outstanding comparison lifecycle or resolve its separate
exact-reference and invalid-diagnostic-evidence repair limitations.

## Governing contracts and current owners

The relevant baseline is [design §§1, 3 and 4](../design/design.md), including
invariants 1, 5–9, 19–23 and 24–30; §30's staged delivery; and §31 acceptance
criteria 1–2, 5–8, 12, 14–15 and 22. Focused contracts are
[§9 configuration](../design/contracts/09-configuration.md),
[§12.1 and §12.7 model lifecycle](../design/contracts/12-model-boundary.md),
[§13.4 model actions](../design/contracts/actions/13-04-model.md),
[§17 Spec](../design/contracts/17-specify.md),
[§21 validation](../design/contracts/21-validation.md),
[§22 repair](../design/contracts/22-repair.md),
[§27 observability](../design/contracts/27-observability.md) and
[§28.7–28.8 testing](../design/contracts/28-testing.md).

**Authority prerequisite:** [accepted ADR 0021](../design/decisions/0021-optional-source-preservation-review.md)
explicitly assigns generation, review and loss localization to `spec_generation`
and describes the two referenced slots. Implementing the handoff requires a
narrow approved amendment to that paragraph. A local YAML interpretation would
contradict accepted routing authority. Phase 0 prepares that decision; this plan
does not silently supersede it. ADR 0021's optional-review behavior, mandatory
review gates, shared repair slot and absence of fallback remain intact.

| Owning boundary | Current source and rollout responsibility |
| --- | --- |
| Workflow routing | [spec.workflow.yaml](../design/workflows/spec.workflow.yaml): `review-support.model` and `review-support.loss-model` currently select `spec_generation`; change these shared request origins after Phase 0. |
| Configuration shape | [configuration schema](../design/schemas/sddtoolkit-config.schema.json), [native config](../src/domain/config.zig) and [config service](../src/application/sddtoolkit_config_service.zig): named slots already exist. Reuse the single reader and native `ModelsConfig`; no hardcoded slot enum or second reader. |
| Binding and capability validation | [repository model allowlist](../src/domain/repository_model_allowlist.zig), [provider contracts](../src/domain/llm_provider_contracts.zig) and [binding action](../src/actions/provider/resolve_provider_model_binding.zig): retain exact catalogue resolution and supported-control checks. |
| Request and correction lifecycle | [request preparation](../src/domain/model_request_preparation.zig), [request identity](../src/domain/model_request_identity.zig) and [lifecycle](../src/domain/workflow_model_request_lifecycle.zig): preserve the originating binding through consumers and protocol correction. |
| Semantic evidence and repair | Existing source-support, principle and loss owners retain their subjects, schemas, native admission and bounded permissions. FIX01-01 separately owns its comparison-contract cutover. |
| Logging and diagnostic evidence | Existing [exchange capture tests](../src/model_exchange_capture_test.zig), [debugger tests](../src/request_debugger_test.zig) and [request description](../src/domain/model_request_description.zig) must demonstrate the selected slot, provider/model, effort and origin without exposing credentials. |

Shared code changes require a demonstrated gap at one of these owning boundaries.
There is no planned persistence schema, recovery mechanism, provider capability or
security-policy change. Routing changes compiled workflow authority; use existing
binding/change-classification rules and fresh execution, with no compatibility
alias, dual reader or fallback. Runtime/config changes still require the native
packaging smoke check.

## Sequence and completion claims

| Phase | Observable result | Exit gate |
| --- | --- | --- |
| 0 — Confirm authority and baseline | Approved narrow routing decision and complete impact inventory | Applicable authority, baseline settings and verification scope recorded |
| 1 — Cut over routing and configuration | Existing assessments select an independent slot | Coordinated YAML, maintained inputs and routing regressions pass |
| 2 — Qualify lifecycle and offline behavior | Binding isolation survives correction, failure and packaging | Focused tests and full offline verification pass |
| 3 — Compare assessment quality | Isolated evidence for settings/model effects | Approved bounded comparison completes and predeclared quality gates are assessed |
| 4 — Verify production recovery | Evidence that the selected configuration improves actual recovery | Individually approved live production runs and required output rubric satisfy declared gates |

Phases 1–2 are one mechanically complete candidate. Phase 3 is semantic evaluation;
Phase 4 is production recovery evaluation. Report all three statuses separately.
A failed quality gate does not undo proof of routing correctness or justify a
weaker validator. Independent configuration can be complete while quality and
recovery acceptance remain open.

## Phase 0 — Confirm authority, scope and baseline

1. Prepare the ADR 0021 amendment for explicit acceptance: generation retains its
   existing slots; the two shared review/loss origins use `assessment`; authorized
   repair uses `repair`; protocol corrections retain their originating binding.
   Referenced slots are required across the selected compiled graph, including
   statically declared optional branches. Unrelated workflows need no new slot.
2. Inventory every expanded caller of `review-support`, request consumer,
   correction/repair path, failure transition, configured example and fixture.
   Record existing call placement, retry limits, prompts and schemas so routing
   work cannot quietly change them. Do not classify calls by a word such as
   “assessment” in their names: extraction, role assignment and authoring retain
   their current assignments unless included in the explicit routing table below.
3. Capture the effective baseline provider/model, reasoning effort, output
   allowance, temperature policy and response mode. Distinguish absent controls
   from explicitly supplied ones. Plan a mechanically equivalent assessment slot
   first, copying the previous effective review settings; higher reasoning is a
   separately identified comparison arm.
4. Record which FIX01-01 contract is actually active in production. Its staged
   native implementation and historical calibration files do not prove that the
   workflow lifecycle has switched contracts. Select one complete contract for
   each comparison and retain known diagnosis/repair limitations in the record.
5. Identify required documentation amendments and regression tests. Obtain the
   narrow routing decision before implementation; seek additional scope only if
   inspection reveals a necessary contract change outside this handoff.

**Exit:** The routing amendment has explicit authority, all affected owners and
inputs are identified, and a reproducible baseline exists. No live run is needed
to complete this phase.

## Phase 1 — Cut over the two origins and maintained inputs

| Responsibility | Model slot | Scope |
| --- | --- | --- |
| Requirement extraction and specification generation | Existing generation slots | Retain existing assignments. |
| Source-preservation review | `assessment` | Only when the existing review path runs. |
| Candidate source-fidelity assessment | `assessment` | Existing source-support subjects. |
| Principle consistency assessment | `assessment` | Existing selected principles and subjects. |
| Omission/loss attribution | `assessment` | Existing fixed finding and bound evidence. |
| Authorized content or assessment-evidence repair | `repair` | Existing repair authorization only; evidence correction cannot reopen a retained verdict. |
| Schema, identity, citation, coverage and permission checks | No model | Existing deterministic owners. |

Change only the slot selections on `review-support.model` and
`review-support.loss-model`. Their callers inherit those selections. Preserve
`review-support.repair` and all generation bindings. Keep source review
enable/disable behavior, call placement, prompts, schemas, transitions and retry
allowances unchanged for this routing candidate.

Add `assessment` to maintained configurations that consume the supplied Spec
definition. The slot retains the existing shape: required `provider` and `model`,
optional `reasoningEffort` and optional `maxOutputTokens`. This illustrative
fragment demonstrates independent reasoning; it is not a complete configuration
or a production-quality recommendation:

```json
{
  "models": {
    "slots": {
      "spec_generation": {
        "provider": "aws-bedrock",
        "model": "openai.gpt-oss-20b-1:0",
        "reasoningEffort": "low"
      },
      "assessment": {
        "provider": "aws-bedrock",
        "model": "openai.gpt-oss-20b-1:0",
        "reasoningEffort": "high"
      },
      "repair": {
        "provider": "aws-bedrock",
        "model": "openai.gpt-oss-20b-1:0",
        "reasoningEffort": "low"
      }
    }
  }
}
```

Merge it into a complete configuration, preserving other slots and settings.
Every selected tuple must already be supported by compiled provider contracts and
resolve through the captured provider catalogue. A new model string alone cannot
enable an unsupported model. No implicit fallback to generation or repair is
permitted. Provider capability checks, temperature policy and actual-token
accounting remain unchanged; no local size ceiling or token reservation is added.

Expected coordinated edits include:

- [design example](../design/examples/.sddtoolkit.json) and
  [live Spec fixture configuration](../test/e2e/wf-001-hello-world/.sddtoolkit.json).
- Spec configurations in [packaging smoke](../test/packaging/smoke.zig) and
  [offline workflow integration tests](../test/integration/workflow_tests.zig).
  Unrelated generation-only workflows remain valid without `assessment`.
- [Spec generation driver](../src/test_fixtures/spec_generation_driver.zig), whose
  current non-repair expectation assumes `spec_generation`, plus affected routing
  assertions in [Spec generation tests](../src/specification_generation_test.zig).
  Replace that assumption with explicit exhaustive expected responsibilities.
- The approved ADR 0021 paragraph, applicable §§9/12.7/17 routing documentation,
  [model guidance](../design/reference-notes/model-request-guidance.md),
  [Spec model-call diagram](../design/diagrams/21-spec-model-call-tree.md) and
  FIX01's status/reference to this rollout. Retain the diagram's Markdown/Mermaid
  format. Do not change historical captures or scores.

The separate [E2E evaluator configuration](../test/e2e/config/evaluation.json) is
not the production assessment slot. Keep evaluator selection independent. Provider
catalogues need changes only for an explicitly selected already-supported tuple;
do not add a provider implementation as part of this phase.

**Exit:** All applicable maintained inputs resolve the new binding, source and
principle review plus loss attribution use it, and generation/repair retain theirs.
Focused regressions pass; full mechanical completion waits for Phase 2.

## Phase 2 — Qualify lifecycle, failures and offline behavior

Add or extend tests at the existing owning boundaries, using fake narrow ports.
Prove the shared contract with unrelated workflow/subject representatives as well
as the reported Spec path.

| Area | Required accepted and rejected evidence |
| --- | --- |
| Independent binding | Distinct fake provider/model bindings route assessment, generation and repair correctly. The same registered model with low generation/repair effort and high assessment effort retains each exact control. |
| Configuration and graph requirements | Referenced `assessment` resolves; a missing slot rejects before provider I/O, including with an optional branch disabled. An unrelated workflow without that reference still works without the slot. Unknown slot fields, catalogue-missing/unsupported models, unsupported effort and invalid bindings reject through existing owners. |
| Retained controls | Omitted and explicit output allowances preserve their presence/value. Temperature and response mode obey the selected registered model contract. No clamp, default model substitution or local capacity gate appears. |
| Request lifecycle | Initial requests, response consumers, protocol corrections and request retirement retain the assessment origin, subject, identity and binding. Cross-request, stale or foreign evidence rejects. A correction cannot switch to `repair`; a separately authorized repair must use `repair`. |
| Semantic and repair authority | Existing source, principle and loss results retain their typed outcomes. Malformed/unsupported findings, inconclusive results, invalid diagnostic evidence and unavailable repair permission follow existing transitions; none becomes approval. Retained verdicts and old-value/revision checks survive evidence repair. |
| Failure and accounting | Provider/protocol failure, cancellation, retry exhaustion and execution-budget exhaustion propagate unchanged. Actual usage is accounted exactly once, including failed content and overshoot; no fallback or success transition discards failure. |
| Observability | Existing metadata/capture/debugger evidence identifies slot, provider/model, reasoning effort and originating YAML request. Correction and repair links remain inspectable. Credential redaction and metadata-only behavior at higher log thresholds still pass. |
| Generic/runtime behavior | Existing review enable/disable paths and call placement remain intact. No new node kind, hidden orchestration, Spec branch, persisted reader or source-tree fallback appears. Packaged execution validates its supplied configuration in a clean environment. |

Use repository-owned steps from [build.zig](../build.zig); the
[README](../README.md#build-and-verify) defines no separate changed-scope aggregate.
These are planned commands, not results recorded by this document:

```sh
zig build test-specification-generation test-model-request-preparation test-model-request-workflow --summary all
zig build test-provider-conformance test-workflow-graph test-model-logging --summary all
zig build test-engine --summary all
zig build test-architecture lint --summary all
zig build test-integration --summary all
zig build verify --summary all
git diff --check
```

`test-engine` includes configuration, repository-allowlist and provider-binding
tests that have no dedicated build step. Run additional owning-boundary steps
when an actual code change requires them.
`verify` includes the full offline unit/integration, architecture and clean native
packaging smoke checks; it sends no live API calls. Record exact commands, counts,
failures and any missing evidence. Review the complete diff for duplicated policy,
weakened assertions, fallback, new capabilities and unrelated changes.

**Exit:** All required offline checks pass, maintained documentation matches the
approved routing, and the mechanically equivalent configuration is proven. Report
“independent configuration and lifecycle verified,” with semantic improvement and
production recovery still unproven.

## Phase 3 — Compare assessment quality with one factor changed

Freeze a bounded comparison plan before requesting authorization for live calls.
Reuse the existing diagnostic/calibration and provider-request owners. Retain
immutable inputs, prompts, selected closed schema, expected judgments, trial
order, settings and output artifacts; expected judgments stay outside prompts.

Compare these arms on identical evidence and response contracts:

1. **Existing configuration:** assessment uses the baseline effective model and
   controls recorded in Phase 0.
2. **Higher reasoning:** change only the assessment reasoning effort to a supported
   value, retaining provider/model and other controls.
3. **Stronger supported model:** select an exact already-registered provider/model
   with declared supported settings. Report the model/settings comparison as such;
   do not imply that changing a provider or other required control isolates effort.

The existing [call diagnostic](../design/harness/e2e.md#test-one-captured-call)
accepts explicit `--model` and `--reasoning-effort` selections and validates them
through the existing catalogue/allowlist owners. Reuse it for captured requests;
its provider is fixed to the capture and its current binding validator supports
Bedrock. It preserves content, schema, response mode and other controls, performs
no workflow repair, and does not supply semantic scoring. The browser debugger's
content/schema edit does not change the originating model binding.

The [current compiled registry](../src/composition/provider_model_contracts.zig)
supports GPT-OSS 20b with low/medium/high effort and Claude 3.5 Haiku with different
response/control capabilities. This does not establish a stronger compatible arm:
Haiku cannot retain the GPT-OSS capture's native-schema mode and output allowance.
If no suitable stronger model is supported, record that arm as unavailable and
retain the limitation. New provider/model support is separately scoped work. A
necessary harness change must likewise be identified and scoped before execution,
with offline verification through the existing provider path. Never silently
change schema transport or controls to manufacture a comparable trial.

Keep FIX01-01's evidence-contract experiment separate. If its production cutover
lands first, regenerate all model-comparison arms from that complete contract and
freeze a fresh baseline. Do not compare old and new evidence contracts while
attributing the difference solely to model choice. Retained source-loss calibration
files are historical evidence, not reusable current-contract requests or renewed
live authorization. When FIX01-01's lifecycle cutover lands, its preservation
comparison requests use `assessment` through the shared loss-request origin;
native attribution and repair authorization remain separate owners.

Use repeated paired trials, varied ordering, independently reviewed expected
judgments and held-out source families. Include candidate-local loss, genuine
upstream loss, source-only omission, preserved paraphrases, joint support,
condition/negation/obligation changes, principle conflicts, uncertain evidence and
correct attribution with unavailable repair. Score detection and attribution as
separate assignments; a correct verdict with irrelevant evidence remains defective.

Before dispatch, specify sample sizes, exact physical-call allowance, cost limit,
stop rules, expected outcomes and quality thresholds. Include failed, empty and
unusable responses in denominators; do not retry until the desired result appears.
Measure incorrect attribution, missed defects, unsupported acceptance, uncertainty,
unnecessary upstream-repair decisions, latency and actual input/output tokens.
Record priced cost with its rate basis, distinguishing estimates from actual usage.
Diagnostic trials measure proposed repair decisions; successful workflow recovery
and its total cost require Phase 4.

**Exit:** The approved comparison completes with an auditable scorecard and an
explicit pass/fail/inconclusive judgment against its predeclared gates. Promote a
quality recommendation only when its gate passes. Otherwise retain independent
configuration, document the result and leave quality acceptance open. Historical
allowances are consumed; this document grants no new calls.

## Phase 4 — Verify production recovery and publication

Select explicit target test projects, the Spec workflow (`spec-generation`, using
the Specify invocation), reference cases, model settings, evaluator and expected
terminal outcomes before each live run.
Use the [production E2E harness](../design/harness/e2e.md) with the real configured
LLM, external services and required rubric evaluation of actual published output.
Obtain explicit approval before **each** E2E run; diagnostic approval is separate.

Include the motivating failure and unrelated held-out representatives. Retain
complete request origins, findings, attribution, repair authorizations, dependency
invalidation, actual usage, publication results and rubric evidence. Establish
whether a correct attribution leads to an existing permitted repair, preserves
unaffected work, avoids unnecessary upstream rebuilding and prevents recurrence.
Also report correct blocking where repair is unavailable. Correct diagnosis alone
is not successful recovery.

Measure recovery rate, repeat defects, unnecessary upstream repairs and total
workflow cost against the declared baseline. Inspect internal evidence separately
from the whole-spec rubric: the evaluator does not independently prove repair
causality or every intermediate principle judgment. Record execution, publication
and quality outcomes separately; a zero harness exit is insufficient for quality
acceptance while [FIX01 R8](FIX01.md#r8--development-acceptance-policy-explicit-decision-required)
remains unresolved. Changing automated acceptance policy requires its own decision.

**Exit:** Declared production recovery and rubric gates pass with inspectable
evidence. If execution, authorized repair, publication or evaluation cannot finish,
record the unmet criterion and keep this phase open. Never substitute an offline
fake, supplied specimen or golden-document comparison for E2E completion.

## Rollout status

| Milestone | Current status |
| --- | --- |
| Phase 0 routing amendment and baseline | Proposed; no acceptance recorded here. |
| Phase 1 routing/configuration implementation | Not implemented by this task. |
| Phase 2 offline mechanical qualification | Not run by this task. |
| Phase 3 semantic comparison | Not run; separate bounded live authorization required. |
| Phase 4 production recovery and rubric | Not run; explicit approval required for each E2E run. |

Update FIX01 with implementation status and links to evidence when the rollout is
executed. Keep outstanding FIX01-01 comparison, repair-permission and diagnostic
limitations visible. This plan creates no new completion authority and makes no
claim of improved semantic outcomes.
