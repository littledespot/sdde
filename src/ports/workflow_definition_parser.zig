const std = @import("std");
const workflow = @import("../domain/workflow_registry.zig");

pub const Error = error{InvalidWorkflowDefinition};

pub const Parser = struct {
    context: *anyopaque,
    parse_fn: *const fn (
        *anyopaque,
        std.mem.Allocator,
        []const workflow.Capture,
    ) Error![]const workflow.RawDefinition,

    pub fn parse(
        self: Parser,
        allocator: std.mem.Allocator,
        captures: []const workflow.Capture,
    ) Error![]const workflow.RawDefinition {
        return self.parse_fn(self.context, allocator, captures);
    }
};
