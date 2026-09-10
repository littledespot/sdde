//! Registered output destinations and exact read preconditions. No raw output
//! path, completion assertion, transaction or saved continuation is accepted.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const artifacts = @import("workflow_artifact_registry.zig");
pub const Target = union(enum) { artifact: enum { specification, reference_context, clarification_state, workflow_state }, form: c.Id };
pub const File = struct { target: Target, bytes: []const u8 };
pub const Prepared = struct {
    feature: @import("feature_directory.zig").Directory,
    paths: artifacts.FeaturePaths,
    prior: c.Captures,
    prior_workflow_state: union(enum) { unselected, captured: ?[]const u8 } = .unselected,
    files: []const File,
};
pub const Error = std.mem.Allocator.Error || error{ InvalidWorkflowOutput, OutputChanged, OutputWriteFailed };

pub fn path(allocator: std.mem.Allocator, paths: artifacts.FeaturePaths, target: Target) Error!artifacts.ArtifactPath {
    return switch (target) {
        .artifact => |kind| switch (kind) {
            inline else => |tag| paths.get(@field(artifacts.Artifact, @tagName(tag))),
        },
        .form => |id| blk: {
            if (id.ordinal == 0 or id.ordinal > 99) return error.InvalidWorkflowOutput;
            const parent = paths.get(.clarification_forms);
            const name = id.filename();
            break :blk .{ .root = parent.root, .root_relative = try std.mem.concat(allocator, u8, &.{ parent.root_relative, "/", &name }), .project_relative = try std.mem.concat(allocator, u8, &.{ parent.project_relative, "/", &name }) };
        },
    };
}

pub fn validateShape(output: Prepared) Error!void {
    if (output.files.len == 0 or output.files.len > c.max_forms + 4 or
        !std.mem.eql(u8, output.feature.selector.feature_id.bytes, output.paths.feature.feature_id.bytes) or
        !std.mem.eql(u8, output.feature.selector.project_relative_path, output.paths.feature.project_relative_path)) return error.InvalidWorkflowOutput;
    for (output.files, 0..) |file, index| {
        if (file.bytes.len == 0) return error.InvalidWorkflowOutput;
        if (file.target == .form and (file.target.form.ordinal == 0 or file.target.form.ordinal > 99 or file.bytes.len > c.max_form_bytes)) return error.InvalidWorkflowOutput;
        // Completion state is the last replacement, never an intermediate write.
        if (file.target == .artifact and file.target.artifact == .workflow_state and
            (index + 1 != output.files.len or output.prior_workflow_state == .unselected)) return error.InvalidWorkflowOutput;
        for (output.files[0..index]) |other| if (std.meta.eql(file.target, other.target)) return error.InvalidWorkflowOutput;
    }
}

pub fn sameCapture(expected: c.Captures, actual: c.Captures) bool {
    if ((expected.state == null) != (actual.state == null) or expected.forms.len != actual.forms.len) return false;
    if (expected.state) |bytes| if (!std.mem.eql(u8, bytes, actual.state.?)) return false;
    for (expected.forms, actual.forms) |left, right| if (!std.meta.eql(left.id, right.id) or !std.mem.eql(u8, left.bytes, right.bytes)) return false;
    return true;
}

pub fn sameBytes(expected: ?[]const u8, actual: ?[]const u8) bool {
    if (expected) |bytes| return actual != null and std.mem.eql(u8, bytes, actual.?);
    return actual == null;
}
