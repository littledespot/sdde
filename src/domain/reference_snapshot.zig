//! Persistable reference data. Execution history, raw model responses and
//! filesystem observations are deliberately absent from this projection.
const std = @import("std");
const e = @import("reference_evidence.zig");
const x = @import("reference_extraction.zig");
const r = @import("reference_reconciliation.zig");
const passive = @import("passive_literals.zig");
pub const Snapshot = struct {
    directory: @import("reference_ingestion.zig").RelativePath,
    inputs: e.Inputs,
    extraction: x.Ledger,
    dispositions: []const r.ClaimDisposition,
    signals: []const r.Signal,
    conflicts: []const r.Conflict,
    passive_records: []const passive.Record,
    passive_occurrences: []const passive.Occurrence,
};
pub const Error = e.Error || error{InvalidReferenceSnapshot};

/// The source gates own extraction/reconciliation validation. Publication
/// projects only their accepted canonical records, retaining every source.
pub fn build(directory: @import("reference_ingestion.zig").RelativePath, inputs: e.Inputs, extracted: x.Accounted, reconciled: r.Accounted, registry: passive.Registry) Error!Snapshot {
    const global = reconciled.records.assignments.checked.prior.prior;
    if (extracted.outcome != .complete or reconciled.outcome != .complete or
        !inputs.corpus.state_id.eql(extracted.ledger.state_id) or
        !inputs.corpus.state_id.eql(global.input.progress.plan.layout.items.state_id) or
        !inputs.corpus.state_id.eql(registry.grammar.reference_state_id)) return error.InvalidReferenceSnapshot;
    return .{
        .directory = directory,
        .inputs = inputs,
        .extraction = extracted.ledger,
        .dispositions = global.dispositions,
        .signals = reconciled.records.signals,
        .conflicts = reconciled.records.conflicts,
        .passive_records = registry.records,
        .passive_occurrences = registry.occurrences,
    };
}

/// Validate persisted source/claim/citation joins before any part of a prior
/// state is reused. Prose support remains model-assisted evidence.
pub fn validate(allocator: std.mem.Allocator, value: Snapshot) Error!void {
    const inputs = value.inputs;
    const corpus = inputs.corpus;
    const ledger = value.extraction;
    const path = @import("relative_directory_path.zig");
    path.validate(value.directory.bytes) catch return error.InvalidReferenceSnapshot;
    if (corpus.state_id.bytes.len == 0 or !corpus.state_id.eql(inputs.chunks.state_id) or !corpus.state_id.eql(ledger.state_id) or
        corpus.sources.len != corpus.source_mappings.len or corpus.block_mappings.len != inputs.chunks.entries.len or
        ledger.chunks.len != inputs.chunks.entries.len or ledger.next_claim_ordinal != ledger.claims.len + 1 or
        ledger.next_citation_ordinal != ledger.citations.len + 1 or value.dispositions.len != ledger.claims.len) return error.InvalidReferenceSnapshot;
    var block_index: usize = 0;
    for (corpus.sources, 0..) |source, source_index| {
        path.validate(source.path.bytes) catch return error.InvalidReferenceSnapshot;
        if (source.id.ordinal != source_index + 1 or corpus.source_mappings[source_index].canonical.ordinal != source.id.ordinal or
            !std.unicode.utf8ValidateSlice(source.bytes)) return error.InvalidReferenceSnapshot;
        for (corpus.sources[0..source_index]) |prior| if (std.mem.eql(u8, prior.path.bytes, source.path.bytes)) return error.InvalidReferenceSnapshot;
        var coverage: @import("reference_source_coverage.zig").Cursor = .{ .bytes = source.bytes };
        for (source.blocks, 0..) |block, index| {
            if (block_index >= inputs.chunks.entries.len or block.id.ordinal != block_index + 1 or block.ordinal != index + 1) return error.InvalidReferenceSnapshot;
            coverage.accept(block.span) catch return error.InvalidReferenceSnapshot;
            const chunk = inputs.chunks.entries[block_index];
            var buffer: [32]u8 = undefined;
            if (!chunk.id.eql(e.identity.formatChunkId(&buffer, @intCast(block_index + 1))) or chunk.source_id.ordinal != source.id.ordinal or
                chunk.block_id.ordinal != block.id.ordinal or chunk.ordinal != 1 or !std.meta.eql(chunk.span, block.span) or
                corpus.block_mappings[block_index].canonical.ordinal != block.id.ordinal) return error.InvalidReferenceSnapshot;
            block_index += 1;
        }
        coverage.finish() catch return error.InvalidReferenceSnapshot;
    }
    if (block_index != inputs.chunks.entries.len) return error.InvalidReferenceSnapshot;
    var claim_index: usize = 0;
    var citation_index: usize = 0;
    for (inputs.chunks.entries, ledger.chunks) |chunk, result| {
        if (!result.scope.state_id.eql(corpus.state_id) or !result.scope.chunk_id.eql(chunk.id)) return error.InvalidReferenceSnapshot;
        switch (result.outcome) {
            .blocked => return error.InvalidReferenceSnapshot,
            .no_feature_claim => {},
            .claims => |ids| for (ids) |id| {
                if (claim_index >= ledger.claims.len or id.ordinal != claim_index + 1) return error.InvalidReferenceSnapshot;
                const claim = ledger.claims[claim_index];
                if (claim.id.ordinal != id.ordinal or !claim.chunk_id.eql(chunk.id) or claim.citation_ids.len == 0 or value.dispositions[claim_index].claim_id.ordinal != id.ordinal) return error.InvalidReferenceSnapshot;
                claim_index += 1;
                for (claim.citation_ids) |citation_id| {
                    if (citation_index >= ledger.citations.len or citation_id.ordinal != citation_index + 1) return error.InvalidReferenceSnapshot;
                    const citation = ledger.citations[citation_index];
                    if (citation.id.ordinal != citation_id.ordinal) return error.InvalidReferenceSnapshot;
                    citation_index += 1;
                }
                if (claim.content == .preserved_token) {
                    const token = claim.content.preserved_token;
                    if (claim.citation_ids.len != 1 or token.citation_id.ordinal != claim.citation_ids[0].ordinal or
                        token.value.id.ordinal == 0 or token.value.downstream_obligation_id.token_id.ordinal != token.value.id.ordinal) return error.InvalidReferenceSnapshot;
                    const citation = ledger.citations[token.citation_id.ordinal - 1].value;
                    if (citation.verbatim == null or !std.mem.eql(u8, token.value.raw_value.bytes, citation.verbatim.?)) return error.InvalidReferenceSnapshot;
                }
            },
        }
    }
    if (claim_index != ledger.claims.len or citation_index != ledger.citations.len) return error.InvalidReferenceSnapshot;
    for (value.passive_records, 1..) |record, ordinal| if (record.id.ordinal != ordinal or record.value.len == 0) return error.InvalidReferenceSnapshot;
    for (value.passive_occurrences) |occurrence| if (occurrence.id.ordinal == 0 or occurrence.id.ordinal > value.passive_records.len) return error.InvalidReferenceSnapshot;
    validateRecords(allocator, value) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceSnapshot;
}

fn validateRecords(allocator: std.mem.Allocator, value: Snapshot) !void {
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const records = try @import("reference_support.zig").snapshot(a, value);
    const items = records.items;
    if (try @import("reference_disposition_validation.zig").check(a, items, records.dispositions) == .invalid) return error.InvalidReferenceSnapshot;
    const allowed = try a.alloc(r.ClaimId, items.entries.len);
    for (items.entries, allowed) |item, *id| id.* = item.claim.id;
    const v = @import("reference_reconciliation_validation.zig");
    const signals = try a.alloc(r.SignalProposal, records.signals.len);
    for (records.signals, signals, 0..) |signal, *proposal, index| {
        proposal.* = .{ .claim_ids = signal.value.claim_ids, .content = @import("model_evidence.zig").content(signal.value.content) };
        if (signal.id.ordinal != index + 1 or try v.signalClaims(items, records.dispositions, proposal.claim_ids, allowed) != null or
            try v.contentIssue(items, proposal.claim_ids, proposal.content) != null or
            !v.signalSelectionAvailable(signals[0..index], index, proposal.claim_ids)) return error.InvalidReferenceSnapshot;
        try citationUnion(a, items, proposal.claim_ids, signal.value.citation_ids);
    }
    if (try v.signalCoverage(a, items, records.dispositions, signals) != null) return error.InvalidReferenceSnapshot;
    const conflicts = try a.alloc(r.ConflictProposal, records.conflicts.len);
    for (records.conflicts, conflicts, 0..) |conflict, *proposal, index| {
        proposal.* = .{ .claim_ids = conflict.value.claim_ids, .kind = conflict.value.kind, .summary = conflict.value.summary.value, .resolution = switch (conflict.value.resolution) {
            .unresolved => .unresolved,
        } };
        if (conflict.id.ordinal != index + 1 or try v.conflictClaims(items, records.dispositions, proposal.claim_ids, allowed) != null or
            !v.conflictSelectionAvailable(conflicts[0..index], index, proposal.kind, proposal.claim_ids)) return error.InvalidReferenceSnapshot;
        try citationUnion(a, items, proposal.claim_ids, conflict.value.citation_ids);
    }
    if (try v.conflictCoverage(a, items, records.dispositions, conflicts) != null) return error.InvalidReferenceSnapshot;
}

fn citationUnion(a: std.mem.Allocator, items: r.Items, claims: []const r.ClaimId, citations: []const r.CitationId) !void {
    const expected = try r.citationUnion(a, items, claims);
    if (expected.len != citations.len) return error.InvalidReferenceSnapshot;
    for (expected, citations) |left, right| if (left.ordinal != right.ordinal) return error.InvalidReferenceSnapshot;
}
