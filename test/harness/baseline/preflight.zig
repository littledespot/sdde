//! Read the actual compiled policy without invoking a project workflow or provider.
const std = @import("std");

pub fn workflowBudget(io: std.Io, a: std.mem.Allocator, project: std.Io.Dir, workflow: []const u8) !u64 {
    var runtime: @import("../../../src/composition/root.zig").Runtime = undefined;
    runtime.init(io, a, project, .{});
    defer runtime.deinit();
    if (runtime.boot != .ready) return error.BaselineTemplateBootstrapFailed;
    const id = @import("../../../src/domain/workflow.zig").WorkflowId.parse(workflow) orelse return error.InvalidBaselineWorkflow;
    const graph = runtime.boot.ready.workflows.registry().resolve(id) orelse return error.InvalidBaselineWorkflow;
    return graph.authority.total_model_token_budget.value;
}
