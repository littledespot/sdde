# ADR 0046: Reconciliation dispositions are complete at response admission

- **Status:** Accepted
- **Date:** 2026-10-31
- **Decision authority:** The user's decision on 31 October 2026, "implement D2.3: the
  requirement loss with recommendations". It approves FIX06 D2.3 option (b), rejecting an
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
    F0100, diagram 05 and the §32 index. Diagram 21 is unchanged: invalid global
    candidates still route to reconciliation repair.

  The overall design remains **Proposed design**.

## Context

Each assigned semantic claim needs exactly one disposition (contract 16 §16.4 step 10;
F0100). The dispositions request didn't state that at response admission. An answer
that left claims out was admitted and collected. Canonical validation then rejected it
as `cardinality`, and repair inserted each missing disposition with its own call.

- **Repair harm.** In the 40 runs before Q4 that reached dispositions, five first answers
  listed only claim 1. They produced all 12 insert repairs, and 2 of those inserts
  answered `duplicate` of claim 1 for hello-world's UTC claim
  (`2026-10-27` 09:40 and `2026-10-29T20-47-23Z`). They are the only hello-world specs
  out of 20 that lost a requirement.
- **No loss from complete answers.** Every complete hello-world first answer kept that
  claim.
- **What the insert lacks.** The insert request carries every claim and the current
  dispositions. It lacks the dispositions task, and it offers `duplicate` and
  `superseded` targets as valid choices.
- **Adding definitions didn't help.** Binding definitions into repair requests (FIX06
  Q2) left harm at 1 in 40 replays.
- **Cost and completion.** On a reverted build, one run spent 104,288 tokens on 24
  inserts and then exceeded its token budget.
- **Precedents.** ADR 0023 (review assignments and preservation comparisons) and ADR
  0038 (records coverage) already put "one entry per assigned member" at response
  admission, corrected as the whole response.

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
   grouped binding over its group's claims. An incomplete answer is now corrected under
   that repair's own `retry-limit` (1), instead of failing at merge.
4. **Readback.** Canonical validation stays the authority behind admission: total
   dispositions, no repeat and authorized IDs.
   - A gap or repeat that still reaches it is an engine invariant failure
     (`InvalidAtomicRepair`), not a repair target.
   - Deleted: the per-claim insert, the redundant-record deletion, the competing-record
     block and the foreign-claim replacement.
   - Kept: replacing one disposition for a record, relationship or cycle defect.
5. **Recording.** Request descriptions record the binding in the existing `members`
   list. Replay reapplies every recorded member set natively, over the bounds the
   recorded schema bytes already carry. The description shape therefore doesn't change:
   `model-request-debug/v13` and its retained captures still decode (ADR 0019).
6. **Scope.** Two members of the omission class are left out:
   - **Statement, signal and conflict coverage inserts:** these are at-least-one
     coverage contracts, not exact membership, and no harm has been observed.
   - **Token classifications:** their composite key can't be bound by `exact_members`.

   Each needs its own decision if harm appears.

## Consequences

- **Model input.** Every initial request is byte-identical. In the request projection,
  206 dispositions requests differ only in the recorded `members`. A correction carries
  the new `member` value; no other correction changes.
- **Report contract.** It gains one schema reason value, `missing_member`. The
  `competing` member of reconciliation `Relations` is no longer set. It stays in the
  report contract until FIX06 §2.13 allows its removal. The dispositions occurrence set
  of the reconciliation source is deleted; it was never reported or persisted, and the
  request projection is unchanged by its removal.
- **Risk.** Some omissions that an insert used to resolve will exhaust their corrections
  and fail the run, so publication rate per case is the deciding guard. The
  requirement-loss target is too rare (2 in 20) for a measurement set to show alone.
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
- **Live:** a measurement set on both development cases, separately approved. It counts
  corrections against the inserts they replace, plus publication per case, lost
  requirements, harmful repairs, sends, tokens and exhausted runs.
