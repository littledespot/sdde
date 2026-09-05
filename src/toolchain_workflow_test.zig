const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const values = @import("application/pipeline_values.zig");
const schemas = @import("application/toolchain_workflow_values.zig");
const runners = @import("application/toolchain_workflow_runner.zig");
const bindings = @import("application/workflow_operation_binding.zig");

test "toolchain bindings derive only the narrow capabilities their actions hold" {
    const capture = comptime bindings.inspect(runners.CaptureProject, &.{});
    const inventory = comptime bindings.inspect(runners.InventoryPresets, &.{});
    const presets = comptime bindings.inspect(runners.CapturePresets, &.{});
    const parse = comptime bindings.inspect(runners.ParseDocuments, &.{});
    const safety = comptime bindings.inspect(runners.ValidateSafety, &.{});
    inline for (.{ capture, inventory, presets }) |source| {
        try std.testing.expect(source.valid and source.toolchain_read and !source.toolchain_parser and !source.model_provider);
    }
    try std.testing.expect(parse.valid and parse.toolchain_parser and !parse.toolchain_read and !parse.model_provider);
    try std.testing.expect(safety.valid and !safety.toolchain_read and !safety.toolchain_parser and !safety.model_provider);
}

test "safety result publication cleans up its sole native owner on every allocation failure" {
    const input = try values.create(std.testing.allocator, schemas.composed, @import("domain/toolchain.zig").Composed, .{ .packages = &.{"example@1.0.0"}, .policies = &.{} });
    defer values.destroy(input);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, safetyAllocationCase, .{input});
}

fn safetyAllocationCase(allocator: std.mem.Allocator, input: *@import("domain/pipeline_data.zig").Value) !void {
    var runner: runners.ValidateSafety = .{ .allocator = allocator, .action = .{ .registry = .{ .contracts = &.{} } } };
    var view: @import("domain/pipeline_data.zig").View = .{};
    view.slots[@intFromEnum(schemas.composed.key)] = input;
    const step: @import("domain/workflow_compilation.zig").CompiledStep = .{
        .id = .{ .bytes = "validate" },
        .operation_id = .{ .bytes = runners.ValidateSafety.Action.contract.id },
        .parameters = &.{},
        .requires = runners.ValidateSafety.Action.contract.requires,
        .produces = runners.ValidateSafety.Action.contract.produces,
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{ .ok, .failed },
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = null,
    };
    var candidate = runners.ValidateSafety.invoke(&runner, .{ .step = .{
        .data = view,
        .step = &step,
        .resources = &.{},
        .model_binding = null,
        .log = pipeline.WorkflowLog.init(.{ .bytes = "TEST".* }),
    } }) catch return error.OutOfMemory;
    const store = @import("application/pipeline_envelope.zig").PipelineEnvelope.init(&.{schemas.valid});
    defer store.discard(&candidate.delta);
    try std.testing.expectEqual(@import("domain/workflow.zig").OutcomeTag.ok, candidate.outcome);
}
