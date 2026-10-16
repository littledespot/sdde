# Text-field composition — accepted amendments through 17 October 2026

Authority: the user's explicit instruction to settle the four Phase 1A decisions
and implement [FIX04 Phase 1A](../../fixes/Z_FIX02.md#phase-1a-plan-decisions-and-results).
The policy decisions amend §§7.1, 17.3, 22 and ADR 0020. ADR 0019 records the
debug-description/replay serialization needed to retain their native witnesses;
the overall design remains Proposed.

## Native exact values — approved 17 October 2026

The user approved both B3 choices: current native request-eligible occurrences may
contribute exact lineage `E` beyond unchanged selected support `S`, and complete
values use contextual delimiters. [ADR 0020](../decisions/0020-derived-exact-reference-lineage.md#native-exact-value-recognition-amendment--approved-17-october-2026)
owns the immutable snapshot/request scope, raw-byte recognition, ambiguity and
repair bounds. This supersedes model-authored `exact_copy` choices and ordinary
whole-word matching; B2 and W1 remain separate from this amendment.

Model text uses prose strings, typing required exact values verbatim; allowed
passive/source references may still use the closed fragments form. No model-facing
type, codec or schema admits `exact_copy`. Native recognition runs before NFC or
other text normalization and constructs canonical exact segments only for current
eligible occurrences in fields whose exact role permits them. Every disjoint
occurrence retains its source identity and raw byte span. Overlap or competing
eligible identities rejects the entire field, without a partial usable result.
Canonical normalization must preserve those bindings: if NFC of unmatched prose
would create an eligible match absent from the raw response, admission rejects a
typed exact-value defect instead of publishing inconsistent canonical authority.

Both outer delimiters must reach actual field edges or pinned Unicode whitespace,
optionally through directly balanced enclosing quote/group wrappers and terminal
prose punctuation before a delimiter. Attached further text remains continuation,
independent of token kind. Opaque run edges beside passive/source references are
not field edges; internal whitespace may still delimit an occurrence. The shared
[boundary owner](../../src/domain/exact_value_boundary.zig) holds the closed
wrapper and terminal policy. Terminal punctuation and negation can remain
semantically ambiguous; matching proves no correct use or fulfillment.

The field inventory below remains unchanged. A prohibited field keeps matching
bytes as prose without exact lineage. An incidental entity-name occurrence cannot
satisfy behavioral coverage. An obligation-bearing field still requires valid
prose composition: recognizing a whole value cannot turn a reference-only value
into behavioral explanation. Generation, response admission/correction, fixed
repair, canonical no-progress comparison, coverage and stored validation share
the same owner. Repair recognition precedes canonical comparison, with unchanged
old-value, revision, sibling, `S` and effective-evidence preconditions.

The native implementation and its offline acceptance evidence are recorded in
[FIX05 B3](../../fixes/FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model).
Offline checks establish mechanics, not live reliability or semantic benefit.
Historical prototype observations retain their original policy and denominators.

## Field inventory and insertion roles

One closed native field registry owns composition policy, issue explanations and
model-facing presentation. Initial authoring, protocol correction, all repair
routes, collection coverage and stored readback consume the same policy. A field
has `required | optional` prose and a `prohibited | incidental |
obligation_bearing` role for each insertion kind. Presence of prose is mechanical
evidence only; its adequacy, support and actual use of an inserted value remain
semantic judgments.

| Declared fields | Nonblank prose | Exact-copy role | Passive/source roles |
| --- | --- | --- | --- |
| Brief description, story; AC Given/When/Then; visible outcome; edge condition/outcome; functional requirement, business rule, non-goal, prohibited behavior | Required | Obligation-bearing | Passive incidental; source prohibited |
| Brief title and goal; entity-applicability basis; entity meaning and each relationship; assumption; clarification question | Required | Prohibited ([Phase 1A.2 amendment](#phase-1a2-amendment--exact-copies-only-where-they-can-carry-an-obligation)) | Passive incidental; source prohibited |
| Entity name | Optional: supplied insertions may express an identity label | Incidental | Passive incidental; source prohibited |
| Extraction and reconciliation business and scope-guard text | Required | Prohibited: preserved-token records carry exact-value identity separately | Passive incidental; source prohibited by their business-text contract |
| Extraction design, technical, validation, implementation-assumption and open-question text; no-feature-claim reason; reconciled versions of those meanings and conflict summary | Required | Prohibited: preserved-token records carry exact-value identity separately | Passive and source incidental |

An incidental occurrence retains its exact lineage and rendering but cannot
satisfy behavioral exact-copy coverage. Coverage credits only an occurrence in
an obligation-bearing field whose composition validated. Exact-copy support is
retained; display equality alone never creates an occurrence outside the approved
current native exact-occurrence scope and recognition policy.
Entity names are the sole field allowed to omit prose; no workflow, filename,
provider, model or current fixture creates another exception. This is not a
fragment-count restriction: several legitimate identity components retain their
normal lineage and semantic checks, without satisfying behavioral coverage.

## Phase 1A.2 amendment — exact copies only where they can carry an obligation

**Approved and implemented offline, 16 October 2026.** Authority: the user's explicit
approval of [FIX04 Phase 1A.2](../../fixes/Z_FIX02.md#phase-1a2-plan-decisions-and-results)
decision 1, following the live evidence in
[FIX04 F11](../../fixes/Z_FIX02.md#f11--high-admission-now-stops-the-defect-but-generation-cannot-recover-from-it).
The native registry now enforces this amendment; separately approved live diagnostics
remain required before closing Phase 1A.2's exit gate.

- **Role change.** In the descriptive fields of the inventory's second row (brief
  title and goal, entity-applicability basis, entity meaning and each relationship,
  assumption, clarification question), the exact-copy role changes from incidental
  to **prohibited**. Prose remains required. Passive and source roles are unchanged.
- **Presentation follows the role.** These fields' projected schemas, guidance and
  offered choices contain no exact-copy insertion. Passive references remain
  permitted, so the native prose-presence check still applies. Where the selected
  contract permits no insertion kind, its schema offers only literal text forms;
  native admission still checks that prose is nonblank.
  A literal the model types there is ordinary prose: the prohibited exact role
  creates no occurrence, lineage or coverage, and display equality never supplies one.
- **Admission and readback.** Admission, protocol correction, every repair route and
  stored readback reject an exact-copy insertion in these fields as a prohibited
  insertion, through the same owners as other prohibited insertions. There is no
  compatibility reader for stored values that contain one.
- **Coverage is unchanged.** Occurrences in these fields could not satisfy behavioral
  exact-copy coverage before this amendment and no longer exist after it.
  Obligation-bearing fields keep exact-copy insertions together with the native prose
  requirement, which schemas still cannot express.
- **Entity names keep the identity-label exception** and an incidental exact-copy
  role; after this amendment they are the only field with that role.

Native wire-type declarations bind each returned text leaf to the registry. The
shared schema owner projects its permitted insertion alternatives for initial
requests, protocol corrections and repairs. Guidance lists only leaves present in
the actual selected schema, including clarification questions when that schema
permits a clarification response. It identifies the fields that may use each
insertion kind; exact-copy catalogues and token-only source-group choices are
offered only when a returned field can use them. Original source evidence remains
available under its separate evidence contract. Model-visible projection does not
change the immutable native packet used for assignment and retention checks.

The previous whole-field raw-literal-to-`exact_copy` coverage reconstruction
cannot produce valid prose in an obligation-bearing field and is removed.
Missing coverage without an independently supported, composition-valid target
returns the existing typed blocked outcome. The engine does not invent prose,
infer occurrences from display equality or add a model assignment to escape it.

## Wire syntax and the source-occurrence exception

The codec's closed string-or-`fragments` form declares model text. Native field
metadata additionally identifies plain-string clarification questions in selected
review/repair responses, without classifying strings by their names or content.
An insertion object, or a complete `fragments` object, written inside its prose is a protocol
error, including across adjacent prose fragments. Ordinary JSON in unrelated
string contracts is unaffected. Recognition uses the closed grammar, not a
keyword or substring ban on braces, JSON or the word `exact_copy`.

The exception is an exact byte occurrence of that complete grammar object in
the current captured original sources. Whitespace and escaping inside the object
are not canonicalized for this comparison. Guidance, derived claims, earlier
model responses, matching display values and sibling candidates do not qualify.
Native request metadata retains the original-source witness across composition,
correction and repair; it is not a provider tool or additional model capability.
Current debug descriptions retain that witness for exact diagnostic replay.
Canonical text normalization preserves the exact bytes of these source-backed
wire-object spans while NFC-normalizing surrounding prose through the existing
normalization owner. Admission, repair comparison and stored revalidation use
that same normalization; the exception cannot admit a value that later fails
readback solely because the engine rewrote its source literal.

Rejection uses the existing bounded protocol-correction path and never converts
prose into an insertion or changes its bytes. Native and stored-value validation
enforce the same rule if a canonical value bypasses wire decoding. A
prose-required value containing only insertions is a typed `reference_only`
composition issue. Under the implemented
[Phase 1A.3 amendment](#phase-1a3-amendment--composition-defects-are-corrected-as-a-unit),
it is rejected at response admission and corrected through the same bounded
protocol correction before review.

Stored clarification state can undergo structural loading before reference
ingestion supplies the current original sources. Its engine-owned questions must
pass the same source-aware policy before refresh, rendering or publication,
including retained records. This does not grant applicability from structural
loading, add persisted source witnesses or permit rewriting protected forms.
User answers retain their separate input contract.

## Phase 1A.3 amendment — composition defects are corrected as a unit

**Approved and implemented offline, 16 October 2026.** Authority: the user's explicit
approval of [FIX04 Phase 1A.3](../../fixes/Z_FIX02.md#phase-1a3-plan-and-decisions-as-approved)
decision 4, option (a), following the live evidence in
[FIX04 F12](../../fixes/Z_FIX02.md#f12--high-descriptive-fields-recover-but-record-fields-collapse-to-insertions).
Implementation and verification are recorded in
[the Phase 1A.3 record](../../fixes/Z_FIX02.md#543-phase-1a3-admission-routing-and-attribution-preparation).
Live attribution and the separately approved workflow diagnostics remain open.

- **Detection moves to response admission.** The composition rules of this contract
  (required prose, prohibited insertion kinds and wire syntax) are checked when a
  model response is admitted, using the native wire-field bindings that already map
  each returned text leaf to its registry field. One rejection reports every
  violating field of that response, each with its typed reason (`reference_only`,
  prohibited insertion or embedded insertion syntax).
- **Correction uses the existing protocol-correction owner.** The rejected response
  goes through the same bounded protocol correction as other admission failures. It
  retains the active assignment, schema, eligible catalogue and retry allowance, and
  presents the complete original request with the typed reasons. No new correction
  allowance, route or model call is added; exhausting the existing bound ends in its
  existing typed outcome.
- **Every response type is covered.** Generation units, extraction, reconciliation,
  clarification questions and repair responses all apply the rule at their own
  admission and correct through their own request's protocol-correction bound.
- **Unit repair no longer receives composition defects.** The composition-specific
  repair presentation introduced in Phase 1A.2 is removed with this routing unless
  another consumer still needs it; there is no parallel path. Repairs for other
  defect kinds, and their `unchanged_repair` exhaustion, are unchanged.
- **Unchanged elsewhere.** Native and stored-value validation still enforce the same
  rules for values that bypass wire decoding, with no compatibility reader. Coverage,
  the source-occurrence exception and the field inventory are unchanged.

## Unchanged repair and reporting

Composition defects use response-level protocol correction. Other diagnostic
kinds keep their structured unit-repair presentation and exact native old-value,
revision and dependency witnesses for compare-and-swap; every replacement uses
the same per-field schema projection and response admission.

After exact active-permit, old-value, revision and dependency checks, canonical
replacement equality identifies no progress for that same defect key. The shared
comparison joins adjacent prose fragments and applies that canonical text
normalization only to declared model-text fields, retaining every insertion's
identity and order. Exact old-value/dependency preconditions remain byte-exact;
progress comparison cannot weaken compare-and-swap or infer semantic equivalence.
The shared runner returns typed exhaustion with reason `unchanged_repair` and the actual
completed count. The exact active permit retains its latest admitted allowance
owner, whether a model-request node or a separately bounded merge node; exhaustion
uses that owner's recorded operation, limit and count. A new authorization cannot
borrow an earlier authorization's admitted attempt. The runner discards the
tentative delta before application: no new
candidate revision, invalidation, semantic review, resolved authority or
publication follows. It preserves charged sends/tokens and makes exhaustion
terminal for the current key. A new target or foreign permit cannot borrow that
decision. Changed repairs retain impacted and full validation, normal limits and
all existing publication gates; no new allowance is granted.

The harness calls its first mechanically recorded rejection `first_native_rejection`.
Representation/admission is a separate failure-attribution category, not a paid
model stage. Admission-escape reporting rechecks admitted native fields with the
canonical composition/wire owners, preserves exact field/origin evidence, and
distinguishes measured zero, observed escape and unavailable coverage. Downstream
sends/tokens describe exposure after the first observed escape; chronology alone
does not prove that every later call was caused by it.
The primary escape denominator is invoked native workflows, including recorded
invocations that fail before their first model send. Missing audits remain
unknown. The comparison scorer's dispatched generation-arm convention is
unchanged; distinct observed producers provide a secondary admission diagnostic.
Producer evidence is a closed model/native/unavailable union. Native summary reuse
links to an earlier audited value and its validation digest; refreshed engine-owned
questions retain validated clarification-state identity. Neither creates a model
receipt. Complete audits containing native producers can report measured zero;
missing model receipts and missing native parents remain unavailable.

Offline tests cover the complete field inventory, legitimate in-sentence and
identity insertions, source exceptions, wire syntax, all repair/readback paths,
coverage and unchanged-repair exhaustion. Replay uses retained authentic outputs
as untrusted input to current admission, never as current workflow authority.
Passing proves mechanical enforcement, not semantic quality or useful completion.
