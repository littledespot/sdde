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
authority). Decided 1 November 2026: D7.4 is not a punctuation rule (AGENTS.md "Prose heuristic").
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

## Q13 D13.6. A non-existent integer ID is corrected with the rejected value and the allowed set

**Implemented 14 November 2026.** Decided 1 November 2026 (user: "the review repair should check that the
claim exists, if the claim supplied by the LLM does not exist then is should attempt to get the LLM to repair
with guidance on the error"); approved 12 November 2026 (user: "yes, update documentation, do not make any
code changes": 22-repair.md §22.6 amended); code go-ahead 14 November 2026 (user: "recommendation
accepted"). Implementation and mechanical checks only; semantic benefit not demonstrated (it has never fired
live, so no set can measure it). Defect class named: none scored (run completion).
- **Change:** an `enum_mismatch` on an integer enumeration (every claim, signal, line, group and link ID a
  model supplies) is corrected with guidance ending `"rejected":N,"allowed":[...]` beside the existing
  locator. A string enumeration and every other reason keep their correction, and the explanation text is
  unchanged. One `rejected` per correction, the first out-of-set value; `allowed` is the whole set, never
  truncated.
- **Owners and rule:** `Diagnostic.rejected` (`model_schema_diagnostic.zig`; part of `eql`, copied with the
  value) is captured at admission by `validateValue` (`model_payload_schema.zig`, the integer-enumeration
  arm). `allowedIntegers` (`model_schema_projection.zig`) returns the compiled node's own set, borrowed, in
  schema order, keyed on node kind and never on a field name or producer. `model_protocol_retry.build` emits
  both and refuses any other pairing (`ModelRequestAssociationInvalid`). A moved ID changes the diagnostic's
  identity, so it resets the repeated-correction notice (22-repair.md §22.6).
- **No persisted contract changes, no version:** reports copy only a diagnostic's reason and path, so the
  report, step event, baseline, call-diagnostic, provider-compatibility, request-debug, replay and
  prompt-column contracts and the event registry are unchanged, and the retained v19 runs stay readable. The
  request debugger records a correction as opaque content and needs nothing.
- **Request projection** (§2.10): `evaluations/request-projection/d136-before` (the e5-final tree's) and
  `d136-final`, 1,635 files each. The manifest and the 135 first requests are byte-identical. Eight
  corrections differ, exactly the scripted integer-choice corrections (scenario 058 calls 0009 and 0010, 061
  call 0004, 062/0006, 063/0007, 064/0007, 082/0008, 083/0008), each only by the appended `rejected` and
  `allowed` members; a read-only script checked each value and set against the request's own rejected
  response and schema. The step trace is identical to `e5-final`.
- **Tests:** `model_payload_schema_test.zig`: admission captures the integer a response gave (`3.0` and `-1e0`
  forms too) and only for an integer enumeration's mismatch; `eql` differs on it and `copy` keeps it; every
  correction is checked against the schema's own `enum` at its pointer and the response's own value, and the
  fields are absent for a string enumeration, a type mismatch, an integer range, an array length, an unknown
  variant and a duplicate or missing member; schemas with different sets give different lists; a retry that
  takes the first allowed value is admitted; the pairing guard. `checkCorrection` runs the real correction on
  a signal row, a citation-line row and the `claim_ids:[999]` row of the real generation schemas
  (`specification_generation_test.zig`) and admits a corrected body. The Spec driver asserts every scripted
  `enum_mismatch` correction, and the main integration matrix proves at least one ran (`choice_corrections`).

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
byte-identical, so the proof is the accepted and rejected owner tests. Semantic benefit is not demonstrated: no
live run since has duplicated an extraction claim.

## Bare-value `reference_only` correction

**Implemented 7 November 2026** (user: "fix the bare-message failure"); **kept 12 November
2026** (user: "yes", to recording it kept). No set could measure it: it has fired once live (8 November,
`2026-11-07T20-44-15Z-9273…`, uncommitted tree), changing nothing, since all three records attempts returned the
same bare outcomes and the run exhausted its retries, so the keep rests on the mechanism. Native recognition makes text that is exactly a source value one
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
  guidance functions, with their tests. 22-repair.md's principle-citation diagnostics sentence
  is removed (SPEC01 §8 "Design–code conflicts").
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

**Implemented 8 November 2026** (user: "yes as per recommendation"); **kept 14 November 2026**
(user: "the above recommendations are approved"); offline only, no request, report or state version. The
keep rests on the mechanism, the offline proof and the native deletes that ran in the HEAD set (thirteen), the
Q22 set (nine) and the Q14 b3 set (ten), all helpful, with no guard failing; the original failure hasn't
recurred, so a benefit on the target defect isn't demonstrated. Defect class: run completion (a loan-renewal run exhausting the
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

- **Decided 3 November 2026** (user: "yes", to "should the evaluator's rubric scores decide acceptance instead of
  your record?"): the `/evaluate-e2e` skill writes each published run's `spec-adjudication-record/v1` from its
  rubric scores and applies it with `zig build adjudicate-spec` (AGENTS.md "Testing expectations"; ADR 0034 and
  design/harness/acceptance.md amended). Only the user triggers or approves the skill (AGENTS.md states the
  rule).
- **Decided 3 November 2026** (user: "YES", "YES approved"): a run's first adjudication under a skill version
  counts (R8, design/harness/acceptance.md).
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
- `3c74781e…` added the title ruling (SPEC01 §7 H1; decided 8 November 2026, user: "recommendations
  accepted for 1 to 6"), a new scoring rule; the reference was re-scored under it on 9 November 2026
  (`evaluations/e2e/<run>/`), no title in it drops a value, and its re-score records stay unapplied
  (`adjudication-record.3c74781e-unapplied.json`, SPEC01 §2 rule 12);
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
counts: E5 below; when they are due: SPEC01 T5.
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
and `weakened_obligation` in an edge case's free-text outcome (EC-001's outcome dropped "calendar",
"existing" or the new due date, failing `successful-renewal` in 4 of the 6 loan-renewal runs before 8
November and 2 of the 3 that day). ADR 0038 Decision 7 records the
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
Decision 3 records the decision, its derived choices and the versions. **D14.1:** b3, not b2 (decided 1
November 2026); b2, that the scenarios naming a claim must together contain every exact value its quoted text
requires, misses claim 4 and business-rule-only cases. b3 was held until lost source requirement recurs
(re-decided 3 November 2026), a condition since met, and held again with b4 not started (8 November 2026);
it was released on 12 November 2026.
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

**Implemented 12 November 2026** (user: "yes" confirming DE2, ADR 0031's derived choices 1–3 and 6–8
(:268-290), then "approved" to the preflight, including the ADR 0031 status edit). The first stage conversion, as the proof of the pattern. No
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

**Implemented 12 November 2026** (user: "apply recommendations and implement", after DE3, which the
user confirmed with "yes" on 12 November 2026: ADR 0032's derived choices 1–8 (:231-248), including offline
evidence). One change covers all three sequences: provider-config, provider bootstrap after selection, and startup
before selection. No behaviour changes: public error codes, the cancel-versus-fail mapping, the
services built, the absence of a lock, and nothing registered or selectable are as before. No
published-output defect class is named and no semantic benefit is claimed; offline evidence
stands in for a live run (DE3), and no live set was taken. **Kept 14 November 2026** (user: "yes", to
keeping E3 for its reduced brittleness; no outcome improvement is claimed). ADR 0032's status
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

## E8. Spec request builders select result definitions through closed enums

**Implemented 12 November 2026** (user: "implement E8"); **kept 14 November 2026** (user: "yes", to keeping E8
for its reduced brittleness; no outcome improvement is claimed). No request, model-facing
text or behaviour changes, so no published-output defect class is named and no semantic benefit is
claimed; the request projection across the integration matrix is byte-identical to `q14b3-after`.
- **Owner:** `src/domain/specification_result_definitions.zig`: one closed enum per Spec schema
  resource (`Extraction`, `Reconciliation`, `Generation`, `Links`, `Support`), each with `id()`
  (the generic `DefinitionId`) and `parse()` (a request's selected definition back to its member).
  ADR 0013's selection clause records the rule.
- **Changed:** the 19 raw-string sites the code-heuristics report listed (the extraction and text
  repairs, the reconciliation assignments and repairs, the specification session, the support
  review and its repair, the record repair and the scenario link), the two computed names of C34
  (`@tagName(stage) ++ "_assignment"`, `"repair_{s}"`, now explicit switches that reject every
  kind without a definition) and a site the report had missed (`specification_support.zig:256`,
  found by the new architecture rule). The scripted fixtures (`spec_generation_driver.zig`,
  `spec_generation_responses.zig`, `source_loss_calibration.zig`) branch on `parse()` instead of
  string equality, so a renamed definition fails to compile instead of turning a check off (C41).
- **Rules:** an architecture test fails when production code under `src/domain`, `application`,
  `actions` or `composition` spells a definition by a string literal in a `DefinitionId` or
  `.definition` initializer, by a literal or computed positional argument to a packet constructor,
  by an enum tag or format (`.{ .bytes = @tagName(…)`, `_assignment"`, `"repair_{s}"`) or by a
  `definition` constant, with rejected fixtures for each shape; it reads text, so it guards those
  shapes and the enums are what make a rename a compile error. It also requires the generic schema,
  composition, packet, repair and handoff owners and the ports to import no Spec enum.
  `specification_result_definitions_test.zig` compiles each shipped schema with the production
  compiler and requires every enum member to be a selectable definition, no name shared by two
  enums, the `parse()` round trip and a rejected cross-schema member.
- **Review:** the contract-reviewer found no blocker. Its two major findings are fixed: a surviving
  computed name (`@tagName(input.purpose)` for a reconciliation base packet; the global purpose
  names no schema definition, so that packet now carries none) and a guard that caught one of four
  old patterns. Its minor findings are fixed too: one exhaustive content-to-definition function,
  a typed support-detail member instead of a string comparison, the doc wording, the cross-enum
  disjointness test and the generic-owner import check.
- **Measures:** raw-string schema-name branches in production 19 to 0 (tests 89 to 69; the rest are
  schema-file tests that take definition names as data).
- **Not done, decided 14 November 2026** (user: "recommendation accepted"): a generic compile-time rule, so E8
  is closed. The check stays at request preparation (ADR 0012:68, ADR 0013:81, 12-model-boundary.md), and ADR
  0013's shipped-schema test is the load-time check; a target project's own schema copy that lacks a member
  still fails at preparation, after earlier calls. If a rule is wanted later, declare the definitions on the
  packet-building operations, not as a list on the request step, which invariant 29 and the scalar-only
  parameter schema forbid.
- **Found, left:** `source_loss_calibration.zig:351` compares a request's definition with
  `assignment_findings`, which no schema declares, so its early return always runs and the code
  after it never does.

## E1. One engine-owned step per model request (ADR 0030)

**Implemented 13 November 2026** (user: "yes action Step 4", "finalise step 5 and implement step 6";
DE1, DE1b, DE1c, DE1d, DE1e). Every model request of the Spec workflow and the packaging fixture is
one `request-model` step; the stages are native bindings of that step's registry entry, no workflow can
select one, and the explicit lifecycle (26 registry entries, the wrapper subgraphs, the retirement
operations and the five detailed actions) is deleted. **Defect class named:** none. The change reduces
brittleness (a mis-wired lifecycle, which only a run failure revealed, cannot be authored) and claims no
semantic benefit; the request projection is byte-identical to the one taken before E1, so what each
request sends is unchanged. **Kept 13 November 2026** (user: "for outcomes have improve out brittleness
has been reduce E1 should be kept"): kept for the reduced brittleness; no outcome improvement is claimed
(see the live set below: no regression, no demonstrated benefit).
- **Live set, 13 November 2026** (DE1f: one set, three runs per development case; build `42fe246e`,
  modified, `spec-e2e-report/v18`): all six runs published and passed adjudication under their case
  rubrics. hello-world 96.43%, 92.86%, 96.43% (no accuracy defect; quote marks around a code span in all
  three, an entity on a no-data feature in one); loan-renewal 96.43%, 92.86%, 96.43% (accuracy defects: one
  minor `unsupported_addition` each in two runs: an overdue-style edge-case condition the source does not
  state, and "records the loan as renewed"). Every run made 9 sends with no correction, re-send or
  runaway; tokens 12,667 to 12,762 (hello-world) and 16,562 to 16,636 (loan-renewal), inside the ranges of
  the two earlier sets on the pre-E1 build (12.7k to 13.1k and 16.2k to 16.8k, apart from an invalid run
  and a 23k run). Each loan-renewal run had one helpful duplicate-delete repair. The earlier sets each had
  one non-passing loan-renewal run (20-10 invalid, 20-18 failed on two critical criteria), this set had
  none; with three runs per case that difference is inside run-to-run variation and E1 changes no request
  byte, so it is reported as no regression, not as a benefit. The model-output artifact was written for
  every call and the per-stage measures read correctly under the kernel. No run took a correction or a
  re-send, so the restored per-attempt rejection evidence is proved offline only. Evaluations:
  `evaluations/e2e/2026-11-13T08-05-*`; adjudications in `evaluations/adjudications/`.
- **Measures** (before, from the preflight and the retained 12 November run's installed YAML; after, the
  final tree):
  - Spec workflow YAML: 994 lines, 166 `use:` and 66 `call:` entries; the request lifecycle was six
    subgraphs (`model-request-body` and five wrappers) reached from 17 request sites. After: 883 lines,
    164 `use:` and 44 `call:` entries, one `request-model` step at each of the 17 sites, no request
    subgraph.
  - Registry: 30 entries (26 of them lifecycle operations) to 8 (ledger initialization, the four
    JSON-composition operations, `release-model-request`, `release-model-transport`, `request-model`);
    the 17 stages are held only by `request-model`.
  - Production code deleted: the actions `assign_model_request_id`, `validate_model_request_binding`,
    `build_model_request`, `decode_model_envelope`, `validate_model_payload_schema` and
    `retire_model_request`, `retire_model_input`, `retire_model_transport` (8 files); the wrappers
    `Assign`, `Validate`, `Build`, `Decode` and the payload `Validate`; the `request_decode` association
    variant; `validateRunawayRoutes` and its two calls; the `payload_schema_requires` branch of
    `workflow_model_invocation`; `selectionForPacket` and `publish` in `model_request_workflow.zig`; the
    wrapper-collapse code of `workflow_step_trace.zig` (the trace keys a step by its whole call path).
    `model_transport.Retirement` keeps `rejected_attempt` and the two releases.
    New: `model_request_stage`, `model_request_kernel` (domain), `model_request_orchestrator` and
    `model_request_child_bindings` (application): the orchestrator has no `anyopaque`, no count and no
    port.
  - Tests: `model_request_workflow_test.zig` 196 lifecycle tests to 177 kept (36 ported, 13 re-driven,
    128 unchanged on the stage seam) plus 32 `request-model` and extraction-evidence tests, 209 in all;
    `model_request_orchestrator_test.zig` 12 spy tests. The unit suite runs 1,975 tests on the final
    tree (1,996 before step 5: 10 deleted here, two step-trace tests and one architecture test merged
    or removed, one rejection test added; then nine YAML-shape tests deleted after the step 5 review).
- **Stage seam:** the test registries (`loadEntries`) bind each stage's own context as a selectable
  step, plus two test-owned releases (`test.release-seam-request`, `test.release-seam-transport`) that
  retire every request key a hand-composed chain of stages leaves current, as `retire-model-*` did. A
  production registry offers none of them, and `request-model: a workflow cannot select a request stage
  or an operation of the removed lifecycle` proves it for every stage ID and every removed ID.
- **Pins:** no runner text-order pin was removed: a stage runs through the same step body
  (`executeBound`) as any step, so each pin on it still holds and now covers every stage. The pins that
  named deleted code were replaced: the pure-action pins on `build_model_request`,
  `decode_model_envelope` and `validate_model_payload_schema` now pin the domain functions they wrapped
  (`preparation.build`, `envelope.decode`, `validation.validate`: signature, purity, forbidden
  imports); the identity-ledger pin counts `prepare_model_request` as the one assigning action; the
  decode-binding and payload-binding pins became one pin on the admission binding (and that no
  `Decode` or `Validate` binding exists); the assembly pin asserts `Initialize` and `Prepare` and that
  `Assign`, `Validate` and `Build` are absent. The orchestrator's own pin (`only follows stage
  outcomes, and only the runner runs a stage`) covers the stage order's owner.
- **Decisions** (user, on my recommendations; the ones still open are in SPEC01 E1):
  - **DE1, 12 November 2026** ("yes i accept", on the eight questions the preflight raised): ADR 0030's
    Acceptance list is the full contract; `input` carries over and E8's definition declaration is not added
    to the step; a `request-model` step counts once toward the 1,024-step limit and once toward the
    workflow's execution ceiling, its stages bounded by its own allowance of at most 2 × (1 + `retry-limit`)
    provider calls; ADR 0039's route rule (`validateRunawayRoutes`) is replaced by branch tests on the kernel
    orchestrator, and ADR 0005:80-82 and `06-pipeline-nodes.md:281-282` ("exactly one retry") are amended; the
    test port rule is the mapping below; the proof that gates landing is offline (the request-projection
    pair, the step-trace pair and named integration assertions) and one live set follows on the user's
    go-ahead; the report and step-event versions advance in the change with no compatibility reader
    (SPEC01 §2.12).
  - **DE1b, 13 November 2026** ("yes for all 3 decisions"): a runtime orchestrator with runner-owned child
    bindings and one runner invocation per stage (ADR 0030:136-160), not a compiled stage graph; the non-kept
    request keys are engine-internal in E1 and their removal from the `DataKey` enum is a follow-up (open,
    SPEC01 E1); steps 2 and 3 first, reported at the end of step 3.
  - **DE1c, 13 November 2026** ("yes, recommendations approved"): the three evidence keys the E2E harness
    reads after a step (`provider_authorization_result`, `model_envelope_result`,
    `provider_invocation_result`) are recorded-retention keys, read through history, and every stage event of
    a kernel step carries its stage name (`action_started`, `action_completed` and `action_invalid` gain the
    optional `step_id` of `action_failed`).
  - **DE1d** ("accept recommendation, and continue implementing") **and DE1e** ("delete the actions and
    cleanup the tests"), 13 November 2026: `release-model-request` and `release-model-transport` stay,
    `Retire` is unchanged and the `retire-model-*` operations go with the old lifecycle, no alias; the five
    detailed request actions no production code calls are deleted, and the test files that used them as
    fixtures are ported onto the stage seam or deleted with a stated reason.
  - **DE1f, 13 November 2026** ("all the decisions are approved"): `model_payload_schema_result` is a fourth
    recorded-retention key; DE1's data-key rule is amended to the implemented one, a kernel step keeps every
    kept key it had published on every outcome and drops the eight internal keys whatever the outcome (stated
    once in `model-request-operations.md`, "The `request-model` step's data contract"); the `action.started`,
    `action.completed` and `action.invalid` log templates are not bumped; one live set, three runs per case,
    after landing.
- **Owners and rules:**
  - `src/domain/model_request_stage.zig` fixes the 17 stages (ADR 0030's 13, with the runaway check, the
    correction, the re-send and the two pre-call terminations each a stage); `model_request_kernel.zig` holds
    the step's contract, the transition table (`next`) and the eight engine-internal keys;
    `model_request_orchestrator.zig` follows only stage outcomes; the runner owns each stage through
    `executeBound` and bounds attempt-accounting entries by 2 × (1 + `retry-limit`) (`KernelAdmission`, proved
    at its seam: no real stage sequence reaches it, since the retry authority and ADR 0039's single re-send
    stop first); `Entry.request_stages` marks the one kernel entry, and `Registry.validate` checks its contract
    against `model_request_kernel.zig`, its capabilities as the exact union of its stages' (`bindRequestKernel`
    derives them from the stage contexts' ports) and its parameters as the preparation stage's plus
    `retry-limit`; `release-model-request` and
    `release-model-transport` retire exactly `model_transport.released_keys`, the kernel's `produces`, stated
    once.
  - A consumer that finds a request's producer goes through `workflow_model.startsRequest` (an architecture
    pin); a kernel step cannot end a workflow with no consumer.
  - An observer reads the evidence keys and `model_payload_schema_result` from recorded history, not from the
    current keys: after a correction the evidence still current when a retry-limit rejection ends the step
    depends on where the request stopped. `Trace.recordStep` observes every attempt of a step before its last
    (`observation.attemptRejection`), so a request admitted after a correction or a re-send still reports its
    protocol rejection, provider stop and capture receipts.
  - Under a baseline experiment a runaway re-send is a harness stop: the frozen binding's temperature is not
    the re-send's (unchanged by E1).
  - A rejection of the step's own closing work names no stage, and no offline run can induce one (that work
    makes no allocation in the proof run). The debugger archive accepts a call's action when it equals its
    caller chain's last operation or, for a `request-model` caller, its inference stage
    (`kernel.callActionBelongsTo`, a reader rule, not a shape).
  - Scripted tests choose each answer in `FakeLLMProvider`'s `before_invoke` and `after_invoke` hooks, the
    seam a kernel step has in place of an `invoke-model` step boundary; the runner's optional
    `request_stage_gate` (consulted before each stage, no capability) stops the provider compatibility probe
    after its one exchange, and only `Trace` sets it.
  - The packaged smoke keeps two denial cases (an operation of the removed lifecycle, a stage id), each
    rejected as an unknown operation; the 13 that passed only because the id is unknown are deleted.
- **Versions (step 6, 13 November 2026; SPEC01 §2.12):** the 20-10 and 20-18 sets were adjudicated before
  this change (DE1 decision 8). Each candidate was judged from its actual writer, and a contract whose
  members and decode rules did not change was not bumped. Advanced, with no compatibility reader:
  `spec-e2e-report` v17 to v18 (`retry_error` is `Exhaustion.Description`, which gained `stage`),
  `e2e-step-event` v2 to v3 (it embeds the same `retry_error`) and `specification-state` v25 to v26 (the
  persisted extraction contract's `parts` are now the `request-model` steps that start each request, with
  that step's operation and parameters; a v25 state is rejected with `InvalidSpecificationState`; ADR 0041,
  on hold, names v26 for its own change and takes v27 when it resumes, SPEC01 E0). Judged unmoved:
  `model-request-debug/v18` and `model-call-evidence/v3` (neither record has a step-action or stage member;
  only the values of `request_step` follow compiled step ids, and Spec's did not change), `request-source/v1`
  (`caller` and `preparation` keep their fields; for a `request-model` step the two name the same step),
  `feature-log/v2` and `event-columns/v3` (no column changed), `baseline-acquisition/v12` (it embeds the
  report, so a retained acquisition holding a v17 report no longer decodes, as after every earlier bump) and
  `action.started/v1`, `action.completed/v1` and `action.invalid/v1` (not bumped, DE1f: the row has the
  `step_id` column, F0002 fixes `message_template_id` as `<event_type>/v1` for every row, and ADR 0031 added
  the same optional member to `action.failed` without a bump; a bump needs a per-event template version and
  an F0002 amendment). Spelling counts: the report version is named on 66 lines in 15 test files, so the bump
  edited all of them (SPEC01 C45 stays open); the other two are named in one writer each.
- **`anyopaque` in the E1 files:** 2 lines, both in `model_request_child_bindings.zig` (the runner-owned
  context and the stage invocation, the same boundary as the other child-binding vtables); none in the
  orchestrator, the kernel contract or the stage list.
- **Final proof (step 7, 13 November 2026).** `zig build verify` passes on the final tree (147 of 147 steps,
  2,100 tests, the unit suite 1,975), as do `test-build-registration` and `test-build-isolation`. The interim
  projection retakes `e1-step4` and `e1-step5` are deleted; `e1-before` and `e1-final` stay as the evidence of
  E1. Request projection: `evaluations/request-projection/e1-final`
  was written by a fresh `test-integration` run on the final tree, and `diff -rq` against `e1-before` is
  empty, so what each request sends is unchanged. Step trace: `evaluations/step-trace/e1-final` was frozen
  from the same run (135 scenarios) and compared with `e1-before` by script, every scenario and every file:
  - `.trace`: 135 of 135 differ only in request-lifecycle lines (a request's stage lines became one
    `request-model` line, `retain-json-part` its own step, `retire-model-*` became `release-model-*`), and
    in 21 of them the retry-exhaustion line gained `:stage=advance-attempt`; every other line, in the same
    order, is identical. No other difference.
  - Summary `.json`: 135 of 135 equal except `steps` (18,016 fewer in all), `trace_sha256` and `files`;
    in 21 the `rejection` text differs only by the `:stage=` suffix; the `files` list differs only in
    `state/workflow.json` in 100 and is identical in 35.
  - Published files: every file a summary lists is byte-identical except `state/workflow.json`, which
    persists the compiled steps, in 100 scenarios (the extraction contract, `specification-state` v26).
  - **Evidence defect in `e1-before`:** it holds four scenarios the current layout cannot produce
    (`reuse_regeneration-127` and `-128`, `source_preservation-126` and `-127`) and 26 `.files`
    directories (20 whole, 6 partly) that no summary lists. They are leftovers of an earlier run's
    numbering: the trace writer never deletes an earlier run's files, and the freeze copied the whole
    directory (the preflight's "402 files" counted them). They are older than the rest of the freeze and
    were left as taken; the 135 current scenarios are the comparison.

### Mapping of the 196 lifecycle tests (DE1 decision 6)

**Provenance.** The original file text is not retained (no version control is read), so the table is
reconstructed from the final file and the changes made while porting. The figures reconcile with the
preflight's: 196 original tests = 177 kept + 19 deleted (the 10 listed below and the 9 marked `deleted`
in the table), and 177 + 32 new = the 209 now in the file. **Dispositions:** *seam* = unchanged, one
stage or a chain of stages driven through the seam registry (a step list lost the removed `validate`
and `build` steps, or `decode`); *port* = the test body changed because the detailed variant it
compared or looped over is gone, an assertion was retargeted to the surviving owner, or its YAML
mutation loop was trimmed; *re-drive* = a cancellation boundary or a release step recomputed for the
shorter chain. The counts are 36 port, 13 re-drive and 128 seam. **YAML-shape class (DE1 decision 6):**
the 20 tests marked `YAML-shape class` in the Note column are the ones whose subject was YAML shape
through the stage seam: parameter, dependency, outcome-mapping or policy mutations of one stage's
declaration, or a forged compiled step. (An earlier reading counted 27; the count could not be
reproduced from the test names, and this table marks each one.) A test whose only subject was YAML
shape is deleted (9: #10, #19, #27, #37, #67, #73, #86, #149, #160), its rows that name a surviving
parameter moved into `request-model: the compiler rejects what the one contract does not allow`. A
test that also asserted a forged compiled contract refused where it runs lost its YAML loop and kept
that half (4 trimmed: #55, #65, #130, #142). A test that asserts a registry contract rule or a forged
compiled step, or a resource binding the kernel carries, stays (7 kept: #2, #24, #31, #46, #78, #153,
#163). No test that asserts a lifecycle outcome, accounting, evidence or cleanup was deleted for being
YAML shape, and no deviation from DE1 decision 6 remains.

| # | Test | Disposition | Note |
| --- | --- | --- | --- |
| 1 | static JSON guidance stays separate from dynamic input and source capture | port | looped over both preparation paths; one now |
| 2 | static context rejects missing resources and conflicting resource kinds before preparation | seam | YAML-shape class, kept: the compiler's resource-kind binding for the `context` parameter, which the kernel carries and no kernel test exercises |
| 3 | protocol corrections retain static context dynamic input and registered controls | seam | |
| 4 | preparation publishes the request, its binding evidence and the selected schema in one delta | port | compared the detailed chain with the combined step; asserts the one path |
| 5 | runner rejects foreign preparation children without accepting the successor | port | renamed; one path |
| 6 | failed preparation selection publishes neither a ledger successor nor partial preparation | port | renamed; one path |
| 7 | post-call accounting preserves native invocation failure and reports its own stale revision | seam | |
| 8 | native domain packets traverse generic fake provider execution without resource or request substitution | port | release asserted on `released_request[_and_input]` |
| 9 | native YAML preparation retains one generic request across distinct steps | port | release call retargeted |
| 10 | compiler rejects missing preparation dependencies and consumer rebinding | deleted | YAML-shape class: parameter and dependency mutations of one stage. Its rows that name a surviving parameter moved into `request-model: the compiler rejects what the one contract does not allow` (missing slot and prompt, slot of the wrong kind, a prompt bound to a result resource, an absent result schema) |
| 11 | one unauthorized slot fails preparation without invoking a consumer | port | one path |
| 12 | each execution has fresh identities and rejects a foreign retained request | port | one path |
| 13 | cancellation at every preparation boundary stops the compiled workflow | re-drive | three boundaries |
| 14 | native preparation releases partial allocations and unapplied deltas | port | one path |
| 15 | retained request consumers still require policy permission and available workflow tokens | seam | |
| 16 | consumer contracts cannot replace retained resources controls or retired size policy | seam | |
| 17 | YAML accounting publishes applied attempt evidence without rebinding or provider work | seam | shorter step list |
| 18 | YAML accounting permits only the declared retries after the initial execution | seam | |
| 19 | accounting schema rejects missing invalid excessive hidden and policy retry parameters | deleted | YAML-shape class. The retry-limit rows (missing, negative, overflow, wrong kind, unknown parameters) moved into the kernel compiler test; the policy row was already there |
| 20 | accounted attempts are isolated and foreign evidence cannot reach a consumer | seam | shorter step list |
| 21 | accounting cancellation and allocation failures retain no partial evidence | re-drive | boundaries 0..3 |
| 22 | new logical requests get initial attempts without resetting the YAML operation bound | seam | |
| 23 | forged accounting transitions and rejected deltas cannot publish attempts | seam | |
| 24 | runner rejects tampered accounting permissions and registry rejects hidden accounting | seam | YAML-shape class, kept: a forged compiled step and a registry contract rule, not YAML parameter shape |
| 25 | runner binds retry authority to the accounting step not the request origin | seam | |
| 26 | YAML assigns the inference operation to the existing attempt without external effects | seam | |
| 27 | assignment rejects missing dependencies and any parameter | deleted | YAML-shape class: a stage has no YAML parameters; the kernel test rejects an unknown parameter of any kind (`kind: inference`, `attempts`, `transition`) |
| 28 | an assigned operation blocks a YAML retry even after its pipeline evidence is consumed | seam | |
| 29 | foreign attempt and assignment evidence never reach an assignment or consumer | seam | |
| 30 | assignment cancellation and allocation failures publish no partial ledger or evidence | re-drive | boundaries 0..4 |
| 31 | assignment registration and compiled graphs reject hidden authority | seam | YAML-shape class, kept: registry contract rules and a forged compiled step |
| 32 | a terminal operation makes retained assignment evidence stale | seam | |
| 33 | forged assignment proposals and rejected deltas cannot publish an operation | seam | |
| 34 | assigned evidence retains its canonical record and request until destroyed | seam | |
| 35 | YAML authorization prepares one private lease for the assigned operation and cleans up | seam | |
| 36 | authorization failure facts and cancellation stay distinct and follow declared outcomes | seam | |
| 37 | authorization takes its deadline from the catalogue and rejects any YAML deadline parameter dependencies and capability permission | deleted | YAML-shape class: only YAML parameter and dependency mutations of one stage. The deadline comes from the catalogue (#40 to #42), and the kernel test rejects `timeout-ms` and `requestTimeoutMs` |
| 38 | duplicate preparation and foreign lease results cannot authorize another operation | seam | |
| 39 | authorization guards expiration overflow unavailable clocks and absent adapters | seam | |
| 40 | authorization binds each slot's catalogue entry deadline so two entries get different deadlines | seam | |
| 41 | authorization fails closed on a zero catalogue deadline the decoder could never admit | seam | |
| 42 | authorization binds the selected entry deadline to every provider operation including protocol corrections | seam | |
| 43 | authorization cancellation and allocation faults release all unpublished capabilities | re-drive | boundaries 0..5 |
| 44 | authorization validates deposited facts and releases backing after mid-preparation cancellation or expiry | seam | |
| 45 | forged authorization results and rejected deltas publish no lease and destroy backing | seam | |
| 46 | authorization compiler and registry reject hidden producers and a forged deadline parameter | seam | YAML-shape class, kept: forged compiled steps and registry contract rules, not YAML parameter shape |
| 47 | YAML pre-call request closure preserves failure and cancellation without provider calls | seam | |
| 48 | pre-call request closure maps both request states and retains immutable owners after cleanup | seam | |
| 49 | YAML pre-call request closure after inference preserves its response and single token charge | seam | |
| 50 | runtime cancellation before pre-call request closure leaves no hidden ledger transition | re-drive | cancel at step 6 |
| 51 | pre-call request closure rejects missing foreign stale duplicate and prepared evidence | seam | |
| 52 | pre-call request closure requires every operation terminal | seam | |
| 53 | pre-call request closure rejects forged successors and cancellation before publication | seam | |
| 54 | pre-call request closure allocation failures release every owner and deposited capability | seam | |
| 55 | pre-call request closure rejects YAML assertions missing prerequisites and forged projections | port | YAML-shape class, trimmed: the YAML mutation loop is deleted; what remains is `pre-call request closure refuses a forged compiled contract where it runs` |
| 56 | YAML pre-call termination preserves authorization failure and cancellation | seam | |
| 57 | pre-call termination rejects prepared missing duplicate and stale evidence without mutation | seam | |
| 58 | pre-call termination rejects foreign inputs and invalid authorization facts | seam | |
| 59 | pre-call termination and terminal-result consumers require no clock or provider deadline | seam | |
| 60 | authorization result consumers require exactly one current lifecycle phase and prepared leases still need a clock | seam | |
| 61 | pre-call termination releases deposited backing once and retains evidence after runner cleanup | seam | |
| 62 | runtime cancellation abandons authorization without hidden pre-call termination | seam | |
| 63 | pre-call termination rejects forged deltas and cancellation before publication | seam | |
| 64 | pre-call termination allocation failures release every owner without calls or token usage | seam | |
| 65 | pre-call termination rejects YAML assertions missing prerequisites and forged compiled contracts | port | YAML-shape class, trimmed: the YAML mutation loop is deleted; what remains is `pre-call termination refuses a forged compiled contract where it runs` |
| 66 | YAML advances the logical request once while preserving its request attempt operation and lease | seam | |
| 67 | request lifecycle YAML rejects hidden transitions retry rebinding and absent authorization | deleted | YAML-shape class: `transition` and other parameters of one stage, which the kernel fixes; an unknown parameter is rejected by the kernel test, and absent authorization is #68 |
| 68 | failed cancelled expired and foreign authorization cannot advance a logical request | seam | |
| 69 | stale request-ledger snapshots cannot reset invocation or reach later consumers | seam | |
| 70 | forged lifecycle successors and rejected deltas never publish request invocation | seam | |
| 71 | request lifecycle cancellation allocation faults and compiler tampering fail closed | re-drive | boundaries 0..6 |
| 72 | YAML provider invocation publishes canonical evidence with the original lease deadline | seam | |
| 73 | provider invocation YAML rejects missing unknown hidden and replacement parameters | deleted | YAML-shape class: the `transition` parameter and others of one stage, which the kernel fixes; an unknown parameter is rejected by the kernel test, and the missing authorization is #74 |
| 74 | provider invocation requires an invoked request and rejects failed cancelled expired and foreign leases | seam | |
| 75 | provider invocation rejects forged transitions and deltas without publishing state or evidence | seam | |
| 76 | invoked evidence cannot cross executions or outlive its canonical status | seam | |
| 77 | provider invocation cancellation allocation failures and retained evidence clean up exactly once | re-drive | boundaries 0..7 |
| 78 | provider invocation accounting permission and exact compiled profile cannot be hidden or weakened | seam | YAML-shape class, kept: registry contract rules and a forged compiled step |
| 79 | provider invocation rechecks cancellation and lease deadline after allocating candidate evidence | seam | |
| 80 | native YAML invokes one model call and retains unparsed output and actual usage | seam | |
| 81 | YAML invocation preserves every stopped outcome and charges its actual usage | seam | |
| 82 | runner logs every provider-applied stop with its exact reason and stops on log failure | seam | |
| 83 | YAML invocation preserves failures and blocks further calls when usage is unavailable | seam | |
| 84 | YAML invocation accounts exact budget exhaustion and overshoot before blocking subsequent calls | seam | |
| 85 | YAML invocation cancellation stays distinct without fabricated usage | seam | |
| 86 | YAML call rejects missing dependencies controls and policy permission | deleted | YAML-shape class: the stage takes no parameters, and the policy-permission rows are in the kernel test (a policy without the model-provider capability) |
| 87 | workflow result retains the exact budget rejection and does not follow a YAML failure edge | seam | |
| 88 | YAML call guards cancellation expiry and absent adapters before effects | seam | |
| 89 | post-call cancellation deadlines malformed associations and usage fail without replay | seam | |
| 90 | rejected invocation deltas retain actual usage without publishing candidate data | seam | |
| 91 | YAML invocation owners and token usage are isolated between executions | seam | |
| 92 | YAML invocation allocation failures release pending responses and consumed or unused leases | seam | |
| 93 | response admission preserves selected requests captured authority and serialized request sizes | port | compared the detailed and combined chains and wrote a wire dump nothing read; asserts the one chain |
| 94 | response admission permits only the exact pure output pair | port | the foreign-parameter variant names the preparation parameters |
| 95 | response admission rejects missing and foreign observation authority without partial publication | seam | |
| 96 | outcome projection rejects replayed sealed admission outputs from a prior attempt | port | was decode, validate and admit modes; admit only |
| 97 | stale sealed protocol correction cannot authorize a later rejected attempt | port | one path |
| 98 | compiler rejects failed request closure routed through unrelated success | seam | |
| 99 | unrelated successful operation cannot discard a prohibiting workflow outcome | seam | |
| 100 | runner preserves failed native closure when compiled control flow is forged | seam | |
| 101 | runner rejects an unrelated filesystem write before invoking its binding | seam | |
| 102 | runner rejects an unrelated model call before provider invocation | seam | |
| 103 | bounded protocol assignments continue many valid units and stop repeated or alternating failures | re-drive | seam release; `decode` assertion removed |
| 104 | native repair progress permits independent requests while retaining the global token budget | re-drive | seam release |
| 105 | dependent reviews retain parent allowances through initial protocol correction and global accounting | re-drive | seam release |
| 106 | protocol retries retain only latest repeated or alternating decoder rejection until local exhaustion | port | one path |
| 107 | selected review nesting and sibling loss retain correction scope through recovery or exhaustion | port | one path; the decode-only assertion removed |
| 108 | protocol repetition requires the current correction association and same typed rejection | seam | |
| 109 | correction handoff releases copied rejection context at every allocation failure | port | step list and re-send index recomputed; decode-only expectation removed |
| 110 | metadata and diagnostic echoes exhaust protocol retries without acceptance or extra accounting | seam | |
| 111 | a first runaway is re-sent once, even at retry-limit 0, and its admitted response closes the request | seam | |
| 112 | every runaway re-send is logged before it is sent, and a logging rejection prevents it | seam | |
| 113 | a re-send refused before it is sent is not logged as re-sent | seam | |
| 114 | the runner refuses a second re-send of one attempt | seam | |
| 115 | a re-send keeps the full prepared identity of the attempt it repeats | seam | |
| 116 | a first runaway is not logged as a missing final answer, and a missing final answer still is | seam | |
| 117 | a runaway on the re-send fails a required request with its typed diagnostic | seam | |
| 118 | a re-sent response passes the same admission and its rejection takes a correction at the configured temperature | seam | |
| 119 | a protocol correction that runs away is re-sent once with its correction intact | seam | |
| 120 | protocol retry budget overshoot charges the response before decoding and blocks another call | seam | |
| 121 | corrected protocol responses pass schema validation before request closure | port | one path |
| 122 | YAML request closure accepts only the schema-valid candidate and preserves content rejection | port | one path |
| 123 | YAML request closure preserves provider stops failures cancellation and invalid UTF8 | seam | |
| 124 | request closure rejects every missing input stale ledger and duplicate closure without mutation | seam | |
| 125 | request closure rejects foreign payload terminal attempt and request evidence | seam | |
| 126 | request closure refuses an additional assigned or invoked operation despite terminal evidence | seam | |
| 127 | request closure needs no live lease deadline or remaining token budget and retains ownership | seam | |
| 128 | request closure rejects forged successors suppressed outcomes and cancelled publication | seam | |
| 129 | request closure releases owned ledgers and responses on allocation failure for every outcome | seam | |
| 130 | request closure YAML rejects missing evidence hidden reasons and forged compiled contracts | port | YAML-shape class, trimmed: the YAML mutation loop is deleted; what remains is `request closure refuses a forged compiled contract where it runs` |
| 131 | YAML provider completion closes only the operation independently of payload validity | seam | |
| 132 | YAML provider completion preserves stopped failed cancelled and unsafe response facts | seam | |
| 133 | YAML completion needs no live lease and works at exact token exhaustion | seam | |
| 134 | YAML completion releases unused authorization after provider-side cancellation exactly once | seam | |
| 135 | YAML completion rejects duplicate stale and missing evidence without altering the ledger | seam | |
| 136 | YAML completion rejects foreign observation and invocation evidence | seam | |
| 137 | terminal evidence cannot authorize a consumer in another execution | seam | |
| 138 | YAML completion evidence and response owners survive runner cleanup | seam | |
| 139 | YAML completion rejects unvalidated response associations without inventing a terminal result | seam | |
| 140 | YAML completion rejects fabricated terminal facts suppressed failures and cancelled publication | seam | |
| 141 | YAML completion releases all retained owners on every allocation failure and terminal branch | seam | |
| 142 | completion YAML rejects missing observations and outcome delivery or selection overrides | port | YAML-shape class, trimmed: the YAML mutation loop is deleted; what remains is `provider completion refuses a forged compiled contract where it runs` |
| 143 | runner logs normalization once with call provenance and stops on log failure | port | one path |
| 144 | approved repeated and partial field prefixes avoid protocol correction | port | one path |
| 145 | normalization never bypasses schema rejection or the protocol retry allowance | port | one path |
| 146 | YAML payload validation uses each exact compiled schema and retains the same candidate | port | one path |
| 147 | YAML payload validation preserves protocol provider cancellation and observation rejection | port | one path |
| 148 | YAML schema evidence retains the tree request and response after all upstream cleanup | port | one path |
| 149 | YAML payload validation rejects missing evidence and hidden schema or retry overrides | deleted | YAML-shape class: the admission stage takes no parameters; an unknown parameter is rejected by the kernel test, and missing evidence is #95 |
| 150 | YAML payload validation allocation failures release retained candidates on every outcome | port | one path |
| 151 | YAML payload validation remains available at the token budget without another charge | port | one path |
| 152 | YAML payload publication rejection and cancellation release evidence without consuming the candidate | port | the spy wraps the admission binding only |
| 153 | compiled payload validation cannot bypass its candidate or add effects | port | one path; YAML-shape class, kept: a forged compiled step |
| 154 | YAML validates a complete observation without decoding or charging tokens twice | seam | |
| 155 | YAML observation validation preserves every stop and provider failure without another charge | seam | |
| 156 | YAML observation validation retains provider cancellation without fabricating evidence | seam | |
| 157 | YAML observation validation rejects unsafe UTF-8 after accounting its reported usage | seam | |
| 158 | YAML observation consumers reject cross-execution results and stale invoked evidence | port | the next stage is the admission step |
| 159 | validated observation owns its request and response after source values and runner cleanup | seam | |
| 160 | observation YAML rejects missing inputs hidden operations and parameter overrides | deleted | YAML-shape class: the stage takes no parameters; an unknown parameter is rejected by the kernel test, and missing inputs are #95 and #158 |
| 161 | observation validation releases all references on every allocation failure | seam | |
| 162 | rejected validation deltas and runtime cancellation release evidence without changing usage | seam | |
| 163 | compiled observation validation cannot hide its dependencies or add a capability | seam | YAML-shape class, kept: a forged compiled step |
| 164 | configured parts keep admitted siblings through protocol recovery and exhaustion with exact accounting | re-drive | seam release |
| 165 | registered non-Spec typed consumer composes references and enforces its own eligibility | re-drive | seam release |
| 166 | composition application handoffs release retained parts and requests at every allocation failure | re-drive | seam release |
| 167 | production request capture failure records non-delivery and response capture failure retains usage | seam | |
| 168 | production source snapshot capture failure preserves its cause and unsent accounting | seam | |
| 169 | production capture accepts an authorized repair packet without a single producing call | seam | |
| 170 | production capture attributes inference bodies to the existing request ledger | seam | |
| 171 | production Bedrock composition executes inference validation and request closure from YAML | seam | |
| 172 | production Bedrock YAML records budget overshoot and blocks another call | seam | |
| 173 | production Bedrock missing credentials follow explicit pre-call termination without effects | seam | |
| 174 | ADR 0039: a repeated runaway is captured in full at debug before its failure, and only its events survive higher levels | seam | |
| 175 | production missing-answer observation retains usage and can close without correction | seam | |
| 176 | missing answers share protocol allowance through mixed failure and successful recovery | port | one path; the decode-only assertion removed |
| 177 | packet result selection binds one immutable named schema and fails before invocation when absent | seam | |
| 178 | retained semantic assignments require complete current packet request binding and accepted origin | seam | |
| 179 | retained semantic assignments preserve the actual accepted correction attempt | seam | |
| 180 | a request binds native exclusions to the one canonical schema | port | was "detailed and consolidated requests bind native exclusions to the same canonical schema"; one path |
| 181 | protocol correction retains the selected integer choice and assembly requirements and rejects a value outside it | seam | renamed by C27 (E4 below); it rejects a value outside a one-value choice instead of an echoed handle |
| 182 | protocol correction retains summary and signal guidance selection bounds categories and evidence | seam | |
| 183 | composition protocol corrections keep complete assignment and grouped defects through recovery or exhaustion | port | one path |
| 184 | retained semantic selections bind native exact scope independently of unchanged input bytes | seam | |
| 185 | a packet request shares the global budget and overshoot fails the run | seam | |
| 186 | global exhaustion and unknown usage block a packet request before sending | seam | |

**Deleted with the decode, payload-validation and runaway-route stages (10), each with the test that covers its intent:**

| Test | Reason |
| --- | --- |
| YAML decoding retains syntax-only evidence and rejected outcomes with exact accounting | asserted a decode step with no schema; the decode stage is part of admission. The syntax matrix is `model_envelope_test.zig`, the rejection and accounting are #147 and #150 |
| YAML decoder never converts stopped failed cancelled or rejected observations into protocol invalid, except a first runaway for its re-send | #147 runs the same plans through admission |
| decoded YAML candidate keeps its tree and original evidence after all source-value cleanup | #148 |
| YAML decoding rejects absent evidence and parameter or outcome overrides before execution | #149 |
| YAML decoder rejects foreign sealed observations without rebinding or a new provider call | #95 |
| YAML decoder releases parse trees and retained evidence on every allocation failure | #150 |
| YAML decoding releases rejected deltas and cancelled trees without consuming its evidence | #152 |
| compiled decoding contracts cannot bypass evidence or add a provider capability | #153 |
| YAML payload validation rejects foreign decoded and nondecoded evidence without rebinding | the stage no longer takes decoded evidence as input; #95 and #158 cover foreign observation evidence |
| the compiler requires every continuing admission to route a runaway to its one re-send | asserted `validateRunawayRoutes`, deleted by DE1 decision 5; the orchestrator's branch tests (`a runaway takes the re-send, not the correction`, `an invalid response takes one protocol correction and returns to attempt accounting`) and #111 to #119 cover the branches |

## E4. Generic repair operations (ADR 0033)

**Kept 14 November 2026** (user: "yes", to keeping E4 for its reduced brittleness; no outcome improvement is
claimed). The `reference-text` and `specification-support` routes stay registered, and `model_text_wire.zig`
`insertion` keeps recognising and rejecting a model-authored `{"kind":"exact_copy"}`: only its comment changed.

**Built** (steps 1 to 7): the contract-variant mechanism (ADR 0030 "Contract variants": registry admission per
variant, selection before compilation, graph and publication rechecks, the runner's `Entry.contractFor`); the
four generic repair operations with 13 owners and 29 variants (`repair_owner.zig`, `repair_workflow.zig`, each
owner binding's `effects`); the Spec workflow's 32 repair steps run them with `owner`. Only Specify's 13
owners exist; Plan, Tasks and Implement owners wait for the quality gate (ADR 0034). ADR 0033 and its
pointers read implemented, and one specification of the four operations replaces the per-owner entries in
[13-04](../design/contracts/actions/13-04-model.md#generic-repair-operations). Q14 b3 extended the
specification-unit repair route these operations replace, and b4 will remove its insert; E4 is a prerequisite
of neither (SPEC01 Q14). It landed under §2.12, as retained reports carry repair keys; no persisted contract
moved.

**Decisions** (user, on my recommendations):
- **DE4, 13 November 2026** ("yes to all 10 decisions", to the E4 preflight's ten recommendations; E1 was
  kept, so ADR 0033's precondition 1 held):
  1. E4 builds ADR 0030's contract-variant mechanism (registry, compiler, runner) as its own early steps, with
     ADR 0030:428-445 as its test list, in the same landing; E1 built none.
  2. ADR 0033's choices 2-3 are confirmed: the 13 owners, source omission's merges split in two. `owner` is
     checked against native facts, at compilation where the variant's required keys prove it, otherwise by a
     terminal runner rejection with a closed diagnostic. It selects no policy, scope or defect identity.
  3. Choices 4-5 are confirmed (already in 22-repair.md:15-19 and :709-712): a "compiled operation" is the
     compiled step instance; §22.1's "distinct" means authorization categories and owners, not operation IDs.
  4. Choices 7-8 are confirmed: all Specify owners convert in one change on offline evidence; one live set
     follows landing only on the user's go-ahead (ADR 0033 choice 6 is moot).
  5. The no-invention branch is removed from ADR 0033:138-139 and its acceptance list (no owner has it); the
     wider design text followed on 14 November 2026 (SPEC01 §8).
  6. Variant retry maxima equal today's YAML values (128, 1, 1, 64, 2); the text and extraction merges still
     forbid `retry-limit`; native key populations are unchanged.
  7. The dispositions authorizer drops its unreachable `more` and the matching YAML edge (ADR 0046).
  8. The freeze compares defect-key bytes (the repair `Family` type names are not renamed) and the step trace
     prints the owner; repair evidence per scenario is frozen too.
  9. The owner is shown through the step's declared parameters; no new report field and no version bump.
  10. The change edits the accepted ADRs' pointers and stale prose (ADR 0005, 0023, 0031, 0033 "three
     reconciliation authorizers", 0030 "two users"), design.md §22 and §32, and deletes or updates the
     per-owner entries in contracts 13-03 and 13-05.
- **14 November 2026** ("yes", to my recommendations): the `reference-text` and `specification-support`
  routes stay registered (against removing two owners and 8 variants); `model_text_wire.zig` `insertion` keeps
  recognising `{"kind":"exact_copy"}` with no `claim_id` and rejecting it as an encoded insertion, and only
  its stale comment was reworded; one live set (3 runs per case) on this build; E4 is kept; the E5 preflight
  starts.

**Live set, 14 November 2026** (build `dbebf8ce`, modified, `spec-e2e-report/v18`; three runs per
development case): all six runs published (9 sends each, 11 in one); five passed adjudication and one
failed on a critical criterion. hello-world 96.43%, 100%, 96.43% (no accuracy defect; quote marks around a
code span in one, an entity on a no-data feature in another); loan-renewal 96.43% (one minor
`unsupported_addition`, "records the loan as renewed"), 85.71% **failed** (`successful-renewal` 2: AC-001
states "fourteen days" and drops "calendar", a `weakened_obligation` from the records generation, the
recorded 'lossy repeats' model limitation, SPEC01 §3, not a repair defect: the run's one repair inserted
a clean AC-002), 100%. Tokens 12,704 to 12,820 (hello-world) and 16,388 to 19,350 (loan-renewal; 19,350 is
the run with the insert repair and two more sends). Three repairs ran live through the generic operations
(two deletes, one insert, all on the specification-unit route, all helpful); no run took the
`reference-text` or `specification-support` routes. The E1 set passed all six runs and each pre-E1 set had
one non-passing loan-renewal run; at three runs per case none of this is a difference, and E4 changes no
request byte, so it is reported as no regression, not as a benefit. Evaluations:
`evaluations/e2e/2026-11-13T23-47-*`; adjudications in `evaluations/adjudications/`.

**Step 5 implemented 14 November 2026** (user: "yes implement step 5"; DE4, the ten decisions approved).
The 29 per-owner repair operations, their 29 action files and the seven owner bindings' action wrappers
are deleted; the four generic operations (`authorize-repair`, `build-repair-input`, `parse-repair`,
`merge-repair`) hold the owner bindings by value and select one by the step's `owner`. **Defect class
named:** none; the change reduces brittleness (29 registrations, 29 wrappers and 29 contracts to keep in
step with each other) and claims no semantic benefit. The request projection is byte-identical to the one
before E4, so what each request sends is unchanged. **Accepted finding** (user, 14 November 2026, "yes"):
the retained-merge `authorization` digest differs in 9 scenarios of the step trace, because of E9 (below);
every other trace file is identical to step 4's.
- **Where the contract data lives now:** once, in each owner binding's `effects`
  (`repair_owner.Effects`: requires, optional, produces, replaces, invalidates), which the generic
  operation's variants are built from; the outcome, role, association, gates and retry maximum are in
  `repair_workflow.zig` and `repair_owner.zig`. The source-omission rules moved from five action files to
  `src/domain/source_omission_repair.zig`.
- **Measures** (recomputed 14 November 2026 for the review fixes below; two baselines, because step 3
  registered the generic operations beside the 29 per-owner ones):
  - Registered repair operations 29 to 4 (variants 10, 6, 6, 7). Native registry entries (excluding the
    core and request entries): 137 to 112 against the tree before E4 (25 fewer: 29 removed, 4 added), and
    141 to 112 against the end of step 4 (when both sets were registered). The 29 `Assembly` fields and init
    lines are gone; the generic operations hold the owner bindings by value.
  - Data keys are unchanged: the nine repair keys of `pipeline.zig` (`specification_coverage_repair`,
    `specification_support_repair`, `source_omission_repair`, `reference_reconciliation_repair`, the
    authorization and result keys of reference-text and reference-extraction, and
    `specification_repair_authorization`) stay, because the owner bindings the generic operations hold read
    and write the same keys; the change removes registrations, not data flow.
  - Files a new repairable owner touches (a variant, not a new operation): before E4, one `Action` file per
    operation it needed (up to four), one registry entry and one `Assembly` field each, one contract each,
    and the YAML steps; after E4, its owner binding (`effects` and its bound domain functions), one
    `RepairOwner` arm in `repair_owner.zig`, one arm in each generic operation it joins in
    `repair_workflow.zig` (the architecture pin counts the arms), one `frozen` row and the YAML steps. The
    registry, the compiler and the four generic contracts do not change.
  - **Defect class named:** none. ADR 0033 chose structural-only evidence for E4 (an approved deviation
    from AGENTS.md "Model output, prompts and evidence"): it changes no prompt, no admission rule and no
    published-output behaviour, and no live run is claimed for it.
  - Action files 188 to 159 (29 deleted, one per removed operation id; the ids are the list in
    `removed_operations` of `repair_operations_test.zig`); about 1,240 lines of action code replaced by
    `effects` declarations, direct domain calls and one 58-line domain file. Owner binding files 7 to 7
    (each rewritten); `repair_workflow.zig` 272 lines.
  - Spec YAML: 910 lines, 32 repair steps naming an `owner`, unchanged by step 5.
  - Tests: unit suite 2,004 to 2,004 (3 added, 3 removed by C27), then 2,007 after the review fixes (3
    real-facts and property tests added, one test replaced), then 2,012 after the final-review fixes (5 tests
    in `src/repair_routes_test.zig`; two existing owner-mismatch tests now pin the specific error);
    `test-architecture` 195; `test-model-request-workflow` 507; `test-integration` 128 with no failed row.
  - `anyopaque`: none in the generic operations, the owner bindings or the new domain files; none added.
- **Old test or pin to replacement:**

| Before step 5 | After |
| --- | --- |
| step 3's equivalence test, which compared each variant with the registered per-owner contract | `every variant states what the per-owner operation it replaced stated, but for the named differences`: a fixed 29-row table (`frozen`) taken from the 29 old contracts on 14 November 2026, before they were deleted; it asserts requires, optional, produces, replaces, invalidates, side effect, role, association, gates, outcomes (less `unreachableOutcome`), retry scope and maximum, and the selector and `retry-limit` parameter, and that the table has 29 rows each served by its owner |
| run tests that built each per-owner assembly field | `a generic operation runs the selected owner's binding and fails as that binding fails` (all 29 variants; the operation's field is the binding's own type) |
| none | `a workflow that names a removed per-owner repair operation is rejected as an unknown operation, at a step and in a called subgraph` (29 ids at two positions, with a control that compiles `merge-repair` at both) |
| none | `the production registry holds the four generic repair operations with their variants, and none of the 29 they replaced` (the composition root's own registry validates; 10, 6, 6 and 7 variants; no other operation has variants) |
| architecture pin `candidate repairs share authority and expose only native scoped operations` read each action's `Action.contract` | the same pin reads each owner binding's `effects` and asserts the generic operations are capability-free and every variant's side effect is none |
| none | architecture pin `no per-owner repair operation remains: the four generic operations are the only registered repair operations`: four `variantEntry(generic_repair.` and none of the per-owner `entry(` families in the composition; no owner binding imports an action, names `Action.contract` or holds an `action` field; no file under `src/actions` has `repair` in its name |
| packet-guidance pin listing the per-owner repair actions that require `.packet_guidance` | the pin walks the four operations' variants and asserts exactly seven (operation, owner) readers: authorize for specification-unit and specification-support; build-input for reference-reconciliation, source-omission, specification-unit and specification-support; merge for specification-support |
| `reference_reconciliation_test.zig` read the per-owner action contracts | reads `repairs.Authorize(.summary).effects` and `repairs.BuildInput.effects` under the generic ids |
- **E9 (applied), the superseded exact-handle correction:** deleted `ValueChoices.permits`, the `unknown_exact` arm of `ValueChoices.correction`
  (the issue's own description is used, as for every other reason), `typed_text.Issue.rejected_exact` and its
  two assignments (the text validator and `recognizeInspected`), and the assertions that read it
  (`typed_text_test.zig`, `packet_guidance_test.zig`, `specification_generation_test.zig`). Kept: the
  first-node and last-node narrowing in `recognizeInspected`, which is the issue's own located range and
  cannot be shown unreachable. **Effect not foreseen in E9:** an authorization's id is the SHA-256 of the
  JSON of its owner, revision, target, operation, dependencies and rule; a rule embeds the
  `typed_text.Issue` (the specification rule's `text_issue`, the reconciliation rule's rejection), so
  removing the member removes its key from those bytes. In 9 of the 135 step-trace scenarios
  (`spec-generation-existing` 005, 008, 018, 020, 024, 028, 054, 055 and 065) a retained merge's
  `authorization` digest, and the permit digest derived from it, differ from step 4's; no other field of any
  trace, summary, state or `.repairs` file differs. The cause is established by reading the code, not by
  restoring the member. `state/workflow.json` is identical in all 135 scenarios, so the id is not in the persisted state; it is
  in the retained-merge evidence (`.repairs`, and the report's `repairs`), whose schema is unchanged.
  **E9's defect class:** none scored. The only model-facing change is the correction text for an unknown
  exact copy in model prose, which now falls to the issue's own description without the
  `repair_tails.value_choices` tail; no scenario or live run shows that path reached, so its reachability in
  live runs is not established.
- **C27 (applied):** the `.construct` singleton choice was set only in tests (SPEC01 §10 C27, ADR
  0020:26-28). Deleted: `IntegerChoice.singleton` and `constructedValue`, `omitConstructedField` with its
  branch and check in `restrict`, the copy in `model_input_packet`, `constructBound` and `constructFields`
  with their four callers (specification collection, specification repair parse, atomic repair parse, the
  composition retention), and the fixture's `modelWire` and `omitScriptedNativeFields`. Tests: three
  singleton tests deleted (`composition reconstructs native singleton choices while retaining the original
  admitted response`, `native singleton fields reconstruct by bound occurrence without changing raw
  responses`, `explicit native singleton construction omits only determined tagged fields`); the E1 table's
  row 181 is now `protocol correction retains the selected integer choice and assembly requirements and
  rejects a value outside it`, which rejects a value outside a one-value choice instead of an echoed
  handle; the retained F10 to F12 replay (`representation_admission_tests.zig`) restores the captured
  handle in the test itself, so the frozen observations are unchanged. The projection and the trace
  retaken after C27 are byte-identical to those before it. **Left:** `model_text_wire.zig` `insertion`
  still accepts an `exact_copy` object with only its `kind` (its comment names the deleted singleton);
  whether prose holding such an object is still recognised as a wire object is a model-output admission
  decision, so it is not changed here.
- **Versions this step moves:** none (the final measures below). **Remains for step 6:** the docs that still
  describe the 29 operations or the singleton: C13-03 and C13-05 per-owner entries, the "not yet
  implemented" pointers and the three-reconciliation-authorizers prose of ADR 0005, 0023, 0031 and 0033,
  ADR 0030 "two users", design.md §22 and §32, C22, F0005, F0100, and
  `test/calibration/authoring-associations/README.md:139-140` (`constructBound`): done in step 6.

**Final measures and proof (step 7, 14 November 2026).** E4 is a structural change and claims no semantic
benefit; its defect class is none (ADR 0033's structural-only evidence, an approved deviation).
- **Evidence kept:** `evaluations/request-projection/e4-before` and `e4-final`, `evaluations/step-trace/e4-before`
  and `e4-final`; the interim `e4-step3` to `e4-step6a` directories are deleted. `e4-final` was written by a
  fresh `test-integration` run (a new `SDDE_REQUEST_PROJECTION` value forces it) on the final tree; every one of
  the 135 `.repairs` files was rewritten by it. **Projection:** `diff -rq` of `e4-final` against `e4-before` and
  against the step 6a retake is empty. **Trace** (135 scenarios, 817 files): `e4-final` is byte-identical to
  `e4-step6a`; against `e4-before`, by script over every file: 678 identical; 65 `.trace` files that differ
  only in repair-step operation ids (the old id became the generic id with `@owner`, same outcome, every other
  line identical and in order); 65 summaries that differ only in `trace_sha256`; 9 `.repairs` files that
  differ only in the authorization and permit digests (E9, accepted). Nothing else differs, including
  outcomes, retry counts, token totals, defect-key bytes, executions, retained merges and every
  `state/workflow.json`. `<scenario>.repairs` (`workflow-repair-evidence/v1`, a trace-fixture file kind, not a
  persisted engine contract) records each retry-bearing step's limit, scope and executions, its defect keys and
  the retained native merges; it cannot record a merge no final candidate retains or a repair attempt's
  request bytes.
- **Sizes** (`wc -l` on 14 November 2026; the pre-E4 sizes of the mechanism files were not recorded and no
  version control is read, so their line changes are not stated): registered repair operations 29 to 4;
  native registry entries 137 to 112 against the tree before E4 (141 to 112 against the end of step 4);
  action files 188 to 159. Removed: 29 action files (372 lines) and the 29 registrations (about 87
  lines). Rewritten: the seven owner bindings, 779 to 901 lines (they now hold each contract's `effects`
  once). Added production files: `repair_owner.zig` 170, `repair_workflow.zig` 272 and
  `source_omission_repair.zig` 58, 500 lines. Net of the replaced 1,238 lines (372, 779 and 87) and the
  1,401 now (901 and 500): about 163 lines more, before the variant mechanism's edits (`workflow_operation.zig`
  157, `workflow_compilation.zig` 229, `workflow_operation_registry.zig` 464, `workflow_graph_compilation.zig`
  431, `workflow_graph_validation.zig` 527, `workflow_registry.zig` 372 and the runner 1,136 lines now, none
  measured before). E4 reduces registrations, wrappers, contracts and the files a new owner touches; it does
  not reduce lines. Spec YAML 910 lines, 32 repair steps naming an `owner`.
- **Tests:** unit suite 1,975 (end of E1) to 2,012; new files `src/operation_variant_test.zig` (12 tests),
  `src/repair_operations_test.zig` (15 tests) and `src/repair_routes_test.zig` (5 tests), plus two step-trace
  fixture tests, one architecture pin group and the E1 and E9 test edits; `test-architecture` 195,
  `test-model-request-workflow` 507, `test-integration` 128 without a failed row. `anyopaque`: 0 in `repair_workflow.zig`, `repair_owner.zig`
  and `source_omission_repair.zig`; the registry port (2), the runner (6) and `operation_variant_test.zig`
  (2) carry the existing binding-context pointers, not attributed to E4 and not re-measured before it.
- **Versions moved:** none (step 6).
- **Evidence limits, stated plainly:** the `reference-text` and `specification-support` routes (8 variants)
  appear in no scenario of the matrix, so their equivalence to the 29 operations they replaced cannot be
  shown offline. They stand on the contract table (`frozen`), a dispatch test and invoke-level tests over real
  facts in `src/repair_routes_test.zig`, which run each operation through the generic operation and assert
  the outcome, the exact keys of the delta and the value against the domain function: the text route's
  authorize, input, parse (after a real request answered through the stage seam) and merge; the support
  route's four operations over a whole and a focused rejected review (merge `ok` and `more`), merge
  `invalid` and authorize `blocked`. Not covered by such a test: the support authorize `more` (a delete) and support merge `more` through a whole
  review (only a focused candidate yields it).
  The other eleven owners run in the scripted matrix. Owner mismatch is pinned for absent keys and for keys
  that hold another kind of value. `Registry.validate()` runs on every step and now checks 112 entries and 29
  variants; its cost is not measured.

## E5. Rejections say why

**Implemented 14 November 2026** (user: "yes", to the ten DE5 recommendations; steps 1 to 7).
**Kept 14 November 2026** (user: "keep E5, update docs", after the live set below; no outcome improvement is
claimed, and the keep rests on the closed reasons and causes and on unchanged request bytes). **Defect class
named:** none. A rejection names the authority check,
the operation cause and the earlier failure that stopped the run, so a failed run is read from its report, step
event, log and trace instead of from a re-run; no request byte, prompt, admission rule or published output
changes, and no semantic benefit is claimed. ADR 0041's publish rules are as they were: every `authority` reason
publishes nothing.
- **Decisions** (DE5, 14 November 2026, "yes", to the E5 preflight's ten recommendations; E1 to E4 were
  implemented and kept):
  1-4. The unchanged `Rejection` tags, the one closed `AuthorityReason` enum grouped by cause class (about 24
     groups, never per line or caller), the report's closed `reason` member with its version bumps and no
     compatibility reader, and the `OperationExecutionFailed` split are stated under Owners and Versions
     below.
  5. A later failure no longer replaces the first; the report carries the first cause beside the terminal one
     (as `model_capture` already does for a later logging failure, its `subsequent_logging_failure`). A
     rejection formed from the result of a call whose capture failed is not carried: the capture failure is
     the call's one cause (user, 14 November 2026: "4 recommendations are approved", the first of which
     accepts that loss; 27-observability.md states the rule). The harness report carries the first cause in a
     type of its own, with no capture-failure kind and a retry exhaustion's facts, and `first_native_rejection`
     names it (the same approval).
  6. The execution ceiling gets its own reason. The clause that the packaged smoke pins the reason name
     instead of a bare `failed` is dropped (user, 14 November 2026: "4 recommendations are approved"): a case
     that routes a `request-model` step's `failed` to itself cannot be built (it ends at
     `WORKFLOW_GRAPH_COMPILE_INVALID`), so no packaged project reaches an authority rejection, and the CLI is
     pinned by `Rejection.diagnostic()` over every reason and by the packaged pins that already print a runner
     rejection through it (`InvalidToolchain`, `InvalidReferenceAccounting`, `InvalidClarificationInput`,
     `InvalidReferenceSelector`). The decision to count the kernel step's retry authority in the ceiling is a
     separate change (SPEC01 E1).
  7. and 8. (the §22.6 correction location; the evaluator partial-body retention and F0005 §9's
     workflow-definition rejection detail) are separate items, open in SPEC01 E5.
  9. Reasons are emitted as upper-cased names under the current token rule; enumerating the closed
     `diagnostic_code` set (F0002's open item) is separate (SPEC01 §8).
  10. The change edits the ADR 0033, 0030 and 0041 pointers and text, contracts 06, 08, 22 and 27,
      `design/harness/e2e.md` and the E5 record.
- **Owners:**
  - `src/domain/workflow_execution.zig`: `AuthorityReason`, one member per cause class, each documented where
    it is defined, is the payload of `Rejection.authority`; a bare `.authority` no longer compiles. The tags,
    `status()` and ADR 0041 are unchanged, and `Rejection.diagnostic()` of an authority rejection is the reason's
    tag name. `FirstCause` is a closed union of every `Rejection` member but `model_capture`, with the same
    payloads, and `FirstCause.replacedBy` is the one rule for what is kept: nothing when either rejection is a
    capture failure or both are the same.
  - The producers are `workflow_pipeline_runner.zig`, `workflow_model_invocation.zig` (`invocation_result`) and
    `model_request_orchestrator.zig` (`kernel_stage_outcome`). A denied lease is told from an unavailable clock,
    and the execution ceiling has its own reason, `step_execution_ceiling`. A reason names the invariant, so every
    site of one invariant raises one reason: a ledger, view or retained request a step cannot read is
    `input_view_unavailable` wherever the runner reads it, a retained request that holds no prepared form is
    `request_state_missing`, the attempt accounting of another stage run than the request's is
    `accounting_transition` at every step that reads it, and an exhaustion the runner cannot name is
    `retry_admission` for a kernel stage as for any step.
  - `error.OperationExecutionFailed` is deleted. Its uses became closed causes in five owner-area sets:
    `src/domain/step_binding_error.zig` (`RequestPreparation`, `ProviderLifecycle`, `StepBinding` and
    `Invocation`) and `repair_owner.Error`; a site whose cause an existing error already names uses that error. The six
    `catch return error.OperationExecutionFailed` sites that discarded `InvalidAtomicRepair` go through
    `repair_owner.mergeTransition` and `validatedMergeTransition`, which return `LastRepairMissing` for a merge
    with no record and the domain's `InvalidAtomicRepair` for a record without its permit. `RepairOwnerMismatch`
    replaces the four generic forms where an owner's binding finds another kind of value at a key it reads and
    where a generic operation does not serve the owner; an absent key stays `MissingRequiredData`, and an absent or
    unparsable `owner` is `RepairOwnerUnresolved`.
  - Two causes were dropped as dead: the runner refuses a step whose retained request has no prepared form
    (`request_state_missing`) or whose authorization was not prepared before a call (`authorization_denied` for a
    failed preparation, `cancelled` for a cancelled one) before any binding runs, so `PreparedRequestMissing` and
    `InvocationAuthorizationNotPrepared` only duplicated those refusals; the bindings state the invariant
    (`prepared().?`, an `unreachable` arm), and runner-level tests pin both refusals (a call step given a failed and
    a cancelled authorization; assign-operation, call and runaway given a retained request that holds no prepared
    form, each with a control that runs). The rule applied, from the contract review and not a user decision: a
    binding asserts an input only behind a runner refusal that a runner-level test pins, and every other check of
    an input stays a typed cause (`step_binding_error.zig` states it). Two sites changed cause: a rejected
    observation at request completion is `ObservationNotValidated` (it was `LifecycleEvidenceForeign`), and a
    reconciliation merge that finds its replacement still pending is `RepairStateMismatch`, as the parse of that
    state is (it was `RepairCandidateMissing`).
  - First cause: `Runner.first_cause` is set in one place, `keepFirstCause` (the earliest replacement wins, and a
    lone failure leaves it unset), from `model_invocation.reconcile` (`Reconciled { rejection, replaced }`), the
    runner's post-call error and candidate paths, `actionEnd` for steps and kernel stages, the retry-exhaustion
    event and the feature-log finalizer (`Finalizer.replaced_fn`, kept by `Runner.finish`). Not sites: a capture
    failure that wins over a reconciled rejection (the capture is the earlier failure), a non-model operation error
    replaced by the runtime's stop (the stop caused it), and a logging failure after an applied outcome (it
    replaces an outcome, not a rejection). A rejection formed from the result of a call whose capture failed is
    not carried: the capture failure is the call's one cause (DE5 5 above; 27-observability.md states the rule).
  - Surfaces: the CLI prints the reason where it printed `failed`; the `run.failed` and action events carry it
    upper-cased under the existing `diagnostic_code` token rule (no new `LOG_*` code, no F0002 or `event-columns`
    change); the step-trace line gains `:first=<tag>:<diagnostic>` only when a first cause was kept, followed by
    a retry exhaustion's counts and stage as the terminal line gives them
    (`workflow-step-trace/v1` stays: an optional suffix of an observation, like `:stage=`). The harness report
    has `TerminalRejection.reason` (the closed `AuthorityReason`, non-null exactly when the kind is `authority`;
    the typed decode rejects a reason on another kind, an authority rejection without one and an unknown reason)
    and `Report.first_cause`, a record of its own (`FirstCause` in `test/harness/e2e/contracts.zig`) read from
    `runner.first_cause` by `observation.capture`: its kind is over the writer's `FirstCause`, so a capture
    failure is unrepresentable and a report that names one does not decode; it pairs `reason` as the terminal
    record does and carries `exhaustion`, what `retry_error` gives a terminal exhaustion, exactly for the kind
    `retry_limit`. The step event carries it for a rejected step and both Markdown views print it, and
    `first_native_rejection` names it (widened to a `TerminalRejection`) in place of the terminal rejection when
    one was kept.
- **Rules** (`architecture_test.zig`): one declaration of the enum and a producer for every member (a reason
  counts as a whole token), none in any production file under `src` but the runner, the request orchestrator and
  the model-invocation reconciliation (a reason named in any `.authority = .<reason>` elsewhere fails, as does any
  other production file that names the reason type, and the scan must reach an application workflow); the enum's
  names are the rows of the 06 table; the old error named nowhere in production, and every cause returned by
  production code (as a whole token, outside comments, string literals and test blocks) except `HarnessFailureStopped`, which only the harness raises (pinned to it); each of the five
  merging bindings calls `repair_owner.mergeTransition(` once
  and the support binding `repair_owner.validatedMergeTransition(` once, so a hand-built transition fails; one
  `FirstCause` definition, one assignment, and the two places that build one. `src/binding_failure_cause_test.zig`
  accounts for every cause exactly once (the evidence limits below).
- **Decided 14 November 2026** (user: "implement the best option"): the shared-helper test (both causes and the
  accepted transition of `mergeTransition` and `validatedMergeTransition`) and the pin that each merging binding
  calls the helper stand in place of a per-owner merge fixture for the four owners without a real-fact fixture
  (extraction, reconciliation, source omission, specification unit): the integration matrix runs their merges, the
  failure path is the same helper code for every owner, and the text and support bindings run through the helper
  with real facts in `repair_routes_test.zig`.
- **Versions.** Advanced: `spec-e2e-report` v18 to v19, `e2e-step-event` v3 to v4, `baseline-acquisition` v12 to
  v13 (`Facts.workflow` embeds the report), `baseline-score` v4 to v5 (`Row.first_native_rejection` embeds
  `TerminalRejection`) and, not named by DE5 3, `provider-compatibility-report` v1 to v2 (its
  `terminal_rejection` is a `TerminalRejection`). Unmoved: `baseline-budget-feasibility/v2`, `baseline-freeze/v3`,
  `baseline-assessment-inputs/v2`, `e2e-measures/v2`, `e2e-measures-set/v2`, `call-diagnostic-report/v3`,
  `spec-adjudication-record/v1`, `spec-adjudication/v3`, `event-columns/v3` and `workflow-step-trace/v1`. There is
  no compatibility reader, so every retained `spec-e2e-report/v18` run (the 20-10, 20-18, E1 and E4 live sets) is
  unreadable by `e2e-measures` ("report unavailable") and rejected by `adjudicate-spec` at stage `report`, and a
  baseline acquisition v12, or a plan naming such a run as feasibility evidence, does not decode; the
  adjudications already applied stand. No skill script, setting or viewer hard-codes a version, and no reader
  exists for a step event or a baseline score, so the writers' tests pin v4 and v5. No artifact of v19, v4, v13 or v5 has been
  written (every retained run is v18), so reshaping `first_cause` into its own record and having
  `first_native_rejection` read it needs no bump. Spellings (C45):
  `spec-e2e-report/v19` on 77 lines in 16 test files, 7 more naming a superseded version in rejection tests, and
  13 for the other four.
- **Evidence (offline; no live run).** Request projection: `evaluations/request-projection/e5-before` (the E4
  tree's, byte-identical to `e4-final`) and `e5-final` (1,635 files, written by a fresh `test-integration` run on
  the final tree): `diff -rq` is empty, so what each request sends is unchanged; the four interim retakes (after
  steps 2 to 5) matched `e5-before` too and are deleted. Step trace: `evaluations/step-trace/e5-before` and
  `e5-final` (135 scenarios, 817 files): every file is identical, by script and by `diff -rq`. The frozen traces
  hold only `rejected:retry_limit:*` rejection lines, so none holds an authority reason, an operation cause or a
  first cause: the identity shows that nothing else moved, not that the new output is right. Unit suite 2,012
  (end of E4) to 2,056; `test-integration` 128 to 130. The new tests: every reason is its own lower-case
  diagnostic with status `failed`, and only `authority` carries one; the cause-set and merge-helper tests; first
  cause pairs (a call error then a stale revision, a refused result that also overshoots the budget, a call error
  then a failing completion event with a persistent sink failure, a step's rejection then its end event, an
  exhausted retry allowance then its event, the finalizer and `Runner.finish`) beside lone-failure assertions
  that no first cause is set; the event test pins each upper-cased code on the action and terminal events; the
  step-trace test pins the reason line and the `:first=` suffix; the harness tests project one rejection of every
  tag and every reason through the real writer and strict reader, reject the three bad pairings, read a real
  runner's first cause into the report and reject the superseded report versions; the first-cause record
  round-trips every kind and rejects a capture failure, a reason or exhaustion facts beside another kind and an
  authority or retry kind without them; the first native rejection names the first cause when one was kept; the
  trace test gives a replaced exhaustion's counts. `zig build verify --summary
  all` on the final tree: 147 of 147 steps, 2,186 tests passed. The review's fixes (reason moves, two dropped
  causes, the fault, guard and cause tests, the pins) and the first-cause record leave the request projection (a
  fresh `test-integration` run) and the step trace (compared in place) identical to `e5-final` (`diff -rq`).
- **Evidence limits, stated plainly.** Every reason has a test that raises it through the runner (for
  `kernel_stage_outcome`, the request orchestrator), and `Rejection.diagnostic()` is pinned over every reason.
  Four of the six reason moves the review asked for (the re-reads of a ledger or view for an accounting
  transition, and of the view for the ledger-replacement check, now `input_view_unavailable`) are definitional:
  by the reviewer's trace an earlier check in the same call reads the same view, so no test reaches them; the
  other two (the attempt accounting of another stage run, and the kernel exhaustion the runner cannot name) are
  pinned. Of the 57 causes, 13 are raised by an executable test through the production check that names them (the
  rows of `src/binding_failure_cause_test.zig` and the runner-level rows `withheld_causes`), 27 are named by a
  test file that mentions them (`asserted_elsewhere`, a naming pin only: it proves the file mentions the cause,
  not that a test asserts it) and 17 are named by no test. The 17 are listed in `not_triggered` of
  `src/binding_failure_cause_test.zig`, which a pin keeps complete: a cause joins a set only with a test or a
  place on that list. The 17 are checks that need state no fixture builds
  (composition and reference owner state, a specification publication, a repair authorization without its
  permit), checks of inputs no producer can build (`RequestOutcomeNotTerminal`, `PayloadCheckInconsistent`,
  `ProviderAuthorizationResultMissing`, `InvocationFailureUnrecorded`) and checks the call chain refuses first
  (`ObservationNotValidated`, `LifecycleRecordMissing`). The first-cause path is proved by pair tests at the reconcile,
  runner and finalizer seams; no scripted scenario produces two failures, so none shows it end to end, and the
  live set's six reports carry `reason` and `first_cause` as null (no authority rejection or replaced failure
  occurred), so a populated one has not been seen. The harness trace keeps one cause,
  `HarnessFailureStopped`, for every failure it retains, so the underlying harness error (an `anyerror`) stays in
  the harness report. The two test glues that finalize (`TestEngineBindings`, the generation `Driver`) call the
  finalizer directly and keep nothing; production goes through `Runner.finish`, pinned in `architecture_test.zig`.
  The producer scan reads source text, so a producer that builds a reason through `@FieldType` and `@enumFromInt`
  would pass it; none exists. The packaged smoke pins no authority reason: no packaged project reaches one, and
  DE5 6's clause was dropped (DE5 6 above).
- **Reported separately** (AGENTS.md "Model output, prompts and evidence"): implementation complete (steps 1 to
  7); mechanical checks passed (above); semantic benefit none claimed and none demonstrated: the live set (below)
  shows no difference from the E4 set at three runs per case, and no scored defect is E5's; brittleness: the one
  name for an operation failure became closed causes and the one `authority` reason became a closed set (counts
  in the table below), a diagnosability gain that no T5 count measures; scope qualified: one live set of six runs,
  some causes named by no test (listed and pinned).
- **Live set, 14 November 2026** (user: "yes perform a live test for E5", scored on "score the run"; build
  `5b7d56e4`, modified, `spec-e2e-report/v19`; three runs per development case): five of six runs published and
  passed adjudication; one loan-renewal run did not publish. hello-world 96.43%, 96.43%, 96.43% (no accuracy
  defect; quote marks around a code span in all three, in one of three in the E4 set); loan-renewal 100% and 96.43%
  (one minor `unsupported_addition`, "records the loan as renewed", as in one E4 run) and one run unpublished:
  `invalid` at `repair-source` after 22 sends and 59,703 tokens, because the disposition call marked claims 4 and 5
  `conflicting` against its instruction and the source review echoed it, ending in `UnlocalizedSourceOmission` (a
  model limitation; the second retained run to end so, the first on 12 November before E1; it counts as an
  attempted workload). Tokens 12,712 to 12,781 (hello-world) and 16,426 to 16,675 (published loan-renewal). Three
  repairs ran, one `delete` each in a hello-world run and both published loan-renewal runs, on the
  specification-unit route, all helpful. E5 changes no prompt, schema, admission rule or repair decision, so this
  is no difference at three runs per case, not a benefit. The new report shape held: `e2e-measures` read all six
  reports and `adjudicate-spec` accepted the five published ones; `reason` and `first_cause` are null in all
  six, as no authority rejection or replaced failure occurred. Evaluations: `evaluations/e2e/2026-11-14T06-58-*`;
  adjudications in `evaluations/adjudications/`.
- **Brittleness counts, E1 to E5 and E8.** "Before" and "Recorded after" are the values the change's own entry
  records; "Now" was measured on 14 November 2026 on the final E5 tree. A cell that says "not recorded" has no
  recorded value.

  | Change | Measure | Before | Recorded after | Now |
  | --- | --- | --- | --- | --- |
  | E1 | Spec YAML lines (`grep -c ""`) | 994 | 883 | 910 |
  | E1 | `use:` lines and `call:` lines in the YAML (`grep -c`) | 166 and 66 | 164 and 44 | 165 and 44 |
  | E1 | Request-lifecycle subgraphs (`model-request-body` references, and `use: request-model` lines) | 6 subgraphs, reached from 17 request sites | none; 17 `request-model` steps | 0 references; 17 steps |
  | E1 | `anyopaque` lines in `model_request_child_bindings.zig` | not recorded | 2 | 2 |
  | E2 | Spec YAML lines | 1,104 | 994 | 910 |
  | E2 | `DataKey` members (`src/domain/pipeline.zig`) | 194 | 170 | 142 |
  | E2 | `entry(` lines in `src/composition/native_workflow_operations.zig` | 166 | 136 | 107 |
  | E3 | Startup and provider-bootstrap sequencing, files and lines | 14 files, 2,157 lines | 2 files, 810 lines | 2 files, 813 lines |
  | E3 | `anyopaque` lines in those sequences' files | 130 | 2 | 2 |
  | E3 | `anyopaque` lines in `src/application/` | not recorded | 105 | 111 |
  | E4 | Registered repair operations (`variantEntry(generic_repair.` lines) | 29 | 4 | 4 |
  | E4 | Action files (`.zig` files under `src/actions`) | 188 | 159 | 159 |
  | E5 | Names for an operation failure, and uses of the old name | 1 name (`OperationExecutionFailed`), 138 uses (40 production files, 3 harness lines) | 57 names; 0 uses of the old name | 57 names; 0 uses of the old name |
  | E5 | `authority` rejection producers, and the reasons they name | 148 sites, no reason | 149 sites, 24 reasons | 149 sites, 24 reasons |
  | E8 | T5.2 raw-string schema-name branches in production (tests) | 19 (89) | 0 (69) | 0 (68) |

  The `code-heuristics` counts, taken with `zig build code-heuristics -- --freeze
  evaluations/request-projection/e5-final` (T5.4 by hand). No retake exists between the one below and now except
  E8's T5.2, so each change's share of these is not recorded.

  | Count (report member) | 2 November 2026, `b38628c` (recorded, SPEC01 T5) | Now |
  | --- | --- | --- |
  | T5.1 model-facing text in tests (`tests_copying_model_text`) | 19 | 19 |
  | T5.2 raw-string schema-name branches (`schema_name_branches`) | 20 (tests 88) | 0 (tests 68) |
  | T5.3 instructions with more than one site (`repeated_instructions`) | 5 at 11 sites | 5 at 11 sites |
  | T5.4 repair steps whose prompt no non-repair step binds | 6 | 6 |
  | T5.5 model- or case-specific branches (`model_or_case_branches`) | 0 | 0 |
  | T5.6 model-facing English outside its owner (`model_text_outside_owner`) | 13 in 4 files | 12 in 4 files |

  **Method.** The `grep -c` and `wc` counts use the pattern in the row on the file named; the `DataKey` members,
  the `src/actions` files, the `anyopaque` lines, the `.authority = .<reason>` producers and the `error{}` members
  were counted by a short script over the same files and patterns; the T5 counts are the tool's, and T5.4 is the
  six `repair-prompt` bindings in `spec.workflow.yaml`, each in a `slot: repair` step, with no non-repair step
  binding it.
  **Reading it.** A later change moves what an earlier one measured, so "Now" minus "Recorded after" is not that
  change's. The YAML's 27 lines between E1's 883 and today's 910 are not attributed in the records (E4 records
  910 after its edits). `anyopaque` lines in `src/application/` rose by 6 since E3: E1 recorded 2 of them (the
  runner-owned child-binding context), and the other 4 are not attributed, because no per-file record exists; the
  files E5 added or rewrote hold none (`step_binding_error.zig`, `workflow_execution.zig`, `repair_owner.zig`,
  `workflow_model_invocation.zig`, `feature_log_activation.zig`, `feature_logging_runtime.zig`), apart from the
  runner's 6 that E4 recorded. T5.1's 19 now include two architecture pins whose literal is a word that also
  occurs in a prompt (the result-schema authority test, E8's rule, and the generic repair operations test, E4's),
  a recorded limit of the tool
  (short absence literals match by substring). E5's gain is in payload-free failure names, which no T5 count
  measures.

## R-A1. Engine-owned release is not adopted

**Not adopted 14 November 2026** (user: "recommendation accepted"; ADR 0030 decision 4a records it): release stays
an explicit YAML step. Engine-owned release needs compiler-derived lifetimes, which are path-sensitive across
loops and joins; it would amend ADRs 0005, 0012, 0030 and 0033 and invariants 25 and 28; and it has no
published-output benefit. About 54 lines of release steps remain in the Spec YAML (E4 rewrote the repair routes
that hold ten of the release sites).
