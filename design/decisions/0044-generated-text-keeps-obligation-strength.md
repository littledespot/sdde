# ADR 0044: Generated text keeps its source's obligation strength

- **Status:** Accepted
- **Date:** 2026-10-27
- **Decision authority:** The user's direction on 27 October 2026, "apply the follow
  recommendations", applying: "Decide how to catch weakened obligations. Review can't be
  relied on, so the option is a deterministic check: use the claim links from ADR 0038,
  and flag a field whose linked source claim says "must" when the field says "may", for a
  correction … its risk is that it's a word-list rule, which CLAUDE.md discourages, so it
  needs an explicit decision; the alternative is to record this as a model limitation."
  The user chose the check, under their engineering principles (simplest correct
  solution, existing boundaries, no parallel paths). On 27 October 2026, after the first
  live pair, the user accepted the recommended fix over withdrawal ("update the docs with
  the above recommendations"): the repair requirement quotes the linked claim, and a
  sentence copied verbatim from a linked claim doesn't count (Decisions 2 and 4). After
  the second pair, asked "Should I reword the repair request?" with the leading-action
  example, the user directed "implement the suggestions" the same day (Decision 4's
  wording).
- **Amends:** §17.3 (specification-unit validation), §22 (unit repair defects), F0100
  and the §32 index; it uses [ADR 0038](0038-record-claims-and-scenario-coverage.md)'s
  claim links. The overall design remains **Proposed design**.

## Context

Loan-renewal's source says "A borrower must be able to renew". Generation has weakened it
to "may renew" in every evaluated loan-renewal run, in the brief, the story or FR-001.
Source review approved it every time: the 26 October labelling found it passed in 8
subjects, and a review-prompt line naming exactly this case made no difference (FIX05 B2).
A weakened obligation is a requirement-preservation defect, and review can't be relied on
to catch it.

The first live pair on the rule (27 October, loan-renewal) fired twice, and both repairs
did harm. The story's "A borrower may renew" was a true weakening, but the repair, told
only the two words and to change nothing else, wrote "A borrower must renew", a duty the
source doesn't state. The entity relationship "A loan may be renewed only once." is the
source's own sentence (it has no mandatory word), flagged because another claim in the
same group says "must"; the repair replaced it with the functional requirement's text.

On the second pair (27 October, after the first fix) the loan-renewal story said "may
renew" again. The repair request then ended "This text weakens its "must" to "may". …
keeping the rest of this text's meaning", and the model returned the story unchanged; its
trace read the weaker word as the goal. One unchanged repair ends the run
(`RepairNoProgress`), so the run published nothing. The requirement now leads with the
action (Decision 4).

## Decision

1. **One native unit-validation rule.** A generated text field must not weaken a
   mandatory obligation stated by a source claim it is linked to. It runs in the existing
   specification-unit validation, beside the exact-value obligation check, for every
   generated field with linked claims:
   - a non-entity record's linked claims are the claims it names (ADR 0038);
   - an entity record's and a narrative field's linked claims are the claims of the groups
     it selects; in entity-membership repair, the feature basis's fixed groups.
   - Every repair route revalidates with the same check, so a repair that stays weak is
     recurring, never resolved, and the repair requirement quotes the claim (Decision 4).
2. **A closed, typed marker policy.**
   - Mandatory markers: `must`, `shall`. Weaker markers: `may`, `might`, `should`,
     `could`.
   - Markers match as whole words, ignoring case, in the field's own text only;
     exact-value segments are never read.
   - A sentence ends at `.`, `!`, `?`, `;` or `:`.
   - A marker followed by `not` or `never`, within the same sentence, is a prohibition,
     not a weakening, and doesn't match.
   - `can` is not a weaker marker: "can renew" is a faithful way to state "must be able
     to renew".
   - A whole sentence of the field that is a whole sentence of one of its linked claims,
     ignoring case, whitespace, a leading list or quote marker and the closing break, is
     the source's own wording. Its weaker markers don't count, because a source sentence
     can't weaken itself; its mandatory markers still do. Part of a claim's sentence is
     not a copy (it can drop the sentence's condition), and a field sentence cut by an
     inserted value is never one.
3. **The defect.** When a linked claim has a mandatory marker, and the field has a weaker
   marker and no mandatory marker, the field has a `weakened_obligation` defect naming
   the claim and both words.
4. **The correction.** The defect takes the existing specification-unit repair route
   (authorize, repair, merge, full revalidation) with its existing allowance; there is no
   new route. Exhaustion follows the existing terminal rule, and ADR 0041 once
   implemented.
   - The repair requirement leads with the action and quotes the linked claim's text in
     full, closing the quote with its own full stop, then names both words: "Restate
     linked claim N's obligation as the claim states it: "…". This text uses "may" where
     the claim uses "must"." It never ends on the weaker word, which a model read as the
     goal, and drops the earlier "changing nothing else", which invited a one-word swap,
     and "keeping the rest of this text's meaning", which framed the repair as a minimal
     change. The generic repair guidance still says "Preserve business meaning". Whether
     a repair keeps the field's other content is measured on live runs, not assumed.

## Consequences

- **Risk: a word-list rule.** CLAUDE.md discourages these; this one is the user's explicit
  decision, generic across cases and fields, and limited to the closed lists above.
  - It misses paraphrased weakening ("is allowed to", "optionally") and other languages.
  - A field that states both a mandatory and a weaker marker passes.
  - Case-insensitive matching reads "May" (the month) and "might" (the noun) as weaker
    markers, so such a field linked to a `must` claim is flagged.
  - It can flag a field whose linked claims carry a mandatory word about a different
    obligation than the field's weaker one. The verbatim exemption covers a field that
    copies its own source sentence, the case seen live; a paraphrase of a non-mandatory
    claim next to a mandatory one can still be flagged. Measure false positives on live
    runs.
- **Persistence.** Stored state and contract versions don't change; the defect is
  validation evidence, not stored content. The rule runs at the model boundary
  (admission and repair revalidation), not at stored readback.
- **Owner.** One closed marker policy in `src/domain/obligation_strength.zig`, applied by
  the existing candidate validation (`validateCandidate`) to brief, story and
  entity-basis values against their selected groups' claims, and to record fields
  against the claims each record names.
- **Tests.**
  - Accepted: a field keeping `must`; `can` for "must be able to"; `may not` for a
    prohibition; `may` inside an exact value; a field whose linked claims have no
    mandatory marker; a field sentence with `may` that copies a whole sentence of one
    linked claim (differing only in case, whitespace, a list marker or the closing
    break) while another linked claim says `must`, in a narrative field and an entity
    relationship and in two unrelated domains; a copied `must` sentence followed by a
    weaker one, whether `.` or `;` separates them; a repair whose replacement copies the
    source sentence resolves.
  - Rejected: a record and a narrative field that turn `must` into `may`, `should`,
    `might` or `could`, including a paraphrase of a copied sentence, part of a claim's
    sentence, and a sentence cut by an inserted value; the defect names the claim and
    both words, and its repair requirement quotes the claim's text.
  - Route: the scripted generation driver repairs a weakened story once and publishes,
    and its repair packet quotes the source claim; persistent weakening exhausts the
    repair allowance.
