//! Total extraction response accounting; one current chunk per request.
const std = @import("std");
const e = @import("reference_extraction.zig");
const source = @import("reference_evidence.zig");
pub const Entry = struct { value: e.RawResult, previous: ?*const Entry };
pub const Progress = struct { scopes: []const source.Scope, latest: ?*const Entry = null, count: usize = 0 };
pub fn initialize(allocator: std.mem.Allocator, inputs: source.Inputs) e.Error!Progress {
    const scopes = try allocator.alloc(source.Scope, inputs.chunks.entries.len);
    for (inputs.chunks.entries, scopes) |chunk, *scope| {
        scope.* = .{ .state_id = .{ .bytes = try allocator.dupe(u8, inputs.corpus.state_id.bytes) }, .chunk_id = .{ .bytes = try allocator.dupe(u8, chunk.id.bytes) } };
        _ = try source.resolve(inputs, scope.*);
    }
    return .{ .scopes = scopes };
}
pub fn current(progress: Progress) ?source.Scope {
    return if (progress.count < progress.scopes.len) progress.scopes[progress.count] else null;
}
pub fn append(allocator: std.mem.Allocator, progress: Progress, scope: source.Scope, bytes: []const u8, origin: ?@import("model_candidate_origin.zig").Origin) e.Error!Progress {
    const expected = current(progress) orelse return error.InvalidReferenceExtraction;
    if (!expected.state_id.eql(scope.state_id) or !expected.chunk_id.eql(scope.chunk_id)) return error.InvalidReferenceExtraction;
    const entry = try allocator.create(Entry);
    entry.* = .{ .value = .{ .scope = expected, .origin = origin, .result = .{ .response = try allocator.dupe(u8, bytes) } }, .previous = progress.latest };
    return .{ .scopes = progress.scopes, .latest = entry, .count = progress.count + 1 };
}
pub fn finish(allocator: std.mem.Allocator, progress: Progress) e.Error!e.Raw {
    if (progress.count != progress.scopes.len) return error.InvalidReferenceExtraction;
    const entries = try allocator.alloc(e.RawResult, progress.count);
    var latest = progress.latest;
    var index = entries.len;
    while (index != 0) {
        index -= 1;
        const entry = latest orelse return error.InvalidReferenceExtraction;
        if (!entry.value.scope.state_id.eql(progress.scopes[index].state_id) or !entry.value.scope.chunk_id.eql(progress.scopes[index].chunk_id)) return error.InvalidReferenceExtraction;
        entries[index] = entry.value;
        latest = entry.previous;
    }
    if (latest != null) return error.InvalidReferenceExtraction;
    return .{ .entries = entries };
}
