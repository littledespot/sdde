//! Read-only projection of registered open forms, shared by CLI and harness.
const std = @import("std");
const c = @import("../domain/clarification_inputs.zig");
const values = @import("pipeline_values.zig");
const inputs = @import("clarification_input_workflow.zig");
const refresh = @import("clarification_refresh_workflow.zig");
const output = @import("workflow_output_binding.zig");
const Notice = @import("../domain/run_outcome.zig").Clarification;

/// The caller's arena owns the notices and every path; no invocation data is borrowed.
pub fn capture(a: std.mem.Allocator, view: *const @import("../domain/pipeline_data.zig").View) ![]const Notice {
    if (view.slots[@intFromEnum(inputs.paths_schema.key)] == null) return &.{};
    const paths = try values.read(view, inputs.paths_schema, @import("../domain/workflow_artifact_registry.zig").FeaturePaths);
    const state: c.ValidatedState = state: {
        if (view.slots[@intFromEnum(output.published_schema.key)] != null and
            (try values.read(view, output.published_schema, bool)).* and
            view.slots[@intFromEnum(refresh.state_schema.key)] != null)
        {
            const current = try values.read(view, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result);
            break :state switch (current.*) {
                .ready => |ready| ready,
                .blocked => return error.InvalidClarificationInput,
            };
        }
        if (view.slots[@intFromEnum(inputs.inputs_schema.key)] == null) return &.{};
        break :state (try values.read(view, inputs.inputs_schema, c.Inputs)).state;
    };
    const current = state.value orelse return &.{};
    var result: std.ArrayList(Notice) = .empty;
    for (current.records) |record| if (record.status == .open) {
        const id = c.Id.parse(record.id) orelse return error.InvalidClarificationInput;
        try result.append(a, .{ .id = id, .path = try @import("../domain/workflow_output.zig").path(a, paths.*, .{ .form = id }) });
    };
    return result.toOwnedSlice(a);
}
