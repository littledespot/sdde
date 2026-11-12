const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const selector = @import("../../domain/reference_selector.zig");
const feature_identity = @import("../../domain/feature_identity.zig");
const source_inventory = @import("../../domain/source_inventory.zig");
const coverage = @import("../../domain/reference_source_coverage.zig");
const corpus_port = @import("../../ports/reference_corpus_source.zig");
const decoder_port = @import("../../ports/reference_decoder.zig");
const identity_port = @import("../../ports/reference_state_identity.zig");
const text_port = @import("../../ports/unicode_normalizer.zig");

/// The closed set of internal steps, in execution order (ADR 0031).
pub const Step = enum {
    inventory_sources,
    validate_inventory,
    capture_sources,
    decode_markdown,
    validate_accounting,
    assign_identities,
    build_chunks,
    validate_chunks,
};

/// Stage-owned diagnostic slot: the step a failing run stopped at, or the step a cancelled run
/// did not start. The binding hands it to the runner (ADR 0031).
pub const Diagnostic = struct { step: ?Step = null };

/// The failure representation of the eight absorbed actions, unchanged. `Cancelled` means the
/// runtime stopped being active; the runner reports which stop it was.
pub const Error = corpus_port.Error || reference.Error || evidence.Error || identity_port.Error || error{Cancelled};

/// One stage: enumerate, validate, capture and decode the selected reference directory, check the
/// accounting of what was read, assign the corpus its identities and build and validate its
/// chunks, yielding the citable reference inputs. Its steps route no outcome of their own: each
/// success continues to the next and every failure ends the stage. Every intermediate lives in
/// the caller's scratch allocator; only the citable inputs cross the stage edge.
pub const Action = struct {
    enumerator: corpus_port.Enumerator,
    normalizer: text_port.Normalizer,
    case_folder: text_port.CaseFolder,
    capturer: corpus_port.Capturer,
    decoder: decoder_port.Decoder,
    identities: identity_port.Source,
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-reference-evidence",
        .kind = .action,
        .requires = &.{ .reference_directory, .feature_directory },
        .produces = &.{.citable_reference_inputs},
        .side_effect = .filesystem_read,
    };

    pub fn execute(self: Action, scratch: std.mem.Allocator, runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic, directory: selector.Directory, feature: feature_identity.FeatureId) Error!evidence.Inputs {
        const raw = steps.inventorySources(self.enumerator, scratch, directory) catch |err| return stopped(diagnostic, .inventory_sources, err);
        try checkpoint(diagnostic, runtime, .validate_inventory);
        const inventory = steps.validateInventory(self.normalizer, self.case_folder, scratch, raw) catch |err| return stopped(diagnostic, .validate_inventory, err);
        try checkpoint(diagnostic, runtime, .capture_sources);
        const captured = steps.captureSources(self.capturer, scratch, inventory) catch |err| return stopped(diagnostic, .capture_sources, err);
        try checkpoint(diagnostic, runtime, .decode_markdown);
        const decoded = steps.decodeMarkdown(self.decoder, scratch, captured) catch |err| return stopped(diagnostic, .decode_markdown, err);
        try checkpoint(diagnostic, runtime, .validate_accounting);
        const inputs = steps.validateAccounting(scratch, decoded) catch |err| return stopped(diagnostic, .validate_accounting, err);
        try checkpoint(diagnostic, runtime, .assign_identities);
        const corpus = steps.assignIdentities(self.identities, scratch, inputs, feature) catch |err| return stopped(diagnostic, .assign_identities, err);
        try checkpoint(diagnostic, runtime, .build_chunks);
        const chunks = steps.buildChunks(scratch, corpus) catch |err| return stopped(diagnostic, .build_chunks, err);
        try checkpoint(diagnostic, runtime, .validate_chunks);
        return steps.validateChunks(inputs, feature, corpus, chunks) catch |err| return stopped(diagnostic, .validate_chunks, err);
    }
};

fn stopped(diagnostic: *Diagnostic, step: Step, err: Error) Error {
    diagnostic.step = step;
    return err;
}

fn checkpoint(diagnostic: *Diagnostic, runtime: pipeline.NodeRuntime, next: Step) Error!void {
    if (runtime.status() != .active) return stopped(diagnostic, next, error.Cancelled);
}

/// The eight internal steps. Each is one typed function with its own tests; none is registered,
/// addressable or composable from workflow YAML. A step that reaches a port takes exactly that
/// port, or the text services of one port module, never the `Action`.
pub const steps = struct {
    pub fn inventorySources(enumerator: corpus_port.Enumerator, allocator: std.mem.Allocator, directory: selector.Directory) corpus_port.Error!reference.RawInventory {
        return enumerator.enumerate(allocator, directory);
    }

    /// Caller arena owns normalized paths and comparison keys.
    pub fn validateInventory(normalizer: text_port.Normalizer, case_folder: text_port.CaseFolder, allocator: std.mem.Allocator, raw: reference.RawInventory) reference.Error!reference.Inventory {
        const checked = source_inventory.validate(allocator, raw.entries, .{ .entries = reference.limits.entries, .depth = reference.limits.depth, .duration_ms = reference.limits.duration_ms }, normalizer, case_folder) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceInventory;
        const entries = try allocator.alloc(reference.Entry, checked.len);
        for (checked, entries, 0..) |entry, *result, index| result.* = .{ .id = .{ .ordinal = @intCast(index + 1) }, .path = .{ .bytes = entry.path }, .raw_path = entry.raw_path, .observation = entry.observation };
        return .{ .directory = raw.directory, .entries = entries };
    }

    pub fn captureSources(capturer: corpus_port.Capturer, allocator: std.mem.Allocator, inventory: reference.Inventory) corpus_port.Error!reference.CapturedCorpus {
        return capturer.capture(allocator, inventory);
    }

    pub fn decodeMarkdown(decoder: decoder_port.Decoder, allocator: std.mem.Allocator, captured: reference.CapturedCorpus) std.mem.Allocator.Error!reference.DecodedCorpus {
        const entries = try allocator.alloc(reference.DecodedEntry, captured.entries.len);
        var total: usize = 0;
        var revision: u32 = 0;
        for (captured.entries, 0..) |item, index| {
            var entry: reference.DecodedEntry = .{ .captured = item, .result = .{ .blocked = .decoder_failure }, .debit = null };
            switch (item.source) {
                .directory => entry.result = .{ .directory = {} },
                .blocked => |failure| entry.result = .{ .blocked = failure },
                .bytes => |bytes| decode: {
                    if (bytes.len > reference.limits.decoded_corpus_bytes - total) {
                        entry.result = .{ .blocked = .decoded_budget };
                        break :decode;
                    }
                    revision += 1;
                    entry.debit = .{ .reserved = bytes.len, .outcome = .{ .released = {} } };
                    const decoded = decoder.decode(allocator, item.entry.path, bytes, bytes.len) catch |err| {
                        entry.result = .{ .blocked = switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            error.UnsupportedMedia => .unsupported_media,
                            error.MalformedText => .malformed_text,
                            error.DecodeLimitExceeded => .decoded_budget,
                        } };
                        break :decode;
                    };
                    entry.result = if (bytes.len == 0) .{ .empty = decoded } else .{ .decoded = decoded };
                    entry.debit = .{ .reserved = bytes.len, .outcome = .{ .committed = bytes.len } };
                    total += bytes.len;
                },
            }
            entries[index] = entry;
        }
        return .{ .captured = captured, .entries = entries, .decoded_bytes = total, .budget_revision = revision };
    }

    pub fn validateAccounting(allocator: std.mem.Allocator, candidate: reference.DecodedCorpus) reference.Error!reference.Inputs {
        const inventory = candidate.captured.inventory;
        if (inventory.entries.len > reference.limits.entries or candidate.entries.len != inventory.entries.len or
            candidate.captured.entries.len != inventory.entries.len) return error.InvalidReferenceAccounting;
        var documents: std.ArrayList(reference.Document) = .empty;
        var source_total: usize = 0;
        var decoded_total: usize = 0;
        var revisions: u32 = 0;
        for (inventory.entries, candidate.captured.entries, candidate.entries, 0..) |entry, captured, decoded, index| {
            if (entry.id.ordinal != index + 1 or !sameEntry(entry, captured.entry) or
                !sameEntry(entry, decoded.captured.entry)) return error.InvalidReferenceAccounting;
            switch (entry.observation) {
                .directory => {
                    if (captured.source != .directory or captured.debit != null or decoded.result != .directory or decoded.debit != null) return error.InvalidReferenceAccounting;
                    continue;
                },
                .file => {},
                .symlink, .special, .unreadable => return error.InvalidReferenceAccounting,
            }
            if (captured.source != .bytes or decoded.captured.source != .bytes) return error.InvalidReferenceAccounting;
            const bytes = captured.source.bytes;
            if (!std.mem.eql(u8, bytes, decoded.captured.source.bytes) or bytes.len != entry.observation.file.size or
                bytes.len > reference.limits.source_file_bytes or bytes.len > reference.limits.source_corpus_bytes - source_total or
                bytes.len > reference.limits.decoded_corpus_bytes - decoded_total) return error.InvalidReferenceAccounting;
            try debit(captured.debit, bytes.len);
            try debit(decoded.captured.debit, bytes.len);
            try debit(decoded.debit, bytes.len);
            revisions += 1;
            source_total += bytes.len;
            const result = switch (decoded.result) {
                .decoded => |value| if (bytes.len != 0) value else return error.InvalidReferenceAccounting,
                .empty => |value| if (bytes.len == 0) value else return error.InvalidReferenceAccounting,
                .directory, .blocked => return error.InvalidReferenceAccounting,
            };
            if (result.blocks.len > reference.limits.blocks_per_file) return error.InvalidReferenceAccounting;
            const blocks = try allocator.alloc(reference.Block, result.blocks.len);
            var cursor: coverage.Cursor = .{ .bytes = bytes };
            for (result.blocks, 0..) |block, block_index| {
                try cursor.accept(block.span);
                blocks[block_index] = .{ .id = .{ .source = entry.id, .ordinal = @intCast(block_index + 1) }, .span = block.span };
            }
            try cursor.finish();
            decoded_total += bytes.len;
            try documents.append(allocator, .{ .source = entry.id, .path = entry.path, .reader = result.reader, .media = result.media, .bytes = bytes, .blocks = blocks });
        }
        if (source_total != candidate.captured.source_bytes or decoded_total != candidate.decoded_bytes or
            revisions != candidate.budget_revision or revisions != candidate.captured.budget_revision) return error.InvalidReferenceAccounting;
        return .{ .inventory = inventory, .documents = try documents.toOwnedSlice(allocator), .source_bytes = source_total, .decoded_bytes = decoded_total };
    }

    /// Slices borrow the validated inputs; new records belong to the caller's arena. This step is
    /// the only one that draws on system entropy, through its own port.
    pub fn assignIdentities(identities: identity_port.Source, allocator: std.mem.Allocator, inputs: reference.Inputs, feature: feature_identity.FeatureId) (evidence.Error || identity_port.Error)!evidence.Corpus {
        const sources = try allocator.alloc(evidence.Source, inputs.documents.len);
        const mappings = try allocator.alloc(evidence.SourceMapping, sources.len);
        var block_mappings: std.ArrayList(evidence.BlockMapping) = .empty;
        for (inputs.documents, 0..) |document, index| {
            const source_id: evidence.identity.SourceId = .{ .ordinal = @intCast(index + 1) };
            mappings[index] = .{ .provisional = document.source, .canonical = source_id };
            const blocks = try allocator.alloc(evidence.Block, document.blocks.len);
            for (document.blocks, 0..) |block, block_index| {
                const block_id: evidence.identity.BlockId = .{ .ordinal = @intCast(block_mappings.items.len + 1) };
                blocks[block_index] = .{ .id = block_id, .ordinal = @intCast(block_index + 1), .span = block.span };
                try block_mappings.append(allocator, .{ .provisional = block.id, .canonical = block_id });
            }
            sources[index] = .{ .id = source_id, .path = document.path, .reader = document.reader, .bytes = document.bytes, .blocks = blocks };
        }
        return .{
            .state_id = try evidence.identity.stateId(allocator, try identities.next()),
            .feature_id = feature,
            .sources = sources,
            .source_mappings = mappings,
            .block_mappings = try block_mappings.toOwnedSlice(allocator),
        };
    }

    pub fn buildChunks(allocator: std.mem.Allocator, corpus: evidence.Corpus) evidence.Error!evidence.Chunks {
        var chunks: std.ArrayList(evidence.Chunk) = .empty;
        for (corpus.sources) |source| for (source.blocks) |block| {
            const ordinal: u32 = @intCast(chunks.items.len + 1);
            try chunks.append(allocator, .{
                .id = try evidence.identity.chunkId(allocator, ordinal),
                .source_id = source.id,
                .block_id = block.id,
                .ordinal = 1,
                .span = block.span,
            });
        };
        return .{ .state_id = corpus.state_id, .partition = .source_blocks_v1, .entries = try chunks.toOwnedSlice(allocator) };
    }

    pub fn validateChunks(inputs: reference.Inputs, feature: feature_identity.FeatureId, corpus: evidence.Corpus, chunks: evidence.Chunks) evidence.Error!evidence.Inputs {
        if (!std.mem.eql(u8, feature.bytes, corpus.feature_id.bytes) or !corpus.state_id.eql(chunks.state_id) or
            corpus.sources.len != inputs.documents.len or corpus.source_mappings.len != inputs.documents.len or
            corpus.block_mappings.len != chunks.entries.len) return error.InvalidReferenceChunks;
        var index: usize = 0;
        for (inputs.documents, corpus.sources, corpus.source_mappings, 0..) |document, source, mapping, source_index| {
            if (source.id.ordinal != source_index + 1 or mapping.canonical.ordinal != source.id.ordinal or
                mapping.provisional.ordinal != document.source.ordinal or source.reader != document.reader or
                !std.mem.eql(u8, source.path.bytes, document.path.bytes) or !std.mem.eql(u8, source.bytes, document.bytes) or
                source.blocks.len != document.blocks.len) return error.InvalidReferenceChunks;
            for (document.blocks, source.blocks, 0..) |original, block, ordinal| {
                if (index >= chunks.entries.len) return error.InvalidReferenceChunks;
                const chunk = chunks.entries[index];
                const block_mapping = corpus.block_mappings[index];
                var id_buffer: [32]u8 = undefined;
                const expected_id = evidence.identity.formatChunkId(&id_buffer, @intCast(index + 1));
                if (block.id.ordinal != index + 1 or block.ordinal != ordinal + 1 or
                    !std.meta.eql(original.id, block_mapping.provisional) or block_mapping.canonical.ordinal != block.id.ordinal or
                    !std.meta.eql(original.span, block.span) or !std.meta.eql(block.span, chunk.span) or
                    !chunk.id.eql(expected_id) or chunk.ordinal != 1 or
                    chunk.block_id.ordinal != block.id.ordinal or chunk.source_id.ordinal != source.id.ordinal) return error.InvalidReferenceChunks;
                index += 1;
            }
        }
        if (index != chunks.entries.len) return error.InvalidReferenceChunks;
        return .{ .corpus = corpus, .chunks = chunks };
    }
};

fn sameEntry(a: reference.Entry, b: reference.Entry) bool {
    return a.id.ordinal == b.id.ordinal and std.mem.eql(u8, a.path.bytes, b.path.bytes) and
        std.mem.eql(u8, a.raw_path, b.raw_path) and std.meta.eql(a.observation, b.observation);
}

fn debit(value: ?reference.Debit, expected: usize) reference.Error!void {
    const record = value orelse return error.InvalidReferenceAccounting;
    if (record.reserved != expected or record.outcome != .committed or record.outcome.committed != expected) return error.InvalidReferenceAccounting;
}
