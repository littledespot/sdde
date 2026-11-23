const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const feature = @import("../../domain/feature_directory.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const authentication = @import("../../domain/clarification_authentication.zig");
const evidence = @import("../../domain/actor_evidence.zig");
const output = @import("../../domain/workflow_output.zig");
const refresh = @import("../../domain/clarification_refresh.zig");
const reference = @import("../../domain/reference_evidence.zig");
const clarification_output = @import("../../domain/clarification_output.zig");

pub const Error = clarification_output.Error;

/// Prepares the output of a run the user cancelled (ADR 0025): the accepted responses, their evidence and the forms, and no
/// specification, reference context or workflow state, since the run made no model call. The forms the run accepted are
/// the authenticated ones it planned, and one of them must have cancelled its record.
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-cancelled-clarification-output",
        .kind = .action,
        .requires = &.{ .activated_feature_directory, .feature_artifact_paths, .raw_clarification_inputs, .clarification_inputs, .authentication_progress, .raw_actor_evidence, .actor_evidence_registry, .citable_reference_inputs },
        .produces = &.{.prepared_workflow_output},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, observed: feature.Directory, paths: artifacts.FeaturePaths, captures: clarification.Captures, inputs: clarification.Inputs, progress: authentication.Progress, prior_registry: ?[]const u8, registry: evidence.Registry, sources: reference.Inputs) Error!output.Prepared {
        const ready: refresh.Ready = .{ .state = inputs.state, .original_sources = try refresh.originalSources(allocator, sources) };
        const prepared = try clarification_output.prepareCancelled(allocator, observed, paths, captures, inputs, progress.pending, ready, registry, prior_registry);
        if (prepared.terminal_outcome != .cancelled) return error.InvalidWorkflowOutput;
        return prepared;
    }
};
