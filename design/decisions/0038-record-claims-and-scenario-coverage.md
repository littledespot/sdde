# ADR 0038: Records name their claims; functional requirements need scenarios

- **Status:** Accepted
- **Date:** 2026-10-25
- **Decision authority:** The user's decisions on 25 October 2026 on
  [FIX05](../../fixes/Z_FIX05.md#21-fix05-retired--28-october-2026) B5: "implement B5 as per recommendation", then
  "APPROVED. Implement B5" for four choices:
  1. each record names the claims it supports, picked from its batch's claims, with the
     group staying the record's link to the source;
  2. every claim a functional requirement names must also be named by at least one
     acceptance criterion or edge case in the same batch;
  3. a gap sends the records response back for one of its existing corrections, and the
     run fails if they run out;
  4. claims become one per requirement for list sources by bringing back the list-item
     split.
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
2. **A functional requirement's claims need a scenario.** In one records response,
   every claim a `functional_requirement` names must also be named by an
   `acceptance_criterion` or `edge_case`. The rule needs no claim categories or
   keywords: title and purpose claims aren't named by functional requirements.
3. **A gap takes the request's protocol correction.** The rule is a native admission
   constraint beside ADR 0023's `exact_members`: the result-schema module records it on
   the records array (`Coverage`), response admission rejects an uncovered claim as
   `uncovered_member` at its exact location (`/records/<i>/claim_ids/<j>`), and the
   records step's existing `retry-limit` bounds the correction. Exhaustion fails the
   run. It asks for missing content and never removes any.
   - Request descriptions record the constraint so replay enforces the same admission;
     `model-request-debug` advances to v12.
4. **List sources yield one claim per requirement.** ADR 0036 Decision 3's native
   list-item split is reinstated: a claim whose cited lines span several top-level
   list items becomes one quoted claim per item, so a list requirement can be checked
   on its own. Its withdrawal rested on a wrong reading: the same five-claim input
   produced both 2 and 304 records, so claim count wasn't driving record inflation.

## Consequences

- **Limits.**
  - Requirements written in one prose sentence stay one claim, so the scenario rule
    can't separate them.
  - The rule checks links, not meaning: an acceptance criterion that names a claim
    but doesn't test it passes. Review stays advisory (ADR 0023).
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
  - **Business rules restating requirements (amended 26 October 2026).** With one claim
    per list item, every run of both cases from the first live pair on wrote business
    rules that restate a functional requirement claim by claim, and organization scores
    fell. On 26 October a records-prompt line was added against it ("A business rule
    states a constraint that no functional requirement in this response already states;
    never restate a requirement claim by claim."). It was a single-run patch, and the
    27 October 08:31 and 09:40 hello-world runs still restated FR-001 claim by claim, so
    it was removed on 28 October 2026 ([FIX06](../../fixes/FIX06.md) Q1a, D1.2).
    Claim-by-claim restatement is left unpatched; FIX06 Q6 and Q8 measure it. The list
    split stays for now: it is what gives a refusal requirement its own claim and
    scenario.
  - **Identical records naming different claims** are not evidence-equivalent, so the
    native duplicate rule blocks them as `competing_records` instead of deleting one
    (ADR 0035 Decision 3).
  - **A repeated claim ID** passes the schema (subset selectors don't enforce
    uniqueness) and ends the unit at parsing, as a repeated `signal_ids` entry does.
- **Persistence.** The canonical record shape is unchanged, so no specification or
  state version changes. The generation schema's records gain a required `claim_ids`.
  Retained captures without it no longer admit, and `model-request-debug/v11`
  descriptions no longer decode.
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
  - The list-item split: its quoting, structure and omission-repair cases (ADR 0036).
