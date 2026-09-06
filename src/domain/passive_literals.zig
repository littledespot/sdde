//! Source-backed, execution-local display candidates. No operational path or
//! persisted registry authority is created here.
const std = @import("std");
const grammar = @import("path_token_grammar.zig");
const scan = @import("path_token_scan.zig");
const naming = @import("naming_policy.zig");
const evidence = @import("reference_evidence.zig");
const safety = @import("toolchain_safety.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
pub const Error = scan.Error || evidence.Error || error{InvalidPassiveLiteral};
pub const Id = struct { ordinal: u32 };
pub const Kind = scan.Kind;
pub const Origin = union(enum) {
    reference_name: evidence.identity.SourceId,
    reference_span: struct { source_id: evidence.identity.SourceId, block_id: evidence.identity.BlockId, start_byte: usize, end_byte: usize },
};
pub const Candidate = struct { kind: Kind, value: []const u8, origin: Origin };
pub const Candidates = struct { grammar: grammar.Grammar, entries: []const Candidate };
pub const Assigned = struct { candidates: Candidates, ids: []const Id };
pub const Record = struct { id: Id, kind: Kind, value: []const u8 };
pub const Occurrence = struct { id: Id, origin: Origin };
pub const Registry = struct { grammar: grammar.Grammar, records: []const Record, occurrences: []const Occurrence };

/// Caller arena owns collections. Source names precede their block occurrences;
/// source/block/byte order is the only allocation order.
pub fn collect(allocator: std.mem.Allocator, compiled: grammar.Grammar, current: *const safety.ValidToolchain, inputs: evidence.Inputs, normalizer: unicode.Normalizer, folder: unicode.CaseFolder, classifier: unicode.LexicalClassifier) Error!Candidates {
    try grammar.validateBinding(allocator, compiled, current, inputs, normalizer, folder);
    var entries: std.ArrayList(Candidate) = .empty;
    for (inputs.corpus.sources, compiled.reference_names) |source, name| {
        try entries.append(allocator, .{ .kind = .display_filename, .value = name.basename, .origin = .{ .reference_name = source.id } });
        for (source.blocks) |block| {
            const found = try scan.scan(allocator, compiled, source.bytes[block.span.start.byte..block.span.end.byte], normalizer, folder, classifier);
            defer scan.destroy(found);
            for (found.matches) |match| try entries.append(allocator, .{
                .kind = match.kind,
                .value = try naming.normalize(allocator, found.text[match.start_byte..match.end_byte], true, normalizer, folder),
                .origin = .{ .reference_span = .{ .source_id = source.id, .block_id = block.id, .start_byte = block.span.start.byte + match.start_byte, .end_byte = block.span.start.byte + match.end_byte } },
            });
        }
    }
    return .{ .grammar = compiled, .entries = try entries.toOwnedSlice(allocator) };
}

pub fn assign(allocator: std.mem.Allocator, candidates: Candidates) Error!Assigned {
    const ids = try allocator.alloc(Id, candidates.entries.len);
    var next: u32 = 1;
    for (candidates.entries, ids, 0..) |candidate, *id, index| {
        for (candidates.entries[0..index], ids[0..index]) |prior, prior_id| {
            if (sameScalar(candidate, prior)) {
                id.* = prior_id;
                break;
            }
        } else {
            id.* = .{ .ordinal = next };
            next = std.math.add(u32, next, 1) catch return error.InvalidPassiveLiteral;
        }
    }
    return .{ .candidates = candidates, .ids = ids };
}

/// Re-scan the exact captured inputs through the one detector. Neither candidate
/// bytes nor supplied IDs can manufacture an occurrence or omit source coverage.
pub fn validate(allocator: std.mem.Allocator, assigned: Assigned, current: *const safety.ValidToolchain, inputs: evidence.Inputs, normalizer: unicode.Normalizer, folder: unicode.CaseFolder, classifier: unicode.LexicalClassifier) Error!Registry {
    const expected = try collect(allocator, assigned.candidates.grammar, current, inputs, normalizer, folder, classifier);
    if (expected.entries.len != assigned.candidates.entries.len or assigned.ids.len != expected.entries.len) return error.InvalidPassiveLiteral;
    var records: std.ArrayList(Record) = .empty;
    const occurrences = try allocator.alloc(Occurrence, expected.entries.len);
    for (expected.entries, assigned.candidates.entries, assigned.ids, occurrences) |candidate, supplied, id, *occurrence| {
        if (!sameScalar(candidate, supplied) or !std.meta.eql(candidate.origin, supplied.origin)) return error.InvalidPassiveLiteral;
        for (records.items) |record| {
            if (record.kind == candidate.kind and std.mem.eql(u8, record.value, candidate.value)) {
                if (id.ordinal != record.id.ordinal) return error.InvalidPassiveLiteral;
                break;
            }
        } else {
            if (id.ordinal == 0 or id.ordinal != records.items.len + 1) return error.InvalidPassiveLiteral;
            try records.append(allocator, .{ .id = id, .kind = candidate.kind, .value = candidate.value });
        }
        occurrence.* = .{ .id = id, .origin = candidate.origin };
    }
    return .{ .grammar = expected.grammar, .records = try records.toOwnedSlice(allocator), .occurrences = occurrences };
}

pub fn resolve(registry: Registry, inputs: evidence.Inputs, scope: evidence.Scope, id: Id) Error!Record {
    return resolveIn(registry, inputs, &.{scope}, id);
}

/// The caller supplies an exact provenance allowlist, never a corpus-wide scope.
pub fn resolveIn(registry: Registry, inputs: evidence.Inputs, scopes: []const evidence.Scope, id: Id) Error!Record {
    if (!registry.grammar.reference_state_id.eql(inputs.corpus.state_id) or !std.mem.eql(u8, registry.grammar.feature_id.bytes, inputs.corpus.feature_id.bytes)) return error.InvalidPassiveLiteral;
    if (scopes.len == 0) return error.InvalidPassiveLiteral;
    for (scopes) |scope| _ = try evidence.resolve(inputs, scope);
    if (id.ordinal == 0 or id.ordinal > registry.records.len) return error.InvalidPassiveLiteral;
    const record = registry.records[id.ordinal - 1];
    if (record.id.ordinal != id.ordinal) return error.InvalidPassiveLiteral;
    for (registry.occurrences) |occurrence| {
        if (occurrence.id.ordinal != id.ordinal) continue;
        for (scopes) |scope| {
            const unit = try evidence.resolve(inputs, scope);
            const allowed = switch (occurrence.origin) {
                .reference_name => |source| source.ordinal == unit.source.id.ordinal,
                .reference_span => |span| span.source_id.ordinal == unit.source.id.ordinal and span.block_id.ordinal == unit.chunk.block_id.ordinal and span.start_byte >= unit.chunk.span.start.byte and span.end_byte <= unit.chunk.span.end.byte,
            };
            if (allowed) return record;
        }
    }
    return error.InvalidPassiveLiteral;
}

fn sameScalar(a: Candidate, b: Candidate) bool {
    return a.kind == b.kind and std.mem.eql(u8, a.value, b.value);
}
