# Withdrawn authoring-input comparison — historical evidence

**Status: withdrawn by the user on 14 October 2026.** The five authoring-input
changes, supporting production projections, active calibration implementation and
associated tests were reverted to the preceding implementation. This directory
retains the [results](results.md) and [scorecard](scorecard.json); it is not an
active preparation or dispatch entry point.

The experiment prepared five independent factors: entity purpose, assembly
context, composition guidance, evidence ownership and source uncertainty. Each
had three assignments, two arms and two repetitions: 60 planned physical calls.
Each candidate enabled only its named factor. Both arms used Bedrock
`openai.gpt-oss-20b-1:0` in `ap-southeast-2`, low reasoning, temperature 0.1,
native schema and a 16,384 output allowance, with fixed MOCK prior context.

Only 46 requests were sent before the 200,000 actual-token stop. The final
in-flight response crossed it to 202,021 tokens. Fourteen requests were not sent.
The proposed budget continuation is cancelled by withdrawal; no further calls
are authorized by this experiment.

The [original frozen plan](../../../../zig-out/authoring-remediations-comparison/freeze.json)
and its workspace snapshots retain the original guidance, case data, assessment
criteria, dependency versions and request bytes. Authentic exchanges, native
admission and canonical resolved records are retained beside it. The
[withdrawal record](../../../../zig-out/authoring-remediations-comparison/withdrawn.json)
identifies the rollback scope. Historical source hashes are intentionally not
rewritten to match restored production code.

The preceding assembly-requirements calibration is also historical: B9 retired
its conditional entity-batch comparison on 17 October 2026. Current tests cover
feature-owned entities; they do not execute or reclassify either historical panel.
The removed candidate data files remain available in the frozen workspace and
rollback archive. Any new candidate needs fresh preparation and approval;
retained results cannot authorize production promotion or new model calls.
