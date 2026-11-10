# ADR 0037: Configured workflow token budget

- **Status:** Accepted
- **Date:** 2026-10-25
- **Decision authority:** The user's decisions on 25 October 2026 on
  FIX05 (`fixes/Z_FIX05.md` §21, git `194e29a`) B4:
  - "make budget configurable and increase to 125000", with the priority "quality over
    cost, but never waste";
  - "make the token cap an external setting, that is stored and loaded from
    .sddtoolkit.json, to the e2e test set the token cap to 125000".
- **Amended by:** [ADR 0041](0041-failed-run-incomplete-publication.md) (26 October
  2026; accepted, on hold since 30 October 2026, not implemented): a budget failure still
  stops all model calls and fails the run, but would publish the validated content as a
  failed incomplete specification.
- **Amends:**
  - [ADR 0011](0011-provider-owned-request-limits.md) "Workflow token accounting" and
    [ADR 0023](0023-advisory-post-generation-review.md) "Budget and incomplete advice"
    (withdrawn with post-generation review on 1 November 2026): the budget's owner and
    value, not its accounting;
  - [ADR 0005](0005-workflow-defined-operations.md): the selected workflow policy no
    longer owns the budget;
  - §9 (configuration shape and workflow policy), §12 (model boundary accounting), the
    §13 `CheckWorkflowTokenBudgetAction`, §14 (orchestration), §17, §22, §27, §31.12,
    F0001, F0005, F0006, F0100 and `design/code.md`;
  - the harness contract ([e2e.md](../harness/e2e.md)): `baseline-budget-feasibility/v2`
    and `baseline-freeze/v3`;
  - the §32 index.

  Invariant 32 is unchanged: one total-token budget per execution, shared by all
  inference. The overall design remains **Proposed design**.

## Context

The single workflow token budget was compiled into every policy profile at 100,000
tokens, nine identical copies, and copied into each compiled graph's authority. Projects
couldn't change it, and loan-renewal runs ended `WorkflowTokenBudgetExceeded` at 100,763
to 112,532 tokens. The user set quality above cost and approved a larger, configurable
budget.

## Decision

1. **The project configuration owns the budget.** `.sddtoolkit.json` has a required root
   member `workflowTokenBudget`: an integer from 1 to 4,294,967,295, the u32 range that
   the catalogue's integer limits use. There is no engine default.
   - The closed configuration type decodes it once at bootstrap through the shared
     positive-integer rule (`positive_json_integer.zig`), which the catalogue's
     `maxOutputTokens` and `requestTimeoutMs` also use. A missing, zero, negative,
     fractional, exponent, quoted, null, duplicate or out-of-range value fails as
     `ENGINE_CONFIG_PARSE_ERROR`.
   - It sits at the root, not under `models`, so model-slot consumers don't depend on a
     setting they never read.
2. **It stays one total limit per execution.** The composition root passes the decoded
   value to the workflow pipeline runner, which starts that execution's token ledger
   from it. Accounting, overshoot retention, the prohibition on calls at or above the
   budget and fatal budget rejection are unchanged (ADR 0011).
3. **Workflow policy and compiled graphs no longer carry it.** Policy profiles keep
   only their capabilities and terminal outcomes. Compiled workflow authority drops the
   budget, so a configuration change is never a change to a bound workflow graph, and
   the runner's policy cross-check compares capabilities only.
4. **Values.** The shipped E2E configuration, which both live cases use, and the
   repository example set 125,000. Offline fixtures set their own explicit values: the
   baseline protocol and unit fixtures keep 100,000 so offline totals stay comparable,
   and the scripted budget test uses 90,000 to show the ledger reads the configuration.

## Consequences

- **Persistence.**
  - Specification and workflow state don't store the budget, so no state version
    changes.
  - The E2E report's `token_accounting.total_budget` records the configured value.
  - The baseline harness reads the budget from the bootstrapped configuration. Its
    feasibility report's `compiled_workflow_budget` becomes `configured_workflow_budget`,
    so `baseline-budget-feasibility` advances to v2 and `baseline-freeze`, which embeds
    it, to v3.
- **Configuration.** Every configuration document must state the budget; the closed
  schema, the example and all fixtures changed together, with no compatibility reader.
- **Not changed.** The experiment-wide stops (1,000 sends, 2,000,000 tokens) stay a
  separate open decision ([SPEC01](../../fixes/SPEC01.md) H4). A larger budget lets runs
  near the limit finish; it doesn't make review cheaper or runs more reliable.
- **Tests.**
  - Decoding accepts 1, 125,000 and 4,294,967,295, and rejects a missing value, 0, −1,
    1.5, `1e3`, `"125000"`, `null`, `[]`, 4,294,967,296 and a duplicate member.
  - The scripted production workflow, run through the engine's own invocation path,
    starts its ledger at a configured 90,000 and fails `WorkflowTokenBudgetExceeded` at
    90,001.
  - The baseline harness reads its protocol configuration's 100,000, and a distinct
    80,000 when the configuration changes.
  - Tests that checked a policy or compiled-graph budget are deleted with the rule.
