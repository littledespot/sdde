//! Construct only decisions forced by the admitted extraction outcome.
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const e = @import("../../domain/reference_extraction.zig");
const runtime = @import("../../domain/json_composition_runtime.zig");
const parser = @import("../../domain/reference_extraction_parser.zig");
pub const Outcome = std.meta.Tag(parser.Content);
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "construct-forced-token-classifications", .kind = .action, .requires = &.{ .json_composition, .structured_token_candidates, .citable_reference_inputs }, .produces = &.{}, .replaces = &.{.json_composition}, .side_effect = .none };
    pub const Result = union(enum) { native: runtime.State, semantic };
    pub fn execute(_: Action, a: std.mem.Allocator, state: runtime.State, source_part: usize, target_part: usize, inputs: @import("../../domain/reference_evidence.zig").Inputs, candidates: e.tokens.Candidates) (runtime.Error || e.Error)!Result {
        if (state.base.unit() != .reference_chunk) return error.InvalidReferenceExtraction;
        const unit = state.base.unit().reference_chunk;
        const scope: @import("../../domain/reference_evidence.zig").Scope = .{ .state_id = .{ .bytes = unit.reference_state_id.bytes }, .chunk_id = .{ .bytes = unit.chunk_id.bytes } };
        _ = try @import("../../domain/reference_evidence.zig").resolve(inputs, scope);
        try e.tokens.validateCandidates(a, inputs, candidates);
        const entry = state.getEntry(source_part) orelse return error.InvalidReferenceExtraction;
        if (entry.source != .model or !state.plan.dependsOn(target_part, source_part)) return error.InvalidReferenceExtraction;
        const body = try std.json.Stringify.valueAlloc(a, entry.value(), .{});
        defer a.free(body);
        const content = @import("../../domain/model_candidate_json.zig").decode(parser.Content, a, body) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceExtraction;
        const forced = (try classifications(a, scope, candidates, if (content == .claims) .claims else .no_feature_claim)) orelse return .semantic;
        const result = .{ .token_classifications = forced };
        const wire = @import("../../domain/model_candidate_json.zig").encode(@TypeOf(result), a, result) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceExtraction;
        defer a.free(wire);
        const parsed = std.json.parseFromSlice(std.json.Value, a, wire, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceExtraction;
        return .{ .native = try state.retainNative(a, try state.select(a, target_part), parsed.value) };
    }
};

/// Only a current chunk's admitted outcome can force its classifications.
/// Positive token-only extraction still needs a semantic classification.
pub fn classifications(a: std.mem.Allocator, scope: @import("../../domain/reference_evidence.zig").Scope, candidates: e.tokens.Candidates, outcome: Outcome) std.mem.Allocator.Error!?[]const e.tokens.Classification {
    var forced: std.ArrayList(e.tokens.Classification) = .empty;
    for (candidates.entries) |candidate| if (candidate.fact.scope.chunk_id.eql(scope.chunk_id)) {
        if (outcome == .claims) return null;
        try forced.append(a, .{ .irrelevant = candidate.id });
    };
    return try forced.toOwnedSlice(a);
}
