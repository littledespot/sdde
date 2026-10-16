# Fix records

[FIX01](FIX01.md) is the sole active backlog and current focus. It contains the
outstanding findings, proposed sequence and required verification. Keep
implementation progress there instead of maintaining parallel implementation files
or task checklists.

[FIX04](FIX04.md) is the active evaluation design for semantically simpler
generation assignments: its findings, experiment design and evidence gates. It keeps
a short status table, not a progress log; the implementation work it needs is
tracked in FIX01. [claude_connector.md](claude_connector.md) proposes a direct
Anthropic provider and is neither accepted nor implemented.

Completed implementation, executed comparisons and their supporting dated reviews
are in [Z_FIX01](Z_FIX01.md), for earlier FIX01 work, and [Z_FIX02](Z_FIX02.md), for
the FIX01-01, FIX01-02, FIX03 and FIX04 work of 10–16 October 2026 and the
unimplemented FIX02 proposal. Outstanding semantic quality, clarification, resource
and live acceptance work remains in FIX01 and FIX04; cleanup does not mark it
complete. FIX01 §8 preserves the broader unresolved audit scope.

The [archive](archive/) retains the original records, approval records,
implementation/run history and experiment evidence referenced by the design.
Historical status statements, checklists and proposals are historical, not active
work or new authorization. Accepted contracts and ADRs remain the governing
authority. The duplicate `FIX_003_TASKS.md` checklist has been removed.
