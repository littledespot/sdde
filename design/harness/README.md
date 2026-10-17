# Spec workflow evaluation harness

The development harness runs the ordinary Spec workflow against an explicitly
selected case, using the real model configured by that case's `.sddtoolkit.json`,
then grades the specification that execution actually published against the
case's rubric. Semantic quality assessment is part of that outcome; mechanical
checks only prove that inputs, execution and judge responses were processed safely.

| Document | Covers |
| --- | --- |
| [e2e.md](e2e.md) | Live E2E, single-call and provider-compatibility diagnostics, environment setup, case/publication contract and retained results |
| [evaluator.md](evaluator.md) | Supplied-spec grading, judge configuration, scoring and reports |
| [acceptance.md](acceptance.md) | R8 development acceptance, human adjudication and grader qualification |

## Authority boundary

- [F0100](../features/F0100-SpecWorkflow.md) owns production Specify behavior and
  [ADR 0009](../decisions/0009-atomic-workflow-execution.md) owns execution and
  publication. The harness adds no transaction store, checkpoint, resume path or
  workflow-specific engine dispatch.
- Rubric judgments are observations. They never approve transitions, publish
  candidates, answer clarifications or weaken deterministic gates.
- Scripted generation, prewritten specifications and golden-document comparison are
  not E2E evidence. Fakes test only individual mechanical boundaries.
- The shared [live-test cost policy](../../test/harness/model_cost_policy.zig)
  permits only `aws-bedrock` / `openai.gpt-oss-20b-1:0` from `ap-southeast-2`, for
  both generation and grading. It supplies no default and does not restrict the
  production model catalogue.
- Every live run needs explicit user approval
  ([AGENTS.md](../../AGENTS.md#testing-expectations)). Ordinary `test` and `verify`
  steps never call a provider.
- Plan, Tasks and Implement each need their own E2E cases.

## Commands

| Command | Live? | Purpose |
| --- | --- | --- |
| `./scripts/e2e-spec.sh --case <case>` | Yes | Generate, publish and grade one case |
| `./scripts/e2e-call.sh ...` | Yes | Resend one captured request |
| `./scripts/provider-compatibility.sh --case <case> --live` | Yes | Send one fresh first request (needs the frozen 16,384-token binding; shipped cases are rejected) |
| `zig build evaluate-spec -- ... --live` | Yes | Grade a supplied specification |
| `zig build adjudicate-spec -- ...` | No | Apply a human adjudication offline |
| `zig build test-integration`, `test-rubric-evaluator`, `verify` | No | Offline mechanics, packaging and smoke checks |

Open calibration and acceptance work is tracked in [FIX05](../../fixes/FIX05.md).
