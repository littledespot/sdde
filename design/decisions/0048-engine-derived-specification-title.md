# ADR 0048: Engine-derived specification title

- **Status:** Accepted
- **Date:** 2026-11-11
- **Decision authority:** The user's decisions on 11 November 2026: option B1, "The engine
  takes the source's first level-1 heading; no heading means a typed block" (Decisions 1–3),
  and "yes level-1 headings block run", for sources whose headings differ (Decision 4). The
  derived choices are recommended readings of them under the existing rules; they are not
  separate decisions.
- **Amends:**
  - design.md §1 (:73) and §4's "Feature directory and brief" row (:251): the title is not
    model-derived; §2's "Reference precedence" row (:89): sources whose title headings
    differ block instead of raising a question, while clarification answers can't be
    consumed (SPEC01 E7); the §32 index;
  - [17-specify.md](../contracts/17-specify.md) §17.1 (:33-35) and §17.3: the brief contains
    the description and primary goal, typed content has no display title, the engine takes
    the title before any generation call (:107-112), and field purposes don't demand a prewritten
    goal;
  - [12-model-boundary.md](../contracts/12-model-boundary.md): the model supplies no title
    (:486-488);
  - [24-workflow-state.md](../contracts/24-workflow-state.md) (:29-40), ADR 0020 (:262), ADR
    0023 (:162-163) and ADR 0024 (:90): `specification/v6` and `specification-state/v25`;
  - [ADR 0041](0041-failed-run-incomplete-publication.md) (:9-12, :45, :100-101, :228): its
    reserved state version moves to v26, and a failed run's published set carries the
    engine's title, not a generated one;
  - [F0100](../features/F0100-SpecWorkflow.md): the implemented list (:26), §3.10's readiness
    subjects (:676-679), the state version (:934) and §5's identity, H1, empty-collection,
    native-proposal and content-unit rules (:1047, :1053, :1089-1090, :1203-1205, :1223);
  - ADR 0016's packet-guidance amendment (:136-150), 12-model-boundary.md (:363) and
    [F0005](../features/F0005-WorkflowDefinitionRegistryService.md) (:278, :622):
    `packet-guidance/v6`, with no `display_name` purpose;
  - [text-field-composition.md](../contracts/text-field-composition.md): the brief title
    leaves the model-written inventory (:67);
  - [07-domain-representations.md](../contracts/07-domain-representations.md): the
    `spec.display_name` slot holds a native text value with no attributed provenance (:126);
  - ADR 0020: the engine's title is no model field (:96-97), the brief requires description
    and goal, and the title holds no claim lineage or group support (:188-191);
  - the [E2E harness](../harness/e2e.md) (:356, :590; acceptance.md:151-155):
    `spec-e2e-report/v16`;
  - ADR 0019 (:14), 12-model-boundary.md (:219), 24-workflow-state.md (:62) and
    27-observability.md (:139): request descriptions advance to `model-request-debug/v17`,
    because their field-policy bindings no longer name the brief title's text field;
  - the code.md specification-IR sample (:509-512).

  The overall design remains **Proposed design**.

## Context

The model-written title restated the source's requirements as a sentence in 21 of 55
hello-world evaluations since 2 November 2026, costing `organization`. In loan-renewal it
lost a source requirement in 4 of 54:

- three titles gave the extension as "fourteen days", dropping "calendar"
  (`2026-11-06T22-45-46Z-d392…`, `2026-11-07T01-18-32Z-ba2e…`, `2026-11-08T05-52-36Z-e4ec…`);
- one dropped "that has not previously been renewed" while the same call's description kept it
  (`2026-11-10T19-41-11Z-6c4c…`).

Under the 8 November 2026 title ruling ([SPEC01](../../fixes/SPEC01.md) §7 H1), a title that
gives a requirement's wording states it, so a lossy title fails that requirement's criterion.
All of these runs used `openai.gpt-oss-20b-1:0`. The counts come from the evaluation records,
not from `e2e-measures`.

- Both development sources open with a level-1 heading: "Hello World Application" and
  "Library Loan Renewal". Of the retained `openai.gpt-oss-20b-1:0` specifications, one of 22
  hello-world titles and none of 22 loan-renewal titles used it.
- In those 44 runs' reference contexts, extraction cited no heading as a claim, so the model
  has no heading claim to select.
- The `display_name` purpose already asked for "A concise name".
  Prompt changes didn't stop the same kind of lossy repeat in entity fields (SPEC01 §3).

AGENTS.md lets deterministic code compute exact source bytes. ADR 0047 took the story from the
model on that ground and blocks when the source lacks its material. Invariant 20
(design.md:162) turns a required datum with no resolution, or with several non-equivalent
ones, into a typed clarification, upstream rework or administrative block, never a default.
Every reference document is a peer with no precedence (design.md:89; 16-reference-ingestion.md
:242). Clarification answers can't be consumed yet (SPEC01 E7), so these cases block.

## Decision

1. **The engine takes the title.** The specification's display name is the text of the
   source's first level-1 heading, as written. No model call writes it.
2. **No heading blocks.** A reference corpus with no level-1 heading blocks before generation
   with the typed rejection `no_title_heading`. The block is never repaired or retried, and no
   title is defaulted.
3. **The brief loses its title.** The brief's model content is its description and primary
   goal. The generation schema's brief variant has no `title`, and packet guidance has no
   `display_name` purpose.
4. **Different headings block.** Peer sources have no precedence (design.md:89), so each
   source contributes its first level-1 heading and they must agree: one distinct heading text
   across the corpus is the title, and several distinct texts block before generation with the
   typed rejection `conflicting_title_headings` (invariant 20), never repaired, retried or
   resolved by choosing one. A source with no level-1 heading contributes none. The engine
   doesn't judge the headings' wording, so "Loan renewal" and "Loan Renewal" differ.

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
   0020:96-97).
3. **Representation:** the title is a native text value, not an attributed value. It holds no
   claim or group support and no stored provenance record. Once published, a user's edit to
   it in `spec.md` follows the existing editability rules (design.md:91; invariant 16). The
   changed content type takes `specification/v6` and `specification-state/v25`, as ADR
   0038's changed entity shape took both versions; ADR 0041's reserved version moves to v26,
   as it did for the versions ADRs 0015 and 0038 took (0041:5-12). Session initialization
   takes the title before any generation call. State readback derives it again from the captured
   sources and rejects a stored title that differs, as readback re-checks an edge-case link
   against its candidate rule (17-specify.md §17.3); the state is engine-owned, so this
   doesn't touch `spec.md` editability.
4. **Coverage:** the title selects no source group, so it maps no claim. ADR 0038's rule for a
   claim no record names, in a group no narrative field selects, applies unchanged
   (0038:236-238).
5. **Readiness:** the display name is not a source-readiness or required-authority subject,
   because the engine derives it, as ADR 0047 Decision 5 settled for the story. Removing its
   slot and purpose advances the required-authority contract to 5 and `packet-guidance` to v6.
6. **Guidance:** the `display_name` purpose is deleted with the field, and with it the
   sentence "The source need not supply a title.", which SPEC01 §9 protected until then.
7. **Report:** `no_title_heading` and `conflicting_title_headings` enter the E2E report's
   native rejections, so they land with `spec-e2e-report/v16` (SPEC01 §2 rule 12). Both are
   the engine's, with no model origin, issue or eligible group, and decoding rejects either
   with one.

## Consequences

- The title is the source heading as written and carries no model wording. It states, weakens
  or drops a requirement only where the heading itself does.
- A corpus whose sources have no level-1 heading, or different ones, blocks where it published
  before. Adding or aligning the heading line unblocks it. While ADR 0041 is on hold, a
  blocked run publishes nothing.
- A generic heading, such as "Notes", becomes the title as written.
- One field leaves the brief request; the brief call remains. Pre-generation source review
  loses its display-name subject, one request per review pass.
- Captured brief responses that carry a title no longer decode, and are retired with the field:
  the authoring-association seeds' titles and the replay corpora's title selections and field
  bindings. Hash-pinned raw captures are unchanged.
- The title no longer selects source groups. In a multi-group feature, a claim no record names,
  in a group that only the title selected, now blocks under ADR 0038. Extraction cited no
  heading as a claim in the 44 retained runs. In a one-group feature, which both development
  cases are, the description, goal and story still select the group.

## Tests

- Accepted (`specification_generation_test.zig`):
  - both development cases' titles equal their sources' level-1 headings;
  - an ATX and a Setext level-1 heading, and an unrelated domain;
  - a corpus where one source has a level-1 heading and another has none;
  - two sources with the same level-1 heading text, one ATX and one Setext;
  - a closing `#` with no space before it kept; CRLF lines; a leading byte-order mark; a
    Setext heading after a blank line that ends a list item; an empty and a level-2 heading
    passed over;
  - end to end (`test/integration/workflow_tests.zig`): the published H1 and the stored
    display name are the source's heading.
- Rejected:
  - no level-1 heading, only an empty one, a level-2 heading or a fenced `#` line blocks with
    `no_title_heading`;
  - different level-1 headings, in either order, block with `conflicting_title_headings`;
  - headings in code, HTML (an indented opener included), comments, list items and block
    quotes are not titles;
  - in a multi-group fixture, a heading-only claim in a group no narrative field selects
    blocks with `no_independent_supported_target`;
  - a title rejection with an origin or a group fails decoding; readback rejects a stored title
    that differs from the one the sources yield, in the domain and in a persisted state;
  - a `model-request-debug/v16` description is refused.
- The request projection (`q22-fixtures`, taken on the fixtures' added headings before the
  change, to `q22-after`; 135 scenarios): the brief request loses the title from its schema,
  field rules and purposes; the entities and repair requests lose the brief's title; every
  generation request's field-policy list loses the title binding; and source review loses the
  display-name subject (22 fewer requests), its later requests carrying the next requirement
  ordinals and contract version 5. The scripted repair fault that targeted the title now
  targets the description. No other request changed.
- Live: a brief screen, then a measurement set on both cases (SPEC01 §2 rules 4–6).
