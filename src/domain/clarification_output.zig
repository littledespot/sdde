const std = @import("std");
const c = @import("clarification_inputs.zig");
const views = @import("clarification_views.zig");
const output = @import("workflow_output.zig");
const evidence = @import("actor_evidence.zig");
const refresh = @import("clarification_refresh.zig");
const acceptance = @import("clarification_acceptance.zig");
const feature_directory = @import("feature_directory.zig");
const artifacts = @import("workflow_artifact_registry.zig");

pub const Error = output.Error || c.Error || evidence.EncodeError || @import("canonical_json.zig").Error;

/// The clarification part of a publication: the forms, the actor-evidence registry that the state's responses join, and
/// the clarification state, in that order (ADR 0025). The registry is written before the state, so a run that stops
/// between them leaves evidence no response names, never a response whose evidence is missing. The run ends `ok` when no
/// record is open, and `needs_user` while one is.
pub fn prepare(allocator: std.mem.Allocator, feature: feature_directory.Directory, paths: artifacts.FeaturePaths, prior: c.Captures, inputs: c.Inputs, state: refresh.Result, rendered: []const views.View, registry: evidence.Registry, prior_registry: ?[]const u8) Error!output.Prepared {
    const terminal_outcome: output.TerminalOutcome = switch (refresh.progress(state)) {
        .ready => .ok,
        .needs_user => .needs_user,
        .blocked => return error.InvalidWorkflowOutput,
    };
    return build(allocator, feature, paths, prior, inputs, state.ready, rendered, registry, prior_registry, terminal_outcome);
}

/// The output of a run that ends `cancelled` because the user's own `cancel` was accepted (ADR 0025): the forms, the
/// registry and the clarification state, and nothing else. `accepted` names the forms this run accepted, and one of them
/// must have cancelled its record. The forms are the canonical projection of the accepted state.
pub fn prepareCancelled(allocator: std.mem.Allocator, feature: feature_directory.Directory, paths: artifacts.FeaturePaths, prior: c.Captures, inputs: c.Inputs, accepted: []const c.Id, ready: refresh.Ready, registry: evidence.Registry, prior_registry: ?[]const u8) Error!output.Prepared {
    if (!acceptance.cancels(inputs, accepted)) return error.InvalidWorkflowOutput;
    return build(allocator, feature, paths, prior, inputs, ready, null, registry, prior_registry, .cancelled);
}

/// `rendered` is a projection a step already produced, checked against the canonical one, or none to publish the canonical.
fn build(allocator: std.mem.Allocator, feature: feature_directory.Directory, paths: artifacts.FeaturePaths, prior: c.Captures, inputs: c.Inputs, ready: refresh.Ready, rendered: ?[]const views.View, registry: evidence.Registry, prior_registry: ?[]const u8, terminal_outcome: output.TerminalOutcome) Error!output.Prepared {
    const value = ready.state.value orelse return error.InvalidWorkflowOutput;
    _ = try ready.validate(allocator);
    _ = try c.validate(.{ .value = value }, feature.selector.feature_id);
    try evidence.validate(registry, feature.selector.feature_id);
    try evidence.validateJoin(registry, value);
    const expected = try views.render(allocator, ready, inputs.protected_forms);
    const shown = rendered orelse expected;
    if (shown.len != expected.len) return error.InvalidWorkflowOutput;
    var files: std.ArrayList(output.File) = .empty;
    for (shown, expected) |view, canonical| {
        if (!std.meta.eql(view.id, canonical.id) or std.meta.activeTag(view.content) != std.meta.activeTag(canonical.content)) return error.InvalidWorkflowOutput;
        switch (view.content) {
            .replace => |bytes| {
                if (!std.mem.eql(u8, bytes, canonical.content.replace)) return error.InvalidWorkflowOutput;
                try files.append(allocator, .{ .target = .{ .form = view.id }, .bytes = bytes });
            },
            .retain => |bytes| if (!std.mem.eql(u8, bytes, canonical.content.retain)) return error.InvalidWorkflowOutput,
        }
    }
    try files.append(allocator, .{ .target = .{ .artifact = .actor_evidence }, .bytes = try evidence.encode(allocator, registry) });
    const bytes = try @import("canonical_json.zig").encode(c.State, allocator, value);
    if (bytes.len > c.max_state_bytes) return error.InvalidWorkflowOutput;
    try files.append(allocator, .{ .target = .{ .artifact = .clarification_state }, .bytes = bytes });
    const prepared: output.Prepared = .{ .terminal_outcome = terminal_outcome, .feature = feature, .paths = paths, .prior = prior, .prior_actor_evidence = .{ .captured = prior_registry }, .files = try files.toOwnedSlice(allocator) };
    try output.validateShape(prepared);
    return prepared;
}
