const std = @import("std");
const schema = @import("../domain/model_result_schema.zig");

pub const Compiler = struct {
    context: *anyopaque,
    compile_fn: *const fn (*anyopaque, std.mem.Allocator, []const u8) schema.Error!*const schema.Schema,

    // Allocator is the receiving graph's arena, discarded in full on failure.
    pub fn compile(self: Compiler, allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
        return self.compile_fn(self.context, allocator, bytes);
    }
};
