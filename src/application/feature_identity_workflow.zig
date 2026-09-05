const std = @import("std");
const identity = @import("../domain/feature_identity.zig");
const reference = @import("../domain/reference_selector.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");

pub const seed_schema = values.schema(.feature_identity_seed, identity.FeatureIdentitySeed, 1, reference.max_bytes * 4 + 1024);

pub const Derive = struct {
    pub const Action = @import("../actions/specify/derive_feature_identity.zig").Action;
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{
        .{ .id = "max-length", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 1, .integer_max = identity.maximum_id_bytes },
    };
    allocator: std.mem.Allocator,
    action: Action,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const step = switch (input) {
            .step => |value| value,
            .invocation => return error.OperationExecutionFailed,
        };
        const configured = step.step.parameters;
        if (configured.len != 1 or !std.mem.eql(u8, configured[0].id.bytes, parameters[0].id) or configured[0].value != .integer) return error.OperationExecutionFailed;
        const policy = identity.NamingPolicy.init(configured[0].value.integer) orelse return error.OperationExecutionFailed;
        const selector = values.read(&step.data, @import("reference_workflow_values.zig").selector, reference.RelativeSelector) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), selector.*, policy) catch return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, seed_schema, identity.FeatureIdentitySeed, result);
    }
};
