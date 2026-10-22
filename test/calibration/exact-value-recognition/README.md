# Exact-value recognition evidence and approved B3 cutover

This directory retains the historical offline prototype and policy comparisons
for [FIX05 B3](../../../fixes/Z_FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model)
(former FIX04 §1.1 item 1). The tools make no model calls; their captured
observations remain diagnostic evidence under their original policies.

**Approved and implemented 17 October 2026; full offline verification passed.** The user chose
current native request-eligible occurrence scope, allowing recognized `E` beyond
unchanged selected support `S`, and contextual complete-value delimiters. The
accepted [ADR 0020 amendment](../../../design/decisions/0020-derived-exact-reference-lineage.md#native-exact-value-recognition)
and [composition contract](../../../design/contracts/text-field-composition.md#native-exact-values)
govern the cutover. `zig build verify -j1 --summary all` passed 163/163 steps and
1,818/1,818 tests, including clean native packaging smoke checks. B2 and W1 remain
separate, unapproved decisions. No live fidelity, cost or publication improvement
is claimed here.

## Current production-admission replay — 17 October 2026

Run the retained-output integration check with no provider or credentials:

```sh
zig build test-exact-value-admission -j1 --summary all
```

It writes the repeatable machine report to
`.zig-cache/exact-value-production-admission/report.json`. The focused check passed
**3/3 build steps and 2/2 tests**. The complete integration suite also owns this
test; the historical prototype command below measures a different contract.

| Requested 16 October run (AEDT) | Retained output replayed | Current production result |
| --- | --- | --- |
| 16:20, insertion-only title | F11 call 7 | Typed `prohibited_exact` rejection; old exact-copy objects also fail the current schema and codec |
| 18:58, collapsed records | F12 call 13 | Typed `reference_only` rejection for Given, When, Then and FR; old exact-copy objects also fail the current schema and codec |
| 20:22, prose without insertions | F13 call 13 | Admitted: three records, two native exact nodes, unchanged `S`, one exact claim added through `E`, one coverage obligation with two behavioral targets |
| 20:33, generation passed before review/budget failure | Raw capture unavailable | Explicit unavailable row; no replay success or escape result is attributed to this run |
| 22:00, insertion syntax in prose | Call 8 | Typed `embedded_insertion_syntax` rejection in description |

The report counts **four of five requested runs actually replayed**, with zero
admission escapes among those four; three reject and F13 admits. A separate,
explicitly scripted loan-renewal control admits two records through the same
native exact-lineage and coverage checks. That control is not an authentic live
capture. The unavailable 20:33 execution is
`2026-10-16T09-33-15Z-d749fce107972fd4feaad6c9ac902538`; its exact replay remains
unverified. F13 supplies an authentic admitted-generation control for the distinct
B3 admission class, without substituting it as evidence for 20:33. Neither review
meaning, harmful repair, budget behavior nor semantic fidelity is assessed here.

The replay keeps raw retained response bytes unchanged and verifies their hashes.
The first two inputs come from the immutable representation archive; F13 comes
from this directory's retained archive. A separately pinned copy of the latest
call's context, original source and output lives in
[retained_current_admission.json](../../harness/exact_value/retained_current_admission.json).
No original capture is edited. Each report row records output/source hashes and
the current selected-schema hash.

Old request descriptions remain historical witnesses. The test explicitly builds
a fresh, scripted current reference/session context over the retained original
source bytes, including native structured-token extraction and scripted semantic
claims/groups. Current session packet owners supply the immutable exact scope,
field policies and selected schema. The test never promotes old metadata to v6,
infers scope from an offered token catalogue, or treats scripted interpretation as
semantic proof. A fake provider supplies the unchanged output to production
invocation validation and `admit-model-response`. Successful record candidates
continue through current `g.parse`, `g.validate`, lineage, exact coverage and stored
validation. This is offline integration evidence, with zero real model calls,
publication, workflow authority or new live-run authorization.

## Historical baseline — 16 October 2026

The pure Zig recognizer receives raw decoded UTF-8 prose, an explicit requirement
binding, and occurrence identities with their declared requirement bindings. It
records exact byte spans only for eligible occurrences. Case, Unicode spelling,
punctuation and whitespace are never normalized or repaired. Repeated disjoint
occurrences remain separate spans. Competing lineages for the same span, or
overlapping eligible spans, make the field ambiguous; there is no longest-match,
first-match or catalogue-order tie breaker. Out-of-binding byte matches are
reported separately and never establish a recognized occurrence.

The experimental whole-value boundary policy uses the existing pinned Unicode
classifier, with connector punctuation and format characters kept inside words.
Letters, numbers, combining marks and adjacent CJK text therefore prevent a
substring match. Spaces and ordinary punctuation delimit a value. Both outer
boundaries must qualify, including for values that themselves end in punctuation.
This is an explicit prototype policy, not an amendment to production text rules.

Recognition is not semantic evidence. A matching value can occur in a negated or
irrelevant sentence; its use still needs semantic assessment. The word-boundary
policy also recognizes `1.2` inside `1.2.3`, and `/v1/renewals` inside
`/v1/renewals/archive`. These explicit lexical-limit tests demonstrate that a
match cannot establish preservation of the complete intended version or path.
No domain-specific punctuation ban has been added to hide that limitation.
Nor does byte
equality relate a preserved token to a behavioral requirement. The corpus runner
uses the explicit experimental `selected_requirement_membership` policy: an
occurrence's own claim ID must be in the field's captured assigned/selected
requirement set. A token and a business
claim from the same source are not automatically bound to each other. Missing
historical metadata remains unavailable, and an offered token catalogue is not a
binding under this policy. Before the 17 October cutover, ADR 0020 permitted an
explicit typed insertion to add `E` to selected support `S`; the historical
prototype did not redefine that eligibility. The later approval instead allows
unique native prose recognition within current request eligibility. It does not
retroactively manufacture eligibility or requirement relations for old captures.

The independent [controls](controls.json) supply accepted, rejected and ambiguous
cases with expected results fixed independently of the recognizer. Authentic
capture regressions run separately as integration tests. The full-corpus command
inventories retained physical captures, including request-only records and
historical metadata gaps; mirrored captures are not independent samples.
Legacy typed insertions and any display projection must remain distinguishable
from exact values actually typed in captured prose. Mechanical recognition and
composition checks do not establish a false-positive rate or workflow completion.
The recognizer's proposed nodes are checked against the existing composition
owner: a value-only match cannot become valid behavioral prose, and an incidental
entity-name occurrence cannot acquire behavioral coverage authority.

The [retained regression fixture](retained.json) pins the exact request
description, packet, selected schema and raw model text, with the context and
physical prompt-log SHA-256 witnesses. Its two F13 responses are the 20:22
hello-world run's records calls 13 and 14, and its unrelated control is the 08:09
loan-renewal run's records call 10 (16 October, Australia/Melbourne). At that
baseline, then-current v5 descriptions were decoded at their canonical owner and their projections compared
exactly; the historical v3 loan description remains an opaque pinned witness.
Its absent native field metadata is not reconstructed from field names.

## B3 policy comparison — 17 October 2026

The initial B3 approval authorized comparison of its open binding and punctuation
questions. The user subsequently approved `request_eligible_occurrences` and
`delimited_complete_value_v1` for production. The alternatives and results below
retain the dated experimental comparison; they are not selectable production
modes. The native implementation and complete offline verification have passed; the live gate remains open.

### Binding scope

Authored source-group selection supplies explicit claims `S`. Before the cutover,
production derived additional exact dependencies `E` from an explicitly selected
eligible insertion, retaining `L = stableUnique(S + E)`. Native recognition must
not silently turn an offered catalogue, a common source or equal bytes into a
semantic requirement association.

The [binding comparison](../../../test/harness/exact_value/binding_experiment.zig)
separates three policies:

| Experimental policy | Exact occurrence eligibility | Consequence |
| --- | --- | --- |
| `selected_requirement_membership` | The token's own claim is already in `S` | Preserves the original prototype restriction; cannot recover the business-bound F13 response. |
| `request_eligible_occurrences` | A current native request scope explicitly authorizes that occurrence; `S` stays fixed | Replaces explicit insertion selection with unique lexical recognition, allowing `E` beyond `S`. Approved 17 October as exact-occurrence authority; it does not prove semantic support. |
| `explicit_requirement_relation` | A current native relation explicitly joins the occurrence to a selected requirement | Requires relation evidence that existing retained business-bound F13 metadata does not provide. Same source and matching text cannot manufacture an edge. |

Synthetic controls state their native eligibility and relation assumptions
explicitly. Current context identity, selected claims, eligible occurrences and
fixed repair scope are validated separately from matching. Missing historical
native eligibility remains unavailable; it is not retroactively asserted from
the projected `preserved_tokens` catalogue. Historical F13 results remain the
selected-membership observations recorded above.

The offline comparison checkpoint had 12 synthetic cases under each policy (36
observations). All then-declared expectations passed:

| Policy | Matched | No match | Ambiguous | Rejected | Unavailable |
| --- | ---: | ---: | ---: | ---: | ---: |
| Selected requirement membership | 2 | 5 | 2 | 2 | 1 |
| Request-eligible occurrences | 5 | 2 | 2 | 2 | 1 |
| Explicit requirement relation | 4 | 3 | 1 | 2 | 2 |

The different counts express different explicit policies, not comparative
accuracy. Guards also cover foreign snapshot/request/unit/field identities,
invalid IDs, changed repair selections, changed eligible occurrence sets, changed
relation edges and allocation failure.

### Complete-value boundaries

The [boundary comparison](../../../test/harness/exact_value/boundary_experiment_tests.zig)
tests the approved `delimited_complete_value_v1` policy at its single canonical
[owner](../../../src/domain/exact_value_boundary.zig) against independently declared
accepted and rejected spans. Unlike the historical word-boundary policy, it uses
surrounding span context. Actual field edges, pinned Unicode
whitespace, balanced enclosing quote/group punctuation and terminal prose
punctuation before a delimiter can delimit a complete exact value. Punctuation
attached to additional value text cannot: `1.2` inside `1.2.3`, a path followed by
`/archive`, and an identifier followed by `-suffix` are the same rejection class.
No branch is selected by token kind, domain, filename or motivating example.
Literal runs beside passive/source references have opaque boundaries, not field
edges; only an interior delimiter can qualify there. The closed 25-codepoint
Unicode White_Space syntax is pure domain data, checked exhaustively against the
pinned Unicode property without giving persisted parsers operation ports.

The offline comparison checkpoint passed all 60 declared boundary controls: 31 accepted complete
spans and 29 rejected continuations/wrapper cases. Additional tests preserve the
original baseline's prefix observations and cover invalid UTF-8/scalar spans,
exact offsets, negation and the remaining terminal-punctuation ambiguity.

This is a conservative lexical policy, not a determination of the intended
complete value. Quoted or whitespace-delimited bytes can still occur in negated
or irrelevant prose. Neither lexical policy establishes semantic preservation,
workflow completion, a false-positive rate or a publication improvement.

### Approved production cutover — implemented and verified offline

The chosen exact-occurrence scope and contextual boundary policy are recorded in
the composition, §7.1 and ADR 0020 amendments. The coordinated implementation
removes model-authored `exact_copy` from both
types/decoding and schemas; retain canonical native occurrences; recognize raw
bytes before normalization; and apply one policy through response-level
composition correction, generation, fixed-scope repair, no-progress comparison,
coverage, rendering and stored readback. Field roles and ambiguity remain
blocking native checks. Existing historical evidence is retained as evidence,
not a compatibility reader or a second production authority path.

The historical comparison and canonical boundary controls run through
`test-exact-value-replay` and the canonical unit suite. They make no model calls.
Their results qualify mechanical policy, not production completion or live
reliability. Before the production cutover, the offline comparison checkpoint
`zig build test-exact-value-replay lint test-architecture -j1 --summary all`
passed 10/10 steps and 209/209 tests (68 exact-value/Unicode tests and 141
architecture tests), including the independent control matrices above.

Run through repository-owned build steps:

```sh
zig build test-exact-value-replay -j1 --summary all
zig build exact-value-replay -j1 -- --output zig-out/exact-value-recognition.next.json --root zig-out --root test/calibration
zig build test-integration -j1 --summary all
zig build verify -j1 --summary all
```

The executable has no dispatch mode or credential lookup. Its report is a
diagnostic projection, never production occurrence, lineage or coverage authority.
Output creation is exclusive; choose a fresh filename for another scan. The
completed scan and its SHA-256, denominators, unavailable evidence and open
representation questions are recorded in [Z_FIX02 §5.4.6](../../../fixes/Z_FIX02.md#546-offline-native-exact-value-recognition-prototype).
The report inventories 3,743 physical rows and measures 454 fields, with mirrors
and unsupported archive placeholders explicitly retained. It does not qualify
production completion or live effects.
