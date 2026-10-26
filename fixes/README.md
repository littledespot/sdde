# Fix records

[FIX05](FIX05.md) is the sole active fix record and current focus. It holds the
17 October 2026 architecture review, the outstanding work, the decisions it needs,
the proposed sequence and the required verification. Keep implementation progress
there instead of maintaining parallel implementation files or task checklists.

FIX05 replaced FIX01 (Spec reliability backlog) and FIX04 (semantic-simplicity
evaluation), which were deleted on 17 October 2026. Their open items keep their
former IDs in FIX05, and their full text remains in git at `b2f10a3`.
[claude_connector.md](claude_connector.md) is the source proposal for the direct
Anthropic provider, implemented as
[ADR 0028](../design/decisions/0028-anthropic-messages-provider.md); it is historical
and not active work.

Completed implementation, executed comparisons and their supporting dated reviews
are in [Z_FIX01](Z_FIX01.md), for earlier FIX01 work; [Z_FIX02](Z_FIX02.md), for
the FIX01-01, FIX01-02, FIX03 and FIX04 work of 10–16 October 2026 and the
unimplemented FIX02 proposal; and [Z_FIX05](Z_FIX05.md), for FIX05 work completed by
26 October 2026 and its dated live diagnostics. Outstanding semantic quality,
clarification, resource and live acceptance work remains in FIX05; cleanup does not
mark it complete.

The [archive](archive/) retains the original records, approval records,
implementation/run history and experiment evidence referenced by the design.
Historical status statements, checklists and proposals are historical, not active
work or new authorization. Accepted contracts and ADRs remain the governing
authority. The duplicate `FIX_003_TASKS.md` checklist has been removed.
