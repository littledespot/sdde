# ADR 0038: Records name their claims; requirements own their claims; behaviour statements need scenarios

- **Status:** Accepted
- **Date:** 2026-10-25
- **Decision authority:** The user's decisions on 25 October 2026 on
  FIX05 (`fixes/Z_FIX05.md` §21, git `194e29a`) B5: "implement B5 as per recommendation", then
  "APPROVED. Implement B5" for four choices:
  1. each record names the claims it supports, picked from its batch's claims, with the
     group staying the record's link to the source;
  2. every claim a functional requirement names must also be named by at least one
     acceptance criterion or edge case in the same batch;
  3. a gap sends the records response back for one of its existing corrections, and the
     run fails if they run out;
  4. claims become one per requirement for list sources by bringing back the list-item
     split.

  Amended 2 November 2026 (SPEC01 D16.1; user: "the above recommendations are approved",
  then "No, behaviour kinds only"): one statement record per claim (Decision 5), and
  coverage for every behaviour statement, not assumptions or non-goals (Decision 2).
  Amended again on 2 November 2026 after the D16.1 set (SPEC01 D16.2; user: "approved",
  then "Yes, exempt FRs"): Decision 5's repeats are deleted natively and requirements are
  exempt.
  Amended on 8 November 2026 (SPEC01 §3 Robustness track; user: "yes as per
  recommendation"): the text of a repeat the owner deletes is not judged (Decision 5);
  and, as the user then decided ("accept both as documented"), the delete order and
  post-admission corner of that change below. The same day (SPEC01 §3 Next item 6; user:
  "Entity lever … is yes and approved", then "yes to all decisions"): an entity is a name
  and its groups (Decision 6). Amended again on 8 November 2026 (SPEC01 §3, the edge-case
  outcome lever; user: "apply recommendations", "recommendations accepted for 1 to 6", then
  "go"): an edge case's outcome is the Then of an acceptance criterion it links to
  (Decision 7). Amended on 12 November 2026 (SPEC01 Q14 b3; user: "B3 is approved,
  implement"): a scenario gap is the session's, repaired by one acceptance criterion whose
  claim the engine fixes (Decision 3); admission keeps only the partly taken statement
  (Decision 5). Amended again on 12 November 2026 (SPEC01 Q14 b4; user: "approved decisions
  1, 3, 4 and 5", then "Approved five sub-option picks"): a second request per group writes
  one criterion for each claim a behaviour statement names, the engine fixing the claim, and
  an edge case no longer counts as cover (Decisions 2 and 3). Not yet implemented: the code
  still runs the previous amendment. Amended on 13 November 2026 (user: "it must use GIVEN,
  WHEN, THEN, never anything else", one `GIVEN` holding both conditions, then "yes, amendment
  to ADR 0038, do not make any code changes"): an edge case is printed as a Given/When/Then
  scenario of the criterion it links to, and the model writes only its own given
  (Decision 7). Not yet implemented: the code, the workflow assets and the sections this
  amendment names still state the 8 November rule. Amended on 14 November 2026 (SPEC01 Q14
  b4, D14.2; user: "update the documentation with the recommendation"): items of one
  scenarios response with equal content take the request's protocol correction, naming every
  item's number, in place of the `competing_records` block (Decision 3). To be implemented
  with the b4 amendment.
- **Amends:**
  - [ADR 0020](0020-derived-exact-reference-lineage.md): a non-entity record's response
    names claims; its canonical selection is a subset of its one group;
  - [ADR 0036](0036-source-quoted-claims.md) Decision 3: the list-item split is
    reinstated;
  - [ADR 0019](0019-single-request-debugger.md): request descriptions advance to
    `model-request-debug/v12`;
  - §12 (record binding and `model-request-debug/v12`), §17.3 and §17.5 (record
    authoring and coverage), §22 (a scenario gap takes protocol correction), F0100 and
    the §32 index.
  - Since 2 November 2026: §12 and §22 also take a `shared_member` correction, and §17
    and §22 a native delete of a repeated statement; request descriptions advance to
    `model-request-debug/v16` and reports to `spec-e2e-report/v14`;
    [ADR 0035](0035-cross-kind-restatement.md) keeps only its story comparison and its
    same-kind delete.
  - Since 8 November 2026: [text-field-composition.md](../contracts/text-field-composition.md),
    §12, §22 and §17 exempt a repeated statement from text admission and repair. That
    change advances no version: first requests are byte-identical, and a recorded request
    replays with the exemption its recorded coverage implies.
  - Since 8 November 2026, Decision 6 (an entity is a name and its groups): §23.1 (the
    related-statements line), §24 (`specification-state/v23`, `specification/v4`) and
    §17; [ADR 0016](0016-configured-json-response-composition.md) (`packet-guidance/v4`);
    [ADR 0020](0020-derived-exact-reference-lineage.md),
    [ADR 0023](0023-advisory-post-generation-review.md) and
    [ADR 0024](0024-native-exact-token-authority.md) (the content and state versions);
    [ADR 0035](0035-cross-kind-restatement.md) (entities, not entity descriptions); and
    [ADR 0041](0041-failed-run-incomplete-publication.md) (its state version moves to
    v24). The entities schema and prompt change, and every generation request's shared
    guidance loses one sentence.
  - Since 8 November 2026, Decision 7 (an edge case's outcome is a linked criterion's Then):
    §17.3 (the outcome-link request), §23.1 (the outcome line),
    §24 (`specification-state/v24`, `specification/v5`), the §32 index and F0100 §5;
    [ADR 0016](0016-configured-json-response-composition.md) (`packet-guidance/v5`);
    [ADR 0047](0047-engine-composed-primary-story.md) (its typed rejection gains a reason);
    and [ADR 0041](0041-failed-run-incomplete-publication.md) (its state version moves to
    v25). The records schema loses the edge case's outcome, the required-authority contract
    is 4, and a link-scenarios step with its own prompt and result schema follows
    generation.
  - Since 12 November 2026, Decision 3's first amendment: admission no longer applies the
    scenario rule or the `uncovered_member` correction; request descriptions advance to
    `model-request-debug/v18` ([ADR 0019](0019-single-request-debugger.md): a recorded rule
    names only its exclusive and owning kinds) and reports to `spec-e2e-report/v17`.
  - The scenario-slot amendment of 12 November 2026, Decisions 2 and 3: §12 (the scenario
    rule is met by construction), §17.3 and §17.5 (a scenarios step and its request), §22
    (the claim-bound insertion is gone), F0100 §5;
    [ADR 0039](0039-configured-temperatures-and-runaway-resend.md) (a re-sent scenarios
    response passes the same checks); and
    [ADR 0047](0047-engine-composed-primary-story.md) (its three model task types become
    four generation task types). No record shape or content version changes; request
    descriptions, reports, state and packet guidance advance only if implementation changes
    a closed member, in the same change (SPEC01 §2 rule 12).
  - The edge-case scenario amendment of 13 November 2026, Decision 7: §17.3 (the edge case's
    one model-written field), §23.1 (the edge-case lines, the separator's use between two
    texts, and their readback), §24 (the edge-case shape),
    [text-field-composition.md](../contracts/text-field-composition.md) (the edge-case field
    row) and F0100 §5; [ADR 0016](0016-configured-json-response-composition.md) (packet
    guidance loses its `condition` entry);
    [ADR 0041](0041-failed-run-incomplete-publication.md) (its reserved state version moves
    on); and every document that states the versions below. The records schema's edge case
    holds `given` in place of `condition`. In the implementing change the canonical content,
    the state and the packet guidance advance from the versions then current, and so do the
    required-authority contract, reports and request descriptions wherever the rename removes
    or renames one of their closed members; earlier versions reject.
  - The equal-criteria amendment of 14 November 2026, Decision 3: §12.2 (the admission
    constraints that stay native), §17.3 (the scenarios response's admission), §22.6 (the
    corrections that name extra fields), [ADR 0019](0019-single-request-debugger.md) (the
    request description records the rule) and [ADR 0039](0039-configured-temperatures-and-runaway-resend.md)
    (a re-sent scenarios response passes the same checks). In the implementing change,
    request descriptions advance, and reports advance if its rejection reason is a closed
    report member.

  "One records call per feature", part of FIX05's B5 proposal, is not adopted: under
  Decision 1 a group's scenarios are all in its own batch, and both live cases already
  form one group. The overall design remains **Proposed design**.

## Context

Every record silently carried all the claims of its group, so the engine couldn't tell
which requirement a record covered. Coverage was satisfied when any record, the story or
even the title selected the group, so loan-renewal's refusal behaviour has had no
scenario in every evaluated publication, and nothing caught it. Coverage gaps could
only block.

## Decision

1. **A record names the claims it supports.** A non-entity record in the records
   response carries `claim_ids`: a nonempty unique subset of its batch's group claims,
   offered as a native unique-subset choice.
   - Parsing keeps the named claims in the group's accepted order, never the model's;
     an empty, repeated or foreign selection rejects the unit.
   - The group stays the record's one association (`source_group_ids`), so there is no
     second binding scheme. Citations are derived natively from the named claims.
   - Validation and stored readback require the record's claims to be an ordered
     subset of its group. A whole-group selection is still valid, so earlier stored
     states keep reading back.
   - Entities keep selecting whole groups. Repairs stay content-only and keep the
     record's claims; the records whose claims the engine sets are Decision 3's slot
     criteria, and the model writes only their content. The records response carries no
     acceptance criterion.
2. **A behaviour statement's claims need a scenario.** In one records batch, every
   claim a `functional_requirement`, `business_rule`, `user_visible_outcome` or
   `prohibited_behavior` names is named by an `acceptance_criterion`; the engine writes
   exactly one per claim and binds it (Decision 3). An `edge_case` is not cover: its outcome
   is a criterion's Then (Decision 7), so it adds no scenario of its own. Assumptions and
   non-goals are scope statements that no scenario tests, so they need none. The rule
   needs no claim categories or keywords: title and purpose claims aren't named by
   behaviour statements. (Functional requirements only, until 2 November 2026; before the
   scenario-slot amendment an edge case counted as cover.)
3. **Each such claim takes one engine-bound criterion, written by a second request per
   group** (amended 12 November 2026; before the amendment a gap in the first response was
   repaired by one insert per claim, and before that admission rejected it as
   `uncovered_member`). A records response carries no acceptance criterion: its request
   excludes the kind and offers no criterion requirement. After every group's records are
   admitted and the native deletes (Decision 5, ADR 0035) have run, the engine plans each
   group's slots, and a scenarios step follows, before Decision 7's link step:
   - **Slots** are one per distinct claim that a surviving `functional_requirement`,
     `business_rule`, `user_visible_outcome` or `prohibited_behavior` of the batch names,
     in record and claim order. A compound claim is one slot (only a model decomposition
     could split it, which is not adopted). A claim no behaviour statement names has none,
     a scope-only claim and an edge-case-only claim included. A group with no slot makes
     no call.
   - **One request per group**, on the generation slot and the shared generation subgraph,
     as an initial generation: no invalid candidate exists, so it is not a repair and uses
     no repair slot. The step takes its own native iteration population, the groups with a
     slot. The request offers each slot, numbered from one, with its claim's source text
     and exact values, and no statement, entity, story or other batch's record, so a
     criterion can't copy a statement's wording (SPEC01 D12.1).
   - **The response is content only:** one item per slot, holding the slot's number and the
     criterion's given, when and then. The result schema selects the numbers as an
     `exact_members` set, so each appears exactly once, and carries no claim, kind or
     group. A missing, repeated or foreign number, or any other property, takes the
     request's protocol correction. So do items of the response as returned that share
     equal content (the duplicate rule's `equalContent`): the correction names the number
     of every item in each equal set, so one retry can fix them all, as Decision 5's
     `shared_member` does, in place of the `competing_records` block they would meet after
     the merge (14 November 2026). It covers one response's own items as returned: equal
     criteria across groups, equal records of other kinds, and equality a field-level
     value repair produces still block.
   - **The engine binds** each criterion's kind (`acceptance_criterion`), claims (the
     slot's one claim) and group (the batch's), and appends the criteria to the group's
     batch in slot order, so the batch spans both responses. The merged batch takes full
     unit validation: the duplicate, restatement, exact-copy and text checks, with
     scenarios exempt from Decision 5's repeated-statement rule. A defect in a written
     criterion's text takes the existing field-level value repair under §22's preconditions,
     retry limits and impacted and full validation, which never changes its claim, kind or
     group. The step's own `retry-limit` bounds its protocol corrections, ADR 0039's re-send
     applies, and exhaustion fails the run. No repair inserts or replaces a whole criterion,
     and no edge case is written here.
   - **Coverage is met by construction.** The session's scenario-coverage check stays on the
     merged batch and at readback. It requires at least one criterion for each such claim,
     so a stored specification whose one criterion names several claims still reads back,
     and a claim it finds without a criterion is an engine defect (`scenario_coverage`)
     that takes no repair.
   - **The acceptance-criterion family** is required of the assembled specification when
     the scenarios step completes, not of a records response.

   Decision 5's partly taken statement, `shared_member`, stays a response-admission
   defect, and request descriptions record that rule so replay enforces the same admission
   (from `model-request-debug/v12`; its covered and covering kinds left with
   `model-request-debug/v18`).
4. **List sources yield one claim per requirement.** ADR 0036 Decision 3's native
   list-item split is reinstated: a claim whose cited lines span several top-level
   list items becomes one quoted claim per item, so a list requirement can be checked
   on its own. Its withdrawal rested on a wrong reading: the same five-claim input
   produced both 2 and 304 records, so claim count wasn't driving record inflation.
5. **Requirements own their claims** (2 November 2026, amended the same day). In one
   records batch, a claim is taken for a `business_rule`, `user_visible_outcome`,
   `assumption`, `non_goal` or `prohibited_behavior` record when a
   `functional_requirement` names it, before or after that record, or an earlier record
   of those kinds does. Scenarios are exempt, since they test what a statement states.
   - **Repeated statement:** such a record whose every claim is taken restates them, and
     the records validator deletes it natively with no model call (`repeated_statement`;
     user, 2 November 2026: "approved"). It runs after ADR 0035's story comparison, so a
     record restating the story keeps that rule, except for a repeat whose own text is
     defective (below). It is kept when it holds an exact copy
     no other record of the batch holds, so no exact value is lost (user: "Yes, keep
     it"); each delete is decided on the batch it leaves. Deleting it leaves every claim
     and exact copy the batch names in place.
   - **Its text is not judged** (user, 8 November 2026: "yes as per recommendation"). A
     record the rule deletes never publishes, so a defect in its own text, such as a bare
     exact value in a prose field, is no defect of the response: response admission omits
     it, and the records validator reports the delete in its place. Both apply one rule,
     `statement_ownership`, to the claim lists and the exact values recognized in the
     text, so on the batch as returned a record admission exempts is a record the session
     deletes. A requirement, a record holding the batch's only copy of an exact value, a
     partly taken record and every defect outside a deleted record's text are judged as
     before. A record whose text holds a value that can't be identified (an ambiguous or
     unrecognizable one, text that is not a valid scalar in a field that can hold an exact
     copy, or, at admission, any explicit insertion, which unit validation recognizes again
     as one run where its handle need not survive) is never judged deletable, since the
     keep rule can't be applied, and it supplies no value to another record.
   - **Order for such a record** (user, 8 November 2026: "accept both as documented"): its
     delete is decided when the unit is validated, ahead of ADR 0035's comparisons, which
     then run on the batch it leaves. A behaviour statement that restates the story and
     alone takes the repeat's claims is deleted after the repeat, not before it, so the
     repeat is lost where valid text would have kept it. Deciding it later would leave the
     exempted defect to a unit repair that refuses it (below).
   - **Partly taken statement:** such a record naming taken claims and others too is
     rejected at response admission as `shared_member` at `/records/<i>`. The correction
     offers the record's shape, names the exclusive and
     owning kinds (`exclusive`), and lists every taken claim's naming in such records
     (`shared`), so one retry can fix them all (user: "Yes, list every location").
   - **Requirements are exempt** (user, 2 November 2026: "Yes, exempt FRs"): a
     requirement is never deleted or rejected by this rule, so one prose claim holding
     two obligations may yield two requirements. Deleting the second would lose the
     obligation it alone states.
   - The result-schema rule records the exclusive and owning kinds, as required members;
     since 12 November 2026 they are all it records (Decision 3).
   - It replaces ADR 0035's comparison between records in one batch (user: "Yes, Q16
     replaces it"). ADR 0035's same-kind delete runs first and is unchanged.
   - The records prompt keeps its "at most one" sentence, requirements included, as the
     rule's first version (SPEC01 D16.1) had it (user: "Yes, keep it").
6. **An entity is a name and its groups** (8 November 2026; user: "Entity lever … is yes
   and approved", then "yes to all decisions"). The model writes an entity's name and
   selects the groups that support it; it writes no meaning or relationship text, which
   restated, weakened or added to requirements wherever it stayed open (SPEC01 §3). The
   engine renders a read-only related-statements line on each entity: the functional
   requirements, business rules, user-visible outcomes and prohibited behaviours that
   share one of its groups, in document order ([§23.1](../contracts/23-rendering.md)). It
   is a display like the source line, never provenance, and the entity's sources do not
   change. Applicability, the basis and the entity unit's order are unchanged.
   - Two entities with the same name and different groups are not evidence-equivalent,
     so the native duplicate rule blocks them as `competing_records` (Decision 1,
     ADR 0035 Decision 3); with equal groups the later one is deleted.
   - The canonical content is `specification/v4` and the state `specification-state/v23`;
     earlier versions reject. `packet-guidance/v4` drops the meaning and relationship
     entries and the entity repair tail; the required-authority contract is 3 and loses
     those slots and the slot member index.
7. **An edge case is a Given/When/Then scenario of the criterion it links to** (8 November
   2026; user: "apply recommendations", "recommendations accepted for 1 to 6", then "go": its
   outcome is the criterion's Then. Amended 13 November 2026; user: "it must use GIVEN, WHEN,
   THEN, never anything else": its Given and When are the criterion's too). The model writes
   an edge case's own given, the boundary or exceptional situation, and the claims it
   supports, and no when or then. Before 8 November it also wrote the outcome: the free
   text restated a criterion's result and dropped part of it wherever it stayed open (the
   loan-renewal edge case that extended the due date "by fourteen days", without
   "calendar", "existing" or the new due date, in four of the last six runs; SPEC01 §3).
   Before 13 November its one field was `condition`, printed alone above the criterion's
   Then, so an edge case could pair a situation the criterion doesn't cover with the
   criterion's result: a loan past its due date printed the refusal the source gives only an
   inactive or previously renewed loan, a material `unsupported_addition` (evaluation
   `2026-11-12T20-18-32Z-0e01cf8809886860bdd3257af99631e9`, D2). The engine prints every
   edge case as three lines labelled `GIVEN`, `WHEN` and `THEN`, and no other label
   ([§23.1](../contracts/23-rendering.md) follows at implementation). Like the source line,
   the parts it copies are a
   display, never provenance, and the edge case's own given is its only content. An edge
   case so keeps its criterion's whole scenario and adds one circumstance: it shows the
   criterion's result for a narrower situation. The 7 November rejection of an
   engine-written outcome concerned filling it from source lines; copying the linked
   criterion's Given, When and Then, the only targets, is allowed.
   - **Lines:** `GIVEN` is the linked criterion's Given, then the edge case's own given, in
     one line. They are joined by the separator §23.1 derives from a clause's ending (`, `,
     or one space after terminal punctuation), applied here between the two texts, so
     neither text's bytes change. `WHEN` is the criterion's When and `THEN` its Then. The
     copied parts are the criterion's own display, exact-value spans included.
   - **Candidates:** the acceptance criteria of the edge case's own records batch that name
     at least one of its claims, across both of its group's responses (Decision 3). They are
     found natively when the scenarios step completes; no link crosses a batch.
   - **One candidate** is the link; no model call. **Two or more** make one closed model
     request per edge case, in a `link-scenarios` step after generation: the request offers
     those criteria, numbered, with their given, when and then, and the answer is one offered
     id, never text and never a record. The result schema admits only the offered ids, so a
     bad answer takes the request's protocol correction and exhaustion fails the run.
   - **None** blocks the run with the typed rejection `edge_case_without_criterion`
     (ADR 0047's rejection), naming the edge case's group and claims. Deleting the edge case
     would lose a stated condition, which Decision 5 never does to a scenario, and a second
     coverage rule would ask for a criterion for a claim no behaviour statement names. The engine writes a criterion
     for every claim a behaviour statement names (Decision 3), so only an edge case naming
     claims no behaviour statement names, a scope-only claim for one, reaches this block,
     after every generation call. Before the scenario-slot amendment an edge case counted as
     cover, so a claim that only an edge case named passed the scenario rule and blocked
     here too; of
     the 31 edge cases in the 26 retained loan-renewal runs, 3 had no such criterion (two
     runs, both on 7 November builds), 20 had one and 8 had several, and hello-world wrote
     none.
   - The canonical content is `specification/v5` and the state `specification-state/v24`: an
     edge case keeps its `condition` and holds the ID of the criterion it links to, which
     state readback checks against the same candidate rule. Earlier versions reject.
     `packet-guidance/v5` drops the edge outcome entry; the required-authority contract is 4
     and loses that slot. ADR 0041's state version moves to v25. Under the 13 November 2026
     amendment the edge case holds `given` in place of `condition`; the amendment list above
     says which versions advance.

## Consequences

- **Limits.**
  - Requirements written in one prose sentence stay one claim, so the scenario rule
    can't separate them.
  - The rule checks links, not meaning: an acceptance criterion that names a claim
    but doesn't test it passes. Since 1 November 2026 no review runs after generation
    (ADR 0023); the human who reviews and edits `spec.md` judges meaning.
  - **An edge case's outcome (Decision 7)** is only as right as its link. Sharing a claim
    makes a criterion a candidate, not the one that governs the condition: with several
    candidates the model's closed choice decides, and a wrong choice prints a wrong
    outcome with no later check. The printed outcome is the criterion's Then exactly, so
    an edge case that is a boundary of a flow, not a flow of its own, shows that flow's
    result. A single candidate links without a choice. With one criterion per claim
    (Decision 3), an edge case naming one claim has that claim's criterion as its only
    candidate, and one naming several slot claims has one candidate for each and takes the
    model's closed choice.
  - **An edge case as a scenario (Decision 7, 13 November 2026).**
    - The link still decides which scenario an edge case narrows. The model writes the edge
      case's own given before any criterion exists (Decision 3) and never sees the Given it
      will follow, and nothing checks that the two are compatible: a wrong link or a
      contradicting given prints as a `GIVEN` whose two parts disagree, which the human who
      reviews `spec.md` judges. Where the criterion's Given doesn't carry the condition that
      governs its Then, an outcome the source doesn't support still prints.
    - The guidance text for the edge case's `given` is not decided here. Packet guidance
      holds exactly one text for each registered key (ADR 0016), and the `given` text
      describes a criterion's whole starting situation, where the edge case's own given is
      one added circumstance. The implementing change decides the key and its text on
      repeated runs; how the model phrases a given is unmeasured.
    - An edge case repeats its criterion's Given and When, so it can't carry a second flow of
      a claim (a cost of Decision 3's slot criteria, below), and a defect in a criterion's
      Given or When repeats in each edge case linked to it. The 9 November ruling that files
      a linked Then's defect once, on the criterion, covers only the Then.
    - Two edge cases with the same own given and different claims still block as
      `competing_records` (below), though under different criteria they would print different
      scenarios.
    - One line holds a copied part and the edge case's own text, so readback takes the own
      given as the text after the copied Given and the separator, and a `GIVEN` line that
      doesn't begin with them rejects. An edit to a criterion's Given or When makes each
      linked edge case's lines differ from the projection, so readback rejects them.
    - The amendment rests on one scored run, and hello-world wrote no edge case in the
      retained runs. Its benefit is not demonstrated, and it is kept or reverted on scored
      repeated runs of both development cases (AGENTS.md "Model output, prompts and
      evidence").
  - **Two edge cases with one condition** and different claims are no longer told apart by
    their outcomes: like any single-field record they block as `competing_records`.
  - A lead-in condition is split from the items it governs. "Unless the borrower is
    staff:" followed by two items becomes three claims, and each item claim reads as
    unconditional; the condition survives only as its own claim.
  - **Coverage now counts the claims each record names.** A record no longer carries
    its whole group into coverage, which has two effects:
    - a claim no record names, in a group no narrative field selects, is unmapped and
      blocks with `no_independent_supported_target` (before, any record of its batch
      carried it);
    - a narrative field that selects a group still maps every claim in it, so a
      corrected response that drops the functional requirement naming a claim passes
      coverage without a scenario.
  - **Repeated statements (Decision 5)** are judged on claim IDs and exact copies, not
    wording:
    - a business rule or prohibition stating a second obligation of an FR's prose claim
      is deleted like a repeat; requirements alone are exempt;
    - scenario slots are planned on the batch the native deletes leave, and a statement
      taken only through a record that ADR 0035 then deletes as a story restatement is
      kept;
    - a repeated statement's own text defect takes no correction and no unit repair:
      admission and the validator exempt the record the rule deletes. The text of a
      record the rule keeps, and any defect elsewhere in the response, still take theirs;
    - admission judges the response as returned (user, 8 November 2026: "accept both as
      documented"). If a unit repair then rewrites the text of the record that held an
      exempted statement's exact value, so that it no longer holds it, the statement is
      kept and a composition defect in its text reaches unit repair, which refuses it
      (`InvalidSpecificationRepair`): an operational failure in place of the protocol
      correction admission would have sent. Repairs keep a record's claims, and no ADR 0035
      delete runs while the defective statement is in the batch. When the statement is
      deleted first and the holder's repair then drops the value, exact-copy coverage
      (`missing_exact_copy`) catches it if the value is mandatory;
    - the delete reads the text as typed, while admission normalizes text first (user, 8
      November 2026: "apply recommendations"; recorded, not handled). A repeated statement
      whose normalized form is an exact value no other record holds could lose it: coverage
      fails the run when the value is mandatory, and an optional value would be lost
      silently. It has not been seen.
  - **Identical records naming different claims** are not evidence-equivalent, so the
    native duplicate rule blocks them as `competing_records` instead of deleting one
    (ADR 0035 Decision 3).
  - **A repeated claim ID** passes the schema (subset selectors don't enforce
    uniqueness) and ends the unit at parsing, as a repeated `signal_ids` entry does.
  - **The slot criteria (Decision 3)** link their claim without checking meaning, like any
    record. A criterion whose content equals another record's with other claims blocks as
    `competing_records` under the existing duplicate rule, except criteria of one
    scenarios response as returned, which take the protocol correction (Decision 3). Binding the claim
    before the model writes closes the routes where the batch names a claim in a statement
    and no scenario, and where one criterion names every claim of its batch without testing
    each one (SPEC01 Q14 b4). It costs four things:
    - each criterion is another restatement, written without the statement, that can lose
      part of its claim or add what the source doesn't state;
    - the engine writes one criterion per claim, so a prose claim holding several flows,
      such as a success and a refusal, has one criterion to carry them, and a second flow of
      the same claim can only be an edge case, whose outcome is a criterion's Then. Whether
      a criterion carries every flow of its claim is judged by the human who reviews
      `spec.md`;
    - a compound claim is one slot, so one criterion carries all its parts;
    - the correction for equal criteria can push the model to invent a difference between
      two claims that state no result of their own, an addition no check sees.
- **Persistence.** Decisions 1 to 5 left the canonical record shape unchanged, so they
  changed no specification or state version; the generation schema's records gained a
  required `claim_ids`. Decision 6 changed the entity shape, so it took
  `specification/v4` and `specification-state/v23`. Decision 7 changed the edge-case
  shape, so it took `specification/v5` and `specification-state/v24`. Decision 3's
  12 November amendment changed no record shape and no specification or state version; the
  recorded admission rule took `model-request-debug/v18`, and the report's closed rejection
  members `spec-e2e-report/v17`. The scenario-slot amendment changes no record shape or
  content version; the amendment list above says when the other versions advance. The
  edge-case scenario amendment renames the edge case's one field, and the amendment list
  says which versions advance.
- **Tests.**
  - The result-schema rule: admitted (a value only an exclusive item names, ungoverned
    kinds, empty), kept by clones, and invalid configurations rejected; admission
    requires no scenario.
  - Records: named subsets parse into group order; empty, repeated and foreign
    selections reject; stored readback accepts a canonical subset and rejects one out
    of group order; the records packet carries the rule, and admission admits a
    functional requirement, business rule, user-visible outcome or prohibited behavior
    whose claim no scenario names; identical records naming different claims block.
  - Coverage: a named claim maps, an unnamed claim in an unselected group blocks, and a
    narrative selection maps it.
  - Scenario slots (Decision 3, 12 November 2026):
    - the planner returns one slot per distinct claim a surviving behaviour statement names,
      in record and claim order: two claims of one statement are two slots, a claim two
      statements name is one, and a scope-only claim, an edge-case-only claim and a claim no
      statement names have none; a group with no slot makes no request; in an unrelated
      domain, one requirement naming six claims gives six slots;
    - the records request excludes the criterion kind and offers no criterion requirement,
      and a records response carrying a criterion rejects;
    - the scenarios request offers the slots numbered from one with only each claim's
      source text and exact values, and no statement or other batch; its result schema
      selects the numbers as an exact-member set and carries no claim, kind or group; a
      missing, repeated or foreign number, or a claim, kind or group, rejects, and replay
      restores the selection;
    - items of one scenarios response with equal content, a pair and a set of three, take
      one protocol correction naming every number of each set, and an accepted retry
      publishes; items that differ in any of given, when or then don't; equal criteria
      across groups, and a pair a field-level value repair makes equal, still block as
      `competing_records`;
    - the engine fixes each criterion's kind, claim and group and appends the criteria to
      the batch in slot order; the merged batch validates, equal content naming other
      claims in an earlier batch blocks as `competing_records`, and a text defect in a
      written criterion takes the field-level value repair and keeps its claim;
    - an edge case is not cover: a claim only an edge case names has no slot, and the edge
      case still blocks with `edge_case_without_criterion`, while an edge case naming one
      behaviour claim links natively to that claim's criterion with no model request;
    - a merged batch lacking a claim's criterion reports `scenario_coverage` and takes no
      repair, and a stored specification whose one criterion names several claims reads
      back;
    - scripted records responses publish with one engine-bound criterion per behaviour
      claim, for one group and for several, and with a re-sent scenarios runaway, and no
      records response is asked for a scenario.
  - Replay: a recorded rule round-trips, admits an uncovered response, and a record
    that doesn't fit the captured schema is refused.
  - Requirements own their claims (Decision 5):
    - at the result-schema rule, each value in one exclusive item is admitted, an
      exclusive kind with no scenario is admitted, ungoverned items may repeat a value,
      owning items are unconstrained, and an exclusive item whose every value is taken,
      by an owning item before or after it or an earlier exclusive item, is admitted;
    - an exclusive item naming taken and untaken values, of another kind or the same
      kind, is rejected at the item, and replay restores the rule;
    - the correction lists every taken value's naming in such items (several items, two
      in one item, behind an opening artefact, none in a wholly taken item), and a
      response whose first such item differs, whose only shared item is wholly taken, or
      with none is refused;
    - exclusive or owning kinds that are missing, repeat, overlap each other, or aren't
      offered reject, and so does a rule on arrays nested in an outer array;
    - a recorded rule without its exclusive or owning kinds doesn't decode;
    - at the records packet, every non-requirement statement kind rejects when partly taken,
      by a requirement before or after it or an earlier statement; wholly taken ones and
      two requirements sharing a claim are admitted;
    - in the session, a batch with outcomes restating requirements before and after them
      and a second requirement on one claim has both outcomes deleted natively, one at a
      time, refuses a model value for the delete, and keeps the requirements and
      scenarios;
    - a repeated statement holding the batch's only copy of an exact value is kept; one
      whose value a requirement also holds is deleted; of two holders, the first goes and
      the last stays;
    - against the real records schema, a partly taken record's correction locates and
      outlines the record node and lists the taken naming;
    - a scripted records response that restates a requirement as a business rule
      publishes with the rule deleted and no correction. Every scripted records batch has
      one claim, so a partly taken record is proven at admission only;
    - the text of a repeated statement is not judged (8 November 2026):
      - at the rule, a statement taken by a requirement before or after it, or by an earlier
        statement, is deleted; one holding the only copy of an exact value, naming an
        untaken, partly taken or no claim, taken only by a later statement, or holding a
        value that can't be identified is kept, and blocks no other record's delete;
      - at admission, the defect of a statement the rule deletes is omitted, for a bare
        value and for another defect alike, and reported for every kept case above and for
        a requirement; an explicit insertion is never read as a held value;
      - at the records validator, the same set reports `repeated_statement` in place of the
        text defect, for a value written as text and for a typed one, a kept record reports
        its defect, which no unit repair can fix, and another record's unidentifiable value
        doesn't stop the delete;
      - the same batches, encoded as the wire carries them and validated as typed records,
        give admission exemptions that are a subset of the validator's deletes, over every
        statement kind and over text that is not a valid scalar; the roles the validator
        gives each kind equal the kinds of the request's statement rule;
      - the statements array is the one array a schema covers, and replay restores it from
        the record: a recorded request exempts a repeat's defect and keeps the first
        statement's, and without the record the same bytes are reported;
      - a scripted response whose extra outcome is only an exact value another record
        holds publishes with the outcome deleted and no correction.
  - An entity is a name and its groups (Decision 6): the related-statements line lists
    the statements sharing a group and neither a scenario, a scope statement, an entity
    nor a statement of another group; the line and the `Source:` line render and read
    back; state `v22` rejects; identical entities of different groups block.
  - An edge case's outcome (Decision 7):
    - the candidates of an edge case are the criteria of its own batch that share a claim:
      one links natively, several are one pending choice, none cannot be linked, and a
      criterion of another batch is never a candidate;
    - the request offers the candidates numbered from one with their given, when and then,
      and nothing of another batch; its result schema admits only the offered ids and no
      text, and a choice outside the offer, a stale request and a malformed answer reject;
      with two candidates and with three in an unrelated domain, the answer's id names its
      own criterion and the rendered outcome is that criterion's Then;
    - the wire carries no outcome: the records response rejects an `expected_outcome`;
    - an outcome edited in the rendering parses, yet differs from the render of the content's
      projection, which publication compares; the state round-trips at v24, rejects v23, and
      readback rejects an edge case whose link is missing, dangling or not a candidate;
    - scripted runs link natively; by one closed request per pending edge case, over three
      source groups with the answers alternating between the last and the first criterion
      offered, so each edge case prints its own answer's Then, the loop runs more than once and
      the persisted links read back; and block with the typed rejection when a batch has an
      edge case and no criterion. Each request is projected as a closed choice with its own
      prompt, and offered ids differ from unit positions in the domain cases.
    - an edge case as a scenario (13 November 2026, not yet implemented):
      - the rendering shows exactly the `GIVEN`, `WHEN` and `THEN` lines: the `GIVEN` is the
        linked criterion's Given, the separator and the edge case's own given, and the `WHEN`
        and `THEN` are the criterion's own, for a native link, for a chosen one and in an
        unrelated domain; a criterion's Given with and without terminal punctuation each
        takes the renderer's separator, and no text's bytes change;
      - the records request projects the edge case's `given` and no `condition`, and the
        records response rejects a `condition`, a `when` and a `then` on an edge case; a
        guidance resource that still carries `condition` rejects, and the field inventory
        covers the edge case's `given`;
      - readback recovers the own given from the text after the copied Given, also when the
        own given equals or begins with the copied Given, and in an unrelated domain; it
        rejects an edited copy of the Given, When or Then, a `GIVEN` line that doesn't begin
        with the copied Given, and a `CONDITION` or `EXPECTED OUTCOME` line;
      - the content, state and packet guidance round-trip at their new versions and reject
        the previous ones;
      - a scripted run publishes an edge case as its criterion's scenario, for a native link
        and for a chosen one.
  - The list-item split: its quoting, structure and omission-repair cases (ADR 0036).
