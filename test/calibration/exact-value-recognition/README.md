# Offline native exact-value recognition prototype

This implements only the offline prototype in [FIX05 B3](../../../fixes/FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model)
(former FIX04 §1.1 item 1).
It makes no model calls and does not change production representation, schemas,
admission, coverage, repair, state or publication. ADR 0020 and the composition
contract remain authoritative; adoption still needs a decision.

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
binding under this policy. Current ADR 0020 separately permits an explicit typed
insertion to add `E` to selected support `S`; this prototype does not redefine that
rule or claim that its experimental restriction is current insertion eligibility.
Whether a unique prose match may add `E` under broader native eligibility is part
of the outstanding representation decision.

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
loan-renewal run's records call 10 (16 October, Australia/Melbourne). Current v5
descriptions are decoded at their canonical owner and their projections compared
exactly; the historical v3 loan description remains an opaque pinned witness.
Its absent native field metadata is not reconstructed from field names.

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
and unsupported archive placeholders explicitly retained. It does not qualify a
production representation switch.
