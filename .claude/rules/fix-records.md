---
paths:
  - "fixes/**"
---

# Fix records

`fixes/README.md` owns this convention. In short:

- `FIX01.md` is the sole active backlog. Record implementation progress there, and
  remove completed tasks from active tracking.
- `FIX04.md` is the active evaluation design for semantically simpler generation
  assignments. It keeps a short status table, not a progress log; the implementation
  work it needs is tracked in FIX01.
- Completed work and supporting dated reviews move to `Z_FIX01.md` or `Z_FIX02.md`.
  `archive/` is historical.
- `claude_connector.md` is an unaccepted provider proposal, not active work.
- Don't create parallel task checklists or implementation files.
- Historical proposals, status statements and checklists grant no approval and
  establish no live acceptance.
