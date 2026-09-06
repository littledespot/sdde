# Spec workflow dependencies

[Backlog index](README.md). These are production-engine dependencies for the
**run-workflow-and-evaluate** path. They are not prerequisites for evaluating an
already supplied specification through H-003–H-006.

Production validation and the external rubric have different purposes. A rubric
can judge a readable specification without a complete parser; it cannot grant
the engine permission to bypass its current safety/publication contracts.

## H-007 — Align the existing specification contract

**Status:** Open — narrow production decisions remain. **Owner:** F0100 and
canonical specification types. **Dependencies:** none; independent of H-001.

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

- [ ] One production schema/renderer/parser contract owns structure and IDs.
- [ ] Optional empty content cannot be turned into fabricated requirements.
- [ ] Semantic adequacy remains a model-assisted/human judgment, not a claimed
  consequence of schema or Markdown validity.
- [ ] F0100/design/code examples agree; no legacy `OQ-*` route emits questions
  into `spec.md`.

Targets: [F0100 §5](../features/F0100-SpecWorkflow.md#5-specmd-projection-contract),
Design §§7/17/23 and their schema/render samples. This ticket does not create
an exact semantic expected `spec.md` for the harness.

## H-008 — Implement the shared required-authority boundary

**Status:** Open. **Owner:** shared domain/actions; Specify contributes evidence.
**Dependencies:** H-007 for concrete Specify registrations, not for all generic
mechanics. Governing source: Design §12.8 and acceptance criteria 36–40.

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

- [ ] Missing, duplicate, foreign, stale, unsupported and conflicting support
  cannot pass a gate or enter ordinary repair as invented content.
- [ ] Tests exercise the same mechanics across unrelated requirement kinds;
  implementing the full Plan/Tasks workflows is not required for those tests.
- [ ] Signals/conflicts have one validation owner and complete provenance.
- [ ] The external judge's score is not a candidate resolution or gate token.

## H-009 — Connect reference operations to model execution

**Status:** Open — foundations exist. **Owner:** registered reference/model
operations. **Dependencies:** reuse current generic request lifecycle work;
H-008 is required at applicable production authority gates.

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

- [ ] Fake provider responses traverse the same domain pipeline as live ones.
- [ ] Production generation/reconciliation does not depend on a fixture-name
  branch, source-tree fallback or hidden built-in workflow graph.
- [ ] Protocol failures, budget exhaustion and semantic conflicts retain their
  distinct outcomes. No failed chunk or unresolved conflict disappears.
- [ ] Source-preserved `Hello, World!` reaches downstream data unchanged.

Targets: native model/reference operation bindings, F0006 and F0100; reuse the
existing targeted extraction/reconciliation/provider tests before extending them.

## H-010 — Generate and validate specification content

**Status:** Open. **Owner:** registered specification actions and typed IR.
**Dependencies:** H-007–H-009.

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

- [ ] Typed output covers the approved section families without invented filler.
- [ ] Generator-supplied IDs, operational paths, unsupported source claims and
  forged completion assertions cannot enter accepted workflow output.
- [ ] Semantic principles/Node/Vitest preferences cannot invent business
  requirements. The generation packet follows Specify's business boundary.
- [ ] Fake tests cover supported content, malformed output, semantic uncertainty,
  preservation and failed repair without fixture-specific success rules.

## H-011 — Complete specification clarification handling

**Status:** Open — read-only input/form validation exists. **Owner:** shared
clarification lifecycle with Specify registrations. **Dependencies:** H-008;
H-010 supplies unit needs. Coordinate output handling with H-012.

Work:

- Build/reuse stable subject-keyed `SNN` needs and controlled forms under
  `<paths.specs>/<feature>/clarify/`; never insert questions into `spec.md`.
- Accept only current applicable authenticated answers/authority resolutions
  through the existing clarification contract, not a score or model assertion.
- Preserve every user-closed form byte-for-byte, including stale or invalid
  closures. Those require user direction, not automatic rewriting/reopening.
- End `needs_user` runs and start subsequent invocations at the workflow's
  beginning with current inputs; do not add a saved continuation.

Acceptance:

- [ ] Repeated detection does not create duplicate subject IDs or overwrite a
  user's answer. An applicable response is reused on a fresh run.
- [ ] Pending/stale/invalid closure and concurrent-close cases cannot overwrite
  the protected file or publish partial successful specification output.
- [ ] The harness observes clarification separately from generation failure and
  never invents answers to obtain a scoreable specification.
- [ ] Unchanged prior `spec.md` after a blocked rerun is not labelled new output.

## H-012 — Render and publish the complete workflow output

**Status:** Open. **Owner:** production renderers/parser and publication boundary.
**Dependencies:** H-007/H-010; H-011 protection on clarification branches.

Work:

- Render `spec.md` and required `reference-context.md` from validated typed
  data; implement editable-spec parsing and normalized round-trip checks.
- Assemble the required canonical reference/provenance/workflow state and
  feature-log evidence using existing path/identity owners.
- Publish only complete successful workflow output. Preserve the explicit
  clarification persistence exception and abandon unsuccessful candidates.
- Overwrite existing registered workflow outputs at the same paths on success,
  including previously edited specs; never overwrite user-closed clarifications.

Acceptance:

- [ ] The same accepted structured payload renders byte-stably. Different valid
  model-generated specifications are not required to be byte-identical.
- [ ] Required sidecar/state joins, round-trip checks and write authorization
  pass before publication; failed runs do not expose partial success.
- [ ] Rerun, interruption, write failure and protected-closure tests cover the
  whole output boundary without a transaction directory/WAL/checkpoint layer.
- [ ] Configured `paths.specs` supplies the root; neither caller nor model
  repeats/hard-codes `specs/` or chooses artifact paths.

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
