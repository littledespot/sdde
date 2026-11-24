//! The user's answer between a case's two legs. The first leg's retained project holds the forms it raised; when it holds
//! exactly one open form and that form offers the case's key, the answered form is the closed form with the key in its
//! answer region, as the user would write it. The first leg's project is evidence and is only read: the answered form is
//! written into the second leg's copy. Nothing is matched to a form by its wording, and nothing is retried or reworded:
//! any other state is reported as the unmet criterion it is. The second leg's run is the act of accepting the answer
//! (ADR 0025), made by the account that runs it.
const std = @import("std");
const clarification = @import("../../../src/domain/clarification_inputs.zig");
const forms = @import("../../../src/domain/clarification_form.zig");
const artifacts = @import("../../../src/domain/workflow_artifact_registry.zig");
const strict_json = @import("../../../src/domain/strict_json.zig");

/// Why there was no form to answer. Each is a diagnostic code of the first leg's report.
pub const Unavailable = enum {
    /// The first leg published no clarification state.
    no_clarification_state,
    /// The state does not hold exactly one open form.
    answer_form_count,
    /// The one open form is not a selection that offers the case's key.
    answer_not_offered,

    pub fn diagnostic(self: Unavailable) []const u8 {
        return switch (self) {
            .no_clarification_state => "NO_CLARIFICATION_STATE",
            .answer_form_count => "ANSWER_FORM_COUNT",
            .answer_not_offered => "ANSWER_NOT_OFFERED",
        };
    }
};
/// The answered form: its project-relative path and exact bytes.
pub const Form = struct { path: []const u8, bytes: []const u8 };
pub const Prepared = union(enum) { ready: Form, unavailable: Unavailable };

/// `specs` and `workflows` are the project's configured roots, and `feature` the case's feature directory. The caller's arena
/// owns what is returned.
pub fn prepare(io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, specs: []const u8, workflows: []const u8, feature: []const u8, key: []const u8) !Prepared {
    const state_path = try std.fs.path.join(allocator, &.{ workflows, "features", feature, "state", artifacts.clarification_state_filename });
    const bytes = project.readFileAlloc(io, state_path, allocator, .limited(clarification.max_state_bytes)) catch |err| switch (err) {
        error.FileNotFound => return .{ .unavailable = .no_clarification_state },
        else => return err,
    };
    const state = try strict_json.decode(clarification.State, allocator, bytes, .{ .maximum_bytes = clarification.max_state_bytes, .maximum_depth = clarification.max_state_depth });
    var open: ?clarification.Record = null;
    for (state.records) |record| {
        if (record.status != .open) continue;
        if (open != null) return .{ .unavailable = .answer_form_count };
        open = record;
    }
    const record = open orelse return .{ .unavailable = .answer_form_count };
    const options = switch (record.answer_schema) {
        .select_one => |value| value,
        else => return .{ .unavailable = .answer_not_offered },
    };
    const offered = for (options) |option| {
        if (std.mem.eql(u8, option.key, key)) break true;
    } else false;
    if (!offered) return .{ .unavailable = .answer_not_offered };
    const id = clarification.Id.parse(record.id) orelse return error.InvalidClarificationInput;
    const filename = id.filename();
    return .{ .ready = .{
        .path = try std.fs.path.join(allocator, &.{ specs, feature, artifacts.clarification_directory_name, &filename }),
        .bytes = try forms.render(allocator, record, .{ .state_ordinal = state.state_ordinal, .state_revision = state.revision, .record_revision = record.revision, .status = record.status }, .closed, key),
    } };
}

/// Copies a first leg's retained project into the second leg's empty project, so the second leg starts from exactly what the
/// first published, and writes the answered form over the form it holds. Every entry keeps its permissions: the engine reads the
/// feature log history the first leg left only while it is owner-only, so a copy at default modes would block the second leg
/// before its first request.
pub fn continueProject(io: std.Io, allocator: std.mem.Allocator, from: std.Io.Dir, into: std.Io.Dir, answered: Form) !void {
    var walker = try from.walk(allocator);
    defer walker.deinit();
    // The walk yields a directory before what it holds, so each parent exists when its entries are copied.
    while (try walker.next(io)) |entry| {
        const stat = try entry.dir.statFile(io, entry.basename, .{ .follow_symlinks = false });
        switch (entry.kind) {
            .directory => try into.createDir(io, entry.path, stat.permissions),
            .file => {
                const bytes = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(256 * 1024 * 1024));
                defer allocator.free(bytes);
                try into.writeFile(io, .{ .sub_path = entry.path, .data = bytes, .flags = .{ .permissions = stat.permissions } });
            },
            else => return error.UnsupportedProjectEntry,
        }
    }
    try into.writeFile(io, .{ .sub_path = answered.path, .data = answered.bytes });
}
