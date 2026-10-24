# ADR 0035: Cross-kind and story restatement in the duplicate rule

- **Status:** Accepted
- **Date:** 2026-10-25
- **Decision authority:** The user's decisions on 25 October 2026:
  - "YES" to [FIX05](../../fixes/FIX05.md) B5's recommended option, cross-kind
    restatement in the native duplicate rule;
  - and three answers given during its preflight:
    - delete a restatement only "if the kept one covers it";
    - when the kept one doesn't cover the evidence, "leave it as today";
    - "keep FR; else the earlier".
- **Amends:**
  - [F0100](../features/F0100-SpecWorkflow.md) §5.7: which duplicates can be deleted;
  - F0100's native validation summary;
  - the §32 index.

  The duplicate check in §17.5 is unchanged. The overall design remains **Proposed
  design**.

## Context

The native duplicate rule compared a record's whole typed content, record kind included,
and compared records only with other records. Identical wording in two record kinds, or a
record repeating the primary user story, therefore passed.

Both clean runs on `8a600d7` published a business rule identical, word for word, to the
primary user story. Source review judged it `supported`, and review can't change output
(ADR 0023).

The rule could delete only an "exact evidence-equivalent" duplicate: same groups and
equal provenance. A record and the story never have equal evidence. The story cites
every group, while a record cites its batch's group.

## Decision

1. **Single-statement kinds are compared by their statement.**
   - The kinds are functional requirement, business rule, assumption, non-goal,
     prohibited behavior and user-visible outcome.
   - Each is compared by its typed statement value, using the same typed equality as
     whole-content duplicates. The comparison runs across kinds within one records
     batch, and against the primary user story.
   - Acceptance criteria, edge cases and entities still compare only as whole same-kind
     content.
   - Records in different batches bind different source groups, so neither covers the
     other. A cross-batch restatement is therefore never flagged.
2. **A restatement is deleted only when the kept occurrence covers its evidence.**
   - The kept occurrence must cite every source group, claim, citation and clarification
     response the restatement cites.
   - Deletion uses the same native delete as `duplicate_record`, which has old-value and
     revision preconditions and impacted and full validation, and makes no model call.
3. **An uncovered restatement is not flagged.**
   - Identical wording whose evidence the kept occurrence doesn't cover stays as
     authored. It is neither deleted nor blocked.
   - Same-kind duplicates keep today's rule: an evidence-equivalent duplicate is deleted
     and a competing one blocks.
4. **The functional requirement is kept.**
   - The primary user story is never deleted.
   - A functional requirement is never deleted as a restatement, because it is a
     required family.
   - Between other kinds, the earlier record is kept and the later one deleted.
5. **Same-kind duplicates are decided first.**
   - Every same-kind duplicate check runs before any restatement can remove a record:
     within the batch (unit validation) and against earlier batches (the session).
   - A competing pair therefore still blocks, even when one of its members also
     restates another record.
6. **Ownership and diagnostics.**
   - Restatements belong to the session's consistency check, after its same-kind checks.
   - The session receives the model candidate the checked records came from. It binds
     the restated record as the observed old value the native delete requires.
   - A restatement has its own rule, `restatement`, so diagnostics distinguish it from an
     evidence-equivalent `duplicate_record`.

## Consequences

- **Removed.** Filler records that repeat the story or another record word for word.
  Removing them reduces review subjects.
- **Not removed:**
  - paraphrases;
  - entity descriptions, since deleting an entity would change the entity decision (FIX05
    R6);
  - restatements whose evidence isn't covered.
- **Completion.** A run can't be blocked by this rule, because only covered restatements
  are flagged.
- **Persistence.** No persisted format changes.
  - Restatements are removed at admission.
  - Assembly reruns the same-kind rule over the combined records.
  - Published-state readback runs neither.
- **Tests.**
  - The family-purpose test keeps one shared wording for functional requirements,
    acceptance criteria, edge cases and entities, and gives each deletable kind its own.
  - The coverage test's user-visible outcome no longer copies the story.
  - The R46 test keeps its original candidate, which still blocks as competing records,
    and adds the covered case.
  - The scripted complete story in the integration fixture now has its own leading
    words, so review-advice scenarios don't trip a restatement delete.
  - New tests cover:
    - a story that cites every group, against a batch-bound record;
    - a later functional requirement removing an earlier record;
    - an uncovered second-batch restatement that stays admitted.
