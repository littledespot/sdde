# ADR 0048: Engine-derived specification title

- **Status:** Accepted
- **Date:** 2026-11-11
- **Decision authority:** User decisions, 11 November 2026 (Decisions 1–4). The derived
  choices are recommended readings of them under the existing rules; they are not separate
  decisions.
- **Amends:** design.md §1, §2 ("Reference precedence") and §4 ("Feature directory and
  brief"); [17-specify.md](../contracts/17-specify.md) §17.1 and §17.3;
  [12-model-boundary.md](../contracts/12-model-boundary.md);
  [24-workflow-state.md](../contracts/24-workflow-state.md);
  [text-field-composition.md](../contracts/text-field-composition.md);
  [07-domain-representations.md](../contracts/07-domain-representations.md);
  [F0100](../features/F0100-SpecWorkflow.md) §3.10 and §5;
  [F0005](../features/F0005-WorkflowDefinitionRegistryService.md); ADR 0016's packet
  guidance; ADR 0019; ADR 0020; the [E2E harness](../harness/e2e.md).

## Context

A model-written title restated the source's requirements as a sentence and, in some runs, lost
one. A title that gives a requirement's wording states it, so a lossy title fails that
requirement's criterion.

AGENTS.md lets deterministic code compute exact source bytes. ADR 0047 took the story from the
model on that ground and blocks when the source lacks its material. Invariant 20 turns a
required datum with no resolution, or with several non-equivalent ones, into a typed
clarification, upstream rework or administrative block, never a default. Every reference
document is a peer with no precedence (design.md §2; §16.4).

## Decision

1. **The engine takes the title.** The specification's display name is the text of the
   source's first level-1 heading, as written. No model call writes it.
2. **No heading blocks.** A reference corpus with no level-1 heading blocks before generation
   with the typed rejection `no_title_heading`. The block is never repaired or retried, and no
   title is defaulted.
3. **The brief loses its title.** The brief's model content is its description and primary
   goal. The generation schema's brief variant has no `title`, and packet guidance has no
   `display_name` purpose.
4. **Different headings block.** Peer sources have no precedence, so each source contributes
   its first level-1 heading and they must agree: one distinct heading text across the corpus
   is the title, and several distinct texts block before generation with the typed rejection
   `conflicting_title_headings` (invariant 20), never repaired, retried or resolved by
   choosing one. A source with no level-1 heading contributes none. The engine doesn't judge
   the headings' wording, so "Loan renewal" and "Loan Renewal" differ.

### Derived choices

1. **Level-1 heading:** a CommonMark level-1 heading at the top level, outside code blocks,
   HTML blocks and comments: ATX (one `#` after at most three spaces, then a space, a tab or
   the line's end) or Setext (a paragraph underlined with `=` that opens after a blank line,
   a heading, a break, a fence or the end of an HTML block). A heading inside a list item or
   block quote isn't the source's title. A heading with empty content isn't a title, so the
   next one counts, and a leading byte-order mark is no part of the first line. The line
   classifier owns this (`markdown_code_spans.levelOneHeading`), and list items and HTML
   blocks extend as its `listSegments` reads them for the story too: an indented line after a
   list item stays in the item, so a heading indented there isn't a title.
2. **Text:** the heading's content as written. The following are removed: the opening `#` run
   and its space or tab, or the Setext underline; a closing `#` sequence that follows a space
   or tab; and leading and trailing spaces and tabs. A Setext heading's lines, each so
   trimmed, are joined by a line feed. Nothing else changes, so "C#" keeps its `#`. The title
   is plain text (`spec.DisplayName`): it can hold no code span or exact-copy occurrence (ADR
   0020).
3. **Representation:** the title is a native text value, not an attributed value. It holds no
   claim or group support and no stored provenance record. Once published, a user's edit to
   it in `spec.md` follows the existing editability rules (invariant 16). Session
   initialization takes the title before any generation call. State readback derives it again
   from the captured sources and rejects a stored title that differs, as readback re-checks an
   edge-case link against its candidate rule (17-specify.md §17.3); the state is engine-owned,
   so this doesn't touch `spec.md` editability.
4. **Coverage:** the title selects no source group, so it maps no claim. ADR 0038's rule for a
   claim no record names, in a group no narrative field selects, applies unchanged.
5. **Readiness:** the display name is not a source-readiness or required-authority subject,
   because the engine derives it, as ADR 0047 Decision 5 settled for the story.
6. **Guidance:** packet guidance has no `display_name` purpose.
7. **Report:** `no_title_heading` and `conflicting_title_headings` are native rejections in the
   E2E report. Both are the engine's, with no model origin, issue or eligible group, and
   decoding rejects either with one.

## Consequences

- The title is the source heading as written and carries no model wording. It states, weakens
  or drops a requirement only where the heading itself does.
- A corpus whose sources have no level-1 heading, or different ones, blocks. Adding or
  aligning the heading line unblocks it. A blocked run publishes nothing.
- A generic heading, such as "Notes", becomes the title as written.
- Captured brief responses that carry a title don't decode.
- The title selects no source groups. In a multi-group feature, a claim no record names, in a
  group that only a title could have selected, blocks under ADR 0038
  (`no_independent_supported_target`). In a one-group feature, which both development cases
  are, the description, goal and story still select the group.
