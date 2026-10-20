@AGENTS.md

# Claude Code

[AGENTS.md](AGENTS.md), imported above, is the contract for every coding agent in this
repository, Claude Code included. Read its references to Codex as references to the
coding agent. This file adds only Claude Code specifics. It doesn't restate, relax or
outrank AGENTS.md.

## Intent

[design/intent.md](design/intent.md) sets out what the engine is for. It turns source
material and user requirements into traceable, validated outputs. Lower-capability
models do focused semantic work. Deterministic code does everything that can be
computed reliably.

Judge an engine change by its effect on:

- requirement preservation;
- unsupported additions;
- false assessments;
- repair-induced harm;
- successful completion;
- latency and cost per acceptable result.

Passing structural tests, or getting more model calls to succeed, is not enough. The
intent statement guides judgment but isn't contract authority. Its proposed shift
toward smaller semantic decisions hasn't been accepted.

## Authority and open work

- AGENTS.md routes work by section of [design/design.md](design/design.md):
  - section *N* is detailed in `design/contracts/NN-*.md`;
  - the §13 action catalogue is in `design/contracts/actions/13-*.md`;
  - accepted amendments are ADRs in [design/decisions/](design/decisions/), indexed in
    design.md §32.
- These documents are large. Use the `design-router` agent to collect the governing
  clauses with citations, rather than reading whole files.
- Before you propose, implement, review or decide an engine change:
  - read [.claude/known-work.md](.claude/known-work.md), a dated snapshot of known
    failure classes and open work;
  - check the accepted ADRs for any rule the change would break.

## Evidence for a contract change

- Decide on at least two unrelated development cases, with replayed repetitions. A
  single run cannot decide a change.
- Never tune on the sixteen reserved qualification features.
- A model limitation under a coherent contract is a valid result. Report it. Don't
  work around it with case-, field- or model-specific rules, sampling changes, extra
  retries, a second model or a weaker admission rule. The standalone evaluator's one
  mechanical correction is an explicit harness exception (user decision, 18 October
  2026), not engine policy.
- Count budget-stopped, malformed and exhausted runs as attempted workloads.
- Report each of these separately: implementation complete, mechanical checks
  passed, semantic benefit demonstrated, brittleness reduced, scope qualified.
- Finding-type accuracy is the share of review findings whose type matches a frozen,
  source-based label. A real defect reported with the wrong type is a harmful
  diagnosis.

## Commands

Use Zig **0.16.0** exactly ([.zigversion](.zigversion)). Build and test only through
`build.zig` steps. `zig build --help` lists them.

| Purpose | Command |
| --- | --- |
| Format and AST check | `zig build lint` |
| Unit tests | `zig build test` |
| Layer and authority boundaries | `zig build test-architecture` |
| One owning boundary | `zig build test-<area>` |
| Offline integration scenarios | `./scripts/test-integration.sh` |
| Packaged executable in a clean directory | `zig build smoke` |
| Complete offline verification | `zig build verify` |

None of these make model calls. The build rejects any `test`, `test-*`, `smoke*` or
`verify` step that depends on a live step.

Billed live calls and engine execution need explicit user approval every time. The
project settings make each of these prompt:

- `zig build run`, `e2e-spec`, `e2e-call`, `evaluate-spec`, `provider-compatibility`
  and `baseline`;
- the matching `scripts/*.sh` launchers;
- any binary under `zig-out/bin/`.

The user starts a live Spec case with `/live-e2e <case>`.

## E2E assessment

- No model grades an E2E run (user decision, 19 October 2026). Use `/evaluate-e2e
  <run>` to assess a retained run. Its output is advisory analysis, not a grade or a
  review.
- Development acceptance is decided only by a human-written
  `human-spec-adjudication/v2` record, applied with the offline
  `zig build adjudicate-spec` ([R8](design/harness/acceptance.md)). Never write that
  record, and never present advisory scores as acceptance. A published run exits
  nonzero until it is adjudicated.
- Write results only under the Git-ignored `evaluations/`, unless the user agrees to
  another location. Only the launcher writes run directories under `zig-out/`, which
  are immutable evidence.

## Claude Code setup

- `.env.e2e` holds live provider credentials. Never read, print, source, copy or edit
  it; the launchers load it themselves. `.env.e2e.example` lists the variable names.
- After each edit to a repository `.zig` file, a hook runs the pinned `zig fmt`. If it
  reports a parse error, fix it before continuing.
- `/preflight <task>` produces the AGENTS.md "Before editing" analysis. `/verify`
  runs the validation ladder and writes the definition-of-done report.
- Before reporting a change complete, have the `contract-reviewer` agent review the
  diff against the AGENTS.md review rules.
- These files are policy, so every edit to them prompts: AGENTS.md, CLAUDE.md,
  accepted ADRs, and the Claude Code settings and hooks. Change them only when the
  task includes that policy change.
- [.claude/README.md](.claude/README.md) describes this configuration for maintainers.
