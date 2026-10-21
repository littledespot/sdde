# ADR 0026: Prune prior-run log segments by header identity

- **Status:** Accepted amendment
- **Date:** 2026-10-20
- **Decision authority:** The user's choice of "header-identity retention" on
  20 October 2026: "Read each prior run's binding identity from its segment headers
  and prune only its closed segments older than 14 days, under that run's lock.
  Never touch an active tail or the current run. Crash-tail finalization stays
  open." The user had earlier chosen to wire retention after activation, with
  fault-injection tests for every destructive step. Full §14.10 historical
  resolution is blocked, because it reads each prior run's logging policy from a
  persisted `BootstrapAuthorityState` that the engine does not implement. The
  rule that invalid prior history blocks is not a new decision. It keeps §14.10
  ("scans/validates all bounded prior-run binding groups") and §26.5 ("alias; or
  permission failure is never skipped").
- **Amends, for prior-run retention only:**
  - §14.10: resolution of each historical policy through bootstrap lineage;
    finalization of prior active tails before the current binding exists; and the
    rule that only complete finalization evidence authorizes the current binding,
    sink and `run.started`;
  - §26.5: the selection order `(closedAtUtc, runId, ordinal)`;
  - the §13 catalogue input of `BuildFeatureLogRetentionAuthorizationAction`;
  - F0002 §7, which defers retention to §§14.10 and 26.5.

  Everything else in §26.5 still governs, including "alias; or permission failure
  is never skipped". The overall design remains **Proposed design**.
- **Amended 21 October 2026:** [log-folder entries](#log-folder-entries-amendment--21-october-2026).
  This amendment also reaches beyond prior-run retention. It amends §26.5 for every
  listing of `logs/events` and `logs/prompts`, including the current run's and the
  debugger's. A regular file whose name is not a segment name is left alone
  instead of blocking.

## Context

§26.5 requires retention after recovery and rotation, so that closed segments
older than the compiler-fixed 14 days are pruned. It is the only authorized
destructive log operation. Production never ran it: only tests reached the
retention runner. §14.10 expects a fresh run to scan prior runs and resolve each
one's policy through bootstrap lineage. That lineage does not exist, and ADR 0009
removed saved execution state.

## Decision

A fresh run prunes its feature's prior-run segments, using the identity recorded
in those segments.

- **When.** After the current run's activation has recovered and rotated its own
  streams, and before `run.started`. The current binding and sink therefore exist
  first, which §14.10 orders the other way round.
- **Discovery is read-only.** For each stream, it lists the feature's prior runs and
  their binding directories under the registry's log collections. The current run
  is never included.
- **Identity.** A binding's identity comes from its directory names, the current
  feature, and the policy ID in its first segment's `segment_header` row.
- **Validation.** Every segment of every prior binding is checked by recovery's
  segment inspector, read-only. That covers:
  - the heading and header rows;
  - the column count of every row;
  - the identity of every row against that binding;
  - sequence continuity, including across the binding's segments;
  - a single trailer that matches the last sequence.
  Ordinals must be consecutive, but may start after 1 once retention has removed
  the oldest segments. A binding directory with no segment is empty and is left
  alone.
- **Invalid history blocks.** Discovery never skips a failure. Each of these blocks
  the run as an ordinary logging failure (`LOG_SINK_FAILURE`):
  - a symlink;
  - an insecure directory;
  - an entry that is neither a directory nor a regular file, a directory inside a
    binding directory, or a segment-named file outside one; a regular file with any
    other name is left alone ([log-folder entries amendment](#log-folder-entries-amendment--21-october-2026));
  - an oversized segment;
  - a mismatched identity or row;
  - a segment that is torn, or has no trailer, before another segment;
  - a lone torn segment that is not ordinal 1, or whose directory names are not
    valid binding names;
  - a torn segment whose bytes are not a prefix of the heading and of that
    stream's `segment_header` row (its kind, schema version, stream and column
    schema), or that exceeds the row size limit;
  - a gap in the ordinals;
  - bytes after a trailer;
  - a sequence with no successor.

  Every retention failure goes through the active logger's failure report, which
  writes the bounded emergency line.
- **Cancellation.** Cancellation while a prior directory or segment is opened
  stays cancellation. Cancellation during a directory check, a segment read, or
  any step under the lock is reported as a logging failure, because the shared
  readers and the sink port have no cancellation outcome. The current run's sink
  has the same gap, which is open work.
- **Crashed runs are kept whole.** A crash leaves a binding's last segment in one
  of three shapes, in either stream:
  - torn before its header row was complete, including empty, when a segment was
    being created or rotated;
  - without a trailer;
  - with bytes after its last complete row.

  Every group of such a run is kept, including that run's closed segments in the
  other stream. Finalizing such a tail (§14.10) is still not implemented.
- **Order.** Closed groups are processed in `(runId, bindingId, stream rank)` order.
  Within a group, retention deletes the longest prefix of segments, in ordinal
  order, whose close time is at or before the cutoff. Sequence is the ordering
  authority and timestamps are informational (§26.5), so a later segment is never
  deleted before an earlier one and the remaining ordinals stay consecutive. Locks
  are taken one group at a time, so no single order spans runs.
- **Pruning.** For each group, the composition opens one stream of that run through
  the registry's per-stream path derivation. That adapter can only lock, prune and
  release. The retention runner then:
  1. builds the single-use authorization, which binds the current run, the
     historical binding, the stream and the cutoff from the trusted clock;
  2. takes that run's own stream lock;
  3. validates the group again under the lock, refusing anything not closed or not
     matching the binding;
  4. deletes the expired ordinal prefix;
  5. releases the lock.

  A lock, validation, deletion or release failure blocks the run.
- **What stays.** Empty binding and run directories are kept, because deleting
  directories is not authorized.
- **Only this path prunes.** The current run's sink has no prune facet.

## Consequences

- Retention now runs on every fresh activation. A prior run's logs disappear only
  after they are closed and older than 14 days.
- A crashed run's logs are kept until crash finalization is decided.
- Damaged or tampered prior-run logs block every later run of the feature until
  someone repairs or removes them. The emergency line gives the failure code but no
  path. This follows §26.5. Since the log-folder entries amendment, a stray regular
  file, such as one a file browser creates, no longer blocks.
- Torn detection assumes the bytes on disk are a prefix of what was written. A
  filesystem that leaves a crashed new file zero-filled at its full length makes
  that segment invalid, and later runs block.
- Discovery reads every prior segment in full on each activation. Each run's
  segments are bounded, but the number of retained prior runs is not.
- Two concurrent runs of the same feature are not supported. If they happen, the
  under-lock check refuses any group that is no longer closed.
- Path authority stays with the workflow artifact registry, which now records its
  log collections. It derives historical stream paths only for the current feature
  and a different run.
- Tests in `src/feature_log_layout_test.zig` cover:
  - pruning of expired runs in both streams;
  - keeping recent, crashed (one stream active) and current runs;
  - crash shapes of a last segment, alone or behind closed segments, each keeping
    its run whole;
  - multi-segment groups: prefix pruning, inverted timestamps, and a group that
    starts after ordinal 1;
  - a prior run with one stream missing;
  - group order;
  - twenty-two invalid-history cases, each rejected by discovery and blocking
    activation;
  - stray regular files at every folder level, left alone;
  - the under-lock check refusing a segment changed or torn after discovery;
  - a held lock;
  - a failed deletion;
  - per-stream path derivation.

  `src/feature_log_runtime_test.zig` checks the coordinator's step order and its
  failure propagation: a prune failure stays the reported cause when release
  also fails. `src/architecture_test.zig` keeps discovery read-only,
  limits the historical adapter to lock, prune and release, and keeps pruning out
  of the current run's sink. Cancellation under the lock, and the number of
  emergency lines, have no direct test.

## Log-folder entries amendment — 21 October 2026

**Approved by the user** on 21 October 2026 ("apply recommendation"), after asking
whether files such as Finder's `.DS_Store` should keep blocking runs. It replaces
the original rule that any unexpected entry blocks, including a file the operating
system created. The Decision list above now states the replacement. It amends
§26.5 for every listing of `logs/events` and `logs/prompts`, which means:
- prior-run discovery;
- the under-lock check and the prune;
- the current run's recovery and segment account;
- the debugger's reads of those folders (ADR 0019).

- **Names the engine owns.** In these folders the engine writes only:
  - run and binding directories;
  - segment files named `NNNN.log`, with exactly four ASCII digits, not `0000`;
  - the `.stream.lock` file in each run directory, which no listing reads.
- **Left alone.** A regular file with any name other than a segment name is not log
  history. Examples are `.DS_Store`, `._0001.log`, `Thumbs.db`, `desktop.ini`,
  `notes.txt` and `0001.log.bak`.
  - A listing knows it from the entry type the directory listing reports.
  - It never opens, deletes or counts the file, and doesn't check its permissions.
  - A binding directory that holds only such files is empty.
- **Still blocks.** These remain failures and are never skipped:
  - an entry that is neither a directory nor a regular file, such as a symlink, or
    one whose type the listing doesn't report;
  - a directory inside a binding directory;
  - a segment-named file outside a binding directory;
  - an insecure directory;
  - every segment failure listed in the Decision, including an ordinal gap.
- **Why this is not skipping.** §26.5's "never skipped" list and its owner-only
  rules cover log directories and segments. A regular file whose name is not a
  segment name is neither, so leaving it alone skips no log evidence. Directories
  stay owner-only, so the file isn't exposed beyond the owner. Retention deletes
  only segments, so it never needs to touch the file.
- **One rule.** Two entry classifiers sit next to the segment and lock names in
  `src/adapters/filesystem/feature_log_file.zig`: one for collection and run
  directories, one for binding directories.
  - Every listing uses them, so placement is decided once.
  - The segment-name parser is private to them.
  - There is no list of operating-system file names.
- **Cost.** A renamed segment, such as `0003.log.bak`, counts as removed, just as if
  it had been deleted.
  - It stays on disk and is never pruned.
  - A renamed middle segment still leaves an ordinal gap, which blocks.
  - A renamed active tail can make a crashed run look closed, so its expired
    segments are pruned.
  - A renamed last segment of an earlier binding of the current run lowers the
    sequence that the current binding continues from.
- **Tests:**
  - `src/feature_log_layout_test.zig`:
    - stray files at the collection, run and binding levels of both streams leave
      discovery and retention unaffected, and are themselves unchanged;
    - a binding directory left holding only a stray file validates as empty;
    - six invalid-history cases:
      - a symlink with an operating-system file name in a binding directory, a run
        directory, and a prompt-stream binding directory;
      - a directory inside a binding directory;
      - a segment-named file in a run directory, and one in the stream collection.
  - `src/feature_log_runtime_test.zig`: the current run's restart recovery with
    stray files in its binding directory, its run directory and a sibling binding,
    and six rejected cases:
    - a symlink in each of those three places;
    - a directory inside the current binding, and one inside the sibling binding;
    - a segment-named file in the run directory.
  - `src/request_debugger_test.zig`: debugger reads with stray files at every level,
    and rejection of a symlink at every level, a directory inside a binding, and a
    segment-named file in the collection or a run directory.
  - `src/adapters/filesystem/feature_log_file.zig`: both classifiers for each entry
    type, plus segment names with a sign, an underscore or the wrong width.
