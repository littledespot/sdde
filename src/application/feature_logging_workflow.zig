const std = @import("std");
const feature = @import("../domain/feature_directory.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const directory = values.schema(.activated_feature_directory, feature.Directory, 1, @import("feature_directory_workflow.zig").directory.maximum_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{directory};

pub const Activate = struct {
    allocator: std.mem.Allocator,
    activator: ?@import("../ports/feature_log_activation.zig").Activator = null,

    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "activate-feature-logging",
        .kind = .step,
        .requires = &.{.feature_directory},
        .produces = &.{.activated_feature_directory},
        .outcomes = &.{ .ok, .blocked, .failed, .cancelled },
        .side_effect = .filesystem_write,
    };

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = values.read(&input.step.data, @import("feature_directory_workflow.zig").directory, feature.Directory) catch return error.OperationExecutionFailed;
        const activator = self.activator orelse return error.OperationExecutionFailed;
        return switch (activator.activate(prior.*, input.step.log.workflow_shortcode)) {
            .ready => |current| ready: {
                var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
                delta.data_writes[@intFromEnum(directory.key)] = values.create(self.allocator, directory, feature.Directory, current) catch return error.OperationExecutionFailed;
                break :ready .{ .outcome = .ok, .delta = delta };
            },
            .blocked => .{ .outcome = .blocked, .delta = .{} },
            .cancelled => .{ .outcome = .cancelled, .delta = .{} },
        };
    }
};

const ActivationSpy = struct {
    const port = @import("../ports/feature_log_activation.zig");
    result: port.Outcome,
    received: ?feature.Directory = null,
    shortcode: ?@import("../domain/telemetry.zig").WorkflowShortcode = null,

    fn activator(self: *ActivationSpy) port.Activator {
        return .{ .context = @ptrCast(self), .activate_fn = activate };
    }

    fn activate(context: *port.Context, prior: feature.Directory, shortcode: @import("../domain/telemetry.zig").WorkflowShortcode) port.Outcome {
        const self: *ActivationSpy = @ptrCast(@alignCast(context));
        self.received = prior;
        self.shortcode = shortcode;
        return self.result;
    }
};

const test_prior: feature.Directory = .{
    .selector = .{ .feature_id = .{ .bytes = "chosen" }, .project_relative_path = "specs/chosen" },
    .root_observation = .absent,
    .observation = .absent,
};

const test_step: @import("../domain/workflow_compilation.zig").CompiledStep = .{
    .id = .{ .bytes = "activate" },
    .operation_id = .{ .bytes = Activate.contract.id },
    .parameters = &.{},
    .requires = Activate.contract.requires,
    .produces = Activate.contract.produces,
    .replaces = Activate.contract.replaces,
    .invalidates = Activate.contract.invalidates,
    .outcomes = Activate.contract.outcomes,
    .side_effect = Activate.contract.side_effect,
    .gates = &.{},
    .capabilities = &.{"feature-output-write"},
    .retry_authority = null,
};

fn testInput(prior: *@import("../domain/pipeline_data.zig").Value) operations.Input {
    var input: operations.Input = .{ .step = .{
        .data = .{},
        .step = &test_step,
        .resources = &.{},
        .model_binding = null,
        .log = .init(.{ .bytes = "SPEC".* }),
    } };
    input.step.data.slots[@intFromEnum(@import("feature_directory_workflow.zig").directory.key)] = prior;
    return input;
}

test "cancelled and blocked feature logging activation preserve their outcomes without data effects" {
    const prior_schema = @import("feature_directory_workflow.zig").directory;
    const prior = try values.create(std.testing.allocator, prior_schema, feature.Directory, test_prior);
    defer values.destroy(prior);
    const input = testInput(prior);
    const port = @import("../ports/feature_log_activation.zig");
    for ([_]port.Outcome{ .cancelled, .{ .blocked = .LOG_SINK_FAILURE } }) |result| {
        var spy: ActivationSpy = .{ .result = result };
        var operation: Activate = .{ .allocator = std.testing.allocator, .activator = spy.activator() };
        const candidate = try Activate.invoke(&operation, input);
        try std.testing.expectEqual(@as(@import("../domain/workflow.zig").OutcomeTag, if (result == .cancelled) .cancelled else .blocked), candidate.outcome);
        var keys: @import("../domain/pipeline.zig").EffectKeys = .{};
        const effects = candidate.delta.effects(&keys);
        try std.testing.expectEqual(@as(usize, 0), effects.data_writes.len);
        try std.testing.expectEqual(@as(usize, 0), effects.data_replacements.len);
        try std.testing.expectEqual(@as(usize, 0), effects.data_invalidations.len);
        try std.testing.expect(candidate.delta.runner_accounting_transition == null);
        try std.testing.expect(candidate.delta.repair_transition == null);
        try std.testing.expectEqual(@as(usize, 0), candidate.delta.addedTelemetryFacts().len);
        try std.testing.expectEqualDeep(test_prior, spy.received.?);
        try std.testing.expectEqualDeep(input.step.log.workflow_shortcode, spy.shortcode.?);
        try std.testing.expectEqualDeep(test_prior, (try values.read(&input.step.data, prior_schema, feature.Directory)).*);
    }
}

test "feature logging activation adds current directory without replacing immutable preflight facts" {
    const prior_schema = @import("feature_directory_workflow.zig").directory;
    const prior = try values.create(std.testing.allocator, prior_schema, feature.Directory, test_prior);
    defer values.destroy(prior);
    const input = testInput(prior);
    var current = test_prior;
    current.root_observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 2 } };
    current.observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 3 } };
    var spy: ActivationSpy = .{ .result = .{ .ready = current } };
    var operation: Activate = .{ .allocator = std.testing.allocator, .activator = spy.activator() };
    const candidate = try Activate.invoke(&operation, input);
    defer values.destroy(candidate.delta.data_writes[@intFromEnum(directory.key)].?);
    try std.testing.expectEqual(.ok, candidate.outcome);
    var keys: @import("../domain/pipeline.zig").EffectKeys = .{};
    const effects = candidate.delta.effects(&keys);
    try std.testing.expectEqualSlices(@import("../domain/pipeline.zig").DataKey, &.{.activated_feature_directory}, effects.data_writes);
    try std.testing.expectEqual(@as(usize, 0), effects.data_replacements.len);
    try std.testing.expectEqual(@as(usize, 0), effects.data_invalidations.len);
    const next: @import("../domain/pipeline_data.zig").View = .{ .slots = candidate.delta.data_writes };
    try std.testing.expectEqualDeep(current, (try values.read(&next, directory, feature.Directory)).*);
    try std.testing.expectEqualDeep(test_prior, (try values.read(&input.step.data, prior_schema, feature.Directory)).*);
}
