const std = @import("std");
const definition = @import("../domain/workflow_definition.zig");
const inventory = @import("../domain/workflow_inventory.zig");

pub const Error = error{InvalidWorkflowDefinition};

pub const Parser = struct {
    context: *anyopaque,
    parse_fn: *const fn (
        *anyopaque,
        std.mem.Allocator,
        []const inventory.Capture,
    ) Error![]const definition.RawDefinition,

    pub fn parse(
        self: Parser,
        allocator: std.mem.Allocator,
        captures: []const inventory.Capture,
    ) Error![]const definition.RawDefinition {
        return self.parse_fn(self.context, allocator, captures);
    }
};
