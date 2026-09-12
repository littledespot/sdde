//! Test composition through the production actions, never a runtime fallback.
const std = @import("std");
const extraction = @import("../domain/reference_extraction.zig");
const evidence = @import("../domain/reference_evidence.zig");
pub const extract = @import("../actions/reference/extract_structured_reference_facts.zig").Action{};
pub const identify = @import("../actions/reference/assign_structured_token_candidate_identities.zig").Action{};
pub const classify = struct {
    pub fn execute(_: @This(), allocator: std.mem.Allocator, inputs: evidence.Inputs, available: extraction.tokens.Candidates, candidate: extraction.TextValidated) !extraction.Classified {
        return switch (try @import("../domain/token_classification_validation.zig").validate(allocator, inputs, available, candidate)) {
            .valid => |accepted| accepted,
            .invalid => error.InvalidStructuredTokens,
        };
    }
}{};
pub const assign = @import("../actions/reference/assign_preserved_token_identities.zig").Action{};
pub const build = @import("../actions/reference/build_preserved_token_claims.zig").Action{};
pub fn candidates(allocator: std.mem.Allocator, inputs: evidence.Inputs) !extraction.tokens.Candidates {
    return identify.execute(allocator, inputs, try extract.execute(allocator, inputs));
}
pub fn assignments(allocator: std.mem.Allocator, inputs: evidence.Inputs, text: extraction.TextValidated) !extraction.TokenAssignments {
    return assign.execute(allocator, try classify.execute(allocator, inputs, try candidates(allocator, inputs), text));
}
pub fn prepare(allocator: std.mem.Allocator, inputs: evidence.Inputs, text: extraction.TextValidated) !extraction.Prepared {
    return build.execute(allocator, try assignments(allocator, inputs, text));
}
pub fn classifications(allocator: std.mem.Allocator, available: extraction.tokens.Candidates, chunk: evidence.Chunk) ![]const extraction.tokens.Classification {
    var result: std.ArrayList(extraction.tokens.Classification) = .empty;
    for (available.entries) |candidate| if (candidate.fact.scope.chunk_id.eql(chunk.id)) try result.append(allocator, .{ .preserve = .{ .token_candidate_id = candidate.id, .kind = .business_exact_string } });
    return result.toOwnedSlice(allocator);
}
/// Explicit closed wire shape: domain unions are not model protocol wrappers.
pub fn wire(allocator: std.mem.Allocator, body: []const u8, choices: []const extraction.tokens.Classification) ![]const u8 {
    var document = try std.json.parseFromSlice(std.json.Value, allocator, body, .{ .allocate = .alloc_always });
    defer document.deinit();
    var items: std.json.Array = .init(allocator);
    for (choices) |choice| {
        const bytes = try @import("../domain/model_candidate_json.zig").encode(extraction.tokens.Classification, allocator, choice);
        const item = try std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always });
        try items.append(item);
    }
    try document.value.object.put(allocator, "token_classifications", .{ .array = items });
    return std.json.Stringify.valueAlloc(allocator, document.value, .{});
}
