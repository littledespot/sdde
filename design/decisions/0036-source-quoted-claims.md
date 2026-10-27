# ADR 0036: Source-quoted extraction claims

- **Status:** Accepted
- **Date:** 2026-10-25
- **Decision authority:** The user's decisions on 25 October 2026 on
  [FIX05](../../fixes/Z_FIX05.md#21-fix05-retired--28-october-2026) B7:
  - "YES" to source-quoted claim wording;
  - "apply the best option" for one claim per source requirement, recorded as a native
    list-item split and later withdrawn (Decision 3);
  - "implement B7 with option 1": claims cite a set of line IDs restricted to the supplied
    lines, bad citations are rejected at admission, one pure function quotes them, and
    claim-text repair and citation repair are deleted;
  - "apply recommendations as per above": generated text loses the Markdown code
    delimiters directly around a recognised exact value (Decision 6), after the first
    live pair showed generation copying the quoted backticks;
  - "make the changes as suggested": keep source quoting and withdraw the list-item
    split, after the second live pair;
  - "APPROVED. Implement B5": reinstate the split
    ([ADR 0038](0038-record-claims-and-scenario-coverage.md)), after the withdrawal's
    evidence turned out to be misread.
- **Amends:**
  - §12.7, the reference-claim proposal;
  - §16.3 and §16.4 step 6, extraction citations and repair;
  - §22, reference-extraction repair;
  - [F0100](../features/F0100-SpecWorkflow.md) §§3.7–3.8 and its validation summary;
  - [text-field composition](../contracts/text-field-composition.md), extraction claim text
    and exact-value code delimiters in generated text;
  - the §13 reference action catalogue, extraction text validation;
  - [ADR 0016](0016-configured-json-response-composition.md) §5, whose extraction repairs
    lose citation repair;
  - the §32 index.

  [ADR 0024](0024-native-exact-token-authority.md)'s forcing rule is unchanged; it now
  reads quoted text. Reconciliation statements and signals stay model text. The overall
  design remains **Proposed design**.
- **Amended by:** [ADR 0045](0045-entity-description-exact-values-as-code-spans.md)
  (entity meaning and each relationship are incidental, so Decision 6 turns their
  recognised exact values into exact copies).

## Context

A model claim carried its own wording and a set of line ranges. In at least five
loan-renewal runs from 17 to 24 October, extraction turned the source's "must be able to
renew" into "may renew". Every later call received both the source and the weakened
claim, followed the claim, and published a specification that contradicted itself. Review
judged the weakened text supported each time.

Extraction also returned one claim for each whole Markdown list, so every record cited the
same claim and native checks couldn't tell distinct duties apart. Per-item chunking
(ADR 0027) was reverted on 21 October because it added extraction calls without better
output.

The claim's wording added nothing the source lacked. It only added a second wording that
could disagree with the source.

## Decision

1. **A model claim is a category and the lines that state it.**
   - The proposal is `{category, citations}`, where `citations` is a set of supplied
     source-line IDs. It has no wording field.
   - Admission restricts `citations` to the chunk's citable line IDs, and to no more IDs
     than there are such lines; a repeated ID adds nothing. A line is citable when it has
     any text, and one predicate (`source_selections.citable`) decides it for admission,
     quoting and tests. The initial
     extraction request bounds `/claims/*/citations`; the source-omission claim repair
     bounds its claim's `citations`.
   - A claim's citations are validated before it is quoted. An unknown or blank cited
     line, or an empty citation set, reaching validation is an invariant failure, not a
     repair target.
2. **The engine quotes each claim from its cited lines, as written.** One function at
   extraction text validation builds the wording.
   - Each run of cited lines contributes the source's own bytes, Markdown included. A run
     continues across uncited blank lines, so a fenced block keeps its blank lines. It is
     trimmed only at its two ends, and never where the end is a fenced code line.
   - Runs are joined by a line holding `…`. It marks the uncited text between them and
     can't complete a JSON value across the gap, so a join never forms an insertion
     object that isn't in the source.
   - Nothing inside a run is rewritten: no marker, code delimiter or whitespace changes.
     A quote is therefore never empty, and exact values appear in it byte for byte.

   `business` and `scope_guard` claims become one literal `BusinessText`; other categories
   become one literal `ReferenceSemanticText`. The shared text validator then checks it as
   before, which normalizes prose to NFC. The Markdown reader admits only scalars that
   validator accepts, so a rejection is an engine defect.
3. **A claim spanning several top-level list items is split** (withdrawn and reinstated
   on 25 October 2026 by [ADR 0038](0038-record-claims-and-scenario-coverage.md)).
   - When the cited lines belong to two or more top-level list items, the engine emits one
     claim per item. Cited lines outside every item, such as a heading before the list or
     prose after it, become one claim per gap between items. Each claim quotes and cites
     its own lines and keeps the proposal's category.
   - List structure comes from the source's reader, computed once per source per
     validation over the whole source, so a chunk boundary can't change it. For
     Markdown, the one owner is `markdown_code_spans.listSegments`, which reuses that
     module's line iterator, list-marker parser, fenced-code scan and heading,
     thematic-break and HTML-block rules.
   - An unindented list marker (`-`, `*`, `+`, `1.` or `1)` with a following space)
     starts a top-level item, including one that opens a fence. Indented lines, fenced
     code and continuation lines directly after an item line belong to it, so nested
     items stay with their parent. A heading, a thematic break, an HTML block or comment,
     or unindented text after a blank line ends it. Lines inside an HTML block or
     comment are never items.
   - Modelled on CommonMark's paragraph-interruption rule, an ordered marker starts an
     item inside a paragraph only as `1.` or `1)`, or as a sibling with the open list's
     delimiter. A wrapped line beginning `2024.` is not an item. The rule is not
     CommonMark itself: for example, `3)` after `1.` and `2.` stays inside item 2.
   - A claim within one item, with or without a heading or prose, stays whole. So do
     prose-only claims and a cited line holding two facts.
   - **Why it was withdrawn and reinstated.** The split was withdrawn after two live
     pairs in which the records call authored 3, 12, 8 and 304 records, against 2 to 4
     with one claim per list. A later run gave the records call the same five-claim
     input and it authored 2 records, so claim count wasn't driving the inflation.
     ADR 0038's scenario rule needs one claim per requirement, which the split supplies
     for list sources.
4. **Repair routes that served model wording are deleted.**
   - Text repair keeps only the `no_feature_claim` reason, still model text.
   - Citation repair (`citation_replacement`, `source_selection_replacement`), its
     `source_selections` diagnostic and the `retain-reference-claim-rejection` operation
     are deleted. `validate-reference-claims` now ends `ok` or `failed`.
   - Classification repair and source-omission repair are unchanged. An omission repair
     returns the same proposal shape, and every claim it quotes is inserted.
5. **Exact values keep their native authority.** ADR 0024's forcing reads the quoted text
   of `business` and `scope_guard` claims. A code span or fenced block that such a claim
   cites in full is therefore preserved, whatever its kind, and becomes an exact
   obligation. As ADR 0024 already provides, a value whose bytes aren't in NFC doesn't
   survive prose normalization, so it isn't forced.

6. **Generated text loses the code delimiters around an exact value.** Quoted claims
   carry the source's Markdown, and generation copies it, so a value written as
   `` `Hello, World!` `` rendered with escaped backticks beside the engine's own code span.
   - The recogniser's `delimited` step counts equal backtick runs directly on both sides
     of each matched value, and every caller cuts the same outer span. The rule
     applies to generated specification fields:
     - where an exact copy is allowed (obligation-bearing or incidental, such as the
       entity name), the value becomes an exact copy;
     - where exact copies are prohibited, the value stays text.
     The composition check uses the same span. Extraction reasons and reconciliation
     text keep their delimiters.
   - Removal is checked against every eligible exact value, the set every later re-check
     uses, even when a repair recognises with its narrower lineage. If matching that set
     without the delimiters doesn't find the same values as with them (for example,
     because a longer value would now join across the gap), every delimiter in that text
     stays as written.
   - A backtick that is all that separates two values belongs to neither. Unequal runs
     give the value no boundary, so the text stays as written.
   - Admission is therefore idempotent, and stored readback and repair re-checks match.
   - A field that can't hold exact copies needs no lineage to lose delimiters, so it uses
     every eligible exact value.
   - Nothing else in the text changes. A code-wrapped value with no other prose is now
     the value alone, so a field that requires prose rejects it as `reference_only`,
     exactly as it rejects the bare value.

## Consequences

- **Fixed by construction.** Obligation strength, conditions and negation are the
  source's own words at extraction, in any modality or language, with no keyword rule.
- **More claims.** A list cited as one claim becomes one claim per item, with no model
  call, so ADR 0038's scenario rule can check each list requirement.
- **Limits.**
  - Several requirements in one prose sentence or paragraph stay one claim.
  - Items with different meanings in one split take the proposal's single category.
  - A cited heading, or other markup line such as a thematic break, split from its list
    becomes a short claim of its own.
  - Claim wording keeps its Markdown, such as list markers and backticks. Later calls
    receive it as the source wrote it.
  - A top-level marker indented by one to three spaces is treated as a continuation, so
    such a list doesn't split. Unindented text after a fence that closes inside an item
    stays with the item. Both err toward not splitting; neither changes wording.
  - Reconciliation statements and signals still restate claims in model text. Whether
    they must reference claim text natively needs its own evidence.
- **Ingestion.** The Markdown reader now rejects C1 control characters (U+0080–U+009F)
  as malformed text, through the typed-text scalar rule. Previously a model paraphrase
  could hide them; a quote can't, so the source fails at ingestion with a typed reason.
- **Persistence.**
  - The extraction schema changes. Persisted specification state already records the
    compiled extraction schema bytes and rejects a mismatch as
    `REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE`, so no state version changes.
  - Specification states written by this change before Decision 6 (only the uncommitted
    live pair of 25 October) hold backtick-wrapped exact copies, and their readback now
    fails. States from committed builds already fail on the extraction schema. Run
    directories are evidence and are never resumed.
  - Stored readback validates claim text against the text policy but doesn't re-quote it
    from its citations. That would need the Unicode normalizer at readback; it is open
    work (FIX05 B7).
  - The E2E report's candidate diagnostic loses the `source_selections` variant and the
    extraction-text claim target. No retained report contains either, so
    `spec-e2e-report/v9` is unchanged and every retained report still decodes.
- **Tests.**
  - Code delimiters:
    - at the recogniser: equal, double and unequal runs, a backtick shared by two values,
      delimiters kept when removing them would join a longer value, a narrow match
      checked against every eligible value, and allocation failure on both paths;
    - a repair bound to one value keeping delimiters whose removal would join another;
    - admission into an obligation field and a field that can't hold exact copies, with
      idempotence, including a code-wrapped value alone;
    - the composition check with a code-wrapped value alone and with prose.
  - Quoting and splitting: top-level, ordered and nested items, continuation lines,
    headings and prose in and out of a split, wrapped numbers, look-alike markers and a
    thematic break, HTML blocks and comments, spacing and trimmed indentation, fenced
    code and an item that opens a fence, a chunk that starts inside a paragraph, and two
    sources whose chunks start inside and after fenced blocks.
  - Exact-value duty for a code span across lines and for fenced blocks: with a blank
    line, content lines only, the opening fence, indented content and an unterminated
    fence. Citing part of a block leaves it free.
  - Joining runs: an ellipsis between runs, including inside a JSON value.
  - Allocation stays proportional to the source across 128 chunks.
  - Admission: blank, unsupplied and over-count citations are rejected, for the initial
    request and for omission repair.
  - Omission repair inserts every claim a list-spanning proposal quotes.
  - Ingestion rejects C1 and DEL characters.
  - A proposal carrying wording is rejected as an unknown property.
  - Scripted models cite only citable lines. Scenarios that need a discarded token or
    an exact-value omission now keep the token off every quoted line.
