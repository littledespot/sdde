# ADR 0007: Pin shared Unicode NFC normalization

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Explicit user approval of a pinned normalization dependency and its native-packaging decision

## Decision

Use [utf8proc 2.11.3](https://github.com/JuliaStrings/utf8proc/releases/tag/v2.11.3),
pinned by URL and Zig content hash in `build.zig.zon`. Compile its C implementation
and Unicode 17.0.0 data into SDDE; do not load a host Unicode library or fetch data
at runtime. This adds no supported platform or runtime dependency beyond the
existing native platform/libc boundary.

One adapter owns NFC (`STABLE | COMPOSE`) behind a pure, bounded normalizer port.
It uses explicit byte lengths and caller-owned allocations; no compatibility
folding, case folding, transliteration, or removal of characters is implied.
Selector policy separately owns separator and segment rules. Existing ASCII
configuration-root policy remains unchanged.

[ADR 0008](0008-feature-naming-policy.md) adds a separately selected naming
transform to this same adapter. It does not change selector NFC or implicitly
enable folding for other consumers.

Install the dependency's MIT/Unicode license notices with the distribution.
Verify Unicode composition, invalid UTF-8, bounds, allocation failures, and
source-free native execution. Future version upgrades require normalization
regression tests and a recorded dependency update.
