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

  Amended 2 November 2026 (FIX06 D16.1; user: "the above recommendations are approved",
  then "No, behaviour kinds only"): one statement record per claim (Decision 5), and
  coverage for every behaviour statement, not assumptions or non-goals (Decision 2).
  Amended again on 2 November 2026 after the D16.1 set (FIX06 D16.2; user: "approved",
  then "Yes, exempt FRs"): Decision 5's repeats are deleted natively and requirements are
  exempt.
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
     record's claims.
2. **A behaviour statement's claims need a scenario.** In one records response, every
   claim a `functional_requirement`, `business_rule`, `user_visible_outcome` or
   `prohibited_behavior` names must also be named by an `acceptance_criterion` or
   `edge_case`. Assumptions and non-goals are scope statements that no scenario tests,
   so they need none. The rule needs no claim categories or keywords: title and
   purpose claims aren't named by behaviour statements. (Functional requirements only,
   until 2 November 2026.)
3. **A gap takes the request's protocol correction.** The rule is a native admission
   constraint beside ADR 0023's `exact_members`: the result-schema module records it on
   the records array (`Coverage`), response admission rejects an uncovered claim as
   `uncovered_member` at its exact location (`/records/<i>/claim_ids/<j>`), and the
   records step's existing `retry-limit` bounds the correction. Exhaustion fails the
   run. It asks for missing content and never removes any. Decision 5's partly taken
   statement, `shared_member`, takes the same route.
   - Request descriptions record the constraint so replay enforces the same admission
     (from `model-request-debug/v12`).
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
     record restating the story keeps that rule. It is kept when it holds an exact copy
     no other record of the batch holds, so no exact value is lost (user: "Yes, keep
     it"); each delete is decided on the batch it leaves. Deleting it leaves every claim
     and exact copy the batch names in place.
   - **Partly taken statement:** such a record naming taken claims and others too is
     rejected at response admission as `shared_member` at `/records/<i>`, before any
     coverage gap. The correction offers the record's shape, names the exclusive and
     owning kinds (`exclusive`), and lists every taken claim's naming in such records
     (`shared`), so one retry can fix them all (user: "Yes, list every location").
   - **Requirements are exempt** (user, 2 November 2026: "Yes, exempt FRs"): a
     requirement is never deleted or rejected by this rule, so one prose claim holding
     two obligations may yield two requirements. Deleting the second would lose the
     obligation it alone states.
   - The result-schema rule records the exclusive and owning kinds beside the covering
     kinds, as required members.
   - It replaces ADR 0035's comparison between records in one batch (user: "Yes, Q16
     replaces it"). ADR 0035's same-kind delete runs first and is unchanged.
   - The records prompt keeps its "at most one" sentence, requirements included, as the
     rule's first version (FIX06 D16.1) had it (user: "Yes, keep it").

## Consequences

- **Limits.**
  - Requirements written in one prose sentence stay one claim, so the scenario rule
    can't separate them.
  - The rule checks links, not meaning: an acceptance criterion that names a claim
    but doesn't test it passes. Since 1 November 2026 no review runs after generation
    (ADR 0023); the human who reviews and edits `spec.md` judges meaning.
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
    - admission judges the response as returned, so coverage is required of a record the
      session then deletes, and a statement taken only through a record that ADR 0035
      then deletes as a story restatement is kept;
    - a repeated statement with a typed-text or exact-copy defect takes that unit repair
      before the session can delete it.
  - **Identical records naming different claims** are not evidence-equivalent, so the
    native duplicate rule blocks them as `competing_records` instead of deleting one
    (ADR 0035 Decision 3).
  - **A repeated claim ID** passes the schema (subset selectors don't enforce
    uniqueness) and ends the unit at parsing, as a repeated `signal_ids` entry does.
- **Persistence.** The canonical record shape is unchanged, so no specification or
  state version changes. The generation schema's records gain a required `claim_ids`.
- **Tests.**
  - The result-schema rule: admitted (covered, a non-covering kind ignored, empty),
    rejected at the exact uncovered value, restored by replay from the record, kept by
    clones, and invalid configurations rejected.
  - Records: named subsets parse into group order; empty, repeated and foreign
    selections reject; stored readback accepts a canonical subset and rejects one out
    of group order; the records packet carries the rule, and admission accepts an
    acceptance criterion or edge case as cover and rejects a functional requirement
    whose claim nothing covers; identical records naming different claims block.
  - Coverage: a named claim maps, an unnamed claim in an unselected group blocks, and a
    narrative selection maps it.
  - Protocol correction: a scripted records response missing its scenarios is corrected
    once and publishes; repeated, it exhausts the records step and fails. The guidance
    names `uncovered_member` at the claim's location.
  - Replay: a recorded coverage round-trips, rejects an uncovered response, and a record
    that doesn't fit the captured schema is refused.
  - Requirements own their claims (Decision 5):
    - at the result-schema rule, each value in one exclusive item is admitted, an
      exclusive kind with no scenario is admitted, covering items may repeat a value,
      owning items are unconstrained, and an exclusive item whose every value is taken,
      by an owning item before or after it or an earlier exclusive item, is admitted;
    - an exclusive item naming taken and untaken values, of another kind or the same
      kind, is rejected at the item before any coverage gap, and replay restores the rule;
    - the correction lists every taken value's naming in such items (several items, two
      in one item, behind an opening artefact, none in a wholly taken item), and a
      response whose first such item differs, whose only shared item is wholly taken, or
      with none is refused;
    - exclusive or owning kinds that repeat, are covering kinds, overlap each other, or
      aren't offered reject, and so does a rule on arrays nested in an outer array;
    - a recorded rule without its exclusive or owning kinds doesn't decode;
    - at the records packet, an uncovered functional requirement, business rule,
      user-visible outcome or prohibited behavior rejects; an assumption or non-goal
      needs no scenario; every non-requirement statement kind rejects when partly taken,
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
      one claim, so a partly taken record is proven at admission only.
  - The list-item split: its quoting, structure and omission-repair cases (ADR 0036).
