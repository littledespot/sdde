# ADR 0047: Engine-composed primary user story

- **Status:** Accepted
- **Date:** 2026-11-03
- **Decision authority:** The user's decisions on 3 November 2026:
  - D19.1, "Yes, may restate (Recommended)": the primary story may restate its source's
    requirements in one paragraph, adding nothing ([Z_FIX06](../../fixes/Z_FIX06.md) Q19 D19.2);
  - "yes" to the Q19 preflight's question, "Should the engine write the story itself, from the
    source's requirement sentences, using these rules?", with the six rules in the Decision.
  - Amended 7 November 2026 (user: "apply recommendations", then "yes, advance both"): Decision
    5 now removes the story from pre-generation source review, advancing `packet-guidance` to v3
    and the required-authority contract to 2.
  - Amended 8 November 2026 ([ADR 0038](0038-record-claims-and-scenario-coverage.md) Decision 7):
    the typed rejection of Decision 2 also carries `edge_case_without_criterion`, which the
    engine raises when a completed records unit holds an edge case that no acceptance criterion
    of its records batch can serve. It is never repaired or retried, has no model origin, and
    names the edge case's group and claims in place of a catalogue.
- **Amends:**
  - design.md §1 and §4: the story is no longer LLM-owned content (the Spec structure row);
  - [17-specify.md](../contracts/17-specify.md) §17.3: three model task types (brief,
    entities, one call per record group) and a native story; the story prompt clause; the
    narrative-assignment population;
  - [F0100](../features/F0100-SpecWorkflow.md) §5.2 (the story's purpose, formerly "Main
    user journey"), §5.7 and the four-call text;
  - [text-field-composition.md](../contracts/text-field-composition.md): the story row's exact
    role;
  - ADR 0020: the story's group selection is native;
  - ADR 0024: the story is not an exact-copy target;
  - ADR 0035: the only-record exception;
  - ADR 0016's packet-guidance amendment and F0100 §3.10: the story's purpose and readiness
    subject (Decision 5, amended 7 November 2026);
  - the §32 index.

  The overall design remains **Proposed design**.

## Context

The model-written story held 26 of 30 weakened obligations scored in published specifications
since 29 October ("A borrower may renew…") and added unsupported content, such as invented
steps ("logs into the library system and selects…"). Prompt wording moved the story between
these modes without removing them ([Z_FIX06](../../fixes/Z_FIX06.md) Q12 D12.2 and Q19
D19.2).

ADR 0036 already makes each claim's wording the engine's quote of its cited source lines, so
obligation strength, conditions and negation are the source's own words by construction.
AGENTS.md lets deterministic code compute exact source bytes and structure; it can join quoted
claims, but it can't paraphrase them.

## Decision

1. **The engine composes the story.** The story unit's content is built natively from the
   business claims (`business` category) of the groups in its catalogue, in source order:
   - each quote becomes one paragraph: its blank and Markdown heading lines are dropped, and
     each other line loses its indentation and leading list marker, the lines joined by one
     space (user, 3 November 2026: "yes"); a quote of headings alone is skipped;
   - the quotes are joined with one space, in one paragraph;
   - exact values are recognised by the same native recognizer as model text, so they render
     as engine code spans;
   - the story selects the groups whose claims it quotes, and its provenance is resolved from
     them as for any authored value.
   No model call writes the story. It then passes the same unit validation as any unit.
2. **No non-content story outcome.** The story has no clarification or inconclusive outcome.
   A catalogue with no business claim blocks with the typed rejection
   `no_story_requirements`. A composed story that fails unit validation or exact-value
   recognition (for example, a quote that is only an exact value, or an ambiguous exact
   value) blocks with the typed rejection `story_not_admissible`, carrying the unit issue;
   it is never repaired or retried (user, 3 November 2026: "implement recommendation").
3. **The story discharges no exact-copy duty.** Its exact role is incidental, as an entity
   name's is: an exact value may occur in it, and records must still carry every required
   exact value.
4. **The only record naming a claim is kept.** ADR 0035's story comparison never deletes a
   record when no other record names one of its claims.
5. **The story is no source-review subject** (amended 7 November 2026). Pre-generation source
   readiness (ADR 0023) assesses the other required feature subjects, not the story: its
   support is the provenance of the claims it quotes (Decision 1), and a catalogue with none
   blocks (Decision 2), so a model review of it can only raise false findings (FIX06,
   `2026-11-02T09-15-31Z`). The story has no required-authority policy, clarification question
   or packet-guidance purpose; removing them advanced `packet-guidance` to v3 and the
   required-authority contract to 2.
6. **Workflow.** The `story` step is the registered action `compose-specification-story`. The
   story prompt and the generation schema's story variant are deleted.

The story keeps its canonical `AttributedValue` shape, so no specification or state version
changes. Its rejection reasons entered `spec-e2e-report/v15` (`test/harness/e2e/contracts.zig`).

## Consequences

- The story can't weaken an obligation or add content, in any language or source format.
- One model call (about 1.4k tokens) leaves every specification run.
- The story reads as the source's requirement sentences, not a narrative; it mirrors the
  functional requirements (D19.1 allows this, and the evaluator doesn't count it as
  restatement).
- A source written in fragments yields a fragmentary story, as hello-world's "Must also
  output date and time in UTC" does.
- Captured story responses in calibration corpora no longer decode and are retired with the
  schema variant.

## Tests

- Accepted: both development cases' stories equal their joined source sentences, with exact
  values recognised; an unrelated-domain fixture.
- Rejected: a catalogue with no business claim blocks with `no_story_requirements`; a heading
  claim and a technical claim are skipped.
- A single-requirement source whose only non-FR record equals the story keeps that record.
- A story exact value satisfies no exact-copy duty.
- The request projection shows the story call removed and no other request changed.
- Live: a measurement set on both cases (FIX06 §2 rules 4–6).
