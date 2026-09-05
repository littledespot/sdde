const std = @import("std");
const schema = @import("../../domain/model_result_schema.zig");
const compiler_port = @import("../../ports/model_result_schema_compiler.zig");
const json = @import("../../domain/strict_json.zig");

pub const Adapter = struct {
    pub fn compiler(self: *Adapter) compiler_port.Compiler {
        return .{ .context = self, .compile_fn = compile };
    }

    fn compile(_: *anyopaque, allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
        var parsed = json.parse(allocator, bytes, .{
            .maximum_bytes = schema.max_bytes,
            .maximum_depth = schema.max_json_depth,
        }, true) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidJsonDocument => error.InvalidModelResultSchema,
        };
        defer parsed.deinit();
        return schema.compile(allocator, parsed.value, bytes);
    }
};
