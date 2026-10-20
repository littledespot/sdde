# Known failure classes and open work

Dated snapshot, last updated 20 October 2026. It mirrors the repository's active fix
record, which stays authoritative. Recheck the code before relying on an item. The
evidence rules for contract changes are in CLAUDE.md.

The labels *Proposed*, *Approved* and "needs a decision" record user decisions. Only
the user changes them; change a label here only to record a decision the user has
already made.

## Spec workflow failure classes seen in live runs

- **Extraction collapses structured sources.** Extraction returns one claim for a
  whole Markdown list of distinct requirements, in every hello-world sample. It has
  also weakened an obligation: "must renew" became "may renew", and review judged
  that supported. *Proposed, not approved:* segment list items natively before
  extraction. Measure first: replay both cases' retained extraction requests, split
  per item. That replay is billed and needs bounded approval. Then decide the §16
  chunking and extraction amendment.
- **Review dominates cost and misreports finding types.** Post-generation review
  takes about 75–80% of workflow tokens. It files invented or unsupported content as
  `candidate_omission`, has judged byte-identical text both supported and omitted,
  and has accepted an obligation-strength change. Under ADR 0023 every
  post-generation finding is advice: it never repairs content, rebuilds an upstream
  stage or creates a clarification. *Built 20 October 2026 (approved 18 October):*
  source review assigns one record family per call (ADR 0023 "Record families",
  `specification-state/v19`). Its effect on cost is not yet measured live.
- **Record authoring duplicates.** A record batch can re-author the whole feature.
  Groups holding only preserved tokens no longer get a batch (ADR 0024). The native
  duplicate rule compares whole typed content, including the record kind, so
  identical text in two record kinds passes. *Proposed:* compare per-group records
  with one complete collection, only if generation-boundary failures remain. Add an
  acceptance-criterion diagnostic or per-family collections only where measured
  failures justify them.
- **Entity applicability is a model judgment** that no native rule can check.
  Hello-world has no data, yet it has been judged both `not_applicable` and
  `required`.
- **Unresolvable positive advisory verdicts** (FIX05 route 4) are withheld from the
  assignment's response schema. *Built 20 October 2026*: one in a response is a
  typed admission defect that takes protocol correction (ADR 0023). The reachable
  case is a coverage subject whose collection has no records. No live run has hit
  it yet.
- **GPT-OSS envelope prefixes.** GPT-OSS-20B often malforms a response's opening, for
  example `{"token{` or `{"find{`. Admission normalizes the truncated member-name form
  (approved 18 October 2026). Widening the normalizer needs a decision.
- **Budget headroom.** Loan-renewal has both exhausted the 100,000-token budget and
  published at 97,475 tokens. Raising the budget doesn't fix reliability.

## Other open work

- **Clarification answer recovery** is a confirmed implementation gap: fresh answers
  cannot complete the registered recovery path. Refresh rejects new nonempty
  submissions with `AuthenticationRequired`, and provenance rejects nonempty
  response-ID sets. Treat it as a separate required feature.
- **Log retention is not wired.** Design §26 requires retention after recovery and
  rotation, and F0002 §6.4 fixes 14 days. Only tests call `retainHistorical` or
  construct the segment pruner.
- **Group-level provenance precision.** A record binds a whole accepted group, so
  membership doesn't mean each record expresses every linked claim. This follows
  ADR 0020 and is not a defect. Decide it before promising stronger provenance.
- **Architecture decisions before Plan.** Several problems are known:
  - lifecycle mechanics live in workflow YAML;
  - each concept costs about six coordinated edits;
  - type-erased child bindings hide data flow;
  - many rejections carry no reason;
  - eight repair routes repeat one shape;
  - reconciliation always makes four calls;
  - two pairs of sibling steps are identical. *Proposed:* merge them; this needs no
    ADR change.

  Before starting Plan, decide the questions on lifecycle, edit cost, child bindings
  and repair routes, and freeze the contract scope. Move lifecycle mechanics out of
  YAML before adding operations for another workflow.
