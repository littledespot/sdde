const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const safety = @import("../domain/toolchain_safety.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const schemas = @import("toolchain_workflow_values.zig");

// One binding runs the one stage action. YAML owns where it sits in the graph; the stage's
// internal steps are functions, not operations.
pub const PrepareToolchain = struct {
    pub const Action = @import("../actions/toolchain/prepare_toolchain.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        var diagnostic: @import("../actions/toolchain/prepare_toolchain.zig").Diagnostic = .{};
        const owner = self.action.execute(scratch.allocator(), self.allocator, input.step.runtime, &diagnostic) catch |operation_error| {
            // The stage-owned slot is read before the unchanged error propagates; the runner
            // records the step in the failed action's event (ADR 0031).
            if (input.step.stage_step) |slot| slot.name = if (diagnostic.step) |step| @tagName(step) else null;
            return operation_error;
        };
        const result = values.adopt(self.allocator, schemas.valid, safety.ValidToolchain, safety.Owner, owner, safety.value, safety.deinitOwner, safety.retainedBytes(owner)) catch |operation_error| {
            safety.deinitOwner(owner);
            return operation_error;
        };
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schemas.valid.key)] = result;
        return .{ .outcome = .ok, .delta = delta };
    }
};
