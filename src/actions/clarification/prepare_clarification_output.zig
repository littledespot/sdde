const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const c = @import("../../domain/clarification_inputs.zig");
const views = @import("../../domain/clarification_views.zig");
const output = @import("../../domain/workflow_output.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-clarification-output",
        .kind = .action,
        .requires = &.{ .feature_directory, .feature_artifact_paths, .raw_clarification_inputs, .clarification_inputs, .refreshed_clarification_state, .clarification_views },
        .produces = &.{.prepared_workflow_output},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_directory.zig").Directory, paths: @import("../../domain/workflow_artifact_registry.zig").FeaturePaths, prior: c.Captures, inputs: c.Inputs, state: @import("../../domain/clarification_refresh.zig").Result, rendered: []const views.View) (output.Error || c.Error || @import("../../domain/canonical_json.zig").Error)!output.Prepared {
        if (state != .ready) return error.InvalidWorkflowOutput;
        const value = state.ready.value orelse return error.InvalidWorkflowOutput;
        _ = try c.validate(.{ .value = value }, feature.selector.feature_id);
        const expected = try views.render(allocator, state.ready, inputs.protected_forms);
        if (rendered.len != expected.len) return error.InvalidWorkflowOutput;
        var files: std.ArrayList(output.File) = .empty;
        for (rendered, expected) |view, canonical| {
            if (!std.meta.eql(view.id, canonical.id) or std.meta.activeTag(view.content) != std.meta.activeTag(canonical.content)) return error.InvalidWorkflowOutput;
            switch (view.content) {
                .replace => |bytes| {
                    if (!std.mem.eql(u8, bytes, canonical.content.replace)) return error.InvalidWorkflowOutput;
                    try files.append(allocator, .{ .target = .{ .form = view.id }, .bytes = bytes });
                },
                .retain => |bytes| if (!std.mem.eql(u8, bytes, canonical.content.retain)) return error.InvalidWorkflowOutput,
            }
        }
        const bytes = try @import("../../domain/canonical_json.zig").encode(c.State, allocator, value);
        if (bytes.len > c.max_state_bytes) return error.InvalidWorkflowOutput;
        try files.append(allocator, .{ .target = .{ .artifact = .clarification_state }, .bytes = bytes });
        const prepared: output.Prepared = .{ .feature = feature, .paths = paths, .prior = prior, .files = try files.toOwnedSlice(allocator) };
        try output.validateShape(prepared);
        return prepared;
    }
};
