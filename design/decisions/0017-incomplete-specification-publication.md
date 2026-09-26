# ADR 0017: Publish an incomplete specification with clarification gaps

- **Status:** Accepted
- **Date:** 2026-09-19
- **Decision authority:** Explicit user direction to update documentation and remediate missing `spec.md` on clarification pauses.
- **Amends:** ADR 0009's clarification persistence exception; Design §§3.3.5, 3.3.19–20, 3.3.30, 17, 23.2, 25 and 31; F0100 §5.5.

## Decision

Specify publishes `spec.md` even when specification-owned clarifications remain open.
This is a validated incomplete projection, never a completed `SpecificationIR` or
`specified` authority. The workflow ends `needs_user`; Plan and all later stages
remain blocked. The governing design retains its Proposed status.

This applies to a valid `needs_user` outcome, not an execution that fails while
open forms exist. Unrepaired JSON/schema rejection remains a terminal error under
[§22.6](../contracts/22-repair.md#226-unparseable-output), with no new specification
publication. Successful correction may continue to a validated clarification pause.

The [§12.8.1 corrective admission contract](../contracts/12-model-boundary.md#1281-clarification-admission-and-candidate-failure-precedence)
defines which findings can establish that pause. Unresolved candidate or review
failure cannot become `needs_user` merely because another valid question exists.
That enforcement is implementation work tracked in FIX_002, not a delivered result.

A clarification pause publishes the complete registered set: incomplete `spec.md`,
current `reference-context.md`, clarification registry/forms, and a canonical
`spec_clarification_pending` workflow-state variant. The pending state replaces
previous completion authority and is written last by the existing shared writer.
All output, path, captured-input and protected-form checks apply before writing.
Failure never records successful completion; fresh runs start at `start`.

The incomplete document visibly states its status, displays retained cited business
requirements and scope constraints from the current validated reference snapshot,
and links every open Spec clarification to its engine-owned `clarify/SNN.md` form.
It does not invent missing fields, infer a completed story, assign final requirement
IDs, render technical claims as business requirements, or resolve conflicts.
Conflicting and superseded claims are not asserted as supported requirements.
Questions and answers remain in controlled forms. No extra model call is needed to
make already available business content visible when the source gate pauses before
generation. All source, generation and candidate-review clarification branches use
the same projection/publication path.

The pending variant retains current reference evidence, clarification identity/revision
and open IDs, plus the existing specification ID ledger for future allocation. It
contains no runner continuation, saved model operation or completion evidence.
The complete-state schema and validators remain strict; pending cannot be loaded as
specified or graded as a completed specification. The incomplete Markdown is a view,
not an alternative input authority; reruns regenerate it and preserve user-closed forms.

## Acceptance criteria

- Source, generation and post-generation gaps publish the incomplete document and real
  question links for arbitrary feature directories and unrelated business domains.
- Supported business statements survive; technical, conflicting and superseded content
  cannot silently become supported specification content.
- Pending and specified have distinct closed state variants. Unknown fields, stale
  clarification/reference bindings, invalid links and attempts to treat pending as
  completion reject. A completed-to-pending rerun revokes prior completion.
- Reruns replace all views, retain monotonic specification IDs and protected closed forms,
  and can converge from pending to specified without resuming a checkpoint.
- Validate the entire pending output before writes; every write failure remains failure.
- Existing open forms cannot turn protocol exhaustion or another terminal failure
  into pending publication; rejected model data never supplies the incomplete view.
- E2E reports distinguish publication of an incomplete document from completion and
  grading. `needs_user` remains ungraded and reports the published specification path.
