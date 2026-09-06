//! A single evaluator operation; no workflow, file, scoring or tool capability.
const std = @import("std");
const wire = @import("openai.zig");
pub const Context = opaque {};
pub const Error = std.mem.Allocator.Error || error{Cancelled};
pub const Port = struct {
    context: *Context,
    invoke_fn: *const fn (*Context, std.mem.Allocator, []const u8, u32) Error!wire.Observation,
    pub fn invoke(self: Port, a: std.mem.Allocator, body: []const u8, timeout_ms: u32) Error!wire.Observation {
        return self.invoke_fn(self.context, a, body, timeout_ms);
    }
};
