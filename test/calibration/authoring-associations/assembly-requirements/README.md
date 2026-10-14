# Assembly requirements and ownership comparisons

This records-only diagnostic contains two adjacent single-factor comparisons,
sharing their middle arm instead of sending it twice:

| Arm | Assembled required families | Shared source guidance |
| --- | --- | --- |
| `baseline` | Previous AC/FR presentation | Exact frozen previous guidance |
| `family` | Current AC/FR plus conditional entity | Exact frozen previous guidance |
| `ownership` | Current AC/FR plus conditional entity | Current clarified assigned-versus-context guidance |

`baseline` versus `family` isolates conditional entity presentation. `family`
versus `ownership` isolates ownership guidance. All arms retain the same
production packet, selected schema, complete sources, whole assigned source
group, business context, exact literal catalogue and current native admission.
The baseline is a diagnostic projection removing only `entity` from
`record_requirements.required_families`. `old-generation.context.json` is the
exact pre-change static guidance retained as an experimental control; only its
`sources` string differs from production. Neither historical control is a
production path, alternative validator, runtime fallback or compatibility reader.
The scope remains `assembled_specification` in every arm.

Five cases comprise three retained development cases and two unrelated controls:

| Case | Collection | Required families |
| --- | --- | --- |
| Captured startup display | Business group plus its separately retained literal occurrence | AC and FR; entities unnecessary |
| Equipment inspection | Two business groups with separate storage and failed-inspection duties | AC, FR and entity |
| Loan renewal | One business group, with a genuinely undecided renewal duration | AC, FR and entity if completed; faithful narrow uncertainty remains separate |
| Warehouse location | One unrelated business group requiring parcel identifiers and associated storage locations | AC, FR and entity |
| Completion notification | One unrelated behavior-only group | AC and FR; entities unnecessary |

The three retained cases are selected by ID from the unchanged parent
`cases.json`; their sources, claims and MOCK context seeds are not duplicated.
The two new controls are declared in this directory's closed `cases.json`.
Business context is controlled MOCK brief/entity output, not a live upstream
handoff. All five cases are development evidence, not held-out qualification.

Each arm runs twice per case: **30 logical collection trials and 42 physical
sends**. Every current native group is sent, including the optional startup
literal-only batch. An empty individual batch remains permitted. AC, FR and
conditional entity floors apply only to the complete assembled specification;
do not require every batch to contain every family, skip a group to meet the
call bound, or fill actual omissions with MOCK seeds.

Pinned settings match the preceding authoring panel: AWS Bedrock
`openai.gpt-oss-20b-1:0` in `ap-southeast-2`, low reasoning, temperature **0.1**,
native schema and a **16,384** output allowance. Seed and top-p remain absent.
Stop before another send when measured input-plus-output usage reaches
**200,000** tokens. No retries, corrections, repairs, model judges, live review
calls, workflow continuation or E2E invocations are included. Unknown dispatch
state stops the experiment without a resend. Preparation grants no dispatch
authority; obtain explicit bounded approval of these 42 new calls, AWS
destination and frozen payloads under §28.8.

The existing fixture prepares this panel through the same production session,
provider encoder and actual receipt reader as the parent authoring panel:

```sh
zig build test-specification-generation --summary all -j2
```

Its owning regression proves that baseline/family differ only by the conditional
family entry and that no-entity controls are byte-identical in that pair. It also
proves family/ownership have identical packet and schema bytes and differ only
by the `sources` string in the static guidance; all other guidance is unchanged.
Generated packets,
complete debugger edits, provider bodies, ancestry preflight and preparation
manifest are beneath `.zig-cache/authoring-associations/v14-text/assembly-requirements/`.
Freeze those bytes after offline verification; dependency changes require a new
preparation and approval. Do not edit a generated packet. Interpret the two
adjacent comparisons separately; baseline/ownership changes two factors and
cannot identify which caused an observed difference.

Use the existing authenticated native `/api/replay` modified-request route and
the authentic parent retained by the manifest. See the parent README for the
canonical run/receipt contract, hash and ancestry checks and zero-send native
preflight. This panel uses the same closed contracts in its own generated
directory: `live-run.json`, `<trial-id>.records-<group-id>.receipt.json` and
`admission.json`. Retain complete authentic request/response records and measured
cost/timing; diagnostic replay IDs never become workflow origins or publication
authority. Native admission uses the current contract for **all** arms, while
the reader verifies each arm's exact frozen model-facing presentation.

Score separately for every repetition and complete actual collection:

1. Completion, response/schema admission and native aggregate assembly. Keep
   malformed, truncated, rejected, empty and not-sent batches in the denominator.
2. Required-family presence across the collection: AC and FR plus meaningful
   entity records when required. Report the family floor separately from the
   entity record's adequacy and source ownership.
3. Assigned obligation preservation, including triggers, conditions, negation,
   relationships and strength. Assess the full collection jointly and each
   record's field purpose independently. IDs and valid JSON are not entailment.
4. Group ownership: record unsupported or wrongly attributed obligations
   separately from legitimate contextual explanation. The full source context
   remains visible. Token-only scope and other ambiguous ownership judgments
   must be marked uncertain, not silently treated as proof or resolved by
   forbidding context in this experiment.
5. Unsupported additions, genuine-gap fidelity and exact literal occurrences
   where actually used. A correct narrow renewal question is distinct from
   completed record content; inventing a duration or asking for supplied facts
   fails the uncertainty criterion.
6. Actual sends, input/output tokens, provider stop reasons and timing, including
   every rejected response. Unknown usage remains unknown, never zero.

The family candidate must eliminate required-family omissions in both repetitions of
each completed required-entity case without losing source meaning, admitting
unsupported additions or inventing entities in no-entity controls. Every
completed collection must pass current native admission and meet its purposes.
The ownership candidate must preserve meaningful assigned obligations without
substituting another group's duty, losing legitimate supporting context,
inventing decisions or forcing token-only batches empty. Keep ambiguous
token-only ownership separate from proven substitution failures. No semantic
validator or admission permission changes in this comparison.

Report paired observations and every remaining failed gate separately for each
factor, not only a summed success percentage. Reuse actual `family` observations
for both comparisons; no additional middle-arm sends are included. This small
controlled panel cannot establish universal
semantic correctness, actual upstream handoff reliability or E2E publication
and rubric quality. Preserve the scored preceding panel unchanged.
