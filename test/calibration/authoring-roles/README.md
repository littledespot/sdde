# Authoring-role calibration

Development diagnostic under design §28.8, separate from integration tests and
live E2E. It measures role selection before R10's coverage gate and cannot publish
or authorize workflow output. Each live trial uses the existing replay owner for
one physical send, with no correction or repair.

## Complete role-decision contract

The current harness uses the production `role_decisions` decoder, native admission
and deterministic conversion into source bindings. It has no sparse-response
reader. Controlled cases use production packet/schema builders. Historical captures
are immutable: the current arm preserves their original facts, evidence and role
purposes while explicitly reprojecting current assignment instructions, guidance,
schema and native support-ID restrictions through the shared production owners. Captured role
purposes must exactly match the current shared purposes; a stale definition
rejects rather than silently changing facts or labels. Modified requests retain
parent/original call ancestry. `plan.json` declares the contract and projection.

Reports use `role-calibration-report/v2`, identifying
`complete-role-decisions/v1`. Historical v1 reports remain unchanged. The report
separates:

- Structural missing decision fields, observed only when a parsed JSON object is
  available. Invalid JSON has unknown coverage; present fields do not prove a
  valid branch or correct semantic judgment.
- `missing_supported_roles`: a required role with no labelled supporting group
  selected, including selection only on wrong groups. This meaning is unchanged.
- `false_unsupported_roles`: an admitted explicit negative decision on a required
  role. Optional labels contribute none. Sparse baseline answers have no explicit
  negative branch, so this metric is unavailable there, not zero.
- Unsupported selected pairs and their wrong-basis subset, with required/assigned
  denominators, unusable answers, all declared trials, per-role and source-family
  rows, unchanged repeats, usage and measured durations.

Zero missing fields cannot compensate for false unsupported decisions or wrong
selected groups. No automatic winner, promotion threshold or application success
rule is introduced. Semantic counts are conditional on admitted answers; protocol,
native and operational failures remain in the declared trial denominator. Missing
usage is unknown, not zero cost.

## Labels and retained evidence

The original pilot and routing cohorts were reviewed and approved by the project
user on 9 October 2026. Label approval is not approval for another API invocation.
`required: true` requires support on at least one `allowed_signal_ids` group.
Multiple allowed IDs are alternatives, not collective support. `required: false`
with allowed IDs permits an ambiguous choice; an empty allowed set means
unsupported. Every selected pair outside its allowed set counts as unsupported,
even if another pair supports the same role. Exact assignment order is not a
semantic target. Labels and rationales never enter model content.

`routing.cohort.json` supplies six development and four previously inspected
held-out cases in disjoint families. Source-order variants stay in their family's
split. `routing-captured.cohort.json` supplies two initial production captures in
one development family. These captures are correlated, not post-repair examples.
Contradictory controlled prose keeps its claims retained; it does not represent
native conflicting dispositions. Separate single-claim groups do not establish
multi-claim or collective-support reliability. Captured inputs retain upstream
errors and need independent semantic review.

The completed guidance-only routing comparison used 48 calls and 65,228 tokens.
Its candidate increased required-role omissions from 27/124 to 37/124 despite
reducing unsupported selections. Production guidance was retained. The
[selection record](../../../fixes/FIX01.md#97-r7-routing-calibration-follow-up--9-october-2026)
retains all reports; that allowance is consumed. These known cases are regression
evidence for the new contract, not a fresh blind confirmation. Broader/new-family,
collective-support and post-repair calibration still need reviewed premises.

## Pinned baseline and comparison scope

The response contract is the single declared intervention: complete decisions and
its concise branch instruction versus the pre-cutover sparse contract. Keep
model/settings, source bytes, native eligible group identities, shared role
purposes and labels fixed. Do not combine this comparison with `--guidance`.
That option remains a separate guidance-only diagnostic using the current contract.

The pre-cutover executable and its two runtime assets were pinned before editing:

| Artifact beneath `zig-out/role-contract-baseline` | SHA-256 |
| --- | --- |
| `sdde-calibrate-roles` | `5dabff71aaf2076efd1fc2eca99cf59a4b9ec1aba6144bdc2f4fe1c60cdbfa2f` |
| `workspace/design/workflows/spec/reconciliation.schema.json` | `b261d4b44be94de3d271d7413f759a6c7588387e180679dcf48da1c853787aaf` |
| `workspace/design/workflows/spec/reconciliation-roles.prompt.md` | `ab1cd891365f8743e9c571b8a0082199549711ec2e6d51f1596158ea5ad8a86a` |

The isolated baseline working directory contains byte-identical copies of the
unchanged cohorts and capture logs, recorded in `manifest.json`. Real directories
preserve the filesystem adapter's no-symlink rule. It reads the pinned
schema/prompt for those runtime assets. The current
executable reads current assets. Both run through their separately compiled
production decoder; there is no production dual reader and no rewritten capture.
The baseline must exist and its hashes must match before running this plan; a
missing artifact is not replaced with the current binary or another default.
These generated artifacts are local retained evidence, not packaged runtime data.

Completed allowance: **48 physical calls**, covering the same labelled regression
premises with two unchanged repeats per arm: development 24, captured 8, and
previously inspected held-out 16. The current arm's internal `baseline` variant
label means its unchanged current guidance; identify the comparison arm by its
separate report and `response_contract`, not that variant label.

Inspect all prepared request pairs before live approval. Require unchanged source
facts, evidence, role purposes and model/settings in each pair; user-packet changes
must be confined to the declared assignment-constraint instructions. Check narrowed
role IDs, complete current schemas and consistent repeat bytes. Freeze the contract,
its instructions and this
comparison before new observations. Reject a promotion claim if complete decisions
increase semantic omissions in aggregate or captured cases, conceal native/protocol
failure, or trade reduced wrong selections for unsupported mandatory roles.
A justified choice must show improvement in omissions or wrong selections while
preserving the other measure, with family/role regressions and cost visible.
This is a review criterion for this diagnostic comparison, not a new engine gate.
Actual publication, actual-output rubric quality and an unchanged E2E repeat remain
separate acceptance evidence; diagnostic selection cannot establish those outcomes.

## Offline preparation commands

First complete repository offline checks and build the current executable:

```sh
zig build test-rubric-evaluator build-role-calibration --summary all
mkdir -p zig-out/role-calibration
```

Run each command below once for each row in the plan table. Replace `COHORT` and
`SPLIT` literally with that row's values; the baseline command runs from the pinned
workspace and the current command from the repository root. Every invocation
creates a fresh output directory with `plan.json`, `report.json`, `report.md` and
immutable requests in `logs/debugger`. Offline trials are `not_run`.

| COHORT | SPLIT | Calls per arm | Both arms |
| --- | --- | ---: | ---: |
| `test/calibration/authoring-roles/routing.cohort.json` | `development` | 12 | 24 |
| `test/calibration/authoring-roles/routing-captured.cohort.json` | `development` | 4 | 8 |
| `test/calibration/authoring-roles/routing.cohort.json` | `held_out` | 8 | 16 |

Sparse baseline:

```sh
(cd zig-out/role-contract-baseline/workspace && ../sdde-calibrate-roles \
  --cohort COHORT --output zig-out/role-calibration \
  --feature zig-out/e2e-spec/2026-10-09T04-19-22Z-7b67250d97b3daaf1179b772812ddfbf/project/specs/hello-world \
  --run RUN-ea37ff5c4087e2b9f980b1bec102e098 --call request-7-inference-1 \
  --split SPLIT --repeats 2)
```

Complete current contract:

```sh
zig build calibrate-roles -- \
  --cohort COHORT --output zig-out/role-calibration \
  --feature zig-out/e2e-spec/2026-10-09T04-19-22Z-7b67250d97b3daaf1179b772812ddfbf/project/specs/hello-world \
  --run RUN-ea37ff5c4087e2b9f980b1bec102e098 --call request-7-inference-1 \
  --split SPLIT --repeats 2
```

Neither command contains `--live` or makes API calls. These explicit retained
bindings are Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning,
temperature 0 and native schema. No default binding/case is selected. Both arms
use the same reviewed cohort facts and labels; original sources and reports are
not modified.

## Live authorization

After offline verification, pair inspection and **fresh explicit bounded user
approval**, add `--live` to each approved command and supply
`TEST_AWS_BEARER_TOKEN_BEDROCK`. No `.env` file is loaded and production credentials
are not a fallback. The user subsequently approved and all six live invocations
completed: 48/48 physical calls. That allowance is consumed; any repeat needs a
new bounded approval. The pinned current executable and its asset hashes are
retained in `zig-out/role-contract-comparison/implementation.json`, with frozen
request pairs in `manifest.json` and aggregate actual outcomes in `results.json`.

The [results](../../../fixes/FIX01.md#99-complete-role-decision-implementation--9-october-2026)
show wrong-basis pairs falling from 39 to 0 and captured-input improvement, but
observed omissions rising from 35/124 to 38/117 admitted required roles, with seven
unscored premises and two missing-final-text answers. Explicit false unsupported
verdicts total 38. The declared semantic promotion condition was not met; zero
missing decision fields across 22 usable answers is mechanical evidence only.
Each complete-workflow E2E invocation separately requires approval and must finish
publication and rubric evaluation of the actual output.
