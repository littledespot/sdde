const std = @import("std");
const requests = @import("../application/model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const binding = @import("../application/workflow_operation_binding.zig");

pub const count = 4;
pub const schemas = requests.schemas;

/// Native bindings only; sequencing belongs to the selected YAML graph.
pub const Assembly = struct {
    initialize: requests.Initialize,
    assign: requests.Assign,
    validate: requests.Validate,
    build: requests.Build,
    entries: [count]operations.Entry,

    pub fn init(self: *Assembly, allocator: std.mem.Allocator) void {
        self.* = .{
            .initialize = .{ .allocator = allocator },
            .assign = .{ .allocator = allocator },
            .validate = .{ .allocator = allocator },
            .build = .{ .allocator = allocator },
            .entries = undefined,
        };
        self.entries = .{
            entry(requests.Initialize, &self.initialize),
            entry(requests.Assign, &self.assign),
            entry(requests.Validate, &self.validate),
            entry(requests.Build, &self.build),
        };
    }
};

fn entry(comptime T: type, context: *T) operations.Entry {
    return .{ .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}
