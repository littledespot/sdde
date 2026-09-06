//! Native action bindings; the selected YAML owns order and success branches.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const spec = @import("../domain/specification.zig");
const owned = @import("specification_values.zig").storage;
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const document_schema = values.schema(.specification_document, owned.Value, 1, null);
pub const rendered_schema = values.schema(.rendered_specification, owned.Value, 1, null);
pub const validated_schema = values.schema(.validated_specification_rendering, bool, 1, @sizeOf(bool));
pub const schemas = [_]data.Schema{ document_schema, rendered_schema, validated_schema };

pub const Project = struct {
    pub const Action = @import("../actions/specification/project_specification_document.zig").Action;
    pub const gates = [_][]const u8{"required-authority@1"};
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authority = @import("required_authority_values.zig");
        const content = authority.read(&input.step.data, @import("required_authority_workflow.zig").content_schema, .content) catch return error.OperationExecutionFailed;
        const support = authority.read(&input.step.data, @import("required_authority_workflow.zig").inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .document = self.action.execute(owner.arena.allocator(), try @import("specification_workflow.zig").readContext(&input.step.data), content, support) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, document_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const Render = struct {
    pub const Action = @import("../actions/specification/render_specification.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const document = owned.read(&input.step.data, document_schema, .document) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .rendered = self.action.execute(owner.arena.allocator(), document) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, rendered_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const Validate = struct {
    pub const Action = @import("../actions/specification/validate_specification_rendering.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const document = owned.read(&input.step.data, document_schema, .document) catch return error.OperationExecutionFailed;
        const bytes = owned.read(&input.step.data, rendered_schema, .rendered) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        self.action.execute(arena.allocator(), document, bytes) catch return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, validated_schema, bool, true);
    }
};
