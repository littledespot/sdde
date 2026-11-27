# ADR 0038: Records name their claims; requirements own their claims; behaviour statements need scenarios

- **Status:** Accepted
- **Date:** 2026-10-25
- **Decision authority:** User decisions, 25 October to 22 November 2026.
- **Amends:** §§12, 12.2, 17.3, 17.5, 21, 22, 22.3, 22.6, 23.1, 24 and 28.6;
  [text-field-composition.md](../contracts/text-field-composition.md);
  [F0100](../features/F0100-SpecWorkflow.md) §5;
  [ADR 0016](0016-configured-json-response-composition.md) (packet guidance);
  [ADR 0019](0019-single-request-debugger.md) (the request description records the
  admission rules below);
  [ADR 0020](0020-derived-exact-reference-lineage.md) (a record names claims; an
  engine-bound criterion's value-repair bound);
  [ADR 0036](0036-source-quoted-claims.md) Decision 3 (the list-item split);
  [ADR 0039](0039-configured-temperatures-and-runaway-resend.md) (a re-sent scenarios
  response passes the same checks);
  [ADR 0047](0047-engine-composed-primary-story.md) (its typed rejection carries
  `edge_case_without_criterion`; the story comparison's only-record exception).

  "One records call per feature" is not adopted: under Decision 1 a group's scenarios are all
  in its own batch.

## Context

When every record silently carried all the claims of its group, the engine couldn't tell
which requirement a record covered. Coverage was satisfied when any record or narrative
field selected the group, so a behaviour could publish with no scenario and nothing caught
it. Coverage gaps could only block.

## Decision

1. **A record names the claims it supports.** A non-entity record in the records
   response carries `claim_ids`: a nonempty unique subset of its batch's group claims,
   offered as a native unique-subset choice.
   - Parsing keeps the named claims in the group's accepted order, never the model's;
     an empty, repeated or foreign selection rejects the unit.
   - The group stays the record's one association (`source_group_ids`), so there is no
     second binding scheme. Citations are derived natively from the named claims.
   - Validation and stored readback require the record's claims to be an ordered
     subset of its group. A whole-group selection is valid.
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
   behaviour statements.
3. **Each such claim takes one engine-bound criterion, written by a second request per
   group.** A records response carries no acceptance criterion: its request excludes the
   kind and offers no criterion requirement, and a records response carrying one rejects.
   Response admission applies no scenario rule. After every group's records are admitted
   and the native deletes (Decision 5) have run, the engine plans each group's slots, and a
   scenarios step follows, before Decision 7's link step:
   - **Slots** are one per distinct claim that a surviving `functional_requirement`,
     `business_rule`, `user_visible_outcome` or `prohibited_behavior` of the batch names,
     in record and claim order. A compound claim is one slot (only a model decomposition
     could split it, which is not adopted). A claim no behaviour statement names has none,
     a scope-only claim and an edge-case-only claim included. A group with no slot makes
     no call.
   - **One request per group**, on the generation slot and the shared generation operations,
     as an initial generation: no invalid candidate exists, so it is not a repair and uses
     no repair slot. The step takes its own native iteration population, the groups with a
     slot. The request offers each slot, numbered from one, with its claim's source text
     and exact values, and no statement, entity, story or other batch's record, so a
     criterion can't copy a statement's wording.
   - **The response is content only:** one item per slot, holding the slot's number, the
     criterion's when and then, and its given where the sources state one (below). The
     result schema selects the numbers as an `exact_members` set, so each appears exactly
     once, and carries no claim, kind or group. A missing, repeated or foreign number, or
     any other property, takes the request's protocol correction. So do items of the
     response that return equal values for given, when and then, compared as returned
     (`equal_items`): the correction names the number of every item in each equal set, so
     one retry can fix them all, as Decision 5's `shared_member` does, in place of the
     `competing_records` block they would meet after the merge. It covers one response's
     own items as returned: equal criteria across groups, equal records of other kinds,
     equality a field-level value repair produces, and items equal only after the typed
     duplicate rule (`equalContent`) normalizes them, such as a string and the same text as
     a one-fragment object, still block.
   - **A criterion's exact copies are its own claim's.** A criterion tests one claim, so it
     may hold an exact copy only of a value that claim's own text holds: the request offers
     each slot the exact values of its own claim, and a copy of another claim's value, such
     as a success message in the criterion of a different requirement, is a defect of the
     criterion's text, not a repair of its claim. That defect takes the existing field-level
     value repair. The slot's own claim may hold several values; the rule compares exact
     values with claims, and judges no wording.
     - **The comparison** is by bytes: a claim holds a value when its text holds those bytes
       (an insertion never does), and a claim that is itself an exact token holds the value
       of equal bytes. It runs on each admitted field of an acceptance criterion, after the
       field's own text policy, and recognizes values group-wide, so a value the slot's
       claim doesn't hold is found wherever the corpus holds it. The typed text issue is
       `foreign_exact`, an exact-copy rejection of that field.
     - **The repair bound** (ADR 0020's S and E; this bullet states it, and §22 points here)
       is the slot's claim, S, plus the values that claim's text holds, in place of the
       table's set equality. The value the defect names adds no claim to it. A repair may
       therefore drop that value, or state a value the slot's claim holds in its place, and
       it keeps every value the criterion already held. A repair that states the value
       again, or another claim's value, is the same defect found again by the full
       validation, so the rejection is typed and retryable, and retry exhaustion fails the
       run; the rule never weakens. The rule applies only to the acceptance criterion the
       engine binds to one claim, at admission, repair and stored readback. An edge case and
       every record whose claims the model chose keep ADR 0020's union and set equality.
   - **A criterion's Given is optional.** A criterion holds a `given` only where the sources
     state a starting situation for its requirement. The scenarios schema requires an
     item's number, `when` and `then` and declares `given` without requiring it; a held
     Given is nonblank, an explicit `null` rejects, and the typed content holds `null` where
     there is none, with the wire omitting it. The shared `given` field guidance, which the
     edge case's own given also reads, says the starting situation is stated without
     assuming the result under test or inventing prerequisites, and that a criterion whose
     sources state none has none; the edge case's own given stays required. The rest of the
     contract holds:
     - **Equality.** An omitted Given is a value of its own for the `distinct` rule and the
       typed duplicate rule: two criteria with equal When and Then that both omit it are
       equal, and one that omits it differs from one that states it (§12.2).
     - **Repair.** An absent Given is no repair target, and no repair adds one or removes
       one; a held Given takes `replace` like any other text field (§22.3).
     - **Rendering.** A criterion without a Given renders `**When** … **Then** …`, with no
       `Given` label and no empty text (§23.1). The offered candidates of the link step show
       a Given only where a criterion holds one.
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
     merged batch; stored readback has no coverage rule. It requires at least one criterion
     for each such claim, so a stored specification whose one criterion names several claims
     still reads back, and a claim it finds without a criterion is an engine defect
     (`scenario_coverage`) that takes no repair.
   - **The acceptance-criterion family** is required of the assembled specification when
     the scenarios step completes, not of a records response.

   Decision 5's partly taken statement, `shared_member`, stays a response-admission
   defect. Request descriptions record that rule, naming only its exclusive and owning
   kinds, and the `distinct` rule, so replay enforces the same admission.
4. **List sources yield one claim per requirement.** ADR 0036 Decision 3's native
   list-item split applies: a claim whose cited lines span several top-level list items
   becomes one quoted claim per item, so a list requirement can be checked on its own.
5. **Requirements own their claims.** In one records batch, a claim is taken for a
   `business_rule`, `user_visible_outcome`, `assumption`, `non_goal` or
   `prohibited_behavior` record when a `functional_requirement` names it, before or after
   that record, or an earlier record of those kinds does. Scenarios are exempt, since they
   test what a statement states.
   - **Repeated statement:** such a record whose every claim is taken restates them, and
     the records validator deletes it natively with no model call (`repeated_statement`).
     It runs after the story comparison (below), so a record restating the story keeps
     that rule, except for a repeat whose own text is defective (below). It is kept when
     it holds an exact copy no other record of the batch holds, so no exact value is lost;
     each delete is decided on the batch it leaves. Deleting it leaves every claim and
     exact copy the batch names in place.
   - **Its text is not judged.** A record the rule deletes never publishes, so a defect in
     its own text, such as a bare exact value in a prose field, is no defect of the
     response: response admission omits it, and the records validator reports the delete in
     its place. Both apply one rule, `statement_ownership`, to the claim lists and the
     exact values recognized in the text, so on the batch as returned a record admission
     exempts is a record the session deletes. A requirement, a record holding the batch's
     only copy of an exact value, a partly taken record and every defect outside a deleted
     record's text are judged as before. A record whose text holds a value that can't be
     identified (an ambiguous or unrecognizable one, text that is not a valid scalar in a
     field that can hold an exact copy, or, at admission, any explicit insertion, which
     unit validation recognizes again as one run where its handle need not survive) is
     never judged deletable, since the keep rule can't be applied, and it supplies no value
     to another record. A recorded request replays with the exemption its record implies.
   - **Order for such a record:** its delete is decided when the unit is validated, ahead
     of the story comparison and the same-kind duplicate checks, which then run on the
     batch it leaves. A behaviour statement that restates the story and alone takes the
     repeat's claims is deleted after the repeat, not before it, so the repeat is lost
     where valid text would have kept it. Deciding it later would leave the exempted defect
     to a unit repair that refuses it (Consequences).
   - **Partly taken statement:** such a record naming taken claims and others too is
     rejected at response admission as `shared_member` at `/records/<i>`. The correction
     offers the record's shape, names the exclusive and owning kinds (`exclusive`), and
     lists every taken claim's naming in such records (`shared`), so one retry can fix them
     all.
   - **Requirements are exempt:** a requirement is never deleted or rejected by this rule,
     so one prose claim holding two obligations may yield two requirements. Deleting the
     second would lose the obligation it alone states.
   - The result-schema rule records the exclusive and owning kinds, as required members,
     and nothing else.
   - This rule is the only comparison between statement records in one batch. §17.5's
     same-kind duplicate rule runs first and is unchanged: an evidence-equivalent duplicate
     is deleted and a competing one blocks as `competing_records`.
   - The records prompt keeps its "at most one" sentence, requirements included.
   - **Story comparison.** A functional requirement, business rule,
     assumption, non-goal, prohibited behaviour or user-visible outcome is compared by its
     typed statement value, using the same typed equality as whole-content duplicates,
     against the primary user story. Acceptance criteria, edge cases and entities compare
     only as whole same-kind content.
     - A record that equals the story is a restatement, deleted natively only when the
       story covers its evidence: the story must cite every source group, claim, citation
       and clarification response the record cites. Deletion uses the same native delete as
       `duplicate_record`, with old-value and revision preconditions and impacted and full
       validation, and makes no model call.
     - A record is never deleted as a restatement when no other record, in its batch or an
       earlier one, names one of its claims (ADR 0047 Decision 4).
     - An uncovered restatement stays as authored. It is neither deleted nor blocked, so
       this comparison can't block a run.
     - The primary user story is never deleted. A functional requirement is never deleted
       as a restatement, because it is a required family.
     - Every same-kind duplicate check runs before any restatement can remove a record:
       within the batch (unit validation) and against earlier batches (the session). A
       competing pair therefore still blocks, even when one of its members also restates
       the story. Repeated statements are decided after both, with the one exception under
       "Order for such a record".
     - Restatements belong to the session's consistency check, after its same-kind checks.
       The session receives the model candidate the checked records came from and binds the
       restated record as the observed old value the native delete requires. The rule is
       `restatement`, so diagnostics distinguish it from an evidence-equivalent
       `duplicate_record`.
     - Paraphrases are not removed, and neither are entities, since deleting an entity
       would change the entity decision.
     - Restatements are removed at admission. Assembly reruns the same-kind rule over the
       combined records. Published-state readback runs neither.
6. **An entity is a name and its groups.** The model writes an entity's name and selects
   the groups that support it; it writes no meaning or relationship text, which restated,
   weakened or added to requirements wherever it stayed open. The engine renders a
   read-only related-statements line on each entity: the functional requirements, business
   rules, user-visible outcomes and prohibited behaviours that share one of its groups, in
   document order ([§23.1](../contracts/23-rendering.md)). It is a display like the source
   line, never provenance, and the entity's sources do not change. Applicability, the
   basis and the entity unit's order are unchanged.
   - Two entities with the same name and different groups are not evidence-equivalent,
     so the native duplicate rule blocks them as `competing_records` (Decision 1; §17.5);
     with equal groups the later one is deleted.
   - Packet guidance has no meaning or relationship entry and no entity repair tail, and
     the required-authority contract has no slot for them and no slot member index.
7. **An edge case is a Given/When/Then scenario of the criterion it links to.** Its Given,
   When and Then are the criterion's. The model writes an edge case's own given (`given`),
   the boundary or exceptional situation, and the claims it supports, and no when or then;
   a records response that carries a `condition`, a `when`, a `then` or an outcome on an
   edge case rejects. The engine prints every edge case as three lines labelled `GIVEN`,
   `WHEN` and `THEN`, and no other label ([§23.1](../contracts/23-rendering.md)). Like the
   source line, the parts it copies are a display, never provenance, and the edge case's
   own given is its only content. An edge case so keeps its criterion's whole scenario and
   adds one circumstance: it shows the criterion's result for a narrower situation. The
   engine never fills an outcome from source lines; copying the linked criterion's Given,
   When and Then, the only targets, is allowed.
   - **Lines:** `GIVEN` is the linked criterion's Given, then the edge case's own given, in
     one line. They are joined by the separator §23.1 derives from a clause's ending (`, `,
     or one space after terminal punctuation), applied here between the two texts, so
     neither text's bytes change. Where the linked criterion has no Given (Decision 3),
     `GIVEN` is the edge case's own given alone, with no separator: the edge case adds its
     one circumstance to a scenario that states no starting situation. `WHEN` is the
     criterion's When and `THEN` its Then. The copied parts are the criterion's own
     display, exact-value spans included.
   - **Readback** takes the own given as the text after the copied Given and the
     separator. It rejects a `GIVEN` line that doesn't begin with a criterion's Given, a
     When or Then that is no criterion's own, and a line under any other label.
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
     coverage rule would ask for a criterion for a claim no behaviour statement names. The
     engine writes a criterion for every claim a behaviour statement names (Decision 3), so
     only an edge case naming claims no behaviour statement names, a scope-only claim for
     one, reaches this block, after every generation call.
   - **Stored form.** An edge case holds its `given` and the ID of the criterion it links
     to. The stored link is named `outcome_of`, and the link vocabulary stays "outcome
     link". State readback checks it against the same candidate rule: a missing, dangling
     or non-candidate link rejects. Packet guidance has no edge outcome or `condition`
     entry, and the required-authority contract has no slot for one.

## Consequences

- **Limits.**
  - Requirements written in one prose sentence stay one claim, so the scenario rule
    can't separate them.
  - The rule checks links, not meaning: an acceptance criterion that names a claim
    but doesn't test it passes. No review runs after generation (ADR 0023); the human who
    reviews and edits `spec.md` judges meaning.
  - **An edge case's outcome (Decision 7)** is only as right as its link. Sharing a claim
    makes a criterion a candidate, not the one that governs the condition: with several
    candidates the model's closed choice decides, and a wrong choice prints a wrong
    outcome with no later check. The printed outcome is the criterion's Then exactly, so
    an edge case that is a boundary of a flow, not a flow of its own, shows that flow's
    result. A single candidate links without a choice. With one criterion per claim
    (Decision 3), an edge case naming one claim has that claim's criterion as its only
    candidate, and one naming several slot claims has one candidate for each and takes the
    model's closed choice.
  - **An edge case as a scenario (Decision 7).**
    - The link decides which scenario an edge case narrows. The model writes the edge
      case's own given before any criterion exists (Decision 3) and never sees the Given it
      will follow, and nothing checks that the two are compatible: a wrong link or a
      contradicting given prints as a `GIVEN` whose two parts disagree, which the human who
      reviews `spec.md` judges. Where the criterion's Given doesn't carry the condition that
      governs its Then, an outcome the source doesn't support still prints.
    - The guidance text for the edge case's `given` is the registered `given` entry.
      Packet guidance holds exactly one text for each registered key (ADR 0016), and a key
      follows a field's name across record families (`src/domain/packet_guidance.zig`), so
      the edge case's `given` shares the criterion's text, which describes a whole starting
      situation, where the edge case's own given is one added circumstance; the edge-case
      family's own text sits beside it in the same request. The edge case's text keeps the
      criterion's sentence about a criterion with no starting situation: a records request
      without it changed what the call wrote, dropping requirement claims and weakening
      obligations. A separate text would need a key by family and field, a native registry
      change, and must carry that sentence or be decided on scored repeated runs of both
      development cases. How the model phrases a given is otherwise unmeasured.
    - An edge case repeats its criterion's Given and When, so it can't carry a second flow of
      a claim (a cost of Decision 3's slot criteria, below), and a defect in a criterion's
      Given or When repeats in each edge case linked to it. A linked Then's defect is filed
      once, on the criterion; that covers only the Then.
    - Two edge cases with the same own given and different claims block as
      `competing_records` (below), though under different criteria they would print different
      scenarios.
    - An edit to a criterion's Given or When makes each linked edge case's lines differ from
      the projection, so readback rejects them.
    - The Given/When/Then form of an edge case is built and kept; its benefit is not
      demonstrated, because the measured sets wrote no edge case.
  - A lead-in condition is split from the items it governs. "Unless the borrower is
    staff:" followed by two items becomes three claims, and each item claim reads as
    unconditional; the condition survives only as its own claim.
  - **Coverage counts the claims each record names.** A record doesn't carry its whole
    group into coverage, which has two effects:
    - a claim no record names, in a group no narrative field selects, is unmapped and
      blocks with `no_independent_supported_target`;
    - a narrative field that selects a group still maps every claim in it, so a
      corrected response that drops the functional requirement naming a claim passes
      coverage without a scenario.
  - **Repeated statements (Decision 5)** are judged on claim IDs and exact copies, not
    wording:
    - a business rule or prohibition stating a second obligation of an FR's prose claim
      is deleted like a repeat; requirements alone are exempt;
    - scenario slots are planned on the batch the native deletes leave, and a statement
      taken only through a record that the story comparison then deletes is kept;
    - a repeated statement's own text defect takes no correction and no unit repair:
      admission and the validator exempt the record the rule deletes. The text of a
      record the rule keeps, and any defect elsewhere in the response, still take theirs;
    - admission judges the response as returned. If a unit repair then rewrites the text of
      the record that held an exempted statement's exact value, so that it no longer holds
      it, the statement is kept and a composition defect in its text reaches unit repair,
      which refuses it (`InvalidSpecificationRepair`): an operational failure in place of
      the protocol correction admission would have sent. Repairs keep a record's claims,
      and no story-comparison delete runs while the defective statement is in the batch.
      When the statement is deleted first and the holder's repair then drops the value,
      exact-copy coverage (`missing_exact_copy`) catches it if the value is mandatory;
    - the delete reads the text as typed, while admission normalizes text first (recorded,
      not handled). A repeated statement whose normalized form is an exact value no other
      record holds could lose it: coverage fails the run when the value is mandatory, and
      an optional value would be lost silently. It has not been seen.
  - **Identical records naming different claims** are not evidence-equivalent, so the
    native duplicate rule blocks them as `competing_records` instead of deleting one
    (§17.5).
  - **A repeated claim ID** passes the schema (subset selectors don't enforce
    uniqueness) and ends the unit at parsing, as a repeated `signal_ids` entry does.
  - **The slot criteria (Decision 3)** link their claim without checking meaning, like any
    record. A criterion whose content equals another record's with other claims blocks as
    `competing_records` under the existing duplicate rule, except criteria of one
    scenarios response as returned, which take the protocol correction (Decision 3). Binding
    the claim before the model writes closes the routes where the batch names a claim in a
    statement and no scenario, and where one criterion names every claim of its batch
    without testing each one. It costs four things:
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
- **Persistence.** Earlier specification and state versions reject; nothing migrates them.
  A stored specification holding a criterion with another claim's exact copy doesn't read
  back.
