const std = @import("std");
const workflow = @import("workflow.zig");

pub const parameter_id = "retry-limit";

pub const Limit = struct {
    value: u32,

    pub fn within(self: Limit, maximum: u32) bool {
        return maximum != 0 and self.value <= maximum;
    }
};

/// Terminal evidence owns its operation name and survives graph/runner teardown.
pub const Exhaustion = struct {
    operation_name: [workflow.max_local_id_bytes]u8,
    operation_name_len: u8,
    limit: Limit,
    completed_executions: u64,

    pub const Description = struct {
        operation_instance_id: workflow.WorkflowStepId,
        retry_limit: u32,
        completed_executions: u64,
    };

    pub fn init(step: workflow.WorkflowStepId, limit: Limit, completed: u64) ?Exhaustion {
        if (workflow.WorkflowStepId.parse(step.bytes) == null or completed <= limit.value) return null;
        var result: Exhaustion = .{ .operation_name = @splat(0), .operation_name_len = @intCast(step.bytes.len), .limit = limit, .completed_executions = completed };
        @memcpy(result.operation_name[0..step.bytes.len], step.bytes);
        return result;
    }

    pub fn operation(self: *const Exhaustion) workflow.WorkflowStepId {
        return .{ .bytes = self.operation_name[0..self.operation_name_len] };
    }

    pub fn describe(self: *const Exhaustion, allocator: std.mem.Allocator) std.mem.Allocator.Error!Description {
        return .{ .operation_instance_id = .{ .bytes = try allocator.dupe(u8, self.operation().bytes) }, .retry_limit = self.limit.value, .completed_executions = self.completed_executions };
    }
};

pub const CompiledAuthority = struct {
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    operation_instance_id: workflow.WorkflowStepId,
    limit: Limit,

    pub fn isValid(self: CompiledAuthority) bool {
        return self.workflow_version != 0 and
            workflow.WorkflowId.parse(self.workflow_id.bytes) != null and
            workflow.WorkflowStepId.parse(self.operation_instance_id.bytes) != null;
    }

    pub fn eql(left: CompiledAuthority, right: CompiledAuthority) bool {
        return left.workflow_version == right.workflow_version and
            left.limit.value == right.limit.value and
            std.mem.eql(u8, left.workflow_id.bytes, right.workflow_id.bytes) and
            std.mem.eql(u8, left.operation_instance_id.bytes, right.operation_instance_id.bytes);
    }
};
