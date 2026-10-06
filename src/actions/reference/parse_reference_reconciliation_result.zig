const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-reference-reconciliation-result", .kind = .action, .requires = &.{.raw_reference_reconciliation}, .produces = &.{.parsed_reference_reconciliation}, .invalidates = &.{.raw_reference_reconciliation}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, raw: r.Raw) r.Error!r.Parsed {
        const projection = @import("../../domain/reference_reconciliation_projection.zig");
        const proposal: @FieldType(r.Parsed, "proposal") = switch (raw.input.purpose) {
            .summary => .{ .summary = try projection.summary(allocator, raw.input, (@import("../../domain/model_candidate_json.zig").decode(projection.SemanticSummary, allocator, raw.bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation).statements) },
            .global => return error.InvalidReferenceReconciliation,
        };
        var source = raw.source;
        var fields: std.ArrayList(r.diagnostic.FieldOrigin) = .empty;
        try fields.appendSlice(allocator, source.fields);
        for (proposal.summary.statements, 0..) |statement, index| {
            if (statement.content == .preserved_token) try fields.append(allocator, .{ .unit = .{ .statement = index }, .field = .record, .origin = null });
        }
        source.fields = try fields.toOwnedSlice(allocator);
        return .{ .source = source, .input = raw.input, .proposal = proposal };
    }
};
