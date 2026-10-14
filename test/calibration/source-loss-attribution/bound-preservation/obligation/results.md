# Phase 3 result — explicit missing obligation

**Completed; semantic acceptance failed.** All 48 approved calls were sent once
on 10 October 2026, 09:59:39–10:01:15 UTC. No retries, repairs, model judges,
additional source-review calls or whole-workflow E2E runs were made.

The source-review contract and native handoff are implemented. The comparison
shows some improvement, but does not establish a reliable semantic fix and does
not permit Phase 4 to proceed under its conditional approval.

| Measure | Baseline | Candidate |
| --- | ---: | ---: |
| Planned / completed calls | 24 / 24 | 24 / 24 |
| Valid JSON and schema | 24/24 | 24/24 |
| Production native admission | 24/24 | 23/24 |
| Correct admitted attribution and preservation labels | 18/24 | 20/24 |
| Adequate semantic evidence | 17/24 | 19/24 |
| Admitted false upstream attribution | 6 | 3 |
| False candidate attribution | 0 | 0 |
| Input tokens | 29,770 | 31,140 |
| Output tokens | 6,300 | 6,370 |
| Median replay round trip | 1,351 ms | 1,300 ms |

The one native rejection is additional to the candidate's three admitted false
upstream attributions. It is not scored as a safe successful diagnosis. Total
usage was **73,580 tokens**: 60,910 input and 12,670 output. Every provider response
reported `stop`; no output-limit or transport failure occurred. Provider latency
is unavailable in the export; round trips exclude subsequent offline admission.

## Per-case outcomes

Correct admitted attribution and preservation labels, out of two trials:

| Case | Baseline | Candidate |
| --- | ---: | ---: |
| Captured description | 0/2 | 0/2 |
| Loan candidate loss | 2/2 | 2/2 |
| Inherited extraction loss | 2/2 | 2/2 |
| Direct signal loss | 2/2 | 2/2 |
| Joint source support | 2/2 | 2/2 |
| Wrong role assignment | 2/2 | 2/2 |
| Multiple unresolved producers | 2/2 | 2/2 |
| Parking candidate loss | 2/2 | 2/2 |
| Captured story | 2/2 | 0/2 |
| Fresh negative door obligation | 0/2 | 2/2 |
| Fresh joint voucher prerequisites | 2/2 | 2/2 |
| Fresh equal-byte literal occurrences | 0/2 | 2/2 |

The fresh cases improved from **2/6 to 6/6**, but the captured story regressed
from **2/2 to 0/2**. The original eight-case subset remained **14/16** for both
arms; evidence adequacy remained **13/16** for both. An improved aggregate cannot
replace the frozen subset, safety and captured-case gates.

## What failed

1. **The complete collection is still being misread.** Both captured-description
   candidate responses label comparison 2 `lost`, although its member 2 explicitly
   requires displaying the greeting at startup. The missing separate literal
   member does not remove that behavior. The candidate no longer needs to infer
   the target obligation from diagnostic prose, yet still makes this error.
2. **The captured story regressed.** Baseline responses recognize the full
   requirement in member 2 of both comparisons. Candidate responses incorrectly
   say it is absent from comparison 2. The first candidate selects `members: []`
   for this nonempty collection, so native admission rejects it. The second
   supplies valid member IDs and is admitted with false story-role attribution.
   The engine's closed contract catches invalid evidence selection; it cannot
   prove the model's semantic claim from structurally valid references.
3. **Correct labels can still have defective evidence.** Candidate extraction
   repetition 2 correctly returns `lost/lost` but falsely says the source lacks
   the requirement to remain stopped until recovery. The source expressly says
   the pump must stop until the level recovers. Baseline unresolved-ownership
   repetition 2 cites only temperature display/recording lines instead of the
   cooling/alarm obligations. These are inadequate explanations despite correct
   derived ownership.

Voucher responses correctly identify the two prerequisites and missing manager
approval. Their lost-view citation includes only the payment source; the manager
premise is cited in the preceding assessment. Assessment records this limitation
while treating the complete answer's explanation as adequate. No label or gate
was changed after observing responses.

## Frozen gate assessment

- Passed: original-subset completion/admission, both extraction/signal/role
  diagnoses, both safe unresolved diagnoses, uncertainty limit, no regression
  within the original eight cases, and all six fresh-case trials.
- Failed: zero false upstream attribution; at least 7/8 candidate-defect results
  (actual 6/8); at least 14/16 adequate evidence (actual 13/16); improvement of at
  least two original-subset results (actual zero); both captured-story results.

The results support separating the omitted obligation from the defect explanation
as an explicit contract. They do **not** support claiming that this presentation
alone fixes loss diagnosis. The remaining failure concerns reasoning over the
complete assigned collections and equivalent representations. Another change
requires a separately frozen hypothesis and approval; no extra calls or broader
repair permissions are implied by this failed panel.

## Verification and retained evidence

- `zig build verify --summary all -j2`: **142/142 steps, 1,461/1,461 tests passed**,
  including architecture, schemas, integration and packaged-executable checks.
- `zig build test-integration --summary all -j2 --global-cache-dir .zig-cache/global`:
  **95/95 tests passed**, including the configured production workflow scenarios.
- `zig build test-specification-generation --summary all -j2` after retaining live
  responses: **290/290 tests passed**; all responses went through production native
  admission. A negative admission result is recorded, not converted into test success
  evidence for semantic quality.
- `git diff --check`: passed.

The [frozen manifest](comparison.json), [per-trial scorecard](scorecard.json) and
[predeclared criteria](README.md) retain all planned denominators. Actual provider
requests, raw responses, parsed responses, native reports, debugger identities,
request/response hashes, usage, execution journal and verification logs are in
[the retained run](../../../../../zig-out/source-loss-obligation-comparison/2026-10-10T09-59-39Z/results/).
Its credential/session-token scan found no matches. The initial automatic approval
review blocked dispatch; the user then explicitly approved these payloads and the
AWS destination before the first send. The 48-call allowance is now consumed.

Assessment was manual and unblinded. Separate code-review agents assessed all
original-eight and final-four responses; the primary agent checked the failure
evidence and calculated the unchanged gates. This is a small regression panel,
not a population accuracy estimate. Source-review requests are prepared and their
handoff is tested offline, but this fixed-omission comparison does not establish
live fidelity of the new upstream `missing_obligation` or successful recovery and
publication. The conditional Phase 4 E2E approval remains unused.
