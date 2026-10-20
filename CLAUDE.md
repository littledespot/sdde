@AGENTS.md

# Claude Code

[AGENTS.md](AGENTS.md), imported above, is the contract for every coding agent in this
repository, Claude Code included. Read its references to Codex as references to the
coding agent. This file adds Claude Code specifics and a dated snapshot of known
failure classes and open work; it does not restate, relax or outrank AGENTS.md.

## Intent

[design/intent.md](design/intent.md) says what the engine is for. It turns source
material and user requirements into traceable, validated outputs. Lower-capability
models do focused semantic work, and deterministic code does everything that can be
computed reliably. Weigh engine changes by their effect on:

- requirement preservation;
- unsupported additions;
- false assessments;
- repair-induced harm;
- successful completion;
- latency and cost per acceptable result.

Passing structural tests, or getting more model calls to succeed, is not enough. The
intent statement guides judgment but is not contract authority. Its proposed
refinement toward smaller semantic decisions is still under evaluation and is not
accepted.

## Navigating authority and work

- AGENTS.md routes work by section number in [design/design.md](design/design.md).
  Section *N* is detailed in `design/contracts/NN-*.md`. The §13 action catalogue is
  in `design/contracts/actions/13-*.md`. Accepted amendments are ADRs in
  [design/decisions/](design/decisions/), indexed in design.md §32.
- These documents are large. Use the `design-router` agent to collect the governing
  clauses with citations instead of reading whole files into the main conversation.

## Commands

Use Zig **0.16.0** exactly ([.zigversion](.zigversion)). Build and test only through
`build.zig` steps; `zig build --help` lists them.

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

Billed live calls and engine execution need explicit user approval every time, and
the project settings make them prompt. That covers:

- `zig build run`, `e2e-spec`, `e2e-call`, `evaluate-spec`, `provider-compatibility`
  and `baseline`;
- the matching `scripts/*.sh` launchers;
- any binary under `zig-out/bin/`.

The user starts a live Spec case with `/live-e2e <case>`.

## E2E assessment

No model grades an E2E run (user decision, 19 October 2026). A run publishes its
artifacts and captures the exact source, rubric and specification for assessment:

- `/evaluate-e2e <run>` assesses a retained run against its rubric offline and traces
  each defect to the call, prompt or engine stage that produced it. Its output under
  the Git-ignored `evaluations/` is advisory analysis, not a grade or review.
- Only a human-written `human-spec-adjudication/v2` record, applied by the offline
  `zig build adjudicate-spec`, decides development acceptance
  ([R8](design/harness/acceptance.md)). Never write that record, or present advisory
  scores as acceptance. A published run exits nonzero until it is adjudicated.
- Before recommending a fix, check "Known failure classes and open work" below for
  an item that already covers it, and the accepted ADRs for a rule it would break.
  For example, ADR 0023 keeps post-generation review findings advisory, so they
  cannot change the output.
- Ask before writing results anywhere outside `evaluations/`. Only the launcher
  writes run directories under `zig-out/`, which are immutable evidence.

## Known failure classes and open work

Status on 20 October 2026. Recheck the code before relying on an item. The first
list covers the Spec workflow's live-run failure classes; the second covers other
open engine work.

- **Extraction collapses structured sources.** It returns one claim for a whole
  Markdown list of distinct requirements, in every hello-world sample, and it has
  weakened an obligation ("must renew" became "may renew"). Review then judged the
  weakened text supported. Proposed, not approved: segment list items natively
  before extraction. First replay both cases' retained extraction requests split per
  item, which is billed and needs bounded approval. Then decide the §16 chunking and
  extraction amendment.
- **Review dominates cost and misreports finding types.** Post-generation review
  takes about 75–80% of workflow tokens. It reports invented or unsupported content
  as `candidate_omission`. It has judged byte-identical text both supported and
  omitted, and has accepted an obligation-strength change. Under ADR 0023 every
  post-generation finding is advice: it never repairs content, rebuilds an upstream
  stage or creates a clarification. Approved on 18 October 2026 but not built: source
  review assigns one record family per call. This amends ADR 0023 and §17.3,
  advances `specification-state` to v19, and leaves the budget and reviewed record
  kinds unchanged.
- **Record authoring duplicates.** A record batch can re-author the whole feature.
  Groups holding only preserved tokens no longer get a batch (ADR 0024). The native
  duplicate rule compares whole typed record content, record kind included, so
  identical text in two record kinds passes. Proposed: compare per-group records with
  one complete record collection, only if generation-boundary failures remain. Add an
  acceptance-criterion diagnostic or per-family collections only where measured
  failures justify them.
- **Entity applicability is a model judgment.** No native rule can judge it. The
  hello-world feature has no data and has been judged both `not_applicable` and
  `required`.
- **An unresolvable positive advisory verdict still blocks.** No run has hit it. The
  fix needs no ADR change: leave positive verdicts out of an assignment's schema
  when they cannot resolve.
- **GPT-OSS envelope prefixes.** GPT-OSS-20B often malforms a response's opening, as
  in `{"token{` or `{"find{`. Admission normalizes the truncated member-name form
  (approved 18 October 2026). Don't widen the normalizer without a decision.
- **Budget headroom.** Loan-renewal has exhausted the 100,000-token budget and has
  published at 97,475. Raising the budget is not a reliability fix.

Other open work:

- **Clarification answer recovery** is a confirmed implementation gap: fresh answers
  cannot complete the registered recovery path. Refresh rejects new nonempty
  submissions with `AuthenticationRequired`, and provenance rejects nonempty
  response-ID sets. Treat it as a separate required feature.
- **Log retention is not wired.** Design §26 requires retention after recovery and
  rotation, and F0002 §6.4 fixes 14 days, but only tests call `retainHistorical` or
  construct the segment pruner.
- **Group-level provenance precision.** A record binds a whole accepted group, so
  membership doesn't mean each record expresses every linked claim. This follows
  ADR 0020 and is not a defect. Decide it before promising stronger provenance.
- **Architecture decisions before Plan.** Lifecycle mechanics live in workflow YAML;
  each concept costs about six coordinated edits; type-erased child bindings hide
  data flow; many rejections carry no reason; eight repair routes repeat one shape;
  reconciliation always makes four calls; two pairs of sibling steps are identical
  (proposal: merge them, no ADR change). Decide the YAML lifecycle, edit cost,
  child-binding and repair-route questions, and freeze contract scope, before
  starting Plan. Move lifecycle mechanics out of YAML before adding operations for
  another workflow.

Deciding a contract change:

- Decide on at least two unrelated development cases with repeated runs. One run
  cannot decide a change. Never tune on the sixteen reserved qualification features.
- A model limitation under a coherent contract is a valid result: report it. Don't
  answer it with case-, field- or model-specific rules, sampling changes, extra
  retries, a second model or a weaker admission rule. The standalone evaluator's one
  mechanical correction is an explicit harness exception (user decision, 18 October
  2026), not engine policy.
- Keep budget-stopped, malformed and exhausted runs in the attempted-workload count.
- Report separately: implementation complete, mechanical checks passed, semantic
  benefit demonstrated, brittleness reduced and scope qualified.
- Finding-type accuracy is the share of review findings whose type matches a frozen,
  source-based label. A real defect reported with the wrong type is a harmful
  diagnosis.

## Claude Code setup

- `.env.e2e` holds live provider credentials. Never read, print, source, copy or edit
  it; the launchers load it themselves. `.env.e2e.example` lists the variable names.
- After each edit to a repository `.zig` file, a hook runs the pinned `zig fmt`. If it
  reports a parse error, fix it before continuing.
- `/preflight <task>` runs the AGENTS.md "Before editing" analysis. `/verify` runs the
  validation ladder and writes the definition-of-done report.
- Before reporting a change complete, have the `contract-reviewer` agent review the
  diff against the AGENTS.md review rules.
- These files are policy, and edits to them always prompt: AGENTS.md, CLAUDE.md,
  accepted ADRs, and the Claude Code settings and hooks. Change them only when the
  task includes that policy change.
- [.claude/README.md](.claude/README.md) describes this configuration for maintainers.
