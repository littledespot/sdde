# Z_FIX06 — Implemented FIX06 items

Implemented FIX06 items ([convention](README.md)): what each changed, its owner, its keep
decision and any rule a later change must follow. Measurements, run-by-run evidence and
earlier versions of these records are in git history. Earlier completed FIX06 work (Q1, Q2,
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
fired, so "not enough evidence"). Open follow-ups: FIX06 Q2b.

## Q4 D4.1. `uncovered_member` correction names the covering kinds

**Kept 30 October 2026.** The correction names the covering kinds from the compiled coverage
rule, never hard-coded (`model_schema_diagnostic.zig`, `model_protocol_retry.zig`);
`required_preserve` unchanged. Evidence `evaluations/e2e/d41-measures-set.json` (correction
never fired). Its live firings are in FIX06 Q14; the extension decided 3 November 2026 is open
in FIX06 Q4.

## Q13 D13.1. Post-generation reviews removed

**Committed in `2b3dc8b`** (user, 1 November 2026: "apply best recommendations"). The
decision and what it removed are ADR 0023's removal amendment (0023:25-42).

## Q7 D7.4. No engine code span where the text already delimits an exact value

**Committed in `340261e`** (user, 1 November 2026: "implement Q7 D7.4."; ADR 0036 records the
authority); the user's ruling that D7.4 is not a punctuation rule stays in FIX06 Q7.
`delimitedByText` (`specification_projection.zig`) gives an exact copy no code span when only
literal text touches it and that text is directly one balanced pair from the closed wrapper
table (`exact_value_boundary.zig`), unless the copy ends in terminal punctuation; passive values
keep their span (ADR 0036 Decision 6; 23-rendering.md §23.1). No request carries the
projection's spans. Every development-case value ends in punctuation, so no artefact-A
occurrence changes (FIX06 Q7); no scripted scenario quotes an exact copy (FIX06 T3).

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
  reviewer (FIX06 H1). Proof limit: FIX06 T3.

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
D16.2 amending D16.1 after its set failed the publication guard (FIX06 §2 rule 1's recorded
exception). ADR 0038 (Decisions 2, 3 and 5) and ADR 0035 record the rule: requirements own
their claims; a partly taken statement is `shared_member`, a wholly taken one a native
`repeated_statement` delete; FR, BR, UO and PB need a scenario. Versions:
`model-request-debug/v16`, `spec-e2e-report/v14`, `baseline-acquisition/v11`. Evidence:
`evaluations/q16-measures-set.json`, `evaluations/d162-measures-set.json` (Keep if not met:
restatement 4 → 3, "not enough evidence"). The native delete first fired on 3 November; the
report lists only some deletes (FIX06 T8).

## Q19 D19.2. The engine composes the story (ADR 0047)

**Committed in `f6ef0f6`; kept 7 November 2026** with D12.3 (FIX06 §2 rule 3's recorded
exception): no story defect in the 12 adjudicated runs since, against 7 in the D12.2 reference's
9 publications. ADR 0047 records the decision and mechanism (`compose-specification-story`,
`src/domain/specification_story.zig`; no story model call; `no_story_requirements` and
`story_not_admissible` block). The story prompt, the generation schema's story variant, the
`authoring-guidance` corpus and the old authoring-associations `scorecard.json` are deleted
(user: "YES"). Motivation: before ADR 0047, 26 of 30 weakenings since 29 October were in the
story.

## Q12 D12.3. The story leaves pre-generation source review

**Implemented 7 November 2026** (user: "apply recommendations", then "yes, advance both"; ADR
0047 Decision 5); kept with ADR 0047 (FIX06 §2 rule 3). Not yet exercised live: no run since
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

**Implemented 7 November 2026** (user: "fix the bare-message failure"); kept or reverted per
FIX06 §3 Next item 1. Native recognition makes text that is exactly a source value one
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
  or a value and never `null`) in `decode_sddtoolkit_config.zig`; `decode`, which requires every
  member, for `decode_llm_provider_config.zig` and the clarification-state parser. So
  `reasoningEffort` is a string when present and `null` rejects (F0001; ADR 0039:84-86 is the
  precedent). An architecture rule (`architecture_test.zig`) forbids a typed `std.json` decode
  in the action, adapter, application and composition layers. The harness and build tools that
  read their own reports were not swept.
- **Dead code:** the principle-citation validator and the principle registry's selection and
  guidance functions, with their tests. 22-repair.md:417-419 still describes principle citation
  diagnostics (FIX06 §8 "Design–code conflicts").
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
  `evaluations/adjudications/`). One applied decision is open (FIX06 §7 H1).
- **v15, implemented 7 November 2026** (user: "implement items 1 and 2"): `spec-e2e-report/v15`
  and `baseline-acquisition/v12` carry ADR 0047's source-catalogue reasons and `issue`, the
  publication reason `adjudication_required`, and an admission audit that accepts no story
  subject. Retained v12–v14 runs stay readable only by the build that made them. The
  supplied-spec evaluator's decision (`evaluation-report/v8`) and the baseline's
  useful-completion state (`baseline-score/v4`) keep their own `human_adjudication_required`.

## T7. One evaluator version per comparison

**Rule:** a keep or revert is decided only on a reference scored in the same evaluator version
(FIX06 §2 rule 5). Skills `af394020…`, `0b552067…`, `1d66d882…`, `3c74781e…` and `185b9bc6…`
count as one evaluator:
- `0b552067…` and `1d66d882…` changed no scoring rule (user, 7 November 2026: "approved"; 8
  November 2026: "recommendations accepted for 1 to 6", which also treats the one divergence,
  a missing refusal scenario scored in `728d…` but not `fa03…`, as evaluator variance);
- `3c74781e…` added the title ruling (FIX06 §7 H1), a new scoring rule; the reference was
  re-scored under it on 9 November 2026 (FIX06 §3 Next item 3), and no title in it drops a
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
(`workflow_tests.zig`, beside D16.2's `shared_statement` scenario). Open parts: FIX06 T3.

## T5. Brittleness counts

**Committed in `93476e7`.** `zig build code-heuristics -- --freeze <dir>` writes them to the
`brittleness` member of `code-heuristics/v2` (`build/code_heuristics/brittleness.zig`). Latest
counts and when they are due: FIX06 T5.
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

**Committed in `f6ef0f6`** (FIX06 §2 rule 4, H6.1; widened 3 November 2026, user: "Yes, count
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
parts: FIX06 E6.

## E6. Lock failures report their own code

**Implemented 8 November 2026** (user: "recommendations accepted for 1 to 6"). No
published-output defect class (a wrong failure code in the feature log); no request, report or
state change. `acquire_feature_log_stream_lock.zig` fails with `LogLockTimeout` only for
`LockUnavailable` and with `LogSinkFailure` for every other sink error (an exhaustive switch in
`Action.execute`), and its `failureCode` gives each one's log code, `LOG_LOCK_TIMEOUT` or
`LOG_SINK_FAILURE` (F0002:545, :556-557); the feature log runner and the retention runner call
it. The cancellation half stays in FIX06 E6.

## Next 6. An entity is a name and its groups (ADR 0038 Decision 6)

**Implemented 8 November 2026** (user: "Entity lever … is yes and approved", then "yes to all
decisions"); **kept 9 November 2026**, with Next 8, on the HEAD set (user: "approved" to the keep
rule). Defect class: entity-field defects, a meaning or relationship that restated a requirement
and lost, weakened or added to it (5 in the 6 reference runs). ADR 0038 Decision 6 records the
mechanism and versions; the engine renders the statements that share a group (§23.1).
- **Keep rule** (9 November 2026): lost requirements per loan-renewal publication no higher than
  the reference's 3 over 3 publications, and all six runs publish.
- **Result** (HEAD set, FIX06 §1): loan-renewal lost 0, all six runs published and passed,
  entity-field defects 0; thirteen native repeated-statement deletes, all graded helpful. The
  no-data entity in hello-world (`invented_or_restating_entity`, a minor scope defect the lever
  doesn't target) was in 2 of 3.

## Next 7. The renderer escapes only the bytes Markdown reads as markup

**Implemented 8 November 2026; kept 9 November 2026** (user: "apply recommendations"). Defect
class: `rendering_artefact`, a backslash before ordinary punctuation (`renewed\.`,
`Hello\, World\!`). The owner is `literal`/`escape` in `src/domain/specification_markdown.zig`
(:370, :375) and §23.1's closed table. No request changes. Kept on guards and mechanism, like a
hygiene phase (FIX06 §2 rule 6): the artefact was in all 6 reference runs and none of the 12
later runs (p = 0.062, under the evidence floor); the change is deterministic.

## Next 8. An edge case's outcome is the Then of a linked criterion (ADR 0038 Decision 7)

**Implemented 8 November 2026** (user: "go", after "apply recommendations" and "recommendations
accepted for 1 to 6"); **kept 9 November 2026** with Next 6 on the HEAD set: loan-renewal lost
requirements 0 against 3 in the reference, 3 of 3 pass. Defect class: `lost_source_requirement`
and `weakened_obligation` in an edge case's free-text outcome. ADR 0038 Decision 7 records the
design, candidate rule and versions. Owners: `scenario_link.zig` (candidates, links,
stored-link check), `scenario_link_request.zig` (the closed request and its admission), the
`link-scenarios` subgraph of `spec.workflow.yaml` (on `links.prompt.md` and
`links.schema.json`) and `assemble`, which resolves the links. Its limit is open in FIX06 §3
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
wholly quoted value of any extractor cannot be irrelevant); it fails on the old schema. Its live set and
keep decision are open in FIX06 E14.

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
