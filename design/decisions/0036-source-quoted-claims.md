# ADR 0036: Source-quoted extraction claims

- **Status:** Accepted
- **Date:** 2026-10-25
- **Decision authority:** The user's decisions on 25 October 2026 on
  FIX05 (`fixes/Z_FIX05.md` §21, git `194e29a`) B7:
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
    evidence turned out to be misread;
  - 1 November 2026, SPEC01 Q7 D7.4, decided and then "implement Q7 D7.4.": the engine adds
    no code span to an exact copy its text already wraps in a balanced pair (Decision 6);
  - 1 November 2026, "Yes, keep the span": a copy that ends in terminal punctuation keeps
    its span, although every development-case value then stays doubled (Decision 6;
    withdrawn on 16 November 2026, below);
  - 3 November 2026, SPEC01 Q7 D7.2, "apply recommendations": Decision 6 stays, and ADR 0045,
    which would have extended it to entity meaning and relationships, is withdrawn;
  - 7 November 2026, SPEC01 Q8 D8.3, "i accept recommendation" and "implement D8.3": a quoted
    claim of the same category and cited lines as an earlier claim of its chunk is the same
    claim (Decisions 3 and 4);
  - 16 November 2026, SPEC01 Q7 A and its bundled-FR watch, "yes as per recommendations":
    the engine gives no code span to an exact copy a balanced pair directly wraps, including
    a copy that ends in terminal punctuation (Decision 6), and generation requests show a
    claim's wording as one paragraph, without list markers or line breaks (Decision 2).
  - 18 November 2026, "implement At extraction: yes. The engine can compute, from line IDs
    alone, that two claims cite exactly the same lines. It could return the existing protocol
    correction naming both, so the model keeps one category. The cost is that one line can no
    longer be filed under two categories.": response admission corrects an extraction answer
    that files one line under two categories (Decision 7). The rule first read "exactly the
    same lines" as the same set of line IDs; on the user's "Wider rule: yes", to the question
    whether it should cover claims whose line sets differ, it binds any line cited by claims
    of two categories. It binds only where the categories differ, because the same category
    on the same lines is already one claim (SPEC01 D8.3, Decision 3).
  - 20 November 2026, SPEC01 C49 ("update the docs with the above recommendations", then
    "preflight and implement"): the paragraph reading of Decision 2 drops the Markdown
    structure lines that have no wording and reads a Setext heading's text as a heading.
  - 21 November 2026, SPEC01 Q8 D8.2, "implement the recommendations for D8.2": a fenced
    block's value excludes the blank lines at its edges, so a claim that cites every citable
    line of the block cites it in full (Decision 5).
- **Amends:**
  - §12.2 and §22.6, whose admission constraints and corrections gain Decision 7's
    agreement rule and its `disagreeing_items` correction;
  - §16.3, extraction claims that cite a common line, and its fenced-block candidate, whose
    value has no blank edge lines and which an all-blank block does not create (Decision 5);
  - [ADR 0019](0019-single-request-debugger.md), whose request description records the
    rule, and [ADR 0039](0039-configured-temperatures-and-runaway-resend.md) Decision 5,
    whose list of native admission constraints gains it;
  - §12.7, the reference-claim proposal;
  - §16.3 and §16.4 step 6, extraction citations and repair;
  - §22, reference-extraction repair;
  - [F0100](../features/F0100-SpecWorkflow.md) §§3.7–3.8 and its validation summary;
  - [text-field composition](../contracts/text-field-composition.md), extraction claim text
    and exact-value code delimiters in generated text;
  - §23.1, the code span of an exact copy its text already delimits (Decision 6);
  - the §13 reference action catalogue, extraction text validation;
  - [ADR 0016](0016-configured-json-response-composition.md) §5, whose extraction repairs
    lose citation repair;
  - the §32 index.

  [ADR 0024](0024-native-exact-token-authority.md)'s forcing rule is unchanged; it now
  reads quoted text. Reconciliation statements and signals stay model text. The overall
  design remains **Proposed design**.

## Context

A model claim carried its own wording and a set of line ranges. In loan-renewal runs,
extraction turned the source's "must be able to renew" into "may renew". Every later call
received both the source and the weakened claim, followed the claim, and published a
specification that contradicted itself. The claim's wording added nothing the source
lacked; it only added a second wording that could disagree with the source.

Extraction also returned one claim for each whole Markdown list, so every record cited the
same claim and native checks couldn't tell distinct duties apart.

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
   - **Generation requests show the quote as one paragraph** (16 November 2026). The claim,
     its stored quote, citations and exact-value duties are unchanged. The wording a records,
     entities or scenarios request shows the model is the paragraph reading the primary story
     uses ([ADR 0047](0047-engine-composed-primary-story.md) Decision 1), from the one
     function the story and the generation display catalogue share. A requirement copied
     from a list then shows no marker or line break for a model to carry into a field that
     joins several requirements. An exact value is offered with its bytes in `exact_texts`,
     and a value that sits on one line keeps them in the wording. A quote with no words in
     its reading, such as a heading alone, is shown as written, so a claim the request
     assigns is never shown empty. Every other request keeps the quote as written:
     extraction, reconciliation, source review and omission.
   - **The reading drops Markdown structure that has no wording** (20 November 2026, SPEC01
     C49, "update the docs with the above recommendations", then "preflight and implement"):
     a code fence's opening and closing line, a table delimiter row, a thematic break and a
     Setext underline, and the text lines of a Setext heading, which is a heading. Every line
     with words stays, table rows and code lines included. The classes are Markdown's own
     block syntax, recognised by the line reader of Decision 3, so no meaning is judged. A
     thematic break joins the three the decision named (fence delimiters, table delimiter
     rows, Setext underlines) because it carries no words either. A Setext underline heads the
     paragraph above it, so a line of text directly above a `---` or `===` line is heading
     text, and YAML front matter reads the same way. A quote left with no words, a fence
     alone for example, reads as one with none, as a heading alone does.

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
   - ADR 0038's scenario rule needs one claim per requirement, which the split supplies
     for list sources (ADR 0038 Decision 4).
   - **One piece of evidence is one claim** (SPEC01 D8.3). A quoted claim with the same
     category and the same cited lines as an earlier claim of its chunk is the same
     evidence, because its wording is the quote of those lines. Extraction text validation
     keeps the first, with its origin, after the split and before claim identities exist.
     Different or partly overlapping lines stay separate claims of their category. A line
     cited under two categories is corrected at admission (Decision 7), so a different
     category on shared lines reaches this step only through an omission-repair insertion.
     The raw model response is unchanged, so duplicates stay countable. This applies to
     model claims only; preserved-token claims keep ADR 0024's occurrences.
4. **Repair routes that served model wording are deleted.**
   - Text repair keeps only the `no_feature_claim` reason, still model text.
   - Citation repair (`citation_replacement`, `source_selection_replacement`), its
     `source_selections` diagnostic and the `retain-reference-claim-rejection` operation
     are deleted. `validate-reference-claims` now ends `ok` or `failed`.
   - Classification repair and source-omission repair are unchanged. An omission repair
     returns the same proposal shape, and every claim it quotes that its chunk doesn't
     already hold is inserted (Decision 3's one-evidence rule). An insertion that adds no
     claim is an unchanged merge, which the shared retry state ends as `unchanged_repair`
     before any dependent rebuild (§22.4).
5. **Exact values keep their native authority.** ADR 0024's forcing reads the quoted text
   of `business` and `scope_guard` claims. A code span or fenced block that such a claim
   cites in full is therefore preserved, whatever its kind, and becomes an exact
   obligation. A fenced block's value is its interior without the blank lines at its
   edges, which cannot be cited (Decision 1), so a claim that cites every citable line
   of the block cites it in full, with or without the fence lines. A block whose
   interior is blank holds no value and creates no candidate. As ADR 0024 already provides, a value whose bytes aren't in NFC doesn't
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
   - **The engine adds no delimiter the text already supplies.** Generation also wraps
     values in quotes, so `"Hello, World!"` rendered as quotes around the engine's code
     span. When the literal text directly around an exact copy is one balanced pair from
     the shared closed wrapper table ([ADR 0020](0020-derived-exact-reference-lineage.md)),
     with no punctuation between the copy and the pair, the projection gives the copy no
     code span and it renders as escaped text.
     - The model's bytes, the stored segment and its lineage don't change, and no meaning
       is judged.
     - These keep the span: an unwrapped copy, a pair with punctuation inside it
       (`"report.csv."`), and a copy beside another display value. Passive values always
       keep theirs (§23).
     - A copy that ends in terminal punctuation from the shared closed table gets no span
       either (16 November 2026, withdrawing the exception of 1 November 2026). The pair
       delimits it, and the model's bytes show whether the final period belongs to the
       value: `"Renewal refused."` renders as the value in its quotes. All three exact
       values in the development cases end this way, so each renders once, not doubled as
       quotes around the engine's span. A copy with other punctuation between it and the
       pair (`"Hello, World!."`) is not directly wrapped and keeps its span.
     - The backtick is in the table, so a backtick run this decision keeps stays as
       written, with no second delimiter.
     - No renderer revision exists to change, and no Plan or Tasks review exists to renew
       ([ADR 0034](0034-spec-quality-gate.md)).
7. **A line is cited under one category** (18 November 2026; the decision authority
   above).
   - **The rule.** In one chunk's claims answer, two claims whose `citations` hold a common
     line ID return the same `category`. IDs compare as integers, without order or repeats.
     Response admission rejects an answer that breaks it as `disagreeing_items`, located at
     the first claim that a later one disagrees with (`/claims/<i>`, scope `parent`). It is a
     native cross-item constraint beside `equal_items` and `shared_member`: the provider
     schema can't express it, so request descriptions record it (`agreements`) and replay
     applies it. The check reads line IDs and category tags only, never prose.
   - **Where it applies.** The initial extraction request, whose `/claims/*/citations`
     selector names `category` as the property that claims citing a common line share. A
     quote that a list split makes equal to another claim's lines always comes from claims
     that cite a common line, so admission sees it before the split. The omission repair
     returns one claim, which has no sibling to agree with, so it keeps Decision 3's rule:
     the same lines in another category are inserted.
   - **The correction.** The existing bounded protocol correction (§22.6) resubmits the
     complete part under the request's `retry-limit` and adds no counter, insertion or
     deletion. Its guidance adds `agreement`: `property` (`citations`), `agree`
     (`category`) and `sets`. Each set is `values`, line IDs that the same claims cite, and
     `items`, the JSON Pointer of every claim that cites them, in response order; a line
     whose claims share one category is not named. The model chooses which category to
     keep, or whether to keep one claim; the engine never chooses. Exhaustion fails the run
     (§22.6).
   - **Why admission.** A sentence filed under two categories can't be reconciled: a
     summary statement names claims of one category, and a duplicate or superseded target
     must share its claim's category. The pair therefore reached records authoring, where
     two groups wrote equal records and the run blocked as `competing_records` (ADR 0035
     Decision 3, ADR 0038). A defect of the response's own contract takes admission's
     correction, as member sets do (ADR 0023, ADR 0038 Decision 3, ADR 0046); it works around
     no model limitation, because the rule judges no meaning and is checked by the engine.
   - **What it does not change.**
     - The same category on the same lines stays one claim natively (Decision 3), and
       claims of one category may share lines.
     - Claims that cite no common line stay separate, in any categories.
     - An omission-repair insertion is not compared: that repair exists to add a claim in
       another category over lines already filed, so it can still reach extraction text
       validation as two categories on the same lines.
   - **Cost.** A line can no longer be filed under two categories: a sentence that is both
     a requirement and a scope boundary is one claim of the category the model keeps, and a
     heading line cited beside two bullets of different categories is cited by one of them.
     Under ADR 0024 a code span in a `business` or `scope_guard` claim is forced and one in
     another category is not, so the kept category decides that duty.
   - **Versions.** `model-request-debug/v20` records the rule. The new rejection reason is
     a closed member of the reports, so `spec-e2e-report/v21`, `e2e-step-event/v6`,
     `baseline-acquisition/v15`, `baseline-score/v7`,
     `provider-compatibility-report/v4` and `exact-value-production-admission/v4` advance
     with it, and earlier runs and captures stay readable only by the build that made
     them. Persisted specification state and the extraction schema, composition and
     operation bytes don't change.

## Consequences

- **Fixed by construction.** Obligation strength, conditions and negation are the
  source's own words at extraction, in any modality or language, with no keyword rule.
- **More claims.** A list cited as one claim becomes one claim per item, with no model
  call, so ADR 0038's scenario rule can check each list requirement.
- **Limits.**
  - Several requirements in one prose sentence or paragraph stay one claim.
  - Decision 7 covers the model's citations in one initial answer. An omission-repair
    insertion can still file a line under two categories, and a correction that keeps
    failing ends the run at extraction instead of at records authoring. Whether it raises
    the publication rate is for repeated runs of both development cases on one build
    (SPEC01 D8.4 holds the evidence).
  - Items with different meanings in one split take the proposal's single category.
  - A cited heading, or other markup line such as a thematic break, split from its list
    becomes a short claim of its own.
  - Claim wording keeps its Markdown, such as list markers and backticks, in storage and in
    every request but the generation requests, which show its paragraph reading (Decision 2).
    A code span or fenced block that crosses lines is flattened in that wording like any
    lines; its exact value is still offered with its bytes.
  - A model that copies a shown wording verbatim can now equal the story, so ADR 0035's
    native deletion of a non-functional record that restates the story can apply to it;
    functional requirements stay exempt.
  - A top-level marker indented by one to three spaces is treated as a continuation, so
    such a list doesn't split. Unindented text after a fence that closes inside an item
    stays with the item. Both err toward not splitting; neither changes wording.
  - Reconciliation statements and signals still restate claims in model text. Whether
    they must reference claim text natively needs its own evidence.
- **Ingestion.** The Markdown reader rejects C1 control characters (U+0080–U+009F) as
  malformed text, through the typed-text scalar rule. A quote can't hide them, so the
  source fails at ingestion with a typed reason.
- **Persistence.**
  - The extraction schema changes. Persisted specification state already records the
    compiled extraction schema bytes and rejects a mismatch as
    `REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE`, so no state version changes.
  - Stored readback validates claim text against the text policy but doesn't re-quote it
    from its citations. That would need the Unicode normalizer at readback; it is open
    work ([SPEC01](../../fixes/SPEC01.md), B7 contract-review leftovers).
- **Tests.**
  - Code delimiters:
    - at the recogniser: equal, double and unequal runs, a backtick shared by two values,
      delimiters kept when removing them would join a longer value, a narrow match
      checked against every eligible value, and allocation failure on both paths;
    - a repair bound to one value keeping delimiters whose removal would join another;
    - admission into an obligation field and a field that can't hold exact copies, with
      idempotence, including a code-wrapped value alone;
    - the composition check with a code-wrapped value alone and with prose.
  - Delimiting text:
    - at the boundary owner: straight, curly and CJK quotes, groups and nested pairs are
      direct pairs; no wrapper, punctuation inside the pair, a pair around a longer
      phrase, mismatched or one-sided wrappers, a continuation and a reference edge are
      not;
    - at the projection: an unrelated value in straight, curly and group pairs, with and
      without a direct pair, and the development cases' three exact values, which end in
      punctuation and take no span inside their pair, through rendering and the parse
      round trip, with a copy that has other punctuation inside the pair keeping its span; a
      copy touching a passive value or another exact copy whose bytes begin with the
      closer keeps it.
  - Paragraph reading for generation requests: a list item, a nested item, a heading and
    blank lines around a cited run, runs cited apart, a code line and an exact value in
    the run, each against the story's reading of the same claim; the stored quote and
    extraction and reconciliation requests unchanged. Structure with no wording: a fence
    with and without an info string in either fence kind, an empty fence, a table delimiter
    row with and without alignment, `=` and `-` underlines with the heading text above them,
    a thematic break, and the same bytes inside a fence, which stay; a quote left with none.
  - Quoting and splitting: top-level, ordered and nested items, continuation lines,
    headings and prose in and out of a split, wrapped numbers, look-alike markers and a
    thematic break, HTML blocks and comments, spacing and trimmed indentation, fenced
    code and an item that opens a fence, a chunk that starts inside a paragraph, and two
    sources whose chunks start inside and after fenced blocks.
  - Exact-value duty for a code span across lines and for fenced blocks: with a blank
    line, content lines only, the opening fence, indented content and an unterminated
    fence, and a blank first or last interior line, which the value excludes. Citing
    part of a block leaves it free.
  - Joining runs: an ellipsis between runs, including inside a JSON value.
  - Allocation stays proportional to the source across 128 chunks.
  - Admission: blank, unsupplied and over-count citations are rejected, for the initial
    request and for omission repair.
  - Omission repair inserts every new claim a list-spanning proposal quotes; an inserted
    duplicate adds nothing and is an unchanged merge; a list-spanning insertion whose first
    item is held adds only the second, with the repair's origin; the same lines in another
    category are inserted.
  - One evidence, one claim: identical proposals, and duplicates per item after the split,
    are one claim; the same lines in two categories (here, as an omission-repair
    insertion makes them), different lines and partly overlapping lines stay separate;
    the raw proposals are unchanged; duplicate claims quoting an exact value keep the
    single claim's exact-value duty.
  - A line is cited under one category (Decision 7):
    - the extraction request's schema admits one claim, claims on different lines, and
      shared lines in one category in any order or with repeats; it rejects a line cited
      under two categories at the first of the claims, whether the lines are the same, a
      whole list sits beside one of its items, or one line is shared, and among other
      claims, for the development cases' two source shapes;
    - the omission repair's request names no agreement;
    - the rule at the owning boundary, in an unrelated domain: a pair sharing one value,
      a whole list beside one of its items, lists that overlap in two values, three items,
      two groups, a shared value that agrees beside one that doesn't, a shared value in
      another array, and a selection without the rule that admits all of them;
    - the correction lists each group of values its items disagree on, the values that the
      same items cite forming one group, with the location of every item that cites them,
      refuses a response whose first disagreeing item is elsewhere or that has none, and
      is refused for a diagnostic of another reason;
    - a composition part that lacks the claims array leaves the selector unused and
      records nothing, and a selector that no schema holds is refused;
    - the recorded rule restores the same admission over the captured bytes, so replay
      rejects what live admission does, and a record that fits no captured schema is
      refused;
    - a scripted extraction answer that files one set of lines under two categories takes
      one correction naming the lines and both claims, and the run publishes from the
      answer that keeps one.
  - Ingestion rejects C1 and DEL characters.
  - A proposal carrying wording is rejected as an unknown property.
  - Scripted models cite only citable lines. Scenarios that need a discarded token or
    an exact-value omission now keep the token off every quoted line.
