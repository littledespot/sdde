# ADR 0024: Own exact-token authority and record scheduling natively

- **Status:** Accepted amendment
- **Date:** 2026-10-17
- **Decision authority:** The user's explicit instruction to implement FIX05 B5
  and B8 together, followed by approval of native exact duties independent of
  semantic kind and canonical-literal byte matching.
- **Amends:** Design §§16–17, their acceptance criteria, ADR 0020's record-task
  population and exact-kind gates, and ADR 0022's classification/disposition
  handoffs. The overall design remains **Proposed design**.

## Record scheduling

A current source group whose complete, nonempty membership consists entirely of
preserved-token claims receives no record-authoring batch. Mixed groups and other
semantic claim categories retain their existing eligibility. One native predicate
owns the count, dense scheduling index and direct group binding. Original signal,
claim, token and citation identities do not change.

This changes scheduling only. General content/question catalogues, narrative
support, clarification evidence and exact-occurrence scope retain token groups.
Zero record-authoring groups produces a typed native binding rejection; it does
not fabricate an empty completed record unit or ask the model to invent behavior.
The existing exact-coverage validator still requires obligation-bearing exact
targets and returns its typed missing-exact outcome when they are absent. Its
aggregate field policy is unchanged: an authorized narrative target can already
satisfy an exact duty; an incidental or prohibited target cannot.

## Native appearance and preservation

For each extractor-owned token candidate, native code checks the canonical
extracted business and scope-constraint claims from the same original chunk.
The token's complete captured byte sequence appearing as a substring of a literal
run forces preservation. Case, whitespace and Unicode bytes remain significant.
Adjacent literal segments form one run; passive/source insertions are opaque
boundaries and their rendered text supplies no match. Empty values are not
witnesses. This predicate uses stored canonical prose, after its existing NFC
validation; it does not reconstruct or match an earlier raw response spelling.
B3's contextual complete-value recognition rule remains a separate contract.

A matched candidate cannot be classified irrelevant. The model may still classify
its semantic kind; native appearance creates a mandatory behavioral exact-value
duty independently of that kind. Selecting `code_sample` or another kind cannot
remove this native duty or its occurrence eligibility. Unmatched candidates keep
their existing semantic relevance/kind rules. Existing kind-specific duties and
visual/style checks remain; the native rule adds no semantic truth claim.

Classification admission, authorized correction/repair, token construction and
stored reference validation use this same predicate. Stored validation rebuilds
the complete candidate/classification/token-claim accounting, including when all
token claims were omitted. A model-provided flag or a missing stored token cannot
hide a forced candidate. No native fact is inferred from a rendered view or log.

## Native token dispositions and duplicate obligations

Within the complete selected reference corpus, native code groups preserved-token
claims by exact captured bytes, without case, whitespace, Unicode or kind
equivalence. The earliest original claim ordinal is the retained representative;
each later equal-byte occurrence is a direct duplicate of it. Every distinct byte
sequence is retained. No token is semantically superseded or put into a model
conflict group. Genuine cross-source requirement conflicts remain decisions over
the extracted semantic claims.

Every original occurrence, token, citation and claim identity remains in canonical
reference state. Equal-byte grouping cannot select a weaker obligation from the
representative's kind: all original duties remain. Native occurrence recognition
uses the single retained representative to avoid competing equal-byte handles.
Validated direct duplicate edges allow that byte witness to discharge the
corresponding original exact-value duties. This does not add claims to authored
support `S` or turn byte equality into semantic support; `E` and `L` retain their
existing derivation from canonical recognized handles.

The model disposes only extracted semantic claims (`content.model`, including its
existing categories). It receives native token dispositions as read-only facts;
token IDs are excluded from disposition subjects, relationship targets and
conflict-group selections. Initial assembly adds native entries in stable original
claim order. Native entries retain native provenance. Shared validation and every
atomic/coupled source-repair path enforce the same boundary; a forged model token
choice cannot become authority through a later merge or stored readback.

## Persistence and verification

Completed and clarification-pending specification state persists these facts;
earlier state versions reject without a migration or compatibility reader.
Canonical specification content remains `specification/v3`. Readback recomputes
native appearance, dispositions, duplicate identities, exact eligibility and
complete coverage; it does not fill corrupt state with a reconstructed success value.

Regression evidence must include unrelated values, mixed kinds, cross-source
duplicates and semantic conflicts, missing forced tokens, forged native entries,
repair bounds and stored forgery. This decision authorizes no live call or budget
change; FIX05 records the implementation evidence.
