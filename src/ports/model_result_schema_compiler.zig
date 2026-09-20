const std = @import("std");
const schema = @import("../domain/model_result_schema.zig");
const composition = @import("../domain/json_composition.zig");
const workflow = @import("../domain/workflow.zig");

pub const Compiler = struct {
    context: *anyopaque,
    compile_fn: *const fn (*anyopaque, std.mem.Allocator, []const u8) schema.Error!*const schema.Schema,
    compile_selected_fn: *const fn (*anyopaque, std.mem.Allocator, []const u8) schema.Error!*const schema.Schema,
    composition_result_alias_fn: *const fn (*anyopaque, std.mem.Allocator, []const u8) composition.Error!workflow.WorkflowResourceId,
    compile_composition_fn: *const fn (*anyopaque, std.mem.Allocator, []const u8, *const schema.Schema) composition.Error!*const composition.Plan,

    // Allocator is the receiving graph's arena, discarded in full on failure.
    pub fn compile(self: Compiler, allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
        return self.compile_fn(self.context, allocator, bytes);
    }

    /// Diagnostic reconstruction of a compiler-selected response contract.
    pub fn compileSelected(self: Compiler, allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
        return self.compile_selected_fn(self.context, allocator, bytes);
    }

    pub fn compositionResultAlias(self: Compiler, allocator: std.mem.Allocator, bytes: []const u8) composition.Error!workflow.WorkflowResourceId {
        return self.composition_result_alias_fn(self.context, allocator, bytes);
    }

    pub fn compileComposition(self: Compiler, allocator: std.mem.Allocator, bytes: []const u8, canonical: *const schema.Schema) composition.Error!*const composition.Plan {
        return self.compile_composition_fn(self.context, allocator, bytes, canonical);
    }
};
