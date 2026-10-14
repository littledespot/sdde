# FIX01-02 Phase 1 — supporting candidate context pilot

**Status: 12/12 approved calls executed; the semantic gate failed.**
Baseline was correct on 1/6 trials; candidate on 2/6, with regression on the
captured case. No production promotion. See [results and limitations](results.md)
and the completed [scorecard](scorecard.json). The approval is consumed.

## One controlled change

Both arms are built from the current production `Source.packetForLoss` request.
The experimental candidate removes exactly:

`supporting_evidence.deficient_subject.business.context.candidate`

This full candidate view repeats the deficient story and adds downstream record
text. The hypothesis is that this surrounding output distracts the model from
judging the assigned upstream collections. The brief and entity explanation,
deficient story, all producer inputs/outputs, classifications, role assignments,
source lines, comparison members and response schema remain byte-equivalent as
JSON values. The prompt and controls are unchanged. There is no runtime option or
production projection change in this phase.

| Input | Purpose | Treatment |
| --- | --- | --- |
| Fixed finding and target purpose | Identify the missing meaning, without asking for a second verdict on the finding | Retain exactly |
| Sources and complete comparison members | Evidence to assess; retain occurrence identity, conditions and obligations | Retain exactly |
| Deficient subject text/slot | Explain the downstream failure already established as the premise | Retain exactly |
| Context brief and entity basis | Interpret the business goal and existing entity decision | Retain exactly |
| Context candidate | Repeated subject, display name and surrounding generated records; not an assigned producer collection | Remove only this field |
| Supporting producer outputs | Explain actual extraction/classification/disposition/signal/role decisions | Retain all, including repeated meanings |
| Native assignment, schema, IDs and permissions | Own admissibility and repair attribution | Unchanged |

This deliberately does not compress every repeated producer rendering. It tests a
single removal first. Successful results would support only this presentation
candidate, not blanket deletion of business context or a claim that all subjects
are self-contained. Broader fields and dependencies require Phase 3 coverage.

## Cases and frozen requests

[comparison.json](comparison.json) freezes three cases × two arms × two repeats,
with counterbalanced arm order. Paths resolve from repository root.

- **Captured story:** the actual malformed greeting story and its canonical brief,
  records, exact reference and sources. The prepared baseline's entire provider
  JSON body equals captured call 16, not merely a description renamed as a story.
- **Loan story:** unrelated eligible-loan renewal, a confirmation literal and a
  new return deadline. The literal is misplaced in the narrative; complete
  upstream claims still express all obligations. Synthetic prose is marked MOCK.
- **Wrong-role story:** notification after appointment cancellation is present in
  extraction but absent from the story's assigned role collection. Supporting
  evidence cannot supply the missing role member. This must remain unsupported
  role loss, not candidate repair.

Labels in `cases.json`, the manifest and scorecard are evaluation expectations.
Only `*.edit.json` content/schema is sent. `*.packet.json` retains native facts for
admission and inspection and is never submitted wholesale to the provider.
Canonical input files are frozen test inputs, not expected output documents.
Historical evidence under `recovery/`, previous experiments and the parent run
remain unchanged.

The existing calibration fixture now shares native case preparation, provider
encoding and admission reporting between historical cases and this pilot. Its
optional story input follows canonical provenance validation. No engine/provider
client, semantic judge or parallel repair mechanism was added.

## Offline verification

Run from repository root:

```sh
zig build test-specification-generation --summary all
zig build verify --summary all
```

Verified on 10 October 2026: **288/288** specification tests and **1,455/1,455**
tests across **142/142** full verification steps passed. All 31 pinned file hashes
were checked. These results establish offline mechanics only.

The fixture checks unchanged schemas/native assignments, selected story targets,
complete collections and the exact one-field presentation difference. Every
frozen edit/provider body must equal the current export. Expected mocked
responses admit with the expected native location; empty assessment collections
reject. All 12 planned result paths have separate `probe-native-*` reports under
`.zig-cache/source-loss-preservation/`. Probes are mechanics checks, never live
results or evidence of semantic correctness.

After each actual trial, place its extracted response at the manifest's
`response_file`, run the focused command, and retain its `native_report`. The same
production `Source.admitComparisons` owner evaluates either arm. Malformed or
incomplete responses remain failures; never replace them with probe responses.
If no final response exists, record native admission as not reached and keep the
trial in its denominator. Re-running offline admission sends no model request.

## Frozen execution procedure — executed; allowance consumed

Reuse the [existing debugger procedure](../../README.md#bounded-replay-procedure)
with this manifest, not the old campaign's consumed allowance:

1. Check all manifest hashes and the exact parent/model/controls. Copy the retained
   run's complete `project` into a fresh diagnostic workspace; never edit the
   parent. Build using `zig build`; start `zig-out/bin/sdde --debugger hello-world`
   from the copied project with the existing dedicated test credential adapter.
2. Read `/api/calls`; locate **RUN-a8204eab393239c09cb75264943ca0d0** and
   **request-16-inference-1**. The API array index is not the model call ordinal.
   The parent is the same for every trial.
3. Send the 12 manifest trials sequentially through the existing `/api/replay`
   modified-replay owner. Use its required token/Origin headers and JSON
   `{"call":<resolved index>,"mode":"modified","edit":<parsed trial edit>}`.
   Both baseline and candidate use this same one-send path. Do not use `e2e-call`
   to change content; it only rebinds model/effort.
4. Record the returned identity immediately, actual serialized request, provider
   response, stop, normalization, UTC time, provider/request IDs, actual token
   usage and latency. Confirm every actual request equals its frozen provider
   body. Run offline native admission, retaining both its result and raw exchange.
5. Stop after 12 physical sends, on any uncertain dispatch/unknown usage/hash or
   configuration drift, or after cumulative actual input+output usage reaches
   100,000 tokens. That usage stop is checked after an exchange and can be crossed
   by the last in-flight response; it is not a runtime reservation/output limit.
   No dollar cap is asserted. Failed sends consume trials; never resend to fill
   the denominator. Restarting does not renew approval.

Controls are Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, low reasoning,
temperature 0, native schema and 16,384 output allowance. Seed and top-p are absent,
not assumed fixed. No corrections, retries, repairs, model judges or E2E runs are
included. The optional nine-call effort comparison is not prepared or authorized.

## Assessment and exit

Fill a copy of [scorecard.template.json](scorecard.template.json), retaining the
original. Mask arm names where practical; record the assessor and any failure to
blind. Judge semantic correctness and explanation adequacy separately from native
admission. Cite response excerpts, original requirements and comparison members;
valid IDs are not proof of entailment.

Candidate must achieve **6/6** complete, schema-valid, natively admitted, correctly
attributed responses with adequate explanations, including both genuine role-loss
trials. False upstream/candidate attribution must be zero. Compare unnecessary
uncertainty, latency, total usage and request size separately. Meaning must be
preserved regardless of whether a literal is embedded in a behavioral claim.

Promotion additionally requires strictly more correct trials than concurrent
baseline and no paired-case regression. A perfect tie is inconclusive for
superiority. Failure stops production promotion; a further experiment requires a
new bounded plan/approval. Even success is a small development pilot, not Phase 3
qualification, E2E publication or rubric acceptance.
