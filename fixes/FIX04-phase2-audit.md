# FIX04 Phase 2 implementation audit — 16 October 2026

This historical audit precedes the subsequently authorized Phase 1A admission
amendment. Its command results describe that earlier build. The
[Phase 1A implementation record](FIX04-phase1a-implementation.md) records the new
contract and verification; the Phase 2 freeze still requires fresh feasibility
evidence on the committed build containing that amendment.

This audit maps [Phase 2 and the common measures](FIX04.md#55-common-measures-meaningful-improvement-and-brittleness)
to the development harness. Implementation, offline enforcement evidence and live
semantic evidence are separate. The governing design remains proposed.
The applicable boundaries are [design §§1, 3–4, 28, 30–31](../design/design.md):
LLM output remains candidate data, semantic assessment is not deterministic
proof, the native workflow/runner retains authority, and automated verification
cannot make live model calls. The changes belong to the development acquisition
and assessment harness; production generation assignments and budget policy
remain governed by their existing contracts.

| Required behavior | Implementation and regression boundary |
| --- | --- |
| Unchanged A alone; original/repeated/transformed development inputs | `test/harness/generation_comparison.zig`: 72 A workloads, equal independent-feature weighting, separate baseline/paired modes |
| Committed provider-integrated source/build, exact inputs and selected settings | `baseline/freeze.zig`, `frozen_binding.zig`: closed freeze, exact source/build/toolchain/input hashes, native compiled budget, explicit model binding and drift rejection |
| Settings across native model roles | The protocol explicitly names its generation slot; generation keeps low reasoning and 16,384 output tokens. Each other request matches its exact frozen slot controls, including omitted provider-owned output allowances; no role-specific exception or substitution is inferred |
| Budget feasibility before freezing | `baseline/feasibility.zig`, `preflight.zig`: authentic selected-binding whole-workflow usage, review/repair included, explicit recorded decision, no completion inferred from stopped lower bounds |
| Exact requests and original responses; corrections remain separate | Production `e2e/invoke.zig` and `trace.zig`, `baseline/acquisition.zig`, `candidates.zig`, `reviews.zig`: native origins, original raw HTTP/model bytes, candidate snapshots and native typed findings |
| Experiment-wide bounded accounting | `baseline/dispatch.zig`, `experiment.zig`: charge before transport, full actual usage including overshoot, halt on unknown/uncertain usage, canonical one-shot freeze claim, no restart or resume |
| Honest incomplete execution | `baseline/acquisition.zig`: every planned trial retained, paid receipts survive report-write failure, independent source-drift diagnostics, failures/unknown usage/unattempted trials remain distinct |
| Diagnostic versus actual complete workflow scope | Native whole-workflow invocation uses actual predecessors; comparison diagnostics cannot invent publication authority; native useful-completion assessment is separate |
| Actual-output fidelity and clarification correctness | `baseline/assessment.zig`: exact native output/source quotations, original versus current labels, explicit dispute/provenance, no generated-view authority |
| Original upstream meaning and corrected predecessors | `baseline/upstream.zig`: each original extraction/reconciliation assignment has its own exact native output/hash/source-backed assessment; corrected originals cannot disappear behind faithful specification generation; the selected generation sizing metric remains unchanged |
| Useful completion | `baseline/useful_completion.zig`: exact native publication plus source fidelity plus canonical frozen-rubric assessment; missing/disputed/unconfigured assessment remains unknown |
| Correct evaluator rubric and isolation | Explicit `--rubric` uses `semantic-simplicity/rubric.json`, replacing template-specific criteria; evaluator files/expectations are excluded from generation materialization |
| Harm, including review before a candidate exists | Cumulative source-backed issue events, exact per-category counts, per-feature incidence and independent-feature risk-stratum rates; later recovery cannot erase harm |
| Robustness, sensitivity and repeats | Per-variant semantic/mechanical/unknown coverage; all variant repetitions checked; attempted/partial/unattempted bundles; unattempted variants cannot become representation failures |
| Finding-type accuracy | Typed native source/principle/preservation findings with source-backed expected kinds; original/latest/corrective confusion counts, precision/recall and explicit unmeasured contracts |
| Failure origin and reproducible examples | Independent supplied causal stage and native chronology, exact trial examples grouped by category/stage/domain/repetition; unknown causes block advancement |
| Complete resource use and stage shares | All physical sends, actual input/output tokens and elapsed time; median/worst distributions, failed-inclusive cost per useful completion, stage and feature totals/shares with unknown usage explicit |
| Qualification sizing and feasible exact counts | User-selected complete first-pass generation fidelity; counts retained when infeasible; forecast includes actual baseline cost and every declared future phase; incomplete evidence cannot select holdout IDs |
| Explicit Phase 2 decision | `baseline/phase2_decision.zig`: advance, retain baseline, revise or inconclusive; generation changes do not compensate for upstream/review/repair/provider failures |

The implementation audit found and corrected gaps in budget reuse, receipt
retention, publication assessment, template-rubric reuse, variant denominators,
material-versus-mechanical variability, cumulative early-review harm, qualification
cost scope and causal-attribution gates. Tests cover accepted and rejected cases
at these owners; scripted tests remain offline integration evidence.
Roundtrip regressions also cover canonical fixed-digest arrays, assembled candidate
snapshots, intermediate per-origin mechanical rejection evidence and inherited
verdict proof for all current partial review-repair schemas.

The live exit gate also requires the frozen development panel's authentic outputs,
completed source-backed assessments, resolved material disagreements, measured
failure sensitivity and exact feasible qualification counts. A diagnostic run on
an uncommitted build cannot close it. The current implementation must not claim
semantic benefit, reduced brittleness or Phase 5 qualification from mechanical
verification alone.

## Approved live diagnostic

The user explicitly approved one live evidence run. Executed:

```sh
./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

[Native report](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.json)
and [readable report](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.md)
retain the exact source/build reconstruction, native requests/responses and
actual usage. The configured binding was Bedrock `openai.gpt-oss-20b-1:0`, Sydney,
low reasoning, native schema. The retained build revision is `94e2838999a889d4b9ea01eeab23bf758f39a1a9`,
with source hash `2a30ee8d6f01e4b286da002c40c75e6bbc759e13faf52ff0f6e9193667014175`
and `modified: true`.

The command failed with `WorkflowTokenBudgetExceeded`: 41 physical model calls,
101,134 actual tokens against the compiled 100,000-token workflow budget, with
complete usage accounting. The terminal operation was
`g58-g46-g36-g25-g14-g6-review-post-source-assess-model-request-call`.
No specification was published and rubric evaluation did not run. This is a
full-workflow development diagnostic with a stopped cost lower bound, not a
frozen baseline, complete product run or quality qualification. There was no
automatic retry, budget increase or second live run.

The current budget decision and committed-baseline prerequisites remain open.
This failed diagnostic does not authorize reducing the panel or changing engine
budget policy. Raising the workflow budget, reducing review/repair cost through
its owning contract, or narrowing qualified scope requires the explicit decision
specified by FIX04 §5.5.

## Final verification and feasibility readback

`zig build test-baseline test-rubric-evaluator --summary all` passed **6/6 steps,
535/535 tests** after the final slot-aware fix. `zig build verify --summary all`
passed **156/156 steps, 1,659/1,659 tests**, including architecture, offline
integration and native clean-directory packaging/smoke checks. Staged and
unstaged `git diff --check` passed. Automated checks made no model calls.

The final offline `baseline prepare` used the explicit protocol, cases,
Hello World workflow template, publication rubric and
`zig-out/baseline/phase2-audit-budget-plan.json`, which names the retained live
diagnostic as cost evidence and keeps the user decision unresolved. Exact command:

```sh
zig build baseline -- prepare --protocol test/calibration/semantic-simplicity/protocol.json --cases test/calibration/semantic-simplicity/cases.json --template-case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json --budget-plan zig-out/baseline/phase2-audit-budget-plan.json --rubric test/calibration/semantic-simplicity/rubric.json
```

The [feasibility report](../zig-out/baseline/2026-10-15T22-38-08Z-4ae44015f25ecde96580bc1c4c065da1/budget-feasibility.json)
successfully imports all 41 exact native exchanges, including the repair slot's
omitted output allowance, and accounts 101,134 actual tokens. It correctly returns
`insufficient` and exits 1 with no freeze, acquisition or API call. Reasons include
uncommitted baseline, unresolved user decision, no complete product-flow cost
evidence, observed workflow-budget exhaustion, and projected experiment-stop
exceedance. This is the expected admission rejection, not a test failure.

The declared baseline/selection/qualification scope is 360–504 workloads. Under
its explicit worst-observed-cost assumption the report projects 14,760–20,664
sends and 36,408,240–50,971,536 tokens, against 1,000 sends and 2,000,000 tokens.
Because the observed workflow stopped, these costs remain diagnostic lower-bound
evidence; they are not completion-cost guarantees or authority to raise limits.
Phase 2's code implementation and mechanical verification are complete. Its live
baseline, semantic assessment and qualification-sizing exit gate remain open.

The user subsequently selected **investigate review/repair cost within current
budgets**. The [retained-capture investigation](FIX04-phase2-cost-investigation.md)
attributes 77.06% of tokens to review, documents the unchanged story repair and
source-obligation diagnosis error, and identifies the owning follow-up contracts.
It made no new model calls or production/budget changes; feasibility remains
insufficient.
