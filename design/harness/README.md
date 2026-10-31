# Spec workflow evaluation harness

The development harness runs the ordinary Spec workflow against an explicitly
selected case, using the real model configured by that case's `.sddtoolkit.json`,
and captures the specification that execution actually published with the case's
sources and rubric. Semantic quality is assessed against that rubric by human
adjudication of the retained run; no model grades an E2E run. Mechanical checks only
prove that inputs and execution were processed safely.

| Document | Covers |
| --- | --- |
| [e2e.md](e2e.md) | Live E2E, single-call and provider-compatibility diagnostics, environment setup, case/publication contract and retained results |
| [evaluator.md](evaluator.md) | Standalone supplied-spec grading, judge configuration, scoring and reports |
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
  permits only named tuples ([ADR 0029](../decisions/0029-bedrock-model-families.md#live-test-cost-policy)):
  `aws-bedrock` / `openai.gpt-oss-20b-1:0` from `ap-southeast-2`, for generation and
  the standalone evaluator, and `aws-bedrock` / `au.anthropic.claude-haiku-5-5`, for
  generation only. The shipped cases select GPT-OSS-20B. The policy supplies no default and does not
  restrict the production model catalogue. The `/evaluate-e2e` Claude Code skill
  is advisory assistant analysis outside this harness and its cost policy.
- Every live run needs explicit user approval
  ([AGENTS.md](../../AGENTS.md#testing-expectations)). Ordinary `test` and `verify`
  steps never call a provider.
- Plan, Tasks and Implement each need their own E2E cases.

## Commands

| Command | Live? | Purpose |
| --- | --- | --- |
| `./scripts/e2e-spec.sh --case <case>` | Yes | Generate and publish one case, capturing it for adjudication |
| `./scripts/e2e-call.sh ...` | Yes | Resend one captured request, or its `--edit` replacement |
| `./scripts/provider-compatibility.sh --case <case> --live` | Yes | Send one fresh first request (needs the frozen 16,384-token binding; shipped cases are rejected) |
| `zig build evaluate-spec -- ... --live` | Yes | Grade a supplied specification |
| `zig build adjudicate-spec -- ...` | No | Apply a human adjudication offline |
| `/evaluate-e2e <run>` (Claude Code) | No | Advisory rubric assessment and defect-origin analysis of a retained run |
| `zig build test-integration`, `test-rubric-evaluator`, `verify` | No | Offline mechanics, packaging and smoke checks |

Open calibration and acceptance work is tracked in [FIX06](../../fixes/FIX06.md).
