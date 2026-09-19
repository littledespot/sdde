const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const draft = @import("../../domain/incomplete_specification.zig");
const state = @import("../../domain/specification_state.zig");
const c = @import("../../domain/clarification_inputs.zig");
const output = @import("../../domain/workflow_output.zig");
pub const Action = struct {
    contracts: ?state.ContractSource = null,
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-incomplete-specification-output",
        .kind = .action,
        .requires = &.{ .activated_feature_directory, .feature_artifact_paths, .raw_clarification_inputs, .clarification_inputs, .refreshed_clarification_state, .clarification_views, .prior_specification_state, .incomplete_specification_state, .rendered_incomplete_specification },
        .produces = &.{.prepared_workflow_output},
        .side_effect = .none,
    };
    pub fn execute(self: Action, a: std.mem.Allocator, feature: @import("../../domain/feature_directory.zig").Directory, paths: @import("../../domain/workflow_artifact_registry.zig").FeaturePaths, captured: c.Captures, inputs: c.Inputs, clarifications: @import("../../domain/clarification_refresh.zig").Result, views: []const @import("../../domain/clarification_views.zig").View, prior: state.Prior, value: draft.State, rendered: []const u8) !output.Prepared {
        if (clarifications != .ready or value.revision != try state.nextRevision(prior)) return error.InvalidWorkflowOutput;
        try draft.validate(a, value, feature.selector.feature_id, self.contracts);
        const expected = try @import("../../domain/incomplete_specification_markdown.zig").render(a, value, clarifications.ready);
        if (!std.mem.eql(u8, expected, rendered) or !std.meta.eql(prior.ledger(), value.id_ledger)) return error.InvalidWorkflowOutput;
        var prepared = try @import("../../domain/clarification_output.zig").prepare(a, feature, paths, captured, inputs, clarifications, views);
        if (prepared.terminal_outcome != .needs_user) return error.InvalidWorkflowOutput;
        const bytes = try @import("../../domain/canonical_json.zig").encode(draft.State, a, value);
        const restored = try state.parse(a, bytes, value.feature, self.contracts);
        if (restored.value != .pending) return error.InvalidWorkflowOutput;
        const restored_view = try @import("../../domain/incomplete_specification_markdown.zig").render(a, restored.value.pending, clarifications.ready);
        if (!std.mem.eql(u8, rendered, restored_view)) return error.InvalidWorkflowOutput;
        const files = try a.alloc(output.File, prepared.files.len + 3);
        files[0] = .{ .target = .{ .artifact = .specification }, .bytes = rendered };
        files[1] = .{ .target = .{ .artifact = .reference_context }, .bytes = try @import("../../domain/reference_context.zig").render(a, value.reference, null) };
        @memcpy(files[2..][0..prepared.files.len], prepared.files);
        files[files.len - 1] = .{ .target = .{ .artifact = .workflow_state }, .bytes = bytes };
        prepared.files = files;
        prepared.prior_workflow_state = .{ .captured = prior.captured };
        try output.validateShape(prepared);
        return prepared;
    }
};
