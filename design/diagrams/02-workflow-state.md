```mermaid
stateDiagram-v2
    [*] --> new
    new --> specifying: sdd specify --reference &lt;relative-selector&gt; passes preactivation and feature activation

    specifying --> spec_clarification_pending: commit open or reused SNN; no partial spec
    spec_clarification_pending --> spec_clarification_pending: rerun still unresolved or deferred; same SNN
    spec_clarification_pending --> spec_clarification_pending: plan tasks or implement exits nonzero while any SNN is open
    spec_clarification_pending --> spec_clarification_pending: one SNN resolves but another SNN remains open
    spec_clarification_pending --> specifying: final open SNN resolves; regenerate complete spec stage
    spec_clarification_pending --> cancelled: authenticated cancel response
    specifying --> specified: validated specification transaction committed; no open SNN

    specified --> specifying: SpecificationContract bootstrap route commits ReworkInvalidationStageTransaction; empty descendant arrays are valid
    specified --> planning: commit validated PlanInputAuthorityStageTransaction with normalized spec, research, repository, baseline-file and complete principle authorities before any model call
    planning --> planning: commit a validated successor PlanInputAuthorityStageTransaction when the durable input bundle refreshes before another model call
    planning --> plan_clarification_pending: commit open or reused PNN; no partial PlanState
    plan_clarification_pending --> plan_clarification_pending: rerun still unresolved/deferred or owning planning bootstrap authority refreshes; same PNN
    plan_clarification_pending --> plan_clarification_pending: tasks or implement exits nonzero while any SNN or PNN is open
    plan_clarification_pending --> plan_clarification_pending: one PNN resolves but another PNN remains open
    plan_clarification_pending --> planning: final open PNN resolves; regenerate complete plan stage
    plan_clarification_pending --> cancelled: authenticated cancel response
    planning --> plan_review_pending: validated read-only plan views and PlanState committed
    plan_review_pending --> planning: commit rejection and clear approval; ordinary regenerated planning may later pause for a PNN
    plan_review_pending --> planned: approve exact current planStateId

    planned --> tasking: tasks gate reloads plan and requires no open SNN or PNN
    tasking --> tasks_clarification_pending: commit open or reused TNN; no partial TaskDefinitionState
    tasks_clarification_pending --> tasks_clarification_pending: rerun still unresolved or deferred; same TNN
    tasks_clarification_pending --> tasks_clarification_pending: implement exits nonzero while any SNN PNN or TNN is open
    tasks_clarification_pending --> tasks_clarification_pending: one TNN resolves but another TNN remains open
    tasks_clarification_pending --> tasking: final open TNN resolves; regenerate complete tasks stage
    tasks_clarification_pending --> cancelled: authenticated cancel response
    tasking --> tasks_review_pending: validated read-only tasks view and TaskDefinitionState committed
    tasks_review_pending --> tasking: commit rejection and clear approval; ordinary regenerated tasking may later pause for a TNN
    tasks_review_pending --> tasked: approve exact current taskDefinitionStateId

    tasked --> implementing: implement gate requires current approvals and no outstanding spec, plan or tasks clarification
    tasked --> blocked: any SNN, PNN or TNN is outstanding; execute no implementation model, command, overlay or project change
    implementing --> implemented: every task transaction and passing ImplementationCompletionStageTransaction committed
    implementing --> final_validation_failed: first commit FinalValidationFailedStageTransaction; failed evidence appended, validation bytes discarded, task runtime unchanged
    final_validation_failed --> implementing: separate LocalizedTaskRemediationStageTransaction retires stale evidence and moves only the owning task to remediation_pending
    final_validation_failed --> implementation_reconciliation_tasks: ImplementationReconciliationStageTransaction retires stale evidence and moves affected completed tasks to needs_reconciliation

    planned --> specifying: reference snapshot changes; clear feature request and all descendants
    planned --> specified: authenticated editable spec changes; clear plan and task descendants
    planned --> planning: principle preset repository or plan authority invalidates plan
    tasked --> specifying: reference snapshot changes; clear feature request and all descendants
    tasked --> specified: authenticated editable spec changes; clear plan and task descendants
    tasked --> planning: plan principle preset or repository authority invalidates tasks
    tasked --> tasking: task definition authority changed before implementation
    implementing --> specifying: reference changed before first task commit; ReferenceRevisionStageTransaction clears feature request and descendants
    implementing --> specified: authenticated spec changed before first task commit; preserve validated user edit and clear descendants
    implementing --> planning: plan or principle authority changed before first task commit
    implementing --> tasking: task definition changed before first task commit

    implementing --> implementation_reconciliation_spec: post-commit reference rework carries next task runtime/evidence retirement and requires later specifying
    implementing --> implementation_reconciliation_spec: post-commit authenticated spec rework carries next task runtime/evidence retirement and preserves edited spec
    implementing --> implementation_reconciliation_plan: post-commit plan/principle rework transaction carries next task runtime and evidence retirement
    implementing --> implementation_reconciliation_tasks: post-commit task-definition rework transaction carries next task runtime and evidence retirement
    implementation_reconciliation_spec --> specifying: reference changed; preserve code and regenerate complete spec then plan/tasks
    implementation_reconciliation_spec --> specified: authenticated spec changed; preserve code/edit then regenerate plan/tasks
    implementation_reconciliation_plan --> planning: preserve code then regenerate and reapprove plan and tasks
    implementation_reconciliation_tasks --> tasking: preserve code then regenerate and reapprove tasks

    specifying --> blocked: non-model authority or environment block
    planning --> blocked: non-model authority or environment block
    tasking --> blocked: non-model authority or environment block
    implementing --> blocked: dependency or authorization block
    specifying --> failed: terminal engine failure
    planning --> failed: terminal engine failure
    tasking --> failed: terminal engine failure
    implementing --> failed: terminal engine failure

    specifying --> cancelled: explicit run cancellation
    specified --> cancelled: explicit run cancellation
    planning --> cancelled: explicit run cancellation
    plan_review_pending --> cancelled: explicit run cancellation
    planned --> cancelled: explicit run cancellation
    tasking --> cancelled: explicit run cancellation
    tasks_review_pending --> cancelled: explicit run cancellation
    tasked --> cancelled: explicit run cancellation
    implementing --> cancelled: explicit run cancellation before commit boundary
    final_validation_failed --> cancelled: explicit run cancellation
    implementation_reconciliation_spec --> cancelled: explicit run cancellation
    implementation_reconciliation_plan --> cancelled: explicit run cancellation
    implementation_reconciliation_tasks --> cancelled: explicit run cancellation

    implemented --> [*]
    blocked --> [*]
    failed --> [*]
    cancelled --> [*]
```
