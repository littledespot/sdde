# Engine intent

**Status:** Statement of intent supplied by the project owner on 17 October 2026.
It explains what the engine is for and how success is judged. It orients judgment;
it is not contract authority. It does not accept the [Proposed design](design.md),
amend an [ADR](decisions/) or establish that any capability is implemented or
proven. The refinement toward smaller semantic decisions remains under evaluation
in [FIX06](../fixes/FIX06.md). Where this statement and a governing contract
differ, report the difference rather than choosing between them.

---

**The engine's intent is to turn source material and user requirements into
traceable, validated development outputs through configurable workflows, using
lower-capability LLMs for focused semantic work and deterministic code for
everything that can be computed reliably.**

The following describes the intended architecture and outcomes, including the
proposed move toward smaller semantic decisions. It does not imply that every
capability is implemented or proven.

## Reusable execution foundation

**The engine provides a reusable execution foundation.** Specification generation
is its first major use case, but its execution logic must remain independent of any
particular development stage, business domain or model. Workflow definitions supply
the sequence, inputs, outputs and permitted transitions.

For the initial specification-driven development process, the intended progression
is:

| Stage | Intended outcome |
|---|---|
| **Specify** | A business specification that faithfully expresses the supplied requirements, with acceptance criteria and traceability to original evidence. |
| **Plan** | A supported technical approach that satisfies the specification and applicable project constraints. |
| **Tasks** | An actionable work breakdown with dependencies, verification expectations and links to governing requirements and design. |
| **Implement** | Changes that fulfil authorised tasks and pass the applicable verification gates. |

Additional workflows should use the same execution mechanisms without adding
workflow-specific branching to the generic engine.

## Engine and toolkit

**The toolkit makes the generic engine useful for a particular process.** The engine
supplies execution capabilities; the toolkit packages the workflow definitions,
prompts, schemas, guidance and supporting configuration that describe how those
capabilities are applied.

| Element | Intended responsibility |
|---|---|
| **Generic engine** | Execute validated workflow definitions and enforce shared execution rules. |
| **Toolkit** | Supply a coherent set of workflows and supporting resources for an intended development process. |
| **Workflow definitions** | Declare operations, dependencies, model assignments, outcomes and transitions. |
| **Actions** | Perform one cohesive operation through narrowly scoped capabilities. |
| **Orchestrators** | Coordinate child operations and branch on typed outcomes. |
| **Runner** | Invoke operations, validate and apply their results, and maintain execution control and accounting. |
| **LLMs** | Interpret meaning, draft content and perform explicitly scoped semantic assessments. |
| **Validators and toolchain** | Check computable properties and provide executable evidence where applicable. |
| **Configuration** | Select authorised models, resources, policies and execution settings. |

Toolkit resources remain declarative. They must not bypass the engine's validation,
introduce arbitrary executable behaviour or create a competing source of workflow
authority.

## Semantic versus deterministic work

**The central responsibility boundary is semantic versus deterministic work.**

The LLM handles tasks such as interpreting a business requirement, recognising a
meaningful conflict, drafting an acceptance criterion or assessing whether an output
preserves a condition.

The engine handles identifiers, source locations, reference resolution, schema
validation, dependency tracking, output assembly, permitted transitions, retry
limits, accounting and publication. It derives provenance from validated selections
and captured evidence wherever possible.

A model response is always **candidate data**. A model saying "valid," "complete" or
"approved" does not establish those states. Equally, valid JSON and valid citations
do not establish that the model understood the requirement correctly.

## Small, complete semantic decisions

**The proposed refinement is to organise model work around small, complete semantic
decisions.** Single responsibility remains the code-design principle, while semantic
simplicity governs the assignments sent to models.

Each assignment should identify:

- The exact judgment or content to produce.
- Its scope and the purpose of the affected output.
- Relevant original evidence and applicable constraints.
- Conditions, exceptions and dependencies that must remain together.
- The permitted response structure and how the result will be assessed.
- How to express unresolved interpretation or genuinely missing information.

The aim is to reduce reasoning difficulty per assignment. An action with one
responsibility can still give a model an overly complicated task. Conversely,
splitting a requirement into isolated fragments can destroy the context needed to
interpret it.

For example, a cancellation rule and its "after dispatch" exception should remain
together. Checking whether an individual statement is supported should remain
distinct from checking whether the complete specification covers all required
behaviour.

## Source fidelity

**Source fidelity must survive every transformation.** Ingestion should account for
all supplied sources and retain the evidence needed to trace derived content back to
them. Extraction, reconciliation and generation must preserve conditions, negation,
obligation strength and exact values.

Generated summaries and earlier drafts must not silently replace original evidence.
Missing information, contradictory sources and model misunderstanding must remain
distinguishable. The engine must not convert uncertainty into invented requirements
simply to progress.

## Validation

**Validation should prevent errors from spreading through the workflow.** Structural
and reference checks belong at the earliest applicable boundary. Semantic assessment
should evaluate meaning against the correct source and assigned purpose.
Whole-output validation must still detect omissions, contradictions and
inconsistencies across otherwise acceptable individual results.

Assessment is itself fallible. A configurable assessment model may help allocate
greater capability to difficult judgments, but its findings still require evidence
and controlled handling. The system must avoid treating an incorrect diagnosis as
unquestionable authority for further changes.

## Repair and clarification

**Repair must be bounded and preserve correct work.** A repair should address an
identified defect within an authorised target, retain relevant source bindings and
trigger validation of affected dependencies. Failed retries must not weaken
requirements or redefine success.

When the source genuinely lacks a necessary decision, the workflow should request
clarification. When the model cannot interpret available evidence reliably, that
should remain an explicit unresolved outcome rather than a fabricated user question
or unsupported answer.

## Toolchain verification

**The toolchain supplies verification where the work supports it.** Planning and
implementation can use parsers, compilers, linters, tests and other configured
tools. Specification work relies more heavily on source fidelity and semantic
assessment because business meaning is often not executable. The engine must
distinguish deterministic evidence from model-assisted judgment.

## Success

**Success means producing useful, faithful outputs at an acceptable total cost.** It
should be demonstrated through action and contract tests, workflow integration
tests, focused semantic evaluations using the intended models, and end-to-end
assessment of actual published outputs.

The important measures are requirement preservation, unsupported additions, false
assessments, repair-induced harm, successful completion, latency and cost per
acceptable result. Passing structural tests or increasing the number of successful
model calls is insufficient.

The intended result is an engine that makes lower-capability models useful through
clear assignments, reliable evidence and controlled execution, while explicitly
stopping when their semantic capability is insufficient.
