const std = @import("std");
const schema = @import("../../domain/model_result_schema.zig");
const compiler_port = @import("../../ports/model_result_schema_compiler.zig");

pub const Adapter = struct {
    pub fn compiler(self: *Adapter) compiler_port.Compiler {
        return .{ .context = self, .compile_fn = compile };
    }

    fn compile(_: *anyopaque, allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
        if (bytes.len == 0 or bytes.len > schema.max_bytes or
            !std.unicode.utf8ValidateSlice(bytes) or std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) return error.InvalidModelResultSchema;
        try validateNesting(allocator, bytes);
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
            .duplicate_field_behavior = .@"error",
            .allocate = .alloc_always,
            .max_value_len = schema.max_bytes,
        }) catch |err| return mapError(err);
        defer parsed.deinit();
        return schema.compile(allocator, parsed.value, bytes);
    }
};

fn validateNesting(allocator: std.mem.Allocator, bytes: []const u8) schema.Error!void {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var depth: usize = 0;
    while (true) {
        const token = scanner.next() catch |err| return mapError(err);
        switch (token) {
            .object_begin, .array_begin => {
                depth += 1;
                if (depth > schema.max_json_depth) return error.InvalidModelResultSchema;
            },
            .object_end, .array_end => {
                if (depth == 0) return error.InvalidModelResultSchema;
                depth -= 1;
            },
            .end_of_document => {
                if (depth != 0) return error.InvalidModelResultSchema;
                return;
            },
            else => {},
        }
    }
}

fn mapError(err: anyerror) schema.Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidModelResultSchema;
}
