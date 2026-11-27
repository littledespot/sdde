# ADR 0033: Generic repair operations with owner-supplied rules

- **Status:** Accepted
- **Date:** 2026-10-22
- **Decision authority:** User decisions, 22 and 23 October and 13, 20 and 21 November 2026.
- **Amends:** [ADR 0005](0005-workflow-defined-operations.md) ("Each operation has one current
  contract") and [ADR 0031](0031-stage-actions.md) (repairs); design.md §22; contracts §13.4,
  §14.4, §22.1 and §22.7; [F0005](../features/F0005-WorkflowDefinitionRegistryService.md) and
  [F0100](../features/F0100-SpecWorkflow.md).
- **Amended by:** [ADR 0046](0046-complete-dispositions-at-admission.md).

## Decision

### Four generic repair operations

Repair uses four registered operations, and no per-owner repair operation is registered:

- `authorize-repair`: decides whether one engine-selected unit may be repaired, and binds
  its target, old value, revision, dependencies and retry identity;
- `build-repair-input`: builds the repair packet for that authorization;
- `parse-repair`: decodes and validates the admitted replacement;
- `merge-repair`: compare-and-swaps the authorized replacement into the candidate. Its
  variant declares whether it also validates, as specification support's
  `merge_validate` role does, or hands off to the following validation steps.

Each takes a required `owner` parameter from a closed, exhaustive enum. Each owner has a
variant only for the operations it uses:

| Owner | Authorize | Input | Parse | Merge (maximum `retry-limit`) |
| --- | --- | --- | --- | --- |
| `reference-text` | yes | yes | yes | yes (none) |
| `reference-extraction` | yes | yes | yes | yes (none) |
| `reference-summary` | yes | — | — | — |
| `reference-dispositions` | yes | — | — | — |
| `reference-signals` | yes | — | — | — |
| `reference-conflicts` | yes | — | — | — |
| `reference-reconciliation` | — | yes | yes | yes (128) |
| `source-omission` | yes | yes | yes | — |
| `source-omission-extraction` | — | — | — | yes (1) |
| `source-omission-reconciliation` | — | — | — | yes (1) |
| `specification-unit` | yes | yes | yes | yes (64) |
| `specification-support` | yes | yes | yes | yes, `merge_validate` (2) |

That is 12 owners and 28 variants. A step that names an owner with no variant for its
operation rejects at compilation.

The model call stays a separate `request-model` step (ADR 0030). Release and every
routed outcome stay YAML steps.

The enum covers Specify's owners, because [ADR 0034](0034-spec-quality-gate.md) defers Plan,
Tasks and Implement work until the Specify quality gate passes. Later workflows add owners and
variants to the same mechanism instead of new operations.

### Owner rules stay with the owner

Each owner's rules live in that owner's own domain module and are contributed to the
shared mechanism:

- **Rules:** authorization, target selection, input packet, parse rules, merge rules and
  invalidation.
- **Selection:** each generic operation selects the owner's rules through one exhaustive
  `switch` over the closed enum. There is no default branch, callback table or dispatcher.
- **Canonical owners:** owner rules reuse the existing canonical validators, normalizers
  and authority owners, and the shared `atomic_repair.Contract` (F0100), never copies of
  them.

### `owner` selects nothing on its own

The YAML `owner` value is a typed selector, not a policy choice:

- **Checked at compilation where it can be.** Where a variant's required keys already
  prove the owner, the compiler checks it.
- **Checked at run time otherwise.** Each operation checks it against the owner that the
  native diagnostic, authorization and context determine: the selected owner's binding
  reads only its own keys and the native facts they carry, so another owner's facts do not
  satisfy it. A mismatch is a **terminal runner rejection**, not a YAML outcome that a
  workflow could route. It ends with the one closed cause `RepairOwnerMismatch`
  (`src/domain/repair_owner.zig`) when the owner's binding finds another kind of value at its
  key or the compiled owner has no variant of the operation; an absent key stays
  `MissingRequiredData`, and a step with no resolvable `owner` is `RepairOwnerUnresolved`.
  These are `operation_failed` causes, which every surface names; the runner's own
  `authority` reasons are a separate closed set
  ([§6](../contracts/06-pipeline-nodes.md#runner-rejection-reasons)).
- **No policy, scope or defect identity.** `owner` grants none of these: it cannot widen
  scope, reset a count or change a defect key. YAML supplies allowances, not defect identity
  (ADR 0005). Caller flags cannot select a policy (ADR 0023).
- **The pre-generation phase witness** stays bound inside authorize, input and merge for
  source-omission owners, whatever `owner` says (§22.5,
  [ADR 0023](0023-advisory-post-generation-review.md#pre-generation-source-repair)).

### Owner-specialized contracts

Each generic operation has one registered contract made of **closed variants, one per
owner it serves**. The variants use the shared contract-variant mechanism of
[ADR 0030](0030-engine-owned-model-request.md) ("Contract variants"), with `owner`
as the selector; this ADR adds no second mechanism. Each variant is a complete contract:

- its outcome set;
- `requires`, `optional`, `produces`, `replaces` and `invalidates`;
- its side-effect class;
- its outcome-association descriptor;
- its repair role;
- whether retry authority is required or forbidden, and if required, its operation-local
  maximum. The native key population the compiler's execution bounds multiply by is the
  repair scope's own, engine-wide (`workflow_retry.maximum_repair_keys`, 128, like
  `maximum_request_assignments`); a variant does not declare one (F0005 §11).

Enforcement:

- **Registry admission** validates every variant independently, with the same repair,
  accounting and descriptor checks as any registered contract. A variant whose role and
  association don't fit rejects.
- **The compiler** selects the variant from the step's `owner` and checks the step
  against that variant alone: outcome mapping, data flow, role and association
  compatibility, and a `retry-limit` that is present only where required and within the
  maximum.
- **The runner** validates every delta, outcome, association and retry authority against
  the compiled step's variant, never against a union of variants. Registry admission,
  graph validation and execution compare the same descriptor (F0005).

Variant facts:

- **Native repairs with no model call.** The authorizers of the specification unit,
  specification support, reference summary, signals and conflicts declare `more`, which
  goes straight to merge with no model call. The `reference-dispositions` variant declares
  no `more`: under ADR 0046 its authorizer returns only a model call or `blocked`, so the
  variant, and its YAML step, carry no unreachable outcome.
- **Source omission's `more`** selects its reconciliation branch. Each branch then merges
  through its own owner, `source-omission-extraction` or `source-omission-reconciliation`.
  Those two variants differ in `requires`, `optional`, `replaces` and `invalidates`.
- **The four reconciliation authorizers** are four steps with distinct owners
  (`reference-summary`, `-dispositions`, `-signals` and `-conflicts`). They feed three
  `merge-repair` steps with the `reference-reconciliation` owner, one per reconciliation
  route, each with its own counter (see "Retry identity"). Each phase keeps its own
  explicit YAML step (ADR 0022).
- **Coverage** is no owner. A mechanical coverage defect has no independently supported
  repair target, so `validate-specification-coverage` returns `blocked` itself.
- **Blocked authorizers.** An authorizer that declares `blocked` names, in its
  descriptor, the closed reader of that decision, and one that does not declare it names
  none. The reader is one of the three native owners that retain a blocked decision:
  reference reconciliation, specification unit or specification support. It determines the
  one result key the descriptor names. The execution binding selects the retained decision
  through one exhaustive `switch` over the reader, so a `blocked` with no reader, a reader
  without `blocked`, or the reader of another result cannot be registered, compiled or built.
- **Merge retries.** The text and extraction merges forbid a `retry-limit`. The other
  merges require one, within their variant's maximum: 128 for `reference-reconciliation`,
  1 for each of the two source-omission merges, 64 for `specification-unit` and 2 for
  `specification-support`.

### Retry identity

"Compiled operation" in §22.7 and F0005 means the expanded compiled step instance
(`operation_instance_id: WorkflowStepId`). Two routes that use the same generic operation
therefore keep separate counters, as F0100 requires.

- **Defect keys** include the validator-owned diagnostic family, so owners never
  alias keys at one step.
- **Native key population** is the repair scope's own, engine-wide
  (`workflow_retry.maximum_repair_keys`, 128), so the compiler's execution bounds stay finite
  and an owner or `owner` value cannot change them.

### What stays the same

- **Repair boundaries.** Every repair rule is unchanged:
  - only the engine-authorized unit changes, under old-value and revision preconditions;
  - impacted, then full-candidate, validation follows;
  - exhaustion blocks or fails and never broadens scope;
  - the repair algebra stays closed.
- **§22.1's distinction** is between authorization categories and phases, not operation
  IDs. Pre-generation source repair and native generation repair remain distinct
  authorized repairs, as distinct owners with distinct rules.
- **Model calls, prompts, slots, tokens and the budget.**

### §14.4

§14.4's "YAML-selected repair operation" that "performs one authorized repair attempt" is
a sequence of YAML steps:

- `authorize-repair`;
- `build-repair-input`;
- `request-model`;
- `parse-repair`;
- `merge-repair`.

A native repair may skip input, request and parse through `more`. It still makes exactly
one authorized attempt, and a further attempt is still a YAML transition. The §13.4 repair
actions describe the domain functions inside these operations. They don't become stage
actions, because authorize and merge carry repair roles (ADR 0031).

### A shared subgraph

A definition may wrap repair routes in a definition-local `repair` subgraph (ADR 0013).
The subgraph forwards `owner`, prompt, schema, slot and limits as ordinary `{param}`
values. Because ADR 0013 permits no templates, one subgraph serves only owners whose
internal edges are identical. Others keep their steps spelled out.

### Tests

- Compiler and registry cases accept each of the 28 variants and reject each violation named
  under "Owner-specialized contracts" and "`owner` selects nothing on its own".
- Each owner rule has unit tests with accepted and rejected cases.
- Architecture tests hold that each generic operation selects owner rules only through an
  exhaustive switch, with no default, callback or dispatcher field, and that no per-owner
  repair operation is registered.

## Consequences

- **A new repairable owner** costs its rules, one enum member, its variants, its own data
  keys and its YAML route. It needs no new operation, binding or registry entry.
- **Repair is less visible from the operation ID.** It comes from the `owner` value.
  The owner is visible through the compiled step's declaration, which reports and the
  debugger carry by step ID; no report field carries it, and the step trace
  prints it as `@<owner>` after the operation ID.
- **No behaviour change is claimed.**

## Not decided here

- Owner enums for Plan, Tasks and Implement, which wait for the
  [ADR 0034](0034-spec-quality-gate.md) Specify quality gate.
