//! Input-only adapter. Reuse the engine's no-follow descriptor capture policy.
const std = @import("std");
const c = @import("contracts.zig");
const directory = @import("../../src/adapters/filesystem/directory_access.zig");
const file = @import("../../src/adapters/filesystem/file_access.zig");
pub const Error = c.Error || error{ InputUnavailable, Cancelled };

pub fn read(io: std.Io, allocator: std.mem.Allocator, root: std.Io.Dir, relative: []const u8) Error![]const u8 {
    try c.path(relative);
    const parent_name = std.fs.path.dirname(relative);
    const parent = if (parent_name) |name| directory.open(io, root, name) catch |err| return map(err) else root;
    defer if (parent_name != null) parent.close(io);
    // Shared capture reserves one extra byte to detect concurrent growth.
    const bytes = file.capture(io, allocator, parent, std.fs.path.basename(relative), null, std.math.maxInt(usize) - 1) catch |err| return map(err);
    return bytes orelse error.InputUnavailable;
}

/// Caller owns one arena for all captured bytes and decoded projections.
/// Artifact origin is supplied separately by the invocation adapter; never read
/// it from the specification or inferred from a path/name.
pub fn capture(io: std.Io, allocator: std.mem.Allocator, root: std.Io.Dir, case_path: []const u8, spec_path: []const u8, evaluation_id: []const u8, generation: c.Generation) Error!c.Capture {
    const case_bytes = try read(io, allocator, root, case_path);
    const selected = try c.parseCase(allocator, case_bytes);
    const rubric_bytes = try read(io, allocator, root, selected.rubric);
    const rubric = try c.parseRubric(allocator, rubric_bytes);
    const sources = try allocator.alloc(c.Document, selected.sources.len);
    for (selected.sources, sources) |source, *document| {
        document.* = .{ .id = source.id, .text = try read(io, allocator, root, source.path) };
    }
    const value: c.Capture = .{
        .evaluation_id = try allocator.dupe(u8, evaluation_id),
        .case = selected,
        .case_bytes = case_bytes,
        .rubric = rubric,
        .rubric_bytes = rubric_bytes,
        .sources = sources,
        .specification = try read(io, allocator, root, spec_path),
        .generation = generation,
    };
    try c.validateCapture(value);
    return value;
}
fn map(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.Cancelled => error.Cancelled,
        else => error.InputUnavailable,
    };
}
