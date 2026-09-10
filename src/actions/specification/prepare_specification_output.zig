const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const state = @import("../../domain/specification_state.zig");
const output = @import("../../domain/workflow_output.zig");
const c = @import("../../domain/clarification_inputs.zig");
const codec = @import("../../domain/specification_markdown.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-specification-output",
        .kind = .action,
        .requires = &.{ .feature_directory, .feature_artifact_paths, .raw_clarification_inputs, .clarification_inputs, .refreshed_clarification_state, .clarification_views, .prior_specification_state, .specification_publication_state, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .rendered_specification, .validated_specification_rendering, .rendered_reference_context },
        .produces = &.{.prepared_workflow_output},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_directory.zig").Directory, paths: @import("../../domain/workflow_artifact_registry.zig").FeaturePaths, captured: c.Captures, inputs: c.Inputs, clarifications: @import("../../domain/clarification_refresh.zig").Result, views: []const @import("../../domain/clarification_views.zig").View, prior: state.Prior, value: state.State, context: @import("../../domain/specification_provenance.zig").Context, specification: []const u8, rendering_valid: bool, reference_context: []const u8) !output.Prepared {
        if (!rendering_valid or clarifications != .ready) return error.InvalidWorkflowOutput;
        try state.validate(allocator, value, feature.selector.feature_id);
        const resolved = try state.checkClarifications(clarifications.ready);
        if (value.revision != try state.nextRevision(prior) or value.clarification.state_ordinal != resolved.state_ordinal or value.clarification.revision != resolved.revision) return error.InvalidWorkflowOutput;
        if (!value.reference.inputs.corpus.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidWorkflowOutput;
        const document = try @import("../../domain/specification_projection.zig").project(allocator, context, value.content);
        const rendered = try codec.render(allocator, document);
        const reparsed = try codec.render(allocator, try codec.parse(allocator, specification));
        if (!std.mem.eql(u8, specification, rendered) or !std.mem.eql(u8, specification, reparsed) or
            !std.mem.eql(u8, reference_context, try @import("../../domain/reference_context.zig").render(allocator, value.reference))) return error.InvalidWorkflowOutput;
        var prepared = try @import("../../domain/clarification_output.zig").prepare(allocator, feature, paths, captured, inputs, clarifications, views);
        const canonical = try @import("../../domain/canonical_json.zig").encode(state.State, allocator, value);
        _ = try state.parse(allocator, canonical, feature.selector.feature_id);
        const files = try allocator.alloc(output.File, prepared.files.len + 3);
        files[0] = .{ .target = .{ .artifact = .specification }, .bytes = specification };
        files[1] = .{ .target = .{ .artifact = .reference_context }, .bytes = reference_context };
        @memcpy(files[2..][0..prepared.files.len], prepared.files);
        files[files.len - 1] = .{ .target = .{ .artifact = .workflow_state }, .bytes = canonical };
        prepared.files = files;
        prepared.prior_workflow_state = .{ .captured = prior.captured };
        try output.validateShape(prepared);
        return prepared;
    }
};
