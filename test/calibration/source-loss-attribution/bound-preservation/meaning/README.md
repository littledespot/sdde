# Bound preservation — meaning versus representation

**Status: 32/32 approved calls executed; semantic gate failed.** Both arms admitted
16/16 responses and attributed 14/16 correctly. The candidate did not improve
attribution. The approval is consumed; no repairs or E2E runs were executed.

Offline verification on 10 October 2026: `zig build test-specification-generation
--summary all` passed **288/288 tests**; `zig build verify --summary all` passed
**1,455/1,455 tests, 142/142 steps**, including integration, architecture/lint and
packaged clean-environment smoke checks. Changed Zig formatting, staged/unstaged
diff checks and frozen source/request/parent/native-snapshot hashes pass.

The preceding [projection comparison](../projection/README.md#results--10-october-2026)
admitted 16/16 candidate responses and attributed 14/16 correctly. Both remaining
errors required a separate preserved-token member even though the assigned
business claim already expressed the required display text. They falsely
attributed candidate loss to role selection. Phase 3 remains unaccepted.

## Candidate and boundary

The shared `source_omission_context.ClaimMeaning` projection now supplies resolved
meaning and source identity without the extraction-category label. The loss prompt
assesses expressed meaning regardless of grouping or category: a value already
expressed in a requirement needs no separate member, while a bare value does not
establish the behavior required around it.

Canonical categories, occurrences, citations, classification decisions, roles,
assignments, persisted evidence, response schema, admission and repair permissions
are unchanged. Classification decisions remain visible when they describe actual
producer behavior. This is not removal of every `kind` field or native recognition
of semantic equivalence. Initial requests, protocol correction and existing repair
paths share the same packet owner. There is no model-specific exception, extra
reviewer, forced token insertion, semantic override or new continuation rule.

The baseline is the preceding projection candidate. Both arms use the current
bound-comparison response contract and production native admission. Historical
requests and results remain immutable. Do not interpret passing structure as
passing semantics or infer that this bundle identifies the cause of model behavior.

## Frozen comparison

[comparison.json](comparison.json) freezes eight cases × two arms × two repetitions
= **32 physical calls**. Request paths resolve against the parent
`bound-preservation/` directory. Source hashes resolve against repository root.
Use AWS Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning,
temperature 0, native schema and 16,384 output allowance. No retries, corrections,
repairs, model judges or E2E calls are included. Any attempted send consumes its
trial; uncertain transport stops dispatch without resending.

The original eight facts and expected verdicts remain unchanged:

- Captured description: the complete collection includes an embedded greeting and
  its separate exact occurrence; the role collection includes the greeting in its
  business claim. Both preserve meaning. The candidate has the actual literal loss.
- Loan, parking and joint-source cases: complete upstream obligations with a
  deficient candidate; assess conditions, negation and joint support.
- Extraction case: required shutdown behavior and recovery conditions are absent
  upstream. Presentation changes must not turn that absence into preservation.
- Fan signal: original requirements preserve the condition that its signal omits.
- Wrong role: the complete extracted collection preserves notification, but its
  assigned role collection does not. Supporting context cannot supply that member.
- Multiple producers: absence across independently owned inputs must remain safely
  unresolved rather than inventing a unique repair owner.

All eight are observed regression inputs, not a fresh holdout. This comparison
covers the captured representation error and unrelated loss controls; it does not
establish all token-classification or exact-literal-loss behavior. Two repetitions
are a pilot, not general reliability evidence.

Keep every existing gate: at least 15/16 completed/schema-valid/native responses;
zero false upstream/candidate attributions; both correct extraction, signal and
role diagnoses; both safe unresolved multi-producer diagnoses; at least 7/8 correct
candidate-defect diagnoses; at most one unnecessary uncertain result; adequate
evidence on at least 14/16; at least two more correct admitted attributions than
concurrent baseline, with no case-level regression. Report raw verdict correctness
separately. If baseline scores too highly to demonstrate the required improvement,
report that result as inconclusive against the unchanged gate, not a pass.

## Verification and execution

`zig build test-specification-generation --summary all` reconstructs each native
case, checks unchanged assignments, source lines, ordered member occurrences and
resolved meaning, and reproduces every frozen body through the production Bedrock
encoder. Current requests must equal the current production packet and prompt.
Historical arms are retained only as experimental evidence, never runtime readers.
The workflow observer checks the projection on live-path fake-port requests,
including protocol correction and repair. Existing lifetime/allocation and native
recovery/readback tests remain applicable.

After fresh explicit bounded approval under [§28.8](../../../../../design/contracts/28-testing.md#288-model-conformance-comparisons),
use the existing [isolated debugger procedure](../../README.md#bounded-replay-procedure):

1. Check all frozen hashes and exact parent/settings before dispatch; copy the
   entire parent comparison directory into the isolated diagnostic workspace.
2. Send each of the 32 modified replay requests once, in manifest order. Retain
   provider bodies, responses, stops, usage, latency and normalization; compare
   each actual provider request with its frozen body.
3. Save decoded responses as
   `.zig-cache/source-loss-preservation/<case>.meaning-<arm>.response-<1|2>.json`.
   Run the focused command to produce corresponding `.native-<1|2>.json` reports
   using production admission for both arms. Missing files are unassessed.
4. Complete [scorecard.template.json](scorecard.template.json) against original
   requirements. Score missing meaning, false upstream/candidate attribution,
   unsupported allegations and evidence adequacy independently of valid IDs/JSON.
   Keep all failures in denominators and disclose non-blinded semantic assessment.

The user explicitly approved all 32 calls, including sending the frozen synthetic
requirements, derived evidence, non-public project guidance and schemas to AWS
Bedrock. The allowance is consumed: **96 diagnostic calls total** across the three
comparisons. Phase 4's three conditional E2E approvals remain unused because
Phase 3 has not passed. The frozen manifest retains its pre-dispatch state;
the execution journal below records actual dispatch and results.

## Results — 10 October 2026

All 32 approved requests executed exactly once, ended with provider `stop`, and
passed JSON/schema validation after the existing Bedrock prefix normalization.
Both arms passed production admission. The debugger stopped; retained artifacts
passed credential/session-token checks. No retries, corrections, repairs, extra
model judges or E2E calls occurred.

The [execution journal](../../../../../zig-out/source-loss-meaning-comparison/2026-10-10T07-49-32Z-iup3mpv6/results/execution.json),
[complete scorecard](../../../../../zig-out/source-loss-meaning-comparison/2026-10-10T07-49-32Z-iup3mpv6/results/scorecard.json)
and [manual source/response assessment](../../../../../zig-out/source-loss-meaning-comparison/2026-10-10T07-49-32Z-iup3mpv6/results/manual-assessment.json)
retain every trial. Post-run production admission passed **288/288 focused tests**.

| Measure | Baseline | Candidate |
| --- | ---: | ---: |
| Completed, JSON/schema valid | 16/16 | 16/16 |
| Native admission | 16/16 | 16/16 |
| Correct comparison verdict sets | 14/16 | 14/16 |
| Correct admitted attribution | 14/16 | 14/16 |
| False upstream ownership | 2 role attributions | 2 role attributions |
| False repairable upstream ownership | 0 | 0 |
| Adequate evidence and explanation | 14/16 | 14/16 |
| Unnecessary unresolved ownership | 0 | 0 |
| Input tokens | 18,230 | 18,302 |
| Output tokens | 3,880 | 3,738 |
| Total tokens | 22,110 | 22,040 |

Total usage was **44,150 tokens**. Recorded debugger roundtrips totaled 20,339 ms
baseline and 20,831 ms candidate; these include local overhead and are not provider
inference latency. No improvement in semantic outcomes was demonstrated.

Both captured-description repetitions still returned `preserved`/`lost`, deriving
the wrong role owner. Member 2 in **both** collections explicitly contains the
required greeting and startup behavior. Only the first collection additionally
contains member 4, a bare exact value. Candidate repetition 1 incorrectly describes
the full behavioral requirement as member 4, then treats its absence from the
second collection as lost meaning. Repetition 2 similarly overlooks member 2.
The baseline explicitly invokes the missing preserved-token category. Removing
that category from resolved claim presentation changed the explanation, not the
wrong decision. Correct output remains `preserved`/`preserved`, attributing the
fixed deficiency to the candidate.

The other seven cases passed both repetitions in both arms. Three frozen gates
failed: zero false upstream ownership; at least 7/8 candidate-defect diagnoses
(actual 6/8); and improvement of at least two correct admitted attributions
(actual zero). Role repair remains prohibited, but false unsupported ownership
still blocks the appropriate candidate-local repair and is not harmless.

The source/response review is non-blinded semantic assessment, not deterministic
proof. Baseline role-loss assessments cite opening-hours line 2 locally, while
their first assessments cite notification line 1. Candidate multi-producer trial 1
cites retained-claim lines rather than missing-obligation lines. The full supplied
sources, fixed finding and explanations establish the correct omissions; these
local citation weaknesses are disclosed rather than scored as invented losses.

**Conclusion and remaining work:** the presentation candidate is implemented and
mechanically verified, but is not semantically accepted. Category removal and this
guidance are insufficient. The observed explanations suggest confusion between
collection membership differences and preserved meaning; they do not establish
the model's internal cause or rule out influence from supporting context. Do not
weaken the gate, force candidate attribution, insert tokens into role membership
or expand repair permissions. A next investigation must distinguish those possible
causes with controlled representation/collection inputs before another production
change; any new live comparison requires a newly frozen plan and approval.
Phase 4 remains unstarted.
