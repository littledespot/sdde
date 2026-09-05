# ADR 0008: Deterministic feature naming policy

- **Status:** Accepted for the approved identity-derivation increment
- **Date:** 2026-09-05
- **Scope:** Finalize the naming contract requested by the user; no feature activation

## Decision

`derive-feature-identity@1` consumes the complete validated NFC reference
selector and requires YAML `with: { max-length: <integer> }`, bounded to 1–255.
There is no default or global configuration override. This supersedes the
undefined `workflow.featureIdMaxLength` setting in design §17.2.

Naming policy `unicode17_ascii_v1` uses the existing statically linked utf8proc
2.11.3 / Unicode 17.0.0 dependency from ADR 0007. Its explicit transform is
`STABLE | DECOMPOSE | COMPAT | CASEFOLD | STRIPMARK`, as defined by the
[pinned API](https://github.com/JuliaStrings/utf8proc/blob/v2.11.3/utf8proc.h).
It performs compatibility decomposition, invariant case folding, and mark
removal, not language-specific transliteration. Selector NFC is unchanged.
One bounded adapter owns both transforms; no additional dependency is introduced.

After folding the whole selector, replace runs outside `[a-z0-9]`, including
segment separators, with one hyphen; trim ends. Truncate the ASCII result to
the configured maximum, trim any resulting trailing hyphen, and reject empty
or portable-invalid IDs through the shared path-component policy. Remaining
non-ASCII text becomes separators, not a guessed spelling. Folding has a
16,384-byte output ceiling; exceeding it fails without partial output.

The seed retains the exact canonical selector, policy version, maximum length,
and typed prospective ID. For example, `Café/Orders` becomes `cafe-orders`;
`日本語` fails with an empty ID. Distinct selectors can produce the same ID:
the seed is not ownership, availability evidence, or a directory capability.
Later registry/transaction gates must reject collisions; no suffix or override
is introduced here. Changing the naming transform requires a new policy version.

This operation has no filesystem or model capability. It creates no feature,
registry, transaction, log, clarification, or specification artifact.
