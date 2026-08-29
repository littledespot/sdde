const std = @import("std");
const bootstrap_root_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_root_registry_service = @import("application/bootstrap_root_registry_service.zig");

test "every action imports only standard domain and port modules" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);

    var walker = try actions.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) {
            continue;
        }

        const source = try entry.dir.readFileAlloc(
            io,
            entry.basename,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        try expectAllowedActionImports(source);
    }
}

test "bootstrap orchestrator imports only binding and result contracts" {
    const source = @embedFile("application/bootstrap_orchestrator.zig");
    try expectAbsent(source, "/actions/");
    try expectAbsent(source, "/adapters/");
    try expectAbsent(source, "std.Io");
}

test "public root does not re-export ports or infrastructure adapters" {
    const source = @embedFile("root.zig");
    try expectAbsent(source, "adapters/");
    try expectAbsent(source, "ports/");
    try expectAbsent(source, "bootstrap_roots");
}

test "validated bootstrap registry authority is opaque" {
    switch (@typeInfo(bootstrap_root_registry.BootstrapRootRegistry)) {
        .@"opaque" => {},
        else => return error.RegistryAuthorityMustBeOpaque,
    }
    switch (@typeInfo(bootstrap_root_registry.ConfiguredBaseRootCapability)) {
        .@"opaque" => {},
        else => return error.RootCapabilityMustBeOpaque,
    }

    const service_source = @embedFile("application/bootstrap_root_registry_service.zig");
    try expectAbsent(service_source, "bootstrap_roots");
    try expectAbsent(service_source, "ValidatedConfiguredRoot");

    const inspector_source = @embedFile("adapters/filesystem/bootstrap_root_inspector.zig");
    try expectAbsent(inspector_source, "workspacePathPolicy");

    const init_type = @typeInfo(@TypeOf(
        bootstrap_root_registry_service.BootstrapRootRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);
    try std.testing.expect(init_type.params[0].type.? == *bootstrap_root_registry.Owner);
}

test "configuration domain ownership is independent of the JSON parser" {
    const source = @embedFile("domain/config.zig");
    try expectAbsent(source, "std.json.Parsed");
    try expectAbsent(source, "PublicError");
    try expectAbsent(source, "Registry");
}

test "feature service filenames and headings end in Service" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var features = try std.Io.Dir.cwd().openDir(io, "design/features", .{ .iterate = true });
    defer features.close(io);

    var iterator = features.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or
            !std.mem.startsWith(u8, entry.name, "F") or
            !std.mem.endsWith(u8, entry.name, ".md"))
        {
            continue;
        }

        try std.testing.expect(std.mem.endsWith(u8, entry.name, "Service.md"));
        const source = try features.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        const heading_end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
        const heading = std.mem.trimEnd(u8, source[0..heading_end], "\r");
        try std.testing.expect(std.mem.endsWith(u8, heading, "Service"));
    }
}

fn expectAbsent(source: []const u8, forbidden: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, source, forbidden) == null);
}

fn expectAllowedActionImports(source: []const u8) !void {
    const prefix = "@import(\"";
    var remaining = source;
    while (std.mem.indexOf(u8, remaining, prefix)) |import_start| {
        const path_start = import_start + prefix.len;
        const path_end = std.mem.indexOfScalarPos(u8, remaining, path_start, '"') orelse {
            return error.UnterminatedImport;
        };
        const path = remaining[path_start..path_end];
        try std.testing.expect(
            std.mem.eql(u8, path, "std") or
                std.mem.eql(u8, path, "builtin") or
                std.mem.startsWith(u8, path, "../../domain/") or
                std.mem.startsWith(u8, path, "../../ports/"),
        );
        remaining = remaining[path_end + 1 ..];
    }
}
