# ADR 0026: Prior-run log finalization and retention by header identity

- **Status:** Accepted
- **Date:** 2026-10-20
- **Decision authority:** User decisions, 20 and 21 October and 14, 19 and 22 November 2026.
- **Amends:** §14.10 (historical policy resolution and the order of prior-run finalization);
  §26.5 (the prior-run selection order, and the entry rules for every listing of `logs/events`
  and `logs/prompts`); the §13.9 catalogue; F0002 §7.
- **Amended by:** [ADR 0032](0032-engine-routines.md).

## Decision

A fresh run closes its feature's crashed prior-run tails and then prunes its prior-run
segments, using the identity recorded in those segments. No persisted bootstrap authority or
lineage is read for a prior run. Both are feature-logging routines that the runtime logging
lifecycle runs ([ADR 0032](0032-engine-routines.md)).

- **When.** After the current run's activation has recovered and rotated its own
  streams, and before `run.started`: first the finalization of crashed prior tails
  ("Crash finalization" below), then retention. The current binding, sink and active logger
  therefore exist first, so a failure reports through the logger's one emergency line.
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
    other name is left alone
    ([log-folder entries](#log-folder-entries-amendment--21-october-2026));
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
- **Cancellation** follows [ADR 0032](0032-engine-routines.md) "Cancellation mapping" in
  discovery, finalization, retention and the current run's sink alike: it is the run's own
  outcome, never a logging failure, and its lock is released.
- **Crashed runs are kept whole until finalized.** A crash leaves a binding's last
  segment in one of three shapes, in either stream:
  - torn before its header row was complete, including empty, when a segment was
    being created or rotated;
  - without a trailer;
  - with bytes after its last complete row.

  Every group of such a run is kept, including that run's closed segments in the
  other stream, until its tails are finalized. A tail torn before its header row was
  complete has no identity to close and is never finalized, so its run stays whole;
  the other two shapes are closed by finalization and then follow the rules below.
- **Order.** Closed groups are processed in `(runId, bindingId, stream rank)` order.
  Within a group, retention deletes the longest prefix of segments, in ordinal
  order, whose close time is at or before the cutoff. Sequence is the ordering
  authority and timestamps are informational (§26.5), so a later segment is never
  deleted before an earlier one and the remaining ordinals stay consecutive. Locks
  are taken one group at a time, so no single order spans runs.
- **Pruning.** For each group, the composition opens one stream of that run through
  the registry's per-stream path derivation. That adapter can only lock, prune and
  release. The retention routine then:
  1. builds the single-use authorization, which binds the current run, the
     historical binding, the stream and the cutoff from the trusted clock;
  2. resolves the stream that authorization names;
  3. takes that run's own stream lock;
  4. prunes: under the lock the group is validated again, anything not closed or not
     matching the binding is refused, and the expired ordinal prefix is deleted;
  5. releases the lock, after any prune outcome.

  A lock, validation, deletion or release failure blocks the run. A prune failure stays the
  reported cause when the release also fails.
- **What stays.** Empty binding and run directories are kept, because deleting
  directories is not authorized.
- **Only this path prunes.** The current run's sink has no prune facet.

### Crash finalization

A fresh run closes each crashed prior run's open tail before retention.

- **Identity.** The header identity alone suffices. Discovery finds both streams by listing
  their directories, never by the current policy, so a prior run's prompt stream is closed
  whatever the current policy captures. The trailer needs only the binding identity, the
  ordinal, the final sequence and the trusted clock. A policy ID that differs from the
  current run's is no error. The identity is a digest of the compiled policy: it names a
  policy without supplying its content.
- **What it writes.** For each tail whose last segment has a complete header row, under that
  run's own stream lock: it reads the group again and proves it still ends in an active
  tail, truncates the tail to its last complete row (the tail truncation recovery already
  makes), writes one `segment_trailer` stamped with the trusted clock's reading at
  finalization, proves the group closed, and releases the lock. Those are the only writes;
  retention stays the only deletion. The trailer's close time is the finalization time, so
  the finalized segment prunes after the retention period from then.
- **What it leaves.** A tail torn before its header row was complete, alone or behind closed
  segments, has no identity to close. It is not written, not deleted and does not block;
  its run stays whole.
- **Crashed by assumption.** Concurrent runs of one feature are unsupported, so any prior
  run's active tail is crashed. A group no longer an active tail under the lock, or one
  that fails validation, blocks the run as an ordinary logging failure
  (`LOG_SINK_FAILURE`); a lock held elsewhere times out and blocks
  (`LOG_LOCK_TIMEOUT`). Each failure goes through the active logger's one emergency line.
- **Idempotence.** A trailer cut short by a cancellation or a crash is truncated
  as a partial row by the next finalization.
- **Adapter.** A sibling of the historical stream adapter opens one stream of one prior
  run through the registry's per-stream path derivation. It can lock, read, recover, close
  and release; it creates, rotates, appends, prunes and deletes nothing. The historical
  stream adapter keeps its limit: lock, prune and release.

### Log-folder entries amendment — 21 October 2026

These entry rules apply to every listing of `logs/events` and `logs/prompts`:
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

## Consequences

- Retention runs on every fresh activation. A prior run's logs disappear only
  after they are closed and older than 14 days.
- A crashed run's headered tails are closed by the next activation, so its segments are
  pruned after the retention period like any closed ones; a tail torn before its header
  row was complete keeps its run whole.
- A crashed tail that cannot be written (a read-only segment, an insecure directory, a
  lock held elsewhere) blocks every later run of the feature until someone repairs or
  removes it.
- Damaged or tampered prior-run logs block every later run of the feature until
  someone repairs or removes them. The emergency line gives the failure code but no
  path. This follows §26.5.
- Torn detection assumes the bytes on disk are a prefix of what was written. A
  filesystem that leaves a crashed new file zero-filled at its full length makes
  that segment invalid, and later runs block.
- Discovery reads every prior segment in full, twice on each activation: once to find
  the crashed tails to finalize and once to find the closed groups to prune. Each run's
  segments are bounded, but the number of retained prior runs is not.
- Two concurrent runs of the same feature are not supported. If they happen, the
  under-lock check refuses any group that is no longer closed. A prior run's active tail
  is therefore treated as crashed.
- Path authority stays with the workflow artifact registry, which records its
  log collections. It derives historical stream paths only for the current feature
  and a different run.
