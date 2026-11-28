# ADR 0047: Engine-composed primary user story

- **Status:** Accepted
- **Date:** 2026-11-03
- **Decision authority:** User decisions, 3, 7, 9 and 20 November 2026.
- **Amends:** design.md §1 and §4; [17-specify.md](../contracts/17-specify.md) §17.3;
  [F0100](../features/F0100-SpecWorkflow.md) §3.10, §5.2 and §5.7;
  [text-field-composition.md](../contracts/text-field-composition.md) (the story row's exact
  role); ADR 0016's packet guidance; ADR 0020 (the story's group selection is native);
  ADR 0024 (the story is not an exact-copy target).
- **Amended by:** [ADR 0038](0038-record-claims-and-scenario-coverage.md) Decision 7 (a
  further reason on Decision 2's typed rejection).

## Context

A model-written story weakened obligations and added unsupported content, and prompt wording
moved it between these modes without removing them. ADR 0036 already makes each claim's
wording the engine's quote of its cited source lines, so obligation strength, conditions and
negation are the source's own words by construction. AGENTS.md lets deterministic code compute
exact source bytes and structure; it can join quoted claims, but it can't paraphrase them.

## Decision

1. **The engine composes the story.** The story unit's content is built natively from the
   business claims (`business` category) of the groups in its catalogue, and any `open_question` claim an applied user
   answer kept ([ADR 0025](0025-clarification-answer-authentication.md)), in source order:
   - each quote becomes one paragraph: its blank and Markdown heading lines are dropped, and
     each other line loses its indentation and leading list marker, the lines joined by one
     space; a quote of headings alone is skipped. A Setext heading's text is a heading, and
     the lines that are Markdown structure with no wording (a code fence's opening and closing
     line, a table delimiter row, a thematic break, a Setext underline) are dropped too, while
     every line with words stays ([ADR 0036](0036-source-quoted-claims.md) Decision 2);
   - the quotes are joined with one space, in one paragraph;
   - exact values are recognised by the same native recognizer as model text, so they render
     as engine code spans;
   - the story selects the groups whose claims it quotes, and its provenance is resolved from
     them as for any authored value.
   No model call writes the story. It then passes the same unit validation as any unit.
2. **No non-content story outcome.** The story has no clarification or inconclusive outcome.
   A catalogue with no such claim blocks with the typed rejection
   `no_story_requirements`. A composed story that fails unit validation or exact-value
   recognition (for example, a quote that is only an exact value, or an ambiguous exact
   value) blocks with the typed rejection `story_not_admissible`, carrying the unit issue;
   it is never repaired or retried. The same typed rejection also carries
   `edge_case_without_criterion` (ADR 0038 Decision 7), which the engine raises when a
   completed records unit holds an edge case that no acceptance criterion of its records
   batch can serve. It is never repaired or retried, has no model origin, and names the edge
   case's group and claims in place of a catalogue.
3. **The story discharges no exact-copy duty.** Its exact role is incidental, as an entity
   name's is: an exact value may occur in it, and records must still carry every required
   exact value.
4. **The only record naming a claim is kept.** The story comparison (ADR 0038 Decision 5)
   never deletes a record when no other record names one of its claims.
5. **The story is no source-review subject.** Pre-generation source readiness (ADR 0023)
   assesses the other required feature subjects, not the story: its support is the provenance
   of the claims it quotes (Decision 1), and a catalogue with none blocks (Decision 2), so a
   support review of it checks nothing that provenance doesn't already establish. The story
   has no required-authority policy, clarification question or packet-guidance purpose.
6. **Workflow.** The `story` step is the registered action `compose-specification-story`.
   There is no story prompt and no story variant in the generation schema.

The story keeps its canonical `AttributedValue` shape. Its rejection reasons are members of the
E2E report contract (`test/harness/e2e/contracts.zig`).

## Consequences

- No model paraphrases the story: it copies the selected business claims' quoted words under
  Decision 1's formatting rules and adds no wording of its own. Its completeness and meaning
  still depend on which claims extraction cites and classifies as `business`, and on the
  context that dropped headings and list markers carried.
- The story reads as the source's requirement sentences, not a narrative; it mirrors the
  functional requirements, which the user allowed, and the evaluator doesn't count it as
  restatement.
- A source written in fragments yields a fragmentary story.
- A single-requirement source whose only non-requirement record equals the story keeps that
  record (Decision 4).
