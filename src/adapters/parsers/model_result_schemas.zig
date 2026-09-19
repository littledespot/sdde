const std = @import("std");
const schema = @import("../../domain/model_result_schema.zig");
const compiler_port = @import("../../ports/model_result_schema_compiler.zig");
const json = @import("../../domain/strict_json.zig");
const composition = @import("../../domain/json_composition.zig");
const workflow = @import("../../domain/workflow.zig");

pub const Adapter = struct {
    pub fn compiler(self: *Adapter) compiler_port.Compiler {
        return .{ .context = self, .compile_fn = compile, .composition_result_alias_fn = compositionResultAlias, .compile_composition_fn = compileComposition };
    }

    fn compile(_: *anyopaque, allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
        var parsed = json.parse(allocator, bytes, .{
            .maximum_bytes = schema.max_bytes,
            .maximum_depth = schema.max_json_depth,
        }, true, null) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidJsonDocument => error.InvalidModelResultSchema,
        };
        defer parsed.deinit();
        return schema.compile(allocator, parsed.value, bytes);
    }

    fn compositionResultAlias(_: *anyopaque, allocator: std.mem.Allocator, bytes: []const u8) composition.Error!workflow.WorkflowResourceId {
        var parsed = try parseComposition(allocator, bytes);
        defer parsed.deinit();
        return .{ .bytes = try allocator.dupe(u8, (try composition.resultAlias(parsed.value)).bytes) };
    }

    fn compileComposition(_: *anyopaque, allocator: std.mem.Allocator, bytes: []const u8, canonical: *const schema.Schema) composition.Error!*const composition.Plan {
        var parsed = try parseComposition(allocator, bytes);
        defer parsed.deinit();
        return composition.compile(allocator, parsed.value, bytes, canonical);
    }

    fn parseComposition(allocator: std.mem.Allocator, bytes: []const u8) composition.Error!std.json.Parsed(std.json.Value) {
        return json.parse(allocator, bytes, .{ .maximum_bytes = schema.max_bytes, .maximum_depth = schema.max_json_depth }, true, null) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidJsonDocument => error.InvalidJsonComposition,
        };
    }
};
