const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const values = @import("pipeline_values.zig");

/// One ordinary typed action result, owned by its delta until runner application.
pub fn publish(allocator: std.mem.Allocator, schema: @import("../domain/pipeline_data.zig").Schema, comptime T: type, result: T) @import("../ports/workflow_operation_registry.zig").Error!@import("../domain/workflow_execution.zig").Candidate {
    var delta: pipeline.NodeDelta = .{};
    delta.data_writes[@intFromEnum(schema.key)] = values.create(allocator, schema, T, result) catch return error.OperationExecutionFailed;
    return .{ .outcome = .ok, .delta = delta };
}
