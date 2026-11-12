# Z_SPEC01 — Implemented SPEC01 items

Implemented SPEC01 items ([convention](README.md)): what each changed, its owner, its keep
decision and any rule a later change must follow. Measurements, run-by-run evidence and
earlier versions of these records are in git history. Earlier completed SPEC01 work (Q1, Q2,
Q3, Q4's first attempt, Q6, D7.1, D11.1/.2/.4/.5, DE6, T1, T5's measures) is
`fixes/Z_FIX06.md` at git `194e29a`; Q10b D10.2, reverted in full with D13.1 (ADR 0023:25-28),
is there at git `388438e`.

## Q2b D2.3. Dispositions complete at response admission (ADR 0046)

**Committed in `194e29a`; kept 1 November 2026** (user: "apply best recommendations"). ADR 0046
records the decision and mechanism: admission rejects a dispositions answer that omits or
repeats an assigned claim (`missing_member`, `duplicate_member`) under the request's retry
limit; the request the model receives is unchanged. Defect class: lost source requirement
(hello-world's UTC claim, lost when the dispositions insert repair answered `duplicate`).
Evidence: `evaluations/d23-12/measures-set.json` (12 of 12 published; the correction never
fired, so "not enough evidence"). Open follow-ups: SPEC01 Q2b.

## Q13 D13.1. Post-generation reviews removed

**Committed in `2b3dc8b`** (user, 1 November 2026: "apply best recommendations"). The
decision and what it removed are ADR 0023's removal amendment (0023:25-42).

## Q7 D7.4. No engine code span where the text already delimits an exact value

**Committed in `340261e`** (user, 1 November 2026: "implement Q7 D7.4."; ADR 0036 records the
authority); the user's ruling that D7.4 is not a punctuation rule stays in SPEC01 Q7.
`delimitedByText` (`specification_projection.zig`) gives an exact copy no code span when only
literal text touches it and that text is directly one balanced pair from the closed wrapper
table (`exact_value_boundary.zig`), unless the copy ends in terminal punctuation; passive values
keep their span (ADR 0036 Decision 6; 23-rendering.md §23.1). No request carries the
projection's spans. Every development-case value ends in punctuation, so no artefact-A
occurrence changes (SPEC01 Q7); no scripted scenario quotes an exact copy (SPEC01 T3).

## Q7 D7.2. ADR 0045 withdrawn

**Docs only, 3 November 2026** (user: "apply recommendations"; ADR 0036 records it): ADR 0036
Decision 6 stays; ADR 0045, accepted but on hold and never implemented, is withdrawn and its
file deleted (git `388438e` keeps it).

## Q13. Inline source lines

**Committed in `6e543e6`** with the D12.1 + D16.2 change set (Q13 changes no request). User
decisions, 1 November 2026: "the claims associate with the AC, FR and EN should be placed after
each AC, FR and EN"; file and lines only, one line per item, with the source file and merged
line ranges computed from the item's claims and their citations; several files join with "; ".
- **Change:** each AC, FR and EN record in `spec.md` shows those lines (23-rendering.md §23.1,
  F0100 §5.6). The live projection and the reference-context snapshot share one trace
  (`traceRequirements`, `specification_projection.zig`); `source_coordinates.lines` turns a
  citation span into its lines, and `specification_markdown.zig` renders and parses the line.
  An AC or FR line follows a blank line, because a two-space line directly under a field
  continues that field.
- The lines reduce no scored defect class; they make each record's links visible to the human
  reviewer (SPEC01 H1). Proof limit: SPEC01 T3.

## Q12 D12.1. Records requests receive no unpublished drafts

**Committed in `6e543e6`; kept with D16.2 on 2 November 2026** as part of the D12.1 + Q16
change set (user: "keep D12.1 + D16.2"; not kept alone, user: "the above recommendations are
approved"). Only the entities unit receives an earlier draft (the brief); records authoring and
repair packets receive neither the brief nor the entity decision (`specification_session.zig`;
17-specify.md §17.3). Effect: FR equal to an unpublished draft fell from 9 of 18 publications
to 0 of 15 (p = 0.004); alone, it raised unsupported addition and restatement
(`evaluations/d121-measures-set.json`).

## Q12 D12.2. Generated fields take obligation strength from one owner

**Committed in `388438e`; kept 3 November 2026** (user: "apply recommendations") under
AGENTS.md's one owner per instruction, although its Keep if wasn't met as written.
`generation.context.json`'s `business_value`, bound to every generation and specification-unit
repair request, owns "preserve source-backed conditions, obligations and obligation strength.";
the record purposes and `records.prompt.md` carry no copy. Story weakening fell 8 of 15 → 1 of
9 (p = 0.093); the story's remaining modes motivated ADR 0047.

## Q16 D16.1 and D16.2. Requirements own their claims (with D12.1)

**Committed with D16.2 in `6e543e6`; kept 2 November 2026** (user: "keep D12.1 + D16.2"),
D16.2 amending D16.1 after its set failed the publication guard (SPEC01 §2 rule 1's recorded
exception). ADR 0038 (Decisions 2, 3 and 5) and ADR 0035 record the rule: requirements own
their claims; a partly taken statement is `shared_member`, a wholly taken one a native
`repeated_statement` delete; FR, BR, UO and PB need a scenario. Versions:
`model-request-debug/v16`, `spec-e2e-report/v14`, `baseline-acquisition/v11`. Evidence:
`evaluations/q16-measures-set.json`, `evaluations/d162-measures-set.json` (Keep if not met:
restatement 4 → 3, "not enough evidence"). The native delete first fired on 3 November; the
report lists only some deletes (SPEC01 T8).

## Q19 D19.2. The engine composes the story (ADR 0047)

**Committed in `f6ef0f6`; kept 7 November 2026** with D12.3 (SPEC01 §2 rule 3's recorded
exception): no story defect in the 12 adjudicated runs since, against 7 in the D12.2 reference's
9 publications. ADR 0047 records the decision and mechanism (`compose-specification-story`,
`src/domain/specification_story.zig`; no story model call; `no_story_requirements` and
`story_not_admissible` block). The story prompt, the generation schema's story variant, the
`authoring-guidance` corpus and the old authoring-associations `scorecard.json` are deleted
(user: "YES"). Motivation: before ADR 0047, 26 of 30 weakenings since 29 October were in the
story.

## Q12 D12.3. The story leaves pre-generation source review

**Implemented 7 November 2026** (user: "apply recommendations", then "yes, advance both"; ADR
0047 Decision 5); kept with ADR 0047 (SPEC01 §2 rule 3). Not yet exercised live: no run since
ADR 0047 has reached source review. `specification_authority.projectRecords` no longer seeds the
story; the story's required-authority policy, slot, clarification question and packet-guidance
purpose are deleted. Defect: `2026-11-02T09-15-31Z` ended `workflow_invalid` when readiness
filed the story purpose as a `candidate_omission`. **Q12 closed 7 November 2026.** Not
recommended: a typed obligation-strength field (07-domain-representations.md:158 forbids a
duplicate modality field; making it matter needs a word check or engine-rendered modal text).

## Q8 D8.3. One piece of evidence is one claim

**Implemented 7 November 2026** (user: "i accept recommendation", then "implement D8.3",
accepting the preflight's resolutions a–f; then "fix the issues", making an insertion that adds
no claim an unchanged merge). The rule is ADR 0036 Decisions 3 and 4 (16-reference-ingestion.md
§16.3; the 13-03 action text). Owner: `reference_extraction_text.appendDistinct`, used by
extraction text validation and `reference_extraction_repair.Omission.merge`; the merge reports
`changed = false` when its insertion adds no claim. Defect: `2026-11-07T06-11-33Z-6897…`'s five
identical extraction claims, which the story repeated five times. Every offline request is
byte-identical, so the proof is the accepted and rejected owner tests.

## Bare-value `reference_only` correction

**Implemented 7 November 2026** (user: "fix the bare-message failure"); **kept 12 November
2026** (user: "yes", to recording it kept). No set could measure it: it has fired once live,
changing nothing, so the keep rests on the mechanism. Native recognition makes text that is exactly a source value one
exact-value node, so a prose-required field holding only it rejects as `reference_only` (ADR
0036:156-158). The field registry's explanation (`text_field_policy.referenceOnly`) is derived
from the exact-copy role: where recognition runs it says an exact source value or supplied
display reference may appear within the prose but cannot be the whole text; elsewhere it names
only the reference (text-field-composition.md amended). No new reason, `Issue` member or report
version; correction text only (D4.1 extension). The sent correction bytes are pinned only at the
owner, since no scenario reaches this correction.

## E10. Alias, string kind, dead code, principles section, stale comments and start rule

**Implemented 8 November 2026** (user: "implement E10", "remove dead code", "apply best
recommendation", "implement then"). No published-output defect class (contract violations in
the closed decoders, dead code and stale text). No request, report member or state change
beyond those named.
- **Alias:** `parseOutcome` (`validate_workflow_definition_schema.zig`) matches a closed
  spelling table, so `needs_user` and `end.needs_user` reject as
  `WorkflowDefinitionSchemaInvalid`; fixtures author `needs-user`. `end.more` is rejected by the
  compiler, which `smoke.zig` pins (14-orchestration.md:100).
- **String kind:** a `[]const u8` member never decodes from an array of byte values. The engine
  decoders use `strict_json`: `decodeAuthored` for a document a user writes (a member with a
  default may be omitted, a present member keeps its wire kind, a defaulted optional is absent
  or a value and never `null`) in `engine_config_decode.zig`; `decode`, which requires every
  member, for `llm_provider_document_decode.zig` and the clarification-state parser. So
  `reasoningEffort` is a string when present and `null` rejects (F0001; ADR 0039:84-86 is the
  precedent). An architecture rule (`architecture_test.zig`) forbids a typed `std.json` decode
  in the action, adapter, application and composition layers. The harness and build tools that
  read their own reports were not swept.
- **Dead code:** the principle-citation validator and the principle registry's selection and
  guidance functions, with their tests. 22-repair.md:417-419 still describes principle citation
  diagnostics (SPEC01 §8 "Design–code conflicts").
- **Principles section removed** (user: "if it unused and brings no value then remove it"): the
  `principles` configuration section, `principle_policy.zig` and the category fields;
  `specification-state` moved to v22, and a `principles` member rejects as unknown. Amended:
  ADRs 0015, 0023 and 0041, 09-configuration.md §9.4, F0001, the schema, the example config and
  the dependent contracts. **Consequence:** the tools that decode a retained run's copied config
  with the closed decoder (`e2e-measures`, `e2e-call` and the baseline tools) no longer read
  runs whose configs carry the section; their evaluations and measures under `evaluations/`
  stay. `adjudicate-spec` decodes no config.
- **Text:** stale comments and the `/evaluate-e2e` start rule in `cli.zig`, `report.zig` and
  `acceptance.zig` match AGENTS.md "Testing expectations"; "The harness makes no judge call." is
  pinned and kept.

## Repeated statement text is not judged

**Implemented 8 November 2026** (user: "yes as per recommendation"); offline only, no request,
report or state version. Defect class: run completion (a loan-renewal run exhausting the
records retry limit on `reference_only` for a bare outcome that repeated another record's
value). `statement_ownership.zig` is the one rule for which statement a batch deletes; payload
admission (`shared_member`), the session's delete, the records validator (`inspectRecords`,
`repeated_statement`) and the composition check use it. A record whose value can't be
identified is never deleted and holds no value for another; requirements, the only holder of an
exact value, and partly taken, untaken or unnamed records stay judged. ADR 0038 Decision 5 and
its consequences, ADR 0035 item 5, text-field-composition.md, 22-repair.md,
12-model-boundary.md, 17-specify.md and F0100 record it. Proof: accepted and rejected cases at
the rule, admission, composition check, validator, replay and a scripted run, and a parity test
that every exemption at the wire is a validator delete.

## H1. Adjudication and `spec-e2e-report/v15`

- **Adjudicated 3 November 2026** (user-triggered `/evaluate-e2e`, skill `af394020…`): the D12.2
  set's publications and the first six ADR 0047 runs (`evaluations/e2e/<run>/`,
  `evaluations/adjudications/`). One applied decision is open (SPEC01 §7 H1).
- **v15, implemented 7 November 2026** (user: "implement items 1 and 2"): `spec-e2e-report/v15`
  and `baseline-acquisition/v12` carry ADR 0047's source-catalogue reasons and `issue`, the
  publication reason `adjudication_required`, and an admission audit that accepts no story
  subject. Retained v12–v14 runs stay readable only by the build that made them. The
  supplied-spec evaluator's decision (`evaluation-report/v8`) and the baseline's
  useful-completion state (`baseline-score/v4`) keep their own `human_adjudication_required`.

## T7. One evaluator version per comparison

**Rule:** a keep or revert is decided only on a reference scored in the same evaluator version
(SPEC01 §2 rule 5). Skills `af394020…`, `0b552067…`, `1d66d882…`, `3c74781e…` and `185b9bc6…`
count as one evaluator:
- `0b552067…` and `1d66d882…` changed no scoring rule (user, 7 November 2026: "approved"; 8
  November 2026: "recommendations accepted for 1 to 6", which also treats the one divergence,
  a missing refusal scenario scored in `728d…` but not `fa03…`, as evaluator variance);
- `3c74781e…` added the title ruling (SPEC01 §7 H1), a new scoring rule; the reference was
  re-scored under it on 9 November 2026 (SPEC01 §3 Next item 3), and no title in it drops a
  value;
- `185b9bc6…` (user, 9 November 2026: "Once, same evaluator, no re-score") files a defect in an
  edge case's linked Then once, on the criterion (ADR 0038 Decision 7); no reference run has an
  outcome link.

**Readings made rules, 3 November 2026** (user: "YES"; in SKILL.md §2): a link defect costs
nothing beyond its content defect; a repeat that gives a requirement's value states it, one that
gives none is a summary; a weaker restatement in a checkable outcome also costs
`clarity-testability`; several minor additions stay minor; repeating the source's own wording,
or an outcome without its verb, isn't weakening. `e2e-assistant-evaluation/v4` records
`skill_sha256` and gives each defect a `basis` (`link` or `content`).

## T3. A duplicate record is deleted in the scripted matrix

**Implemented 8 November 2026** (user: "implement then"); test-only. The scripted records fault
`.duplicate_record` (`spec_generation_driver.zig`) repeats the first functional requirement
exactly; the run publishes with no correction, and no batch keeps two records of equal content
(`workflow_tests.zig`, beside D16.2's `shared_statement` scenario). Open parts: SPEC01 T3.

## T5. Brittleness counts

**Committed in `93476e7`.** `zig build code-heuristics -- --freeze <dir>` writes them to the
`brittleness` member of `code-heuristics/v2` (`build/code_heuristics/brittleness.zig`). Latest
counts and when they are due: SPEC01 T5.
- **Definitions** (approved 1 November 2026; exact matches only):
  - A is every `.md` and JSON string value under `design/workflows/`, whitespace-collapsed.
  - M is production literals outside tests, of 3+ whitespace-separated runs, whose decoded
    bytes occur in a freeze's `guidance` content parts, `protocol_prompt` or `schema` (the
    schema's decoded strings included), and whose collapsed bytes A lacks.
  - Literal roles are syntactic: a direct argument of `eql`, `startsWith` or `endsWith`; a
    direct argument of `indexOf`, `lastIndexOf` or `indexOfPos`, which is an absence
    assertion when compared `== null`; or the `.bytes` value of a `DefinitionId`
    initializer. An initializer is a typed declaration, a `return` from a function
    returning `DefinitionId`, `DefinitionId.parse` or `DefinitionId{…}`, or an anonymous
    `.{ .bytes = … }` argument at a position where a function of that name takes a
    `DefinitionId`. A value chosen by a `switch` inside it counts as its value.
- **User decisions, 1 November 2026:**
  - The freeze is read strictly by `request_projection.Projection` and `Manifest`, without
    a version check, because the freeze has none.
  - M reads only `guidance` parts, as decoded values; `src/test_fixtures/` isn't
    production.
  - M takes T5.1's 3-run minimum. Without it, about 80 JSON-schema keywords count.
  - T5.1 counts an absence assertion only when A or M holds its literal.
  - T5.4 is counted by hand, because the compiled Spec graph needs the composition root's
    native assembly.
- **Limits:** a comparison through a helper isn't a direct operand
  (`reference_reconciliation_stage.zig:87` compares `definition(stage)`). A name routed
  through a local before `.{ .bytes = name }` isn't counted
  (`reference_reconciliation_repair.zig:324-327`, `specification_repair.zig:267-269`).
  Argument positions match functions by name only. Short absence literals match A by
  substring (`"id"`, `"$defs"`). The "native code" diagnostic texts reach requests only in
  `user` parts, so they aren't in M.

## T6. Structural counts in the measures

**Committed in `f6ef0f6`** (SPEC01 §2 rule 4, H6.1; widened 3 November 2026, user: "Yes, count
them"). `measures.structure` (`test/harness/e2e/measures.zig`) reads each response through the
production envelope parser and counts records by kind, the entities `disposition` and entity
count, a `claims` response's claims by `category` or `no_feature_claim`, and every
`{"fragments":[...]}` object, with those inserting no reference apart; wire names come from
their owning types, and an unknown kind or category counts apart. Run measures keep every call
(`e2e-measures/v2`); the set summary (`e2e-measures-set/v2`) pools each request's last attempt;
`e2e-call` trials record the same structure (`call-diagnostic-report/v3`). Baseline:
`evaluations/t6-baseline/`.

## E6. Producerless rejection reported as a harness error

**Committed in `dac4c4c`.** A `no_feature_claim` chunk that a source-omission repair turned into
a claim had, by rule, no `preserve` classification origin, which the shared `attribution()`
mapped to `missing_response` (`harness_error` `MissingProviderEvidence`). The validator names
the rule (`producerless`, missing entries only) and `attribution()` gives `candidate`
(contract 27); a lost origin on a duplicate, unknown or forbidden entry still rejects. Open
parts: SPEC01 E6.

## E6. Lock failures report their own code

**Implemented 8 November 2026** (user: "recommendations accepted for 1 to 6"). No
published-output defect class (a wrong failure code in the feature log); no request, report or
state change. `acquire_feature_log_stream_lock.zig` fails with `LogLockTimeout` only for
`LockUnavailable` and with `LogSinkFailure` for every other sink error (an exhaustive switch in
`Action.execute`), and its `failureCode` gives each one's log code, `LOG_LOCK_TIMEOUT` or
`LOG_SINK_FAILURE` (F0002:545, :556-557); the feature log runner and the retention runner call
it. The cancellation half stays in SPEC01 E6.

## Next 6. An entity is a name and its groups (ADR 0038 Decision 6)

**Implemented 8 November 2026** (user: "Entity lever … is yes and approved", then "yes to all
decisions"); **kept 9 November 2026**, with Next 8, on the HEAD set (user: "approved" to the keep
rule). Defect class: entity-field defects, a meaning or relationship that restated a requirement
and lost, weakened or added to it (5 in the 6 reference runs). ADR 0038 Decision 6 records the
mechanism and versions; the engine renders the statements that share a group (§23.1).
- **Keep rule** (9 November 2026): lost requirements per loan-renewal publication no higher than
  the reference's 3 over 3 publications, and all six runs publish.
- **Result** (HEAD set, SPEC01 §1): loan-renewal lost 0, all six runs published and passed,
  entity-field defects 0; thirteen native repeated-statement deletes, all graded helpful. The
  no-data entity in hello-world (`invented_or_restating_entity`, a minor scope defect the lever
  doesn't target) was in 2 of 3.

## Next 7. The renderer escapes only the bytes Markdown reads as markup

**Implemented 8 November 2026; kept 9 November 2026** (user: "apply recommendations"). Defect
class: `rendering_artefact`, a backslash before ordinary punctuation (`renewed\.`,
`Hello\, World\!`). The owner is `literal`/`escape` in `src/domain/specification_markdown.zig`
(:370, :375) and §23.1's closed table. No request changes. Kept on guards and mechanism, like a
hygiene phase (SPEC01 §2 rule 6): the artefact was in all 6 reference runs and none of the 12
later runs (p = 0.062, under the evidence floor); the change is deterministic.

## Next 8. An edge case's outcome is the Then of a linked criterion (ADR 0038 Decision 7)

**Implemented 8 November 2026** (user: "go", after "apply recommendations" and "recommendations
accepted for 1 to 6"); **kept 9 November 2026** with Next 6 on the HEAD set: loan-renewal lost
requirements 0 against 3 in the reference, 3 of 3 pass. Defect class: `lost_source_requirement`
and `weakened_obligation` in an edge case's free-text outcome. ADR 0038 Decision 7 records the
design, candidate rule and versions. Owners: `scenario_link.zig` (candidates, links,
stored-link check), `scenario_link_request.zig` (the closed request and its admission), the
`link-scenarios` subgraph of `spec.workflow.yaml` (on `links.prompt.md` and
`links.schema.json`) and `assemble`, which resolves the links. Its limit is open in SPEC01 §3
Next item 8; E11 removed its identity prediction.

## E14. Forced irrelevance for every extractor

**Implemented 9 November 2026** (user: "implement 1. E14", then "go"). Defect class: successful
completion, and unsupported exact values. The extraction schema's `irrelevant` variant admitted
only `markdown_inline_code_v1`, so a `no_feature_claim` chunk holding a fenced-code or
link-destination candidate failed its run when `construct-forced-token-classifications`
retained its forced classifications (`InvalidAssembledCandidate`), and a model answering
`claims` could only preserve such a candidate. Owner: `extraction.schema.json`, whose one
`$defs/extractor_id` now serves both `token_candidate_id` and the flat `irrelevant` variant
(F0100 §3.8's shape; ADR 0006 allows no `$ref` siblings). Test: `reference_extraction_test.zig`
"irrelevant classifications satisfy the extraction schema for every registered extractor"
(three unrelated-domain sources covering the extractor registry, the forced wire and a `claims`
answer through the real composition, an unknown extractor rejected, and ADR 0024's rule that a
wholly quoted value of any extractor cannot be irrelevant); it fails on the old schema. It
changes model input only by the `irrelevant` variant's extractor list (108 of the scripted
matrix's 1,656 requests). **Kept 10 November 2026** (user: "keep E14") on its set
`2026-11-09T19-51-5*`: 6 of 6 published and passed, no lost source requirement, no token
classified `irrelevant`; its target can't occur in the development cases (benefit not
demonstrated).

## E11. One owner for record identity

**Implemented 10 November 2026** (user: "implement E11, and yes delete recordIndex and
associated test"). Defect class: a latent wrong edge-case outcome. `assemble` predicted each
linked record's ID from its records-unit position (`positionId`) while `assign` allocated IDs in
its own merged order, and neither `assign` nor readback could tell a wrong candidate from the
right one. Now `specification_identity.assign` takes each link as indexes into the records it
receives, checks it with `scenario_link.candidate` (the rule readback uses) and stores the IDs it
allocates; `assemble` carries each records-unit record's position through its merge and sort.
`positionId`, `outcomeIds` and `recordIndex` (no production caller) are deleted, with
17-specify.md §17.3 and F0100 §5.7 amended to say repair targets records by candidate index.
Test: `specification_generation_test.zig` "record assignment resolves edge-case links to the IDs
it allocates and refuses any other link" (room booking, an advanced prior ledger, two batches;
a missing, duplicate, out-of-range, non-edge-case and cross-batch link each rejected), and the
two-batch `assemble` test rejects a link past the records unit and a cross-batch one. Requests
and published bytes are unchanged. Live runs (user-approved, 10 November 2026):
`2026-11-09T20-29-51Z` hello-world and `20-29-52Z` loan-renewal published and passed
adjudication (92.86% each; accuracy 0/0/0/0 and 0/0/1/0, the known AC-001 recording clause);
loan-renewal's EC-001 linked natively to AC-001, its sole candidate.

## C1. An empty exact-member answer is corrected, not a crash (ADR 0046)

**Implemented 11 November 2026** (user: "implement C1"). Defect class: successful completion.
`validateValue` (`model_payload_schema.zig`) began its repeat scan with `for (1..count)`, which
panics on an empty array, so an array with a member set and no `minItems` aborted the process
before its missing-member check. Every answer bound by `withDispositionChoices` reached it
(native member count; `semantic_dispositions` states no minimum): the dispositions request,
its repairs and the source-omission conflict-group repair (`reference_reconciliation_repair.zig`
`:334`, `:753`; ADR 0046 Decision 3), and a replay of any of them (`request_replay.zig:211`). A
model answer `{"claim_dispositions":[],"conflict_groups":[]}` would have ended the run with a
panic. The scan now starts at index 0, so an empty array is rejected as `missing_member` at the
array, naming the first assigned member (ADR 0046:54-56), and takes the bounded correction
(:58-60). Owner: `model_payload_schema.zig`. Tests, both of which crashed on the old code: in
`model_payload_schema_test.zig`, a generic schema without `minItems` rejects `[]` and a
one-item omission as `missing_member` naming member 2, with their corrections, and admits the
complete set; in `reference_model_input_test.zig`, the dispositions restriction on the real
reconciliation schema rejects the empty answer in both fixture domains, naming the first
semantic claim. No request builder changes; the only new model input is ADR 0046's existing
correction, sent where an empty answer used to abort. §2 rule 10's request-projection diff
wasn't taken. No schema, report or log version changes, and no keep decision is needed.
**Rule:** a member or coverage check must handle an empty array.

## Q22. Engine-derived title (ADR 0048)

**Implemented 11 November 2026** (user: option B1 "approved", then "yes level-1 headings block
run"); **kept 11 November 2026** (user: "yes mark Q22 as kept"). Defect class: lost source
requirement and restatement through the model-written title (4 of 54 loan-renewal and 21 of 55
hello-world evaluations since 2 November). ADR 0048 records the decisions, derived choices and
versions. Owners: `markdown_code_spans.levelOneHeading` (heading classification),
`specification_title.zig` (derivation and the readback check) and
`specification_session.initialize`, which takes the title or blocks with `no_title_heading` or
`conflicting_title_headings`. No screen ran (user: "yes as per recommendation"): every retained
capture was `model-request-debug/v16`, which the build refuses.
- **Set** (`2026-11-11T10-14-3*`; revision `35e7937`, `build.source.modified` true, one source
  `e8a54c98…`; 3 runs per case, none retried; skill `3fe52a92…`): 6 of 6 published and passed.
  Content-basis counts, lost / weakened / unsupported / contradiction: hello-world 0 / 0 / 0 / 0
  and loan-renewal 0 / 0 / 3 / 0, all three AC-001's recording clause from a records request that
  hashes as before Q22. All six H1s are the sources' headings, the nine native deletes were all
  helpful, and title restatement fell to 0 of 3 hello-world (reference 3 of 3). The target was
  0 in both states ("benefit not demonstrated"), so the keep rests on the mechanism and the
  guards. Measures: `evaluations/q22-measures-set.json`.
- **Evaluator version:** the reference counts (SPEC01 §1) were scored under `185b9bc6…`, which
  T7 doesn't count with `3fe52a92…`, and weren't re-scored first (SPEC01 §2 rule 5). A re-score
  can't reverse the keep: the set has no lost, weakened or contradiction defect; each of its
  three additions is an AC-001 Then byte-identical to one in the reference, which the skill
  scores the same; and on the target the set holds 0.

## Q14 b3. A scenario gap takes an engine-bound criterion insert (ADR 0038 Decision 3)

**Implemented 12 November 2026** (user: "B3 is approved, implement"); **kept 12 November
2026** (user: "keep B3"). Defect class: lost source requirement, a behaviour claim no scenario
tests, reached when the whole-response correction answered a scenario gap by adding the
claim to an unrelated criterion or exhausted the records retries (SPEC01 Q14). ADR 0038
Decision 3 records the decision, its derived choices and the versions.
- **Owners:** `specification_session.scenarioCoverageIssue` (after the duplicate,
  restatement and repeated-statement checks, on the batch their deletes leave);
  `specification_candidate.GroupPolicy.scenario`, a fixed record beside entity membership;
  and `specification_repair` (authorize, packet with the `provenance` context and the
  claim's exact values, parse, merge, retry validation). Admission keeps only
  `shared_member`: the result-schema rule records the exclusive and owning kinds, and the
  `uncovered_member` reason and its correction are gone. `model-request-debug/v18`,
  `spec-e2e-report/v17`.
- **Tests:** in `specification_generation_test.zig`, the session reports the uncovered claim
  after the native delete, needs none for a scope-only claim, authorizes the insert at the end
  of the batch with the claim and group fixed, selects the criterion definition, refuses an
  edge case or other claims, validates the merged batch and refuses the stale rejection; six
  claims of one requirement take six inserts within the bound frozen at the first, which
  `targetBound` sizes with a criterion per claim a statement names (contract review, 12
  November 2026); the
  admission, result-schema and replay tests admit an uncovered response; the scripted matrix
  publishes uncovered batches, one or every, and a re-sent runaway, each with its inserts and
  no correction. Request projection `q22-final` to `q14b3-after`: 1,450 of 1,633 requests
  unchanged, 179 records requests differ only in their recorded rule, and the 4 changed
  requests of the three uncovered scenarios became repair-slot inserts (one call added).
- **Set** (`2026-11-11T20-47-36Z` to `-41Z`; revision `666e0c30`, `build.source.modified` true;
  3 runs per case, none retried; skill `3fe52a92…`, the Q22 evaluator; reference the Q22 set):
  6 of 6 published and passed, 9 calls each, no correction, re-send, runaway or admission
  rejection. Content-basis counts, lost / weakened / unsupported / contradiction: hello-world
  0 / 0 / 0 / 0 and loan-renewal 0 / 0 / 3 / 0 (AC-001's recording clause), the Q22 set's
  counts; `-38Z`, `-39Z` and `-40Z` publish records byte-identical to a Q22 run. The 10 native
  deletes of the loan-renewal runs were all helpful. No `scenario_coverage` event fired, so no
  insert ran live; the target was 0 in both states ("benefit not demonstrated"), so the keep
  rests on the mechanism, the offline tests and the guards (lost source requirement 0 in both
  cases, publication 3 of 3 each, exhausted 0). Median tokens 12,712 and 16,342 against the Q22
  set's 12,796 and 16,290. Measures: `evaluations/q14b3-measures-set.json`.
- **Not covered by a test or a live run:** replacing an inserted criterion, and exhaustion of
  the insert's repair bound.
- **Rule:** an inserted record's association is the engine's; the model writes content only.

## E2. `prepare-toolchain` is one stage action (ADR 0031)

**Implemented 12 November 2026** (user: "yes" confirming DE2, then "approved" to the preflight,
including the ADR 0031 status edit). The first stage conversion, as the proof of the pattern. No
behaviour, model request, report, log or state version changes, so no published-output defect
class is named and no semantic benefit is claimed (ADR 0031:250-252); no live run (choice 7).
- **Owners:** `src/actions/toolchain/prepare_toolchain.zig` (the closed `Step` enum, the
  `Diagnostic` slot, `Action.execute` sequencing nine `steps.*` functions with a `NodeRuntime`
  check between them, and one `NodeContract`: requires nothing, produces `valid_toolchain`,
  `filesystem_read`); one binding, `toolchain_workflow_runner.PrepareToolchain`; the composition
  root's one registry entry. A step that reaches a port takes only that port; `validateSafety`
  alone yields the `safety.Owner`, allocated from the retained allocator while every
  intermediate lives in the binding's scratch arena. The failure representation of each step is
  unchanged (`InvalidToolchain`), except that the parser must now return exactly one document per
  capture: a short or long result rejects at `parse_documents`, where it used to shrink the
  registry silently and an empty one failed as `OperationExecutionFailed` (user: "yes", 12
  November 2026, contract review).
- **Runner:** `StepInput.runtime` carries the runner's `NodeRuntime` (always active for a
  binding invoked outside the runner), and a non-model operation that fails after the runtime
  stopped reports that stop (`cancelled`, `deadline_exhausted`), as the checks before and after
  the invocation do, so a cancelled stage reports what the nine separate nodes did. An
  allocation failure stays itself and a model call keeps its own reconciled status (contract
  review, 12 November 2026).
- **Removed:** the nine actions, nine bindings, eight stage-internal `DataKey`s and their
  schemas, the Specify subgraph, and the fixture's eight extra steps.
- **Failing step in the event** (ADR 0031:200-201; user: "yes", 12 November 2026): the runner
  lends each step invocation a slot (`StepInput.stage_step`, `pipeline.StageStepSlot`), the
  binding writes the failing step's name before returning its unchanged error, and the failed
  action's event records it as `step_id`, a new optional field of `action.failed` only (the
  registry rejects it elsewhere). The event heading gains a column, so **`event-columns/v2`
  becomes `event-columns/v3`** (38 columns, `step_id` after `rule_id`; F0002, 26-security,
  design.md updated; no migration, as F0002 requires). The measures harness reads the current
  heading only, so a feature log written before this change is rejected by it; the saved
  `measures.json` of earlier runs are unaffected. The prompt stream is unchanged
  (`prompt-columns/v3`).
- **Stale pointers** to ADR 0031 as not yet implemented in design.md, ADR 0003, ADR 0005 and ADR
  0016 now name `prepare-toolchain` as the first stage action (user: "yes").
- **Evidence (offline):** request projection before and after across the integration matrix is
  byte-identical (`diff -rq` empty; both equal `q14b3-after`), 122 of 122 integration
  scenarios pass, and the unit suite covers each function with fake ports, the stage edge (every
  failing step reported, cancellation between each pair of steps, allocation failure in each
  step and in the owner, cleanup) and the architecture rules with rejected fixtures.
- **Live set** (user: "perform 3 e2e live runs and evaluations per test case"; run directories
  `2026-11-12T00-18-16Z` to `-20Z`; revision `be2966ce`, `build.source.modified` true; 3 runs per
  case; skill `3fe52a92…`; reference the b3 and Q22 sets): not required by choice 7, taken after
  the event-field change. Two earlier launch rounds produced no result (a launch without the
  environment loader, then a provider `AccessDeniedException`, "Authentication failed: Please
  make sure your API Key is valid.", on a first request byte-identical to a working run's), so
  their directories are unusable evidence. 6 of 6 published and passed, 9 calls each, no correction, re-send, runaway
  or admission rejection. Content-basis counts, lost / weakened / unsupported / contradiction:
  hello-world 0 / 0 / 0 / 0 and loan-renewal 0 / 0 / 2 / 0 (AC-001's recording clause in two of
  three runs; the third has none), against 0 / 0 / 0 / 0 and 0 / 0 / 3 / 0 before. Hello-world:
  each run has an entity (3 of 3, against 1 of 3 in both earlier sets), costing one scope point,
  and the quote-mark artefact is absent (organization 4). The 17 native deletes of the
  loan-renewal runs (7, 7, 6) were all helpful, including an assumption, a non-goal and a
  prohibited behavior the source does not state. No `scenario_coverage` event fired, so no insert
  ran live. Median tokens 12,768 and 16,500 against the b3 set's 12,712 and 16,342. The new
  `event-columns/v3` logs were written and read by the measures harness; no run failed an
  action, so no `step_id` was recorded live.
- **Measures (ADR 0031:355-357), before then after:**

  | Measure | Before | After |
  | --- | --- | --- |
  | Toolchain YAML in `spec.workflow.yaml` | 30-line subgraph, 9 steps (file 1,104 lines) | 1 step (file 1,074 lines) |
  | Toolchain fixture | 17 lines, 9 steps | 9 lines, 1 step |
  | Registry entries (`entry(` lines) | 166 | 158 |
  | `DataKey` members | 194 | 186 |
  | Toolchain action files | 9 (107 lines) | 1 (130 lines), beside `compile_naming_policy` |
  | Binding and values files | 136 and 19 lines | 35 and 10 lines |
  | Files a new pure toolchain step touches | 8 (action, binding, values, `DataKey`, composition, YAML, fixture, 13-01) | 2 code files (the stage and its test) and the 13-01 entry |
- **Rule:** the internal steps of a stage are functions, so a project cannot recompose them and
  a concept change lands in the stage's file.

## E2b. `prepare-inputs` is the second stage action (ADR 0031)

**Implemented 12 November 2026** (user: "yes" to starting it, after the preflight). The 13-step
`inputs` subgraph of the Specify workflow is one stage action. No behaviour, model request, report,
log or state version changes, so no published-output defect class is named and no semantic benefit
is claimed; offline evidence stands in for a live run (choice 7), and the E2c live set ran this
stage too. **Kept 12 November 2026** (user: "Keeping the changes"). The ADR 0031 status line and
the design pointers name it the
second stage action (user: "yes", 12 November 2026).
- **Owners:** `src/actions/specify/prepare_inputs.zig` (the closed 13-member `Step` enum, the
  `Diagnostic` slot, `Action.execute` sequencing 13 `steps.*` functions with a `NodeRuntime`
  check between them; requires `specify_invocation`, produces the eight edge keys,
  `filesystem_read`); one binding, `input_preparation_workflow.PrepareInputs`; the composition
  root's one registry entry. Each port step takes only its own port, and its port aliases are
  named `*_port` so the architecture rule sees them. The prior specification state and the bytes
  it was parsed from use the retained allocator and the binding's owner; every other value is
  allocated in scratch space and copied into the delta.
- **Removed:** the 13 actions, their 13 bindings and `reference_workflow_runner.zig`, six
  stage-internal `DataKey`s, the 13-step subgraph, and the `feature-input-preflight` fixture (the
  `reference-preflight` fixture is now the single stage step). The failure representation of each
  step is unchanged.
- **Test wiring:** hand-built assemblies in the integration tests now bind the workflow-state
  reader on the stage, as the composition root does.
- **Evidence (offline):** request projection across the integration matrix is byte-identical to
  `q14b3-after` (`diff -rq` empty); 122 of 122 integration scenarios; the unit suite adds nine
  stage-edge and binding tests (every failing step named, cancellation between each pair, allocation
  failure in scratch and retained space, exact produced keys, slot behaviour) and the architecture
  suite four rules with rejected fixtures; `zig build verify` passes (169 of 169 steps, 2,041
  tests).
- **Measures, before then after:**

  | Measure | Before | After |
  | --- | --- | --- |
  | Input-preparation YAML in `spec.workflow.yaml` | 42-line subgraph, 13 steps (file 1,074 lines) | 1 step (file 1,032 lines) |
  | Registry entries (`entry(` lines) | 158 | 148 |
  | `DataKey` members | 186 | 180 |
  | Input-preparation action files | 13 | 1 |
  | Fixtures | `feature-input-preflight` plus the preflight steps in two others | one step in `reference-preflight`, one in `reference-ingestion` |

## E2c. `prepare-reference-evidence` and `prepare-reference-tokens` are the third and fourth stage actions (ADR 0031)

**Implemented 12 November 2026** (user: "apply best recommendations" to the open decisions for
the 15-step `prepare-references` subgraph). Both answers were my recommendation: `compile-naming-policy`
stays a separate step, and identity assignment keeps one port of its own. The first makes the
subgraph two stages with the naming step between them, since the grammar step needs its output.
No behaviour, model request, report, log or state version changes, so no published-output defect
class is named and no semantic benefit is claimed; offline evidence stands in for a live run
(choice 7), and a live set was taken anyway (below). **Kept 12 November 2026** (user: "Keeping the
changes", covering this entry and E2b). The ADR 0031 status
line, its one-port rule and the design pointers name all four stage actions (user: "action the
best practice recommendations", 12 November 2026).
- **Owners:**
  - `src/actions/reference/prepare_reference_evidence.zig`: eight steps (inventory, validate
    inventory, capture, decode, validate accounting, assign identities, build chunks, validate
    chunks); requires `reference_directory` and `feature_directory`, produces
    `citable_reference_inputs`, `filesystem_read`.
  - `src/actions/reference/prepare_reference_tokens.zig`: six steps (build grammar, scan
    literals, assign literals, validate literals, extract facts, assign candidates); requires
    `compiled_naming_policy`, `valid_toolchain` and `citable_reference_inputs`, produces
    `path_token_grammar`, `reference_passive_literals` and `structured_token_candidates`, `none`.
  - Two bindings (`reference_evidence_preparation_workflow`, `reference_token_preparation_workflow`)
    and two registry entries. Each stage has a closed `Step` enum, a `Diagnostic` slot and a
    `NodeRuntime` check between steps.
- **Port rule:** the user's earlier "yes" (12 November 2026) counts the Unicode text services
  (normalizer, case folder, lexical classifier), all types of one port module, as one port family.
  The architecture rule counts every `*_port` type in a step's parameters as one port, except that
  the text services' alias (`text_port`) counts once in all; no other module is exempt, with
  rejected fixtures for two types of `corpus_port`, `source_port` and `parser_port`. The `execute`
  rule now rejects the whole words `Input` and `StepInput` (so `operations.Input` is caught and the
  token stage's `evidence.Inputs` is not). The identity source stays one port in
  `assignIdentities`, the only step that draws entropy.
- **Removed:** the 14 actions, their bindings and schemas (`reference_ingestion_workflow.zig`
  whole, and the stage-internal parts of the evidence, path-token, passive-literal and
  structured-token binding files), ten stage-internal `DataKey`s, the 48-line subgraph, and the
  two redundant composed test fixtures (`reference_text_workflow.zig`,
  `reference_tokens_workflow.zig`): the stage always produces what each of them ended at, so the
  one `prepared` composition serves all callers. The failure representation of each step is
  unchanged. `compile-naming-policy` runs as its own step in the Specify graph instead of inside
  the subgraph.
- **Tests:** the per-step tests in the ingestion, evidence, path-token, typed-text and
  structured-token test files call the step functions. The compiler test for reference ingestion
  drops the mid-chain `core.noop` substitutions, which tested a chain that no longer exists, and
  keeps the capability, parameter and dataflow rejections against the stage.
- **Evidence (offline):** request projection across the integration matrix is byte-identical to
  `q14b3-after` (`diff -rq` empty); 122 of 122 integration scenarios; a new test file covers each
  stage edge with fake ports (each reachable failing step named, cancellation between each pair,
  allocation failure in scratch space, the exact produced keys, slot behaviour); the chunk
  validation and the literal and token steps can fail at the edge only by allocation, since their
  derived inputs cannot be forged there, and their rejections stay tested as functions.
  `zig build verify` passes (169 of 169 steps, 2,059 tests).
- **Live set** (user: "run 3 e2e run per test case, once done perform an evaluation on each"; run
  directories `2026-11-12T03-04-19Z` to `-23Z`; revision `a120c188`, `build.source.modified` true;
  3 runs per case; skill `3fe52a92…`; compared with the E2 set): not required by choice 7, taken
  because the preparation stages run against real adapters and the `compile-naming-policy` step
  now precedes feature-log activation. In all six runs `references`, `naming` and `tokens`
  completed `ok`, in that order, before any model call. 5 of 6 published and passed adjudication;
  the sixth, loan-renewal, ended `workflow_failed` (`RetryLimitExhausted` at the scenario-link
  choice request `g26-g14-g4-link-choose-request-account`, after three answers with reasoning and
  no text; a model limitation in the generation phase, long after the stages, so counted as an
  attempted workload and not repaired). Content-basis counts, lost / weakened / unsupported /
  contradiction: hello-world 0 / 0 / 0 / 0 in 3 of 3 runs and loan-renewal 0 / 0 / 0 / 0 and
  0 / 0 / 1 / 0 (AC-001's recording clause, one of two published runs), against 0 / 0 / 0 / 0 and
  0 / 0 / 2 / 0 in the E2 set. Aggregates 96.43% for four runs and 100% for one. Hello-world: one
  of three runs added an entity (3 of 3 in the E2 set) and two of three show the quote-mark
  artefact (none in the E2 set), each costing one point. One hello-world run took one protocol
  correction (10 calls); every other published run took 9 calls and none a re-send or runaway.
  Median tokens 12,783 for hello-world and 16,206 and 16,477 for the two published loan-renewal
  runs (the failed run used 17,916), against 12,768 and 16,500 in the E2 set. Every native delete
  in the published runs (one each) was helpful. Evaluations: `evaluations/e2e/<run>/`.
- **Measures, before then after:**

  | Measure | Before | After |
  | --- | --- | --- |
  | Reference preparation YAML in `spec.workflow.yaml` | 48-line subgraph, 15 steps (file 1,032 lines) | 3 steps in the main graph (file 994 lines) |
  | Registry entries (`entry(` lines) | 148 | 136 |
  | `DataKey` members | 180 | 170 |
  | Reference preparation action files | 14 | 2 |
  | Composed test fixtures | 3 variants plus the ingestion fixture | one `prepared` composition plus the ingestion fixture |
- **Rule:** the Unicode text services are one port family for ADR 0031's one-port rule; any other
  step that mixes two port modules is rejected.

## E3. Startup and provider bootstrap are ADR 0032 engine routines

**Implemented 12 November 2026** (user: "apply recommendations and implement", after DE3). One
change covers all three sequences: provider-config, provider bootstrap after selection, and startup
before selection. No behaviour changes: public error codes, the cancel-versus-fail mapping, the
services built, the absence of a lock, and nothing registered or selectable are as before. No
published-output defect class is named and no semantic benefit is claimed; offline evidence
stands in for a live run (DE3), and no live set was taken. **Not yet kept.** ADR 0032's status
is "partly implemented" and the design pointers say so; feature logging stays unconverted.
- **Owners:**
  - `src/application/startup_routine.zig`: 29 steps in a closed `Step` enum, a routine-owned
    `Diagnostic` slot, a `Ports` set no step receives, `code(step)` for the public code of each
    step, and a `NodeRuntime` check before the first step and after each. Its steps take one port
    each (`config_locator`, `root_inspector`, the workflow `Enumerator` and `Capturer`, the
    definition `Parser`, the result-schema `Compiler`); the path limits and the registered
    operation contracts are values. `validateWorkflowInventory` returns `ValidatedInventory` and
    `validateWorkflowOperations` returns `ValidatedOperations`, which the later steps require.
    The composition root builds the ports and the services from the routine's validated owners
    (`runInProjectWithRegistry`); the `Outcome` type lives in `bootstrap_services.zig`.
  - `src/application/model_provider_bootstrap_routine.zig`: 7 steps, one port (the provider
    document locator); `not_required` makes no port call. Reached through the runner-owned
    `model_provider_bootstrap_binding.zig`.
  - Moved logic, with its tests: `engine_config_decode`, `bootstrap_root_derivation`,
    `workflow_authority_inventory_build`, `workflow_resource_binding`,
    `workflow_definition_schema`, `workflow_graph_compilation`, `workflow_graph_validation`,
    `llm_provider_document_decode`, `llm_provider_registry_build` and
    `provider_requirement_derivation` (all `src/domain/`).
- **Removed:** 14 sequencing files (the startup orchestrator, runners, execution state and child
  bindings; the provider-config and provider-bootstrap orchestrators, runners, child bindings
  and service), 29 startup and provider actions, 27 `DataKey`s (5 provider, 22 startup; 142
  remain), and the 11 spy-child tests. `validate-workflow-operation-registry` stays: the workflow
  selection runner still uses it.
- **Rules:** the architecture test enforces ADR 0032:291-303 for the two routines: imports only
  `std`, domain and port modules, no `std.Io`, no `anyopaque`, an entry that only passes port
  fields on, no step that takes the port set, two ports or an erased parameter, and only
  `src/composition/`, tests and the provider-bootstrap binding (for its own routine) import a
  routine, with startup importing no log, lock or transaction module; every `*_routine.zig`
  under `src/application/` is discovered and held to the routine rules; each rule has rejected
  fixtures.
- **Tests:** `src/startup_routine_test.zig` runs the routine against fake ports: port order, each
  reachable failing step with its code and step, cancellation from a port, cancellation and
  deadline at every check (one more check than there are steps), an allocation-failure sweep
  that must leak nothing and report a step whose code matches, the distinct validated types, and
  the moved step tests. `bootstrap_root_registry_test.zig` carries the registry validator's tests.
- **Evidence (offline):** request projection across the integration matrix is byte-identical to
  `q14b3-after` (`diff -rq` empty); integration scenarios pass; `zig build verify` passes (169 of
  169 steps, 2,060 tests); lint and the architecture tests pass.
- **Measures, before then after:**

  | Measure | Before | After |
  | --- | --- | --- |
  | Sequencing files and lines (startup and provider sequences) | 14 files, 2,157 lines | 2 routine files, 810 lines (594 and 216) |
  | `anyopaque` lines in the converted sequences | 130 | 2 (the provider-bootstrap binding's; none in either routine; 105 in all of `src/application/`) |
  | Startup `DataKey`s | 42 | 15 |
  | Spy-child tests | 11 | 0 |
  | Files to add one startup step | an action, its runner field and invoke function, a vtable slot, the orchestrator call, the dispatcher function, a spy-table entry, composition wiring | the routine (enum member, step, entry call, `code` arm) and its test; composition only for a new port |

  The routine files do not hold the moved logic: the domain modules above total about 2,400
  lines, so total lines fall less than the sequencing lines do. The last row is read from the
  structure, not measured by a counted change.
- **Open:** feature logging (ADR 0032:152-172); the remaining `anyopaque` lines are the
  feature-logging, workflow-engine, workflow-pipeline and Specify-invocation bindings.
