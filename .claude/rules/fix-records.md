---
paths:
  - "fixes/**"
---

# Fix records

`fixes/README.md` owns this convention. In short:

- `FIX05.md` is the sole active fix record: the architecture review plus all open
  work consolidated from the deleted FIX01 and FIX04. Record implementation progress
  there, and remove completed tasks from active tracking.
- Completed work and supporting dated reviews move to `Z_FIX05.md` (FIX05 work);
  `Z_FIX01.md` and `Z_FIX02.md` hold earlier work. `archive/` is historical.
- `claude_connector.md` is the historical source proposal for ADR 0028, not active
  work.
- Don't create parallel task checklists or implementation files.
- Historical proposals, status statements and checklists grant no approval and
  establish no live acceptance.
