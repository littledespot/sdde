# ADR 0027: Extract one top-level list item at a time

- **Status:** Accepted amendment
- **Date:** 2026-10-21
- **Decision authority:** The user's instruction "implement B7" on 21 October 2026.
  FIX05 B7 recorded the proposal as "measure first; then Decision". The user then
  chose three options:
  - "One call per item": each top-level list item becomes its own extraction
    chunk, and nested sub-items stay with their parent;
  - "Lead-in context": an item chunk carries its nearest heading and lead-in
    paragraph as read-only, non-citable context;
  - "Implement, then live pair": implement and verify offline now, then measure
    with separately approved live runs instead of a billed replay first.
- **Amends:**
  - §16.3, which gains list items as structure the parser decides;
  - §16.4 steps 6 and 7 (chunking and per-chunk outcomes);
  - §12.5 ("one reference chunk … per call") and §12.7 (the partition identity
    in extraction-contract metadata);
  - the §13.3 `ChunkReferenceAction` entry, whose partition is now native and
    structure-aware;
  - ADR 0016 §5 and "Persisted contract readiness", for the native partition
    identity;
  - the "same original chunk" scope of ADR 0024's forced classification, which
    now applies to the item chunk;
  - F0100 §§3.4, 3.5 and 3.11, and diagram 05.

  The overall design remains **Proposed design**.

## Context

Both development sources are Markdown lists of distinct requirements: three items
in hello-world and five in loan-renewal. The reader cut blocks at 64-line windows,
each block was one chunk, and extraction made one call per chunk. So each whole list
reached the model in one call, and the model decided how to split it.

In every run since Phase 1A, extraction returned one claim for the whole list. In
loan-renewal that claim also weakened "A borrower must be able to renew" to "A
borrower may renew". The extraction context already asked for "one independently
meaningful source fact per entry", so rewording does not fix this (FIX05 B7).

List structure can be decided mechanically. Under §§1 and 3.2, the engine should
give a low-capability model a bounded assignment instead of a split it fails to
make.

## Decision

- **Partition.** The native chunk partition is `source_list_items_v1`, owned by
  `src/domain/reference_chunk_partition.zig`. It replaces `source_blocks_v1` in
  place, with no parallel partition.
  - Each top-level Markdown list item is one chunk. That covers a bullet (`-`, `+`,
    `*`) or an ordered marker (up to nine digits then `.` or `)`), with up to three
    spaces of indentation, followed by a space or tab. The chunk includes the
    item's continuation lines, lazy continuation lines and nested items.
  - A sibling item ends the item. So do these, when outdented from the item's
    content: a heading, a thematic break, a fence's opening line, or a line after a
    blank line. Indented, they are item content.
  - The lines between lists form text chunks.
  - Fenced code content, a fence's closing line, and lines that start inside a
    multi-line exact-value span are hidden: they are never classified and never
    start a chunk.
- **Shared parser.** List markers, headings and separators are classified by the
  shared source parser in `markdown_code_spans.zig`, which also owns exact-value
  spans. No second Markdown parser or library is added. Syntax identifies form,
  never meaning.
- **Blocks.** The reader's 64-line blocks and its identities are unchanged. Chunks
  tile their block exactly in order and never cross it, so a block holds one or
  more chunks, and a chunk's `ordinal` is its position within the block.
- **Lead-in context.** An item chunk carries spans for the nearest preceding heading,
  ATX or setext, and the paragraph that introduces its list.
  - The extraction request shows them as `lead_in` before `source_lines`. A text
    chunk's request has no `lead_in`.
  - They are read-only: citations still select only the chunk's own `source_lines`,
    so a claim cannot span items or cite context.
  - The extraction context explains `lead_in` in its always-sent purpose, and says
    to keep any condition or subject the item depends on from it.
  - A condition kept from the lead-in has no citation. Review still compares claims
    with the original sources, but no native provenance records the lead-in.
  - The lead-in is the whole introducing paragraph, repeated in each item's request.
    Its size is not bounded beyond the source's own limits.
- **Exact values in a lead-in.** A list whose heading or introducing paragraph
  contains an exact-value span is not split: the text and its list stay one chunk,
  as before. Item claims could otherwise copy a value whose native preserve duty
  ADR 0024 scopes to the introducing chunk, and the duty would be lost.
- **Other boundary rules.**
  - A fence's opening line is classified, so an outdented fence ends a list even
    without a blank line before it.
  - Indentation counts a tab to the next four-column stop.
  - Only a bullet, or an ordered list starting at 1, can interrupt a paragraph.
  - A thematic break that ends a list stays with the last item, so it costs no
    chunk of its own.
- **Claim count.** Segmentation bounds each call's scope. It does not fix how many
  claims an item yields; that stays with the model, including `no_feature_claim`.
- **Validation.** The chunk validator and the persisted reference snapshot both
  accept chunks only when they equal the canonical partition, recomputed from the
  validated corpus.
- **Versions.** The partition identity enters the extraction-contract binding, so
  older snapshots reject with `REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE`.
  `specification-state` advances to v20 because the persisted chunk shape gains
  `lead_in`. The claim schema, extraction composition and `model-request-debug`
  are unchanged.

## Consequences

- One extraction call per item replaces one per list. Hello-world goes from one
  content call to four, and loan-renewal to six, plus classification calls for item
  chunks with exact tokens. Downstream, more claims mean more source groups,
  record batches and review subjects under the single 100,000-token budget. Whether
  loan-renewal stays within budget is measured live, not assumed.
- Cross-item relations, such as an item that restates another, fall to
  reconciliation, as for claims from different documents.
- Claim and citation IDs follow the new chunk order. Three frozen calibration
  captures with list sources had their IDs renumbered without changing meaning
  (`test/calibration/source-loss-attribution/bound-preservation`).
- Tests:
  - `src/reference_evidence_test.zig` covers:
    - flat, ordered, nested, continued and lazily continued items;
    - lead-ins, including setext headings;
    - lists kept whole because their lead-in has an exact value;
    - list ends, fences after and inside items, thematic breaks, tabs, and
      paragraph interruption;
    - inline spans across a marker line;
    - CRLF and CR line endings, prose without lists;
    - lists longer than one block, and an item clipped mid-line at a block
      boundary;
    - six rejected forgeries;
  - `src/specification_generation_test.zig` rejects a persisted snapshot with
    the superseded one-chunk-per-block shape or a dropped lead-in;
  - `src/reference_model_input_test.zig` covers the `lead_in` request field and
    citation scope.
- Passive literals, such as file names, are offered to a chunk only where they
  occur in its own lines. An item whose lead-in names one sees it in `lead_in` but
  can write it only as plain prose. Admitting lead-in occurrences to the item's
  passive scope would need its own typed policy and is not decided here.
- Accepted deviations from CommonMark: a lone `-` line is treated as a separator
  and ends a list, while a lone `*`, `+` or `1.` is ordinary text. Lists inside
  block quotes are not split.
- Not decided here:
  - other structures, such as tables and block quotes;
  - non-Markdown readers;
  - any native rule on claim count or modality. A modality check would be the
    §3.2 non-goal of keyword rules.
