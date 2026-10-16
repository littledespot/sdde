# Representation admission: retained offline evidence

[retained.json](retained.json) copies exact model-output and transport-context
bytes from the five development diagnostics listed in FIX04 F10. SHA-256 values
bind each raw response, context, original source and selected wire value. The
closed `representation-admission-capture/v1` fixture has no workflow authority.
Historical reports and request descriptions are neither rewritten nor imported
through a compatibility reader.

The replay covers 23 captured exchanges and 79 selected values: 10 insertion-only
values, 19 values containing encoded insertion syntax and 50 prose-bearing
controls from the same captures. All F10 exchanges are included; the final run's
brief and record calls add controls. Authoring and omission-repair values retain
their original field policies. For 13 October hello-world call 13, the escaped
description is the exact `subject.text` in the captured review request. The
reviewer's diagnostic explanation is not a business-text field and is not
mislabelled as rejected generation.

[The integration replay](../../integration/representation_admission_tests.zig)
uses native envelope normalization, the exact captured selected response schema,
native wire decoding, shared composition checks and the shared source-aware
wire guard. Singleton exact-copy handles are reconstructed only from that
captured schema's construction fact and its sole supplied preserved-token ID.
No current workflow request or origin is manufactured. Separate parcel-delivery
and room-booking controls construct real passive references through native
ingestion and registry owners.

This runs within `zig build test-integration`, with no provider, credentials or
dependency on ignored `zig-out` files. It writes the mechanical counts to
`.zig-cache/representation-admission/replay.json`. Passing proves these captured
mechanical defects now stop at their owners; it assesses neither semantic
quality nor live workflow completion.
