# Fix records

- [SPEC01](SPEC01.md) holds open work and user decisions not yet recorded in an ADR. Each item
  names the published-output defect it targets, its owner, status, next step and one-line
  evidence; a decision recorded in an ADR is cited, not restated.
- [Z_SPEC01](Z_SPEC01.md) holds implemented SPEC01 items. Move an item there when it is
  implemented; its open parts and keep decision stay in SPEC01.
- Delete closed or reverted work; git history keeps it. No other files in `fixes/`.
- Nothing in either file grants approval or establishes live acceptance.
