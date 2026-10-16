# Representation admission: retained offline evidence

[retained.json](retained.json) copies authentic request, response, transport outcome,
model-output and context bytes from the five development diagnostics in FIX04 F10
and the 16 October 2026 F11 and 18:58 F12 diagnostics. SHA-256 values bind each
artifact, original source and selected wire value. The closed
`representation-admission-capture/v3` fixture has no workflow authority.
Historical reports and request descriptions are
neither rewritten nor imported through a compatibility reader.

The replay covers seven runs, 32 exchanges and 100 selected values: 13
`reference_only` rejections, five `prohibited_exact` rejections, 20 values containing
encoded insertion syntax and 62 admitted controls. All F10 exchanges are
included; F11 adds the brief and unchanged title-repair responses, with description
and goal controls from its brief. Every value retains its native field identity and
is assessed against the current approved field policy. F10's two insertion-only
titles and entity basis now reject as `prohibited_exact` under the Phase 1A.2
amendment; their authentic wire bytes remain unchanged.

F12 adds calls 8–14: the brief and its protocol correction, the insertion-only story
and successful story repair, the entity-applicability basis, all seven text fields
from the records response and the unchanged Given repair. All four defective records
fields reject as `reference_only`; the insertion-only entity name admits under its
declared identity-label policy. The basis and entity prose remain mechanical
controls; their admission does not establish correct entity applicability or meaning.

For 13 October hello-world call 13, the escaped description is the exact
`subject.text` in the captured review request. The reviewer's diagnostic explanation
is not a business-text field and is not mislabelled as rejected generation.

[The integration replay](../../integration/representation_admission_tests.zig)
uses native envelope normalization, the canonical selected-schema compiler adapter,
native wire decoding, shared composition checks and the source-aware wire guard.
The schema-only wire guard rejects 11 complete responses for encoded insertion
syntax. Those response counts are separate from selected native-field results.
Historical contexts retain no native field-binding metadata, so the replay does
not invent those bindings or claim to exercise whole-response composition admission
or bounded protocol-correction routing. Current routing is verified separately at
its production boundary.
Singleton exact-copy handles are reconstructed only from the captured schema's
construction fact and its sole supplied preserved-token ID. Separate parcel-delivery
and room-booking controls construct real passive references through native ingestion
and registry owners. A native summary-reuse scenario exercises canonical reuse and
validation actions, known native provenance and missing-model-evidence negatives.
These scenarios create no authentic provider evidence or workflow authority.

This runs within `zig build test-integration`, with no provider, credentials or
dependency on ignored `zig-out` files. It writes the closed
`representation-admission-replay/v3` mechanical count artifact to
`.zig-cache/representation-admission/replay.json`. Passing proves these retained
mechanical defects stop at the current owners; it assesses neither semantic quality
nor live workflow completion.
