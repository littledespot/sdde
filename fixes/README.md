# Fix records

[FIX06](FIX06.md) is the sole active fix record and current focus. It holds all open
work in one ordered sequence: quality phases, each validated by repeated E2E runs on a
committed build, plus engine, test, human-decision and research tracks, with the
evidence rules every phase follows. Keep implementation progress there instead of
maintaining parallel implementation files or task checklists.

FIX05 (the 17 October 2026 architecture review and consolidated open work) was retired on
28 October 2026: its open items moved to FIX06 under their original IDs, and its closed
items, snapshots and an ID map are in [Z_FIX05 §21](Z_FIX05.md#21-fix05-retired--28-october-2026).
FIX05 had replaced FIX01 (Spec reliability backlog) and FIX04 (semantic-simplicity
evaluation), deleted on 17 October 2026, whose full text remains in git at `b2f10a3`.
[claude_connector.md](claude_connector.md) is the source proposal for the direct
Anthropic provider, implemented as
[ADR 0028](../design/decisions/0028-anthropic-messages-provider.md); it is historical
and not active work.

Completed implementation, executed comparisons and their supporting dated reviews
are in [Z_FIX01](Z_FIX01.md), for earlier FIX01 work; [Z_FIX02](Z_FIX02.md), for
the FIX01-01, FIX01-02, FIX03 and FIX04 work of 10–16 October 2026 and the
unimplemented FIX02 proposal; and [Z_FIX05](Z_FIX05.md), for all completed FIX05 work,
its dated live diagnostics and its retirement record. Outstanding semantic quality,
clarification, resource and live acceptance work is in FIX06; cleanup does not mark it
complete.

The [archive](archive/) retains the original records, approval records,
implementation/run history and experiment evidence referenced by the design.
Historical status statements, checklists and proposals are historical, not active
work or new authorization. Accepted contracts and ADRs remain the governing
authority. The duplicate `FIX_003_TASKS.md` checklist has been removed.
