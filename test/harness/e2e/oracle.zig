//! Observe the engine's output; this module never manufactures a specification.
const std = @import("std");
const c = @import("contracts.zig");
const paths = @import("../../../src/domain/workflow_artifact_registry.zig");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");
const files = @import("../../../src/adapters/filesystem/file_access.zig");
pub const Publication = union(enum) { not_observed, confirmed: *const @import("../../../src/domain/workflow_output.zig").Prepared };
pub const Result = struct { status: c.Status, missing_artifact: ?c.Artifact = null, specification: ?[]const u8 = null, specification_bytes: ?[]const u8 = null };

pub fn inspect(io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, outcome: @import("../../../src/domain/workflow.zig").OutcomeTag, publication: Publication, expected: []const c.Artifact, resolved: paths.FeaturePaths) !Result {
    if (outcome != .ok) return .{ .status = .workflow_failed };
    if (publication != .confirmed) return .{ .status = .publication_missing };
    var specification_bytes: ?[]const u8 = null;
    var retained = false;
    defer if (!retained) {
        if (specification_bytes) |bytes| allocator.free(bytes);
    };
    for (expected) |artifact| {
        const path = switch (artifact) {
            inline else => |tag| resolved.get(@field(paths.Artifact, @tagName(tag))).project_relative,
        };
        const parent = directories.open(io, project, std.fs.path.dirname(path).?) catch |err| return switch (err) {
            error.DirectoryMissing => .{ .status = .artifact_missing, .missing_artifact = artifact },
            else => .{ .status = .artifact_unreadable, .missing_artifact = artifact },
        };
        defer parent.close(io);
        const captured = files.capture(io, allocator, parent, std.fs.path.basename(path), null, std.math.maxInt(usize) - 1) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => .{ .status = .artifact_unreadable, .missing_artifact = artifact },
        };
        const bytes = captured orelse return .{ .status = .artifact_missing, .missing_artifact = artifact };
        defer allocator.free(bytes);
        if (bytes.len == 0) return .{ .status = .artifact_unreadable, .missing_artifact = artifact };
        const published = for (publication.confirmed.files) |file| {
            if (file.target == .artifact and std.mem.eql(u8, @tagName(file.target.artifact), @tagName(artifact))) break file.bytes;
        } else return .{ .status = .publication_missing, .missing_artifact = artifact };
        if (!std.mem.eql(u8, published, bytes)) {
            return .{ .status = .artifact_changed, .missing_artifact = artifact };
        }
        if (artifact == .specification) specification_bytes = try allocator.dupe(u8, bytes);
    }
    retained = true;
    return .{ .status = .generated, .specification = resolved.get(.specification).project_relative, .specification_bytes = specification_bytes };
}
