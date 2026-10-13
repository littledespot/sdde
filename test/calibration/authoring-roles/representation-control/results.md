# Phase 5 historical representation diagnostic results

The approved panel completed **22/22 actual AWS Bedrock exchanges** between `2026-10-12T21:36:25.594340Z` and `2026-10-12T21:36:45.545014Z`. It used the frozen historical complete-role classifier, GPT-OSS-20B in `ap-southeast-2`, low reasoning, temperature `0.1`, native schema and a 16,384-token output allowance. No retries, corrections, repairs, model judges or E2E runs occurred.

The user explicitly approved the previously proposed diagnostic labels. The original proposed cohort remains unchanged; reviewed copies supplied the frozen native scoring owner. The following semantic counts are **against those approved labels**, not independent deterministic proof or an authored-quality estimate. Captured cases are known correlated regressions.

All **22 request body hashes, controls and authentic original/parent ancestry** matched the frozen preparation. Usage was known for every exchange: **36,410 input + 3,289 output = 39,699 tokens**, below the 150,000 actual-token experiment stop.

## Results

**21/22 answers passed native/protocol admission.** The remaining implementation-only repeat returned no final text (`missing_final_text`): extraction failed, with JSON and schema checks unavailable. It remains in the declared denominator; no semantic score is invented for it.

Among admitted answers, **28/114 required-role observations were explicitly false `unsupported` decisions**. There were **14/104 label-disallowed role/group selections**: 12 wrong-basis selections and two forbidden story positives in the constraint-only control. **11/22 trials** met all role-selection labels.

| Case | Admitted / declared | Missing / required roles | False unsupported | Disallowed pairs | Exact label trials | Input + output tokens |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| captured-four-negative-latest | 2/2 | 4/12 | 4 | 6 | 0/2 | 3338 + 443 |
| captured-four-negative-preceding | 2/2 | 8/12 | 8 | 0 | 0/2 | 3342 + 352 |
| captured-supported-control | 2/2 | 0/12 | 0 | 0 | 2/2 | 3738 + 359 |
| startup-whole-chunk | 2/2 | 10/12 | 10 | 0 | 0/2 | 3420 + 272 |
| startup-separate-lines | 2/2 | 0/12 | 0 | 6 | 1/2 | 3820 + 356 |
| lamp-whole-chunk | 2/2 | 6/12 | 6 | 0 | 1/2 | 3008 + 249 |
| lamp-separate-lines | 2/2 | 0/12 | 0 | 0 | 2/2 | 3408 + 218 |
| parcel-whole-chunk | 2/2 | 0/12 | 0 | 0 | 2/2 | 3056 + 230 |
| parcel-separate-lines | 2/2 | 0/12 | 0 | 0 | 2/2 | 3456 + 206 |
| implementation-only-insufficient | 1/2 | 0/0 | 0 | 0 | 1/2 | 2972 + 216 |
| constraint-only-partial-support | 2/2 | 0/6 | 0 | 2 | 0/2 | 2852 + 388 |

## Representation and unchanged repeats

Across the three byte-identical-source representation pairs, whole-chunk claims produced **16/36 false unsupported role decisions**; separate-line claims produced **0/36**. Parcel succeeded in both representations. Startup and lamp contributed the difference. However, separate-line startup repeat 1 selected both the behavioral group and a copied-token-only group for every role, adding **six label-disallowed pairs**. Reduced false blocks did not establish correct support selection.

**Four of ten fully admitted case pairs changed their semantic decisions on an unchanged repeat**: latest captured failure, startup whole-chunk, startup separate-lines and lamp whole-chunk. Implementation-only changed admission separately: its first answer correctly declared all roles unsupported; its second supplied no final answer.

The constraint-only control supported three required roles but falsely supported a user-story role twice. Optional description and goal selections were allowed by the approved labels and were not counted as missing roles.

## Corrected executable preparation

The first launcher process selected the pinned automated **offline wrapper**, which had model connections compiled out. Its generic `transport_failed` receipt contained no HTTP status/body/usage. Static analysis proved `_offline.live_model_connections = false` and an immediate error return before HTTP; **zero AWS payloads were sent**. Preserve that original process receipt and [analysis](/Users/trentinbarnard/projects/sdde/zig-out/phase5-role-representation/transport-analysis.json). It did not consume a model-call allowance.

The existing live-capable historical target was rebuilt through its isolated repository `build.zig`, with all 17 retained preparation/scoring owners byte-identical. The new binary’s live flag and native HTTP path were verified. The original offline executable, proposed labels and captures were preserved. The live-capable binary reconstructed all 22 provider bodies, settings and ancestry unchanged before the approved schedule began. No current production classifier or compatibility path was restored.

This panel supports investigating representation sensitivity and confirms continued classification variability. It **does not** qualify selecting groups during current authoring calls, explain their different output errors, establish publication/rubric quality or complete Phase 5/Phase 11. Assess the current authoring panel independently; do not present these different tasks as a paired improvement result.

See [scorecard](scorecard.json), [frozen original preparation](preparation.json), [amended approved preparation](/Users/trentinbarnard/projects/sdde/zig-out/phase5-role-representation/approved-live-preparation.json) and [actual dispatch journal](/Users/trentinbarnard/projects/sdde/zig-out/phase5-role-representation/live-capable-dispatch-journal.json).
