# ADR 0033: Generic repair operations with owner-supplied rules

- **Status:** Accepted amendment. **Not yet implemented:** the Specify definition still
  uses per-owner repair operations until the conversion lands. Documents that describe
  per-owner repair operations carry a pointer to this ADR until then.
- **Date:** 2026-10-22
- **Decision authority:** The user's instruction on 22 October 2026, "update the
  documentation on the yes, ass suggested". It decides [FIX05](../../fixes/Z_FIX05.md#21-fix05-retired--28-october-2026) W3
  as restated after [ADR 0030](0030-engine-owned-model-request.md) and
  [ADR 0031](0031-stage-actions.md). The suggestion was:
  - generic repair operations, with each owner supplying only its own rules;
  - sequenced after ADR 0030 is implemented and ADR 0031's first conversion is measured.

  The choices under "Derived under existing rules" follow from existing authority and
  await the user's confirmation, except choice 1, which the user confirmed on
  23 October 2026 ("update the documentation around option 1"): per-owner variants use
  one shared contract-variant mechanism, which
  [ADR 0030](0030-engine-owned-model-request.md) builds first and this ADR reuses.
- **Amends:**
  - [ADR 0005](0005-workflow-defined-operations.md): "Each operation has one current
    contract", which becomes one contract with closed owner variants for the four repair
    operations;
  - [ADR 0023](0023-advisory-post-generation-review.md): a pointer confirming that the
    `owner` parameter selects no policy;
  - [ADR 0031](0031-stage-actions.md): its derived choice 5 (the restated W3);
  - design.md: the §22 summary and the §32 index;
  - contracts:
    - §22.1 ("Pre-generation source repair and native generation/protocol repair remain
      distinct authorized operations");
    - §22.7 ("compiled operation");
    - §14.4 (the composite repair operation);
    - the §13.4 repair entries;
  - [F0005](../features/F0005-WorkflowDefinitionRegistryService.md): one contract per
    operation ID, exact outcome mapping, the operation-local retry maximum, and repair
    key populations;
  - [F0100](../features/F0100-SpecWorkflow.md): the per-owner repair operations of the
    Spec definition.

  The overall design remains **Proposed design**.

## Context

The Specify definition repairs invalid model output through 29 per-owner operations:

- 10 authorize;
- 6 build-input;
- 6 parse;
- 7 merge.

Two native advisory repair stops sit alongside them. Seven of the routes make a model call
with the `repair` slot: reference text, reference extraction, reference reconciliation,
specification support, specification unit, and source-omission extraction and
reconciliation. Several authorizers can also send a native repair straight to merge
without a model call. Coverage only authorizes, and ends `blocked` or `failed`.

Each operation costs a binding, a registry entry, data keys, a YAML step and tests. The
same four jobs repeat per owner with different rules.

FIX05 W3 first proposed one repair operation per owner that also made the model call.
ADR 0030 (every model call is its own `request-model` step) and ADR 0031 (a stage action
never calls a model, and has repair role `none`) both forbid that. AGENTS.md prefers
the alternative: "Domain-specific components may contribute typed facts, candidates, or
evidence to a shared mechanism." So do invariant 23 and the §13.10 precedent of
specializing one contract "by native review purpose". The code already specializes the
reconciliation authorizers by kind (`reconciliation_repair.Authorize(.summary)` and its
siblings).

## Decision

### Four generic repair operations

The 29 per-owner operations are replaced by four registered operations:

- `authorize-repair`: decides whether one engine-selected unit may be repaired, and binds
  its target, old value, revision, dependencies and retry identity;
- `build-repair-input`: builds the repair packet for that authorization;
- `parse-repair`: decodes and validates the admitted replacement;
- `merge-repair`: compare-and-swaps the authorized replacement into the candidate. Its
  variant declares whether it also validates, as specification support's
  `merge_validate` role does today, or hands off to the following validation steps.

Each takes a required `owner` parameter from a closed, exhaustive enum. Each owner has a
variant only for the operations it uses today:

| Owner | Authorize | Input | Parse | Merge (YAML retry limit today) |
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
| `specification-coverage` | yes, `blocked`/`failed` only | — | — | — |

That is 13 owners and 29 variants, one per removed operation. A step that names an owner
with no variant for its operation rejects at compilation.

The model call stays a separate `request-model` step (ADR 0030). Release, the advisory
repair stop steps and every routed outcome stay YAML steps.

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
  native diagnostic, authorization and context determine. A mismatch is a **terminal
  runner rejection** with a closed diagnostic, not a YAML outcome that a workflow could
  route.
- **No policy, scope or defect identity.** `owner` grants none of these. YAML supplies
  allowances, not defect identity (ADR 0005). Caller flags cannot select a policy
  (ADR 0023).
- **The pre-generation phase witness** stays bound inside authorize, input and merge for
  source-omission owners, whatever `owner` says (§22.5, ADR 0023).
- **The no-invention branch** of §14.4 survives inside `authorize-repair` for the owners
  where it applies today.

### Owner-specialized contracts

Each generic operation has one registered contract made of **closed variants, one per
owner it serves**. The variants use the shared contract-variant mechanism that
[ADR 0030](0030-engine-owned-model-request.md) builds ("Contract variants"), with `owner`
as the selector; this ADR adds no second mechanism. Each variant is a complete contract:

- its outcome set;
- `requires`, `optional`, `produces`, `replaces` and `invalidates`;
- its side-effect class;
- its outcome-association descriptor;
- its repair role;
- whether retry authority is required or forbidden, and if required, its operation-local
  maximum and finite native key population.

Enforcement:

- **Registry admission** validates every variant independently, with the same repair,
  accounting and descriptor checks as any registered contract today.
- **The compiler** selects the variant from the step's `owner` and checks the step
  against that variant alone: outcome mapping, data flow, role and association
  compatibility, and a `retry-limit` that is present only where required and within the
  maximum.
- **The runner** validates every delta, outcome, association and retry authority against
  the compiled step's variant, never against a union of variants. Registry admission,
  graph validation and execution compare the same descriptor (F0005).

Today's differences become variant facts:

- **Native repairs with no model call.** The authorizers of the specification unit,
  specification support, reference summary, dispositions, signals and conflicts declare
  `more`, which today goes straight to merge with no model call.
- **Source omission's `more`** selects its reconciliation branch. Each branch then merges
  through its own owner, `source-omission-extraction` or `source-omission-reconciliation`.
  Those two variants differ in `requires`, `optional`, `replaces` and `invalidates`.
- **The three reconciliation authorizers** are three steps with distinct owners feeding
  one `merge-repair` with the `reference-reconciliation` owner. Each phase keeps its own
  explicit YAML step (ADR 0022).
- **Coverage** declares only `blocked` and `failed`, so it gains no unreachable outcome.
- **Merge retries.** The text and extraction merges forbid a `retry-limit`, as today. The
  other merges require one within their declared maximum.

### Retry identity

"Compiled operation" in §22.7 and F0005 means the expanded compiled step instance. The
code already keys retry identity that way (`operation_instance_id: WorkflowStepId`). Two
routes that use the same generic operation therefore keep separate counters, as F0100
requires.

- **Defect keys** still include the validator-owned diagnostic family, so owners never
  alias keys at one step.
- **Native key populations** are declared per variant, so the compiler's execution
  bounds stay finite.

### What stays the same

- **Repair boundaries.** Every repair rule is unchanged:
  - only the engine-authorized unit changes, under old-value and revision preconditions;
  - impacted, then full-candidate, validation follows;
  - exhaustion blocks or fails and never broadens scope;
  - the repair algebra stays closed.
- **§22.1's distinction** is between authorization categories and phases, not operation
  IDs. Pre-generation source repair and native generation repair remain distinct
  authorized repairs, as distinct owners with distinct rules.
- **Advisory repair stops** (`stop-specification-repair-advice`,
  `stop-specification-protocol-repair-advice`) stay native stop steps (ADR 0023).
- **Model calls, prompts, slots, tokens and the budget.**

### §14.4

§14.4's "YAML-selected repair operation" that "performs one authorized repair attempt" is
now a sequence of YAML steps:

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

### Sequencing

This converts only after:

1. ADR 0030 is implemented, because the routes use `request-model`;
2. ADR 0031's first conversion, `prepare-toolchain`, is measured.

All Specify owners convert in one change, with no compatibility form, removing the 29
per-owner operations. The enum covers Specify's owners now, because ADR 0034 defers Plan,
Tasks and Implement work until the Specify quality gate passes. Later workflows add owners and variants to the same mechanism
instead of new operations.

### Evidence

A structural change, with no semantic change claimed, so the evidence is offline:

- **Freeze first.** Before converting, record every repair route's outcomes, repair
  evidence, retry counts, defect keys and token accounting.
- **Reproduce** them across:
  - the integration scenario matrix, including its repair fault-injection scenarios;
  - two unrelated development cases through Specify.

  Only the Specify definition uses repair operations today. A second offline repair
  fixture workflow may be added for isolation.
- **Measure:** operations, bindings, data keys, YAML lines, and the files a "new
  repairable owner" change touches.

Each statement CLAUDE.md lists is reported separately.

- **Contract versions.** Registered action and compiled step IDs change, so the
  implementation advances each closed contract whose shape changes (as ADR 0030 states).
- **Retained evidence.** Measurements that need retained captures run first.

## Derived under existing rules

The user approved the suggestion. These choices are derived from existing authority, not
from the user's words, and await the user's confirmation, except choice 1, which the user
confirmed on 23 October 2026:

1. **Owner-specialized contracts.** Each generic operation's contract consists of
   complete per-owner variants, validated independently. The alternative was distinct
   contracts for owners whose shapes differ. **Confirmed on 23 October 2026,** through
   ADR 0030's shared contract-variant mechanism, which ADR 0030 builds first.
2. **The owner list.** The 13 owners above, including the split of source omission's
   merges into two owners.
3. **`owner` is checked against native facts,** and a mismatch is terminal. It selects no
   policy, scope or defect identity.
4. **"Compiled operation" means the compiled step instance,** matching the code.
5. **§22.1's "distinct authorized operations"** means distinct authorization categories,
   not distinct operation IDs.
6. **Advisory repair stops stay native stop steps** outside the four operations.
7. **All Specify owners convert in one change,** after A1 and the first A2 conversion, and
   the enum is Specify-only for now.
8. **Evidence:** structural conversion on offline evidence (as ADR 0031's derived
   choice 7, also awaiting confirmation).

## Consequences

Expected benefits, pending the measure:

- **Fewer operations.** 29 owner-specific operations should become 4 generic ones, with
  matching cuts in bindings and registry entries. Only the data keys that passed values
  between per-owner operations go; each owner keeps its own `requires` and `produces` keys.
- **Cheaper new owners.** A new repairable owner should cost its rules, one enum member,
  its variants, its own data keys and its YAML route. It needs no new operation, binding or
  registry entry.
- **The boundary rules stay shared.** They already live in the shared
  `atomic_repair.Contract`. This change also shares the operations around it.

Costs:

- **No new compiler extension here.** The compiler, registry and runner gain contract
  variants with ADR 0030, which is implemented first; this ADR adds its 13 owners'
  variants to that mechanism.
- **The largest refactor of the four.** It touches every repair route, and repair is
  safety-critical. The freeze-and-reproduce evidence and the sequencing bound the risk.
- **Repair is less visible from the operation ID.** It now comes from the `owner` value.
  Reports and the debugger must show both.
- **No behaviour change is claimed.**

## Acceptance

All offline:

- **Equivalence.** The frozen outcomes, evidence, retry counts, defect keys and token
  accounting are reproduced for every owner, including:
  - every no-model `more` path (specification unit, specification support, reference
    summary, dispositions, signals and conflicts);
  - source omission's `more` to its reconciliation branch and both of its merges;
  - the three reconciliation authorizers feeding one merge;
  - coverage `blocked`;
  - specification support's `merge_validate`;
  - the no-invention branch;
  - both advisory repair stops.
- **`owner` checks.** A YAML `owner` that disagrees with the native owner is a terminal
  runner rejection, or a compile error where provable. `owner` cannot widen scope, reset
  a count or change a defect key.
- **Retry isolation.** Two steps using the same generic operation keep separate counters.
- **Compiler and registry cases:**
  - accepted: each of the 29 variants;
  - rejected: an unknown owner, or an owner with no variant for the operation;
  - rejected: an outcome the variant doesn't declare, and an unmapped declared outcome;
  - rejected: a missing `retry-limit` where required, a `retry-limit` where forbidden, and
    one above the variant's maximum;
  - rejected at registry admission: a variant whose role and association don't fit;
  - rejected: an execution delta outside the step's variant.
- **Unit tests per owner rule,** with the removed per-owner operations' accepted and
  rejected cases preserved.
- **Architecture tests:**
  - each generic operation selects owner rules only through an exhaustive switch, with no
    default, callback or dispatcher field;
  - no per-owner repair operation remains registered.
- **Build checks:** `zig build verify` and the clean packaged-executable smoke test pass.
- **Measures**, recorded before and after.

## Not decided here

- Owner enums for Plan, Tasks and Implement, which wait for the
  [ADR 0034](0034-spec-quality-gate.md) Specify quality gate.
- Engine-owned release, which ADR 0030 leaves open.
- FIX05 R6's exact-reference repair eligibility. That stays open, and this ADR doesn't
  foreclose it.
