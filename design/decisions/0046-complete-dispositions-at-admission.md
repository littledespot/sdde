# ADR 0046: Reconciliation dispositions are complete at response admission

- **Status:** Accepted
- **Date:** 2026-10-31
- **Decision authority:** The user's decision on 31 October 2026, "implement D2.3: the
  requirement loss with recommendations". It approves SPEC01 D2.3 option (b), rejecting an
  incomplete dispositions answer at response admission instead of inserting each missing
  disposition by repair. It also approves the recommended variant, which leaves the first
  request unchanged.
- **Amends:**
  - [ADR 0022](0022-native-reference-phase-handoffs.md): a missing or repeated
    disposition is no longer a phase repair. Disposition repair still replaces one
    disposition.
  - [ADR 0023](0023-advisory-post-generation-review.md): the scope of its membership
    rule extends to reconciliation dispositions and to the source-omission
    conflict-group repair.
  - [ADR 0033](0033-generic-repair-operations.md): the dispositions authorizer loses its
    insert and delete paths, and E4 takes its freeze after this change.
  - Also amended: §12.2, §16.4 (step 10 and the false-conflict repair), §22.4, §22.6,
    F0100 and the §32 index.
  - **Amended 27 November 2026** (decision 3 only; user: "implement A and T1"): the
    conflict-group repair binds the claims it decides again, not every claim of its group.
  - **Amended 28 November 2026** (decisions 7 and 8; user: "all approved, update", after the preflight of
    changes 1 and 2 of ENGINE01 §10 item 10): a group that names a claim not disposed `conflicting` is rejected at
    admission and corrected as the whole response, and the dispositions request shows that rule. It amends
    Decision 4's "Kept" line, the Consequences' "Model input" and "Risk" bullets, §12.2's list of admission constraints,
    §16.4 step 10, §22.4 and §22.6's correction kinds, and [ADR 0022](0022-native-reference-phase-handoffs.md) "Conflict
    groups" for the dispositions stage only: its rule that a conflicting claim in no group stays a `no_required_member`
    block is unchanged. The request description takes `model-request-debug/v23` ([ADR 0019](0019-single-request-debugger.md)).

  The overall design remains **Proposed design**.

## Context

Each assigned semantic claim needs exactly one disposition (contract 16 §16.4 step 10;
F0100). The dispositions request didn't state that at response admission. An answer
that left claims out was admitted and collected. Canonical validation then rejected it
as `cardinality`, and repair inserted each missing disposition with its own call.

- **Repair harm.** In the 40 runs before Q4 that reached dispositions, five first answers
  listed only claim 1. They produced all 12 insert repairs, and 2 of those inserts
  answered `duplicate` of claim 1 for hello-world's UTC claim: the only hello-world
  specifications out of 20 that lost a requirement. Every complete hello-world first
  answer kept that claim.
- **What the insert lacks.** The insert request carries every claim and the current
  dispositions. It lacks the dispositions task, and it offers `duplicate` and
  `superseded` targets as valid choices.
- **Adding definitions didn't help.** Binding definitions into repair requests (SPEC01
  Q2, `fixes/Z_FIX06.md` at git `194e29a`) left harm at 1 in 40 replays.
- **Cost and completion.** On a reverted build, one run spent 104,288 tokens on 24
  inserts and then exceeded its token budget.
- **Precedents.** ADR 0023 (preservation comparisons) and ADR 0038 (records coverage)
  already put "one entry per assigned member" at response admission, corrected as the
  whole response.

## Decision

1. **Binding.** A dispositions assignment binds its semantic claim IDs as an
   `exact_members` choice on `claim_dispositions[].claim_id`, with the count native:
   - The token claims stay excluded (ADR 0024).
   - The selected schema keeps its canonical bounds and states no count, so the request
     the model receives is unchanged.
   - Admission rejects a repeated claim as `duplicate_member` and an omitted one as
     `missing_member`. The `missing_member` diagnostic is located at the array, and its
     correction names the first omitted member as `member`.
   - An empty semantic set binds nothing and admits only `[]`, as before.
2. **Correction.** The existing bounded protocol correction resubmits the whole
   assignment under the dispositions request's `retry-limit` (2). It adds no counter,
   insertion or deletion. Exhaustion fails the run (§22.6).
3. **Conflict-group repair.** The source-omission conflict-group repair uses the same
   grouped binding over the claims it decides again: its group's claims, except any that another
   conflict record also holds ([ADR 0022](0022-native-reference-phase-handoffs.md), amended 27 November 2026).
   An incomplete answer is now corrected under that repair's own `retry-limit` (1), instead of failing at merge.
4. **Readback.** Canonical validation stays the authority behind admission: total
   dispositions, no repeat and authorized IDs.
   - A gap or repeat that still reaches it is an engine invariant failure
     (`InvalidAtomicRepair`), not a repair target.
   - Deleted: the per-claim insert, the redundant-record deletion, the competing-record
     block and the foreign-claim replacement.
   - Kept: replacing one disposition for a record, relationship or cycle defect. A group naming a claim that is not
     disposed `conflicting` is none of these: it is rejected at admission (Decision 7), since a replacement of one
     disposition cannot repair a disagreement between the groups and the dispositions.
5. **Recording.** Request descriptions record the binding in the existing `members`
   list. Replay reapplies every recorded member set natively, over the bounds the
   recorded schema bytes already carry. For the membership binding alone the description shape therefore doesn't change,
   and `model-request-debug` took no new version (ADR 0019); Decision 7 later records a rule and takes v23.
6. **Scope.** Two members of the omission class are left out. The conflicts answer's group IDs left
   this list on 25 November 2026: [ADR 0022](0022-native-reference-phase-handoffs.md) "Conflict groups" binds
   them as exact members, since two records over one claim pair left a conflict that no answer could resolve.
   - **Statement and signal coverage inserts:** these are at-least-one
     coverage contracts, not exact membership, and no harm has been observed.
   - **Token classifications:** their composite key can't be bound by `exact_members`.

   Each needs its own decision if harm appears.
7. **Group agreement at admission** (28 November 2026). A response that holds `conflict_groups` and
   `claim_dispositions` must agree: every claim ID named in `conflict_groups[].claim_ids` that the response disposes
   (it is the `claim_id` of a `claim_dispositions` item) is disposed with kind `conflicting`. A claim the response
   does not dispose is not this rule's: the conflict-group repair (Decision 3) disposes only the claims it decides
   again, and in the dispositions request membership already makes every claim disposed.
   - It is a native admission constraint beside `exact_members`, `equal_items`, `shared_member` and
     `disagreeing_items` (§12.2): the provider schema cannot express it, and it reads claim IDs and disposition tags
     only, never prose ([ADR 0036](0036-source-quoted-claims.md) Decision 7's test). Both arrays are admitted first,
     so a membership defect is reported before this one.
   - Admission rejects the first group item that lists such a claim as `group_member_not_conflicting`, located at that
     group item. Its correction names the first offending claim as `member`, carries the rejected response, whose group
     is at the located item, and takes the existing bounded protocol correction of the whole response under the
     request's `retry-limit` (2), as Decision 2 does. It adds no counter, insertion, deletion or partial merge, and
     the engine chooses neither the group to drop nor the disposition to change. Exhaustion is the request's existing
     one and fails the run (§22.6).
   - It applies to the dispositions request and to the conflict-group repair request (Decision 3), whose response
     states groups and dispositions together.
   - Request descriptions record the rule as `listings`, so replay applies it, as ADR 0036 does with `agreements`. The
     description therefore takes `model-request-debug/v23` ([ADR 0019](0019-single-request-debugger.md)), and captures
     of earlier versions are no longer read, as for every earlier recorded rule.
   - Canonical validation stays the authority behind admission (Decision 4): a disagreement that reaches it is an
     engine invariant failure, not a repair target.
   - The reverse direction, a `conflicting` claim in no group, is not an admission rule: it stays the later
     `no_required_member` block ([ADR 0022](0022-native-reference-phase-handoffs.md) "Conflict groups").
8. **The rule is shown to the model** (28 November 2026; built after Decision 7, behind its own replay screen).
   - The dispositions request lists the rule as a typed constraint, `grouped_claims_conflicting`, in the
     `.disposition = .rules` scope, with one requirement text: "Every claim in a conflict group must have disposition
     `conflicting`." It carries no engine vocabulary and no case wording.
   - `conflicting_related_claims` keeps its other uses (a conflict record must match a declared group, and the final
     reconciliation check). The dispositions-stage group check reports `grouped_claims_conflicting`, so each rule has
     one identity and one text.
   - **Reading of AGENTS.md "Model output, prompts and evidence"**, decided with this change: "prompts and
     model-facing guidance... carry no restated engine-enforced rules" forbids a prompt file or workflow-authored
     guidance from restating a rule. The native constraint projection
     ([F0100](../features/F0100-SpecWorkflow.md) "concise guidance projected from native constraint identities"; code
     `reconciliationGuidance`) is the designed single owner of a rule's model-facing text, so the rule is stated there
     once and `reconciliation-dispositions.prompt.md` does not restate it.
   - It changes the dispositions request in every case. Decision 7 does not, and may be built and measured first.

## Consequences

- **Model input.** Decision 7 leaves every initial request byte-identical; dispositions request
  descriptions differ only in the recorded `members` and the recorded group rule. A correction carries the new
  `member` value; the group-agreement correction is the one new correction kind. Decision 8 changes the dispositions
  request text in every case, so it follows a paired replay screen of the dispositions call from each case (SPEC01 §2,
  rule 4) and its own measured build.
- **Report contract.** It gains one schema reason value, `missing_member`. The
  `competing` member of reconciliation `Relations` is no longer set, and the report
  contract dropped it in `spec-e2e-report/v24`. The dispositions occurrence set
  of the reconciliation source is deleted; it was never reported or persisted, and the
  request projection is unchanged by its removal.
- **Risk.** Some omissions that an insert used to resolve will exhaust their corrections
  and fail the run, so publication rate per case is the deciding guard. The
  requirement-loss target is too rare (2 in 20) for a measurement set to show alone. A group-agreement correction
  can drop the genuine group instead of the false one, which would publish a contradiction as a false assessment; the
  conflict case's live runs are the guard, and the development cases guard against regression. A replay screen of the
  captured failing calls is not possible: their request descriptions are v22, which the replay tools no longer read, and
  a run directory is immutable evidence.
- **Replays.** A retained capture's first dispositions request is unchanged, so
  replaying it measures only the omission rate. The correction request exists only in
  captures from this build.

## Validation

- **Offline tests:**
  - The result-schema mode keeps canonical bounds. It is rejected on any other
    collection.
  - Payload admission:
    - an omitted member is rejected as `missing_member` at the array, and its
      correction names it;
    - a repeat is rejected as `duplicate_member`;
    - a complete set is admitted.
  - The dispositions packet binds the semantic claims natively and derives the same
    model bytes as a sequence choice.
  - A gap or repeat reaching readback is not a repair target.
  - The scripted sequence: a correction that still omits a claim is corrected once more
    and publishes; repeated, it exhausts the dispositions request and fails.
  - Group agreement (Decision 7):
    - a group member disposed `retained` is rejected as `group_member_not_conflicting` at that group, and the
      correction names the claim and is built from the real retry action; a corrected response is admitted;
    - overlapping groups whose members are all `conflicting`, a response with no groups and a group naming a claim the
      response does not dispose are admitted;
    - a `conflicting` claim in no group is not rejected at admission;
    - the schema rule needs a sibling array with a required integer key and a required closed state offering the kind,
      one governed array and every name, and its recorded choice must fit the captured schema;
    - the conflict-group repair request applies the same rule, and replay applies the recorded rule, which a
      description without it does not;
    - exhaustion is the request's generic retry limit, not reason-specific, and has no scripted workflow scenario of
      its own;
    - for Decision 7 alone, a byte diff of request-projection freezes shows every initial request unchanged;
    - for Decision 8, the constraint appears in the dispositions request once, its text carries no engine vocabulary,
      and the prompt file does not restate it.
- **Live:** a measurement set on both development cases, separately approved. It counts
  corrections against the inserts they replace, plus publication per case, lost
  requirements, harmful repairs, sends, tokens and exhausted runs.
- **Live, group agreement:** a live set on one recorded source hash, separately approved: the conflict case, several
  launches, for the effect, and both development cases for no regression. For the conflict case it counts the launches in
  which the correction fires, whether the resubmitted response is consistent and keeps the genuine group, whether the
  run then reaches a form or publishes, and the launches that exhaust the correction. The three failing calls that
  motivated the rule (`2026-11-28T01-33-20Z-5d196478…` call 5, `2026-11-28T02-27-09Z-8a26e165…` call 5 and
  `2026-11-28T02-31-13Z-56ef1aed…` call 4) cannot be replayed.
