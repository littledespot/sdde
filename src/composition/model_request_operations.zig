const std = @import("std");
const requests = @import("../application/model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const binding = @import("../application/workflow_operation_binding.zig");
const attempts = @import("../application/model_attempt_workflow.zig");
const provider_operations = @import("../application/provider_operation_workflow.zig");
const accounting = @import("../application/workflow_model_accounting.zig");
const authorization = @import("../application/provider_authorization_workflow.zig");
const lifecycle = @import("../application/model_request_lifecycle_workflow.zig");
const provider_lifecycle = @import("../application/provider_operation_lifecycle_workflow.zig");
const invocation = @import("../application/model_invocation_workflow.zig");

pub const count = 10;
pub const schemas = requests.schemas ++ [_]@import("../domain/pipeline_data.zig").Schema{ accounting.schema, accounting.operation_schema, accounting.invoked_schema, authorization.schema, invocation.schema };

/// Native bindings only; sequencing belongs to the selected YAML graph.
pub const Assembly = struct {
    initialize: requests.Initialize,
    assign: requests.Assign,
    validate: requests.Validate,
    build: requests.Build,
    advance_attempt: attempts.Advance,
    assign_operation: provider_operations.Assign,
    prepare_authorization: authorization.Prepare,
    advance_request: lifecycle.Advance,
    advance_operation: provider_lifecycle.Advance,
    invoke_model: invocation.Invoke,
    entries: [count]operations.Entry,

    pub fn init(self: *Assembly, allocator: std.mem.Allocator) void {
        self.* = .{
            .initialize = .{ .allocator = allocator },
            .assign = .{ .allocator = allocator },
            .validate = .{ .allocator = allocator },
            .build = .{ .allocator = allocator },
            .advance_attempt = .{},
            .assign_operation = .{},
            .prepare_authorization = .{ .allocator = allocator },
            .advance_request = .{ .allocator = allocator },
            .advance_operation = .{},
            .invoke_model = .{ .allocator = allocator },
            .entries = undefined,
        };
        self.entries = .{
            entry(requests.Initialize, &self.initialize),
            entry(requests.Assign, &self.assign),
            entry(requests.Validate, &self.validate),
            entry(requests.Build, &self.build),
            entry(attempts.Advance, &self.advance_attempt),
            entry(provider_operations.Assign, &self.assign_operation),
            entry(authorization.Prepare, &self.prepare_authorization),
            entry(lifecycle.Advance, &self.advance_request),
            entry(provider_lifecycle.Advance, &self.advance_operation),
            entry(invocation.Invoke, &self.invoke_model),
        };
    }
};

fn entry(comptime T: type, context: *T) operations.Entry {
    return .{ .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}
