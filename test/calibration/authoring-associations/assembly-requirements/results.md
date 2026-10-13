# Assembly requirements and ownership comparison results

The approved comparison completed **42/42 calls**, covering **30 complete
collection trials**. Native admission improved from **3/10 baseline collections
to 7/10 in each candidate arm**, but **neither candidate passed qualification**.
Explicit entity requirements reduced family omissions; they did not establish
meaningful entities, reliable completion or correct source ownership.

## Separate outcomes

| Metric | Baseline | Family | Ownership |
| --- | ---: | ---: | ---: |
| Physical calls | 14/14 | 14/14 | 14/14 |
| Completed, schema-valid responses | 14/14 | 12/14 | 13/14 |
| Output-limit stops | 0 | 2 | 1 |
| Native-admitted collections | 3/10 | 7/10 | 7/10 |
| Complete required-entity collections containing AC/FR/entity | 0/6 | 4/6 | 5/6 |
| Native-admitted required-entity collections | 0/6 | 3/6 | 4/6 |
| Admitted collections passing known semantic checks | 2/10 | 2/10 | 4/10 |
| Additional admitted startup collection with uncertain token ownership | 1/10 | 1/10 | 1/10 |
| Input tokens | 28,318 | 28,334 | 28,726 |
| Output tokens | 6,182 | 40,462 | 30,676 |
| Total actual tokens | 34,500 | 68,796 | 59,402 |

The six required-entity trials per arm include equipment, renewal and warehouse,
each repeated twice. Among completed Family collections, required-entity omissions
disappeared: all four complete collections contained entities; the other two were truncated.
Ownership contained entities in all five complete collections, with one truncated.
These presence counts include collections rejected for duplicates or failing
semantic checks. Partial entity lists never count as completed family coverage.
The denominator remains six; rejected and truncated outputs are retained.

Baseline versus Family changes only conditional entity presentation. Family versus
Ownership changes only shared assignment/context guidance, using the same Family
receipts for both comparisons. The combined Baseline/Ownership contrast changes
two factors. No-entity Baseline/Family requests are byte-identical and still produce
different answers, demonstrating response variability in unchanged controls.

## Findings against original meaning

| Case | Baseline | Family | Ownership |
| --- | --- | --- | --- |
| Startup | Both retain business meaning; repeat 1 is rejected for a duplicate record. Token-only ownership remains uncertain. | Repeat 1 puts the greeting alone in every token-batch acceptance field and FR: correct literal, wrong field purpose. Repeat 2 preserves meaning. | Both preserve meaning; repeat 2 is rejected for a duplicate record. Token-only ownership remains uncertain. |
| Equipment | Both omit entities and attach another group's availability duty to the retention group's acceptance criterion. | Repeat 1 truncates during entity expansion. Repeat 2 contains entities and retains aggregate obligations, but swaps group duties and requires unsupplied inspection-date recording. | Repeat 1 still substitutes availability for retention and its second call truncates. Repeat 2 returns 145 and 98 entity records, including ellipsis placeholders and unsupported technical/governance structures; native duplicate rejection also applies. |
| Renewal | Both omit entities but retain eligible extension and the explicitly undecided duration. Some tracking is implicit; an AC guard is weak in repeat 2. | Repeat 1 truncates during entity expansion. Repeat 2 changes eligibility to active/not-returned and drops the supplied duration uncertainty. | Both supply a relevant Loan/deadline entity. Eligibility survives in FR, but AC guards remain weak and the assigned undecided-duration fact disappears. |
| Warehouse | Both omit entities. One invents audit logging/timestamps/authorization; the other produces repetitive constraints and misplaced trigger/results. | Repeat 1 emits 86 entities, including 17 ellipsis placeholders and unsupported register-wrapper structures, then fails duplicate admission. Repeat 2 is concise and source-supported. | Both are concise and preserve identifier/location retention with relevant entities. Readback can demonstrate retained data and is supported by the supplied location goal. |
| Completion notification | Both preserve the success-triggered notification and field purposes. | Repeat 1 places successful completion in both `given` and `when`; repeat 2 is meaningful. | Both preserve the notification duty and field purposes. |

The equipment substitution is a definite ownership defect across different original
sources. Startup's literal-only group has the same authoritative source context;
its ownership is explicitly uncertain. That uncertainty does not justify skipping
the group, forcing empty output, expanding selected claims, banning context or
weakening duplicate admission. Correct greeting text appears in every startup
collection; literal correctness does not make a literal-only `given` or `when`
meaningful.

Renewal's eligible extension is not labelled wholly absent when an FR retains it.
The missing known uncertainty and weak acceptance guard are separate observations.
No arm invented an arbitrary numeric duration or returned a clarification. A
clarification was not required simply to draft known behavior; loss of the supplied
undecided-duration fact is the measured defect. Illustrative equipment/parcel IDs
and simple readback scenarios are not automatically classified as invented rules.

Three calls reached **16,384 output tokens**: equipment Family repeat 1/group 1,
equipment Ownership repeat 1/group 2 and renewal Family repeat 1. Their actual
responses visibly expand long entity hierarchies before truncation. Several other
responses finish with repeated entities and placeholders. More entity emission
therefore raises presence without establishing entity adequacy. The Family arm
uses almost twice the baseline tokens; the Ownership arm remains more expensive
than baseline. This small panel does not establish why generation began repeating
or prove that every observed regression was caused by a changed instruction.

## Native checks, evidence and limits

Current native admission rejects six Baseline collections for missing entities
and one for duplicate records; Family has two noncandidate output-limit responses
and one duplicate rejection; Ownership has one output-limit response and two
duplicate rejections. Admission uses the same current contract in every arm,
including existing singleton construction and fixed group associations. Inspector
schema success is separate from native collection admission.

The [scorecard](scorecard.json) retains every trial's actual identities, costs,
native issue, component judgments and evidence references. Authentic requests,
responses, frozen plan and dispatch journal remain under
[the comparison directory](../../../../zig-out/assembly-requirements-comparison/).
The [native receipt report](../../../../zig-out/assembly-requirements-comparison/native-admission.json)
was copied from the existing collector without changing its judgments.

The receipt collector passed:

```sh
zig build test-specification-generation --summary all -j2
```

**320/320 tests, 3/3 steps, exit 0.** Earlier complete offline verification remains
**1,489/1,489 tests, 137/137 steps**, including packaging. This invocation made
no additional model calls. The debugger was stopped after dispatch; the 42-call
allowance is consumed and no calls were resent.

Total measured usage is **85,378 input + 77,320 output = 162,698 tokens**, below
the 200,000-token stop. All costs are known, with zero unsent or uncertain sends.
Summed loopback replay durations are **238.533 seconds**, not full experiment
wall-clock time or isolated provider latency. There were no retries, corrections,
repairs, model judges, source-review calls, workflow continuation or E2E invocations.

These are manual judgments by implementation agents with independent review,
not deterministic semantic proof. Five development cases, two repetitions and
controlled MOCK prior context do not qualify the real production handoff,
publication or actual-output rubric. Warehouse gives useful positive evidence;
equipment and renewal leave both candidates' overall gates failed. Phase 5 remains
open. A further production change must address the observed source-backed entity
and field-purpose defects through the shared owners and measured comparisons;
these results do not support declaring the authoring workflow reliable.
