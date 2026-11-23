//! Registered output destinations and exact read preconditions. No raw output
//! path, completion assertion, transaction or saved continuation is accepted.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const artifacts = @import("workflow_artifact_registry.zig");
pub const Target = union(enum) { artifact: enum { specification, reference_context, clarification_state, workflow_state, actor_evidence }, form: c.Id };
pub const File = struct { target: Target, bytes: []const u8 };
/// How the run ends once its output is written: complete, awaiting the user, or cancelled by the user's own `cancel`
/// (ADR 0025), which publishes the clarification state and the actor evidence and nothing else.
pub const TerminalOutcome = enum { ok, needs_user, cancelled };
/// A single-file precondition: `unselected` when the output does not write the file, else the bytes captured before the run
/// (none when the file was absent), which the writer rechecks before and between its writes.
pub const Prior = union(enum) { unselected, captured: ?[]const u8 };
pub const Prepared = struct {
    terminal_outcome: TerminalOutcome,
    feature: @import("feature_directory.zig").Directory,
    paths: artifacts.FeaturePaths,
    prior: c.Captures,
    prior_workflow_state: Prior = .unselected,
    /// The actor-evidence registry's prior bytes, selected when the output writes the registry (ADR 0025).
    prior_actor_evidence: Prior = .unselected,
    files: []const File,
};
pub const Error = std.mem.Allocator.Error || error{ InvalidWorkflowOutput, OutputChanged, OutputWriteFailed, Cancelled };

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
    if (output.files.len == 0 or output.files.len > c.max_forms + 5 or
        !std.mem.eql(u8, output.feature.selector.feature_id.bytes, output.paths.feature.feature_id.bytes) or
        !std.mem.eql(u8, output.feature.selector.project_relative_path, output.paths.feature.project_relative_path)) return error.InvalidWorkflowOutput;
    for (output.files, 0..) |file, index| {
        if (file.bytes.len == 0) return error.InvalidWorkflowOutput;
        if (file.target == .form and (file.target.form.ordinal == 0 or file.target.form.ordinal > 99 or file.bytes.len > c.max_form_bytes)) return error.InvalidWorkflowOutput;
        // Completion state is the last replacement, never an intermediate write.
        if (file.target == .artifact and file.target.artifact == .workflow_state and
            (index + 1 != output.files.len or output.prior_workflow_state == .unselected)) return error.InvalidWorkflowOutput;
        // The registry is written before the state that joins it, so a run that stops between them leaves evidence no
        // response names, never a response whose evidence is missing (ADR 0025).
        if (file.target == .artifact and file.target.artifact == .actor_evidence) {
            if (output.prior_actor_evidence == .unselected) return error.InvalidWorkflowOutput;
            for (output.files[0..index]) |earlier| if (earlier.target == .artifact and
                (earlier.target.artifact == .clarification_state or earlier.target.artifact == .workflow_state)) return error.InvalidWorkflowOutput;
        }
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
