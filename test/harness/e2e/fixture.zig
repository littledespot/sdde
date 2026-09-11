const std = @import("std");
const contracts = @import("contracts.zig");
const files = @import("../files.zig");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");
const relative = @import("../../../src/domain/relative_directory_path.zig");
pub const CapturedFile = struct { mapping: contracts.Copy, bytes: []const u8 };
pub const Capture = struct {
    config_source: []const u8,
    config: []const u8,
    directories: []const []const u8,
    files: []const CapturedFile,
    script_source: []const u8,
    script_bytes: []const u8,
    script: @import("../../../src/test_fixtures/specification_script.zig").Script,
    expected_source: []const u8,
    expected_bytes: []const u8,
};

/// The caller owns one arena for the case, captured bytes and invocation.
pub fn capture(io: std.Io, allocator: std.mem.Allocator, repository: std.Io.Dir, selected: contracts.Case) !Capture {
    const config = try files.read(io, allocator, repository, selected.config);
    const captured = try allocator.alloc(CapturedFile, selected.files.len);
    for (selected.files, captured) |mapping, *file| file.* = .{
        .mapping = mapping,
        .bytes = try files.read(io, allocator, repository, mapping.source),
    };
    const script_bytes = try files.read(io, allocator, repository, selected.provider_script);
    const script = try @import("../../../src/test_fixtures/specification_script.zig").parse(allocator, script_bytes);
    const expected_bytes = try files.read(io, allocator, repository, selected.expected_specification);
    _ = try @import("../../../src/domain/specification_markdown.zig").parse(allocator, expected_bytes);
    return .{ .config_source = selected.config, .config = config, .directories = selected.directories, .files = captured, .script_source = selected.provider_script, .script_bytes = script_bytes, .script = script, .expected_source = selected.expected_specification, .expected_bytes = expected_bytes };
}

pub fn materialize(io: std.Io, project: std.Io.Dir, captured: Capture) !void {
    try write(io, project, ".sddtoolkit.json", captured.config);
    for (captured.directories) |path| {
        const directory = try directories.ensure(io, project, path);
        directory.close(io);
    }
    for (captured.files) |file| try write(io, project, file.mapping.destination, file.bytes);
}

/// Once ordinary bootstrap validates configuration, reject any fixture which
/// pre-seeds feature output. A file's prior existence cannot satisfy the oracle.
pub fn validateOutputs(captured: Capture, roots: @import("../../../src/domain/workflow_artifact_registry.zig").FeatureRoots, allocator: std.mem.Allocator) !void {
    const states = try std.mem.concat(allocator, u8, &.{ roots.workflows, "/features" });
    defer allocator.free(states);
    for (captured.files) |file| {
        if (relative.contains(roots.specs, file.mapping.destination) or relative.contains(states, file.mapping.destination)) return error.FixtureContainsWorkflowOutput;
    }
}

pub fn verifySources(io: std.Io, allocator: std.mem.Allocator, repository: std.Io.Dir, captured: Capture) !void {
    for ([_]struct { path: []const u8, bytes: []const u8 }{
        .{ .path = captured.script_source, .bytes = captured.script_bytes },
        .{ .path = captured.expected_source, .bytes = captured.expected_bytes },
    }) |input| {
        const current = try files.read(io, allocator, repository, input.path);
        defer allocator.free(current);
        if (!std.mem.eql(u8, current, input.bytes)) return error.FixtureChanged;
    }
    const config = try files.read(io, allocator, repository, captured.config_source);
    defer allocator.free(config);
    if (!std.mem.eql(u8, config, captured.config)) return error.FixtureChanged;
    for (captured.files) |file| {
        const current = try files.read(io, allocator, repository, file.mapping.source);
        defer allocator.free(current);
        if (!std.mem.eql(u8, current, file.bytes)) return error.FixtureChanged;
    }
}

fn write(io: std.Io, root: std.Io.Dir, path: []const u8, bytes: []const u8) !void {
    const parent_path = std.fs.path.dirname(path);
    const parent = if (parent_path) |name| try directories.ensure(io, root, name) else root;
    defer if (parent_path != null) parent.close(io);
    const file = try parent.createFile(io, std.fs.path.basename(path), .{ .exclusive = true });
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}
