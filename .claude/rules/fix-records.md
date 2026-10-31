---
paths:
  - "fixes/**"
---

# Fix records

`fixes/README.md` owns this convention. In short:

- `FIX06.md` is the sole active fix record: all open work in one ordered sequence,
  keeping the IDs of the retired FIX05 (and of FIX01 and FIX04 before it). Record
  implementation progress there, and remove completed tasks from active tracking.
- Completed FIX06 work moves to `Z_FIX06.md` (create it when first needed);
  `Z_FIX05.md` holds FIX05 work and its retirement (§21), and `Z_FIX01.md` and
  `Z_FIX02.md` hold earlier work. `archive/` is historical.
- `claude_connector.md` is the historical source proposal for ADR 0028, not active
  work.
- Don't create parallel task checklists or implementation files.
- Historical proposals, status statements and checklists grant no approval and
  establish no live acceptance.
