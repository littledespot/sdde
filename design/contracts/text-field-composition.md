# Text-field composition — accepted Phase 1A amendment, 16 October 2026

Authority: the user's explicit instruction to settle the four Phase 1A decisions
and implement [FIX04 Phase 1A](../../fixes/FIX04.md#phase-1a--close-the-representation-admission-gap-before-the-baseline).
The policy decisions amend §§7.1, 17.3, 22 and ADR 0020. ADR 0019 records the
debug-description/replay serialization needed to retain their native witnesses;
the overall design remains Proposed.

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
| Brief title and goal; entity-applicability basis; entity meaning and each relationship; assumption; clarification question | Required | Incidental | Passive incidental; source prohibited |
| Entity name | Optional: supplied insertions may express an identity label | Incidental | Passive incidental; source prohibited |
| Extraction and reconciliation business and scope-guard text | Required | Prohibited: preserved-token records carry exact-value identity separately | Passive incidental; source prohibited by their business-text contract |
| Extraction design, technical, validation, implementation-assumption and open-question text; no-feature-claim reason; reconciled versions of those meanings and conflict summary | Required | Prohibited: preserved-token records carry exact-value identity separately | Passive and source incidental |

An incidental occurrence retains its exact lineage and rendering but cannot
satisfy behavioral exact-copy coverage. Coverage credits only an occurrence in
an obligation-bearing field whose composition validated. Exact-copy support is
retained, and ordinary prose equal to a display value never creates an occurrence.
Entity names are the sole field allowed to omit prose; no workflow, filename,
provider, model or current fixture creates another exception. This is not a
fragment-count restriction: several legitimate identity components retain their
normal lineage and semantic checks, without satisfying behavioral coverage.

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
composition issue, routed through existing authorized unit repair before review.

Stored clarification state can undergo structural loading before reference
ingestion supplies the current original sources. Its engine-owned questions must
pass the same source-aware policy before refresh, rendering or publication,
including retained records. This does not grant applicability from structural
loading, add persisted source witnesses or permit rewriting protected forms.
User answers retain their separate input contract.

## Unchanged repair and reporting

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
unchanged; distinct producer origins provide a secondary admission diagnostic.

Offline tests cover the complete field inventory, legitimate in-sentence and
identity insertions, source exceptions, wire syntax, all repair/readback paths,
coverage and unchanged-repair exhaustion. Replay uses retained authentic outputs
as untrusted input to current admission, never as current workflow authority.
Passing proves mechanical enforcement, not semantic quality or useful completion.
