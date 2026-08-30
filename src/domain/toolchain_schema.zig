const std = @import("std");
const toolchain = @import("toolchain.zig");

pub fn parseProject(allocator: std.mem.Allocator, document: toolchain.RawDocument) toolchain.Error!toolchain.Project {
    const map = mapping(document.root) orelse return error.InvalidToolchain;
    if (map.len != 3 or !scalarEquals(field(map, "schema"), toolchain.project_schema)) return error.InvalidToolchain;
    return .{
        .presets = try refList(allocator, field(map, "presets"), toolchain.max_refs, packageRefValid),
        .policies = try refList(allocator, field(map, "policies"), toolchain.max_policies, policyRefValid),
    };
}

pub fn parseRegistry(allocator: std.mem.Allocator, documents: []const toolchain.RawDocument) toolchain.Error!toolchain.Registry {
    if (documents.len > toolchain.max_presets) return error.InvalidToolchain;
    const presets = allocator.alloc(toolchain.Preset, documents.len) catch return error.InvalidToolchain;
    for (documents, presets) |document, *preset| {
        const map = mapping(document.root) orelse return error.InvalidToolchain;
        if (map.len != 5 or !scalarEquals(field(map, "schema"), toolchain.preset_schema)) return error.InvalidToolchain;
        const package = scalar(field(map, "package")) orelse return error.InvalidToolchain;
        if (!packageRefValid(package)) return error.InvalidToolchain;
        const split = std.mem.lastIndexOfScalar(u8, package, '@') orelse return error.InvalidToolchain;
        preset.* = .{
            .package = package,
            .package_id = package[0..split],
            .layer = std.meta.stringToEnum(toolchain.Layer, scalar(field(map, "layer")) orelse return error.InvalidToolchain) orelse return error.InvalidToolchain,
            .extends = try refList(allocator, field(map, "extends"), toolchain.max_refs, packageRefValid),
            .policies = try refList(allocator, field(map, "policies"), toolchain.max_policies, policyRefValid),
        };
    }
    std.mem.sort(toolchain.Preset, presets, {}, lessPreset);
    for (presets, 0..) |preset, index| {
        if (index != 0 and std.mem.eql(u8, presets[index - 1].package, preset.package)) return error.InvalidToolchain;
    }
    return .{ .presets = presets };
}

pub fn lessPreset(_: void, left: toolchain.Preset, right: toolchain.Preset) bool {
    const layer = @intFromEnum(left.layer) < @intFromEnum(right.layer);
    return if (left.layer != right.layer) layer else std.mem.order(u8, left.package, right.package) == .lt;
}

fn mapping(node: *toolchain.RawNode) ?[]const toolchain.Pair {
    return switch (node.*) {
        .mapping => |value| value,
        else => null,
    };
}

fn scalar(node: ?*toolchain.RawNode) ?[]const u8 {
    const present = node orelse return null;
    return switch (present.*) {
        .scalar => |value| value,
        else => null,
    };
}

fn scalarEquals(node: ?*toolchain.RawNode, expected: []const u8) bool {
    return if (scalar(node)) |actual| std.mem.eql(u8, actual, expected) else false;
}

fn field(map: []const toolchain.Pair, name: []const u8) ?*toolchain.RawNode {
    for (map) |pair| {
        const key = scalar(pair.key) orelse return null;
        if (std.mem.eql(u8, key, name)) return pair.value;
    }
    return null;
}

fn refList(
    allocator: std.mem.Allocator,
    node: ?*toolchain.RawNode,
    maximum: usize,
    validator: *const fn ([]const u8) bool,
) toolchain.Error![]const []const u8 {
    const present = node orelse return error.InvalidToolchain;
    const values = switch (present.*) {
        .sequence => |items| items,
        else => return error.InvalidToolchain,
    };
    if (values.len > maximum) return error.InvalidToolchain;
    const result = allocator.alloc([]const u8, values.len) catch return error.InvalidToolchain;
    for (values, result, 0..) |item, *destination, index| {
        destination.* = scalar(item) orelse return error.InvalidToolchain;
        if (!validator(destination.*)) return error.InvalidToolchain;
        for (result[0..index]) |prior| if (std.mem.eql(u8, prior, destination.*)) return error.InvalidToolchain;
    }
    return result;
}

fn packageRefValid(reference: []const u8) bool {
    const split = std.mem.lastIndexOfScalar(u8, reference, '@') orelse return false;
    return idValid(reference[0..split]) and semverValid(reference[split + 1 ..]);
}

fn policyRefValid(reference: []const u8) bool {
    const split = std.mem.lastIndexOfScalar(u8, reference, '@') orelse return false;
    if (!idValid(reference[0..split])) return false;
    const version = reference[split + 1 ..];
    if (version.len == 0 or version[0] == '0') return false;
    for (version) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}

fn idValid(id: []const u8) bool {
    if (id.len == 0 or !std.ascii.isLower(id[0])) return false;
    var separator = false;
    for (id) |byte| if (std.ascii.isLower(byte) or std.ascii.isDigit(byte)) {
        separator = false;
    } else if (byte == '.' or byte == '-') {
        if (separator) return false;
        separator = true;
    } else return false;
    return !separator;
}

fn semverValid(version: []const u8) bool {
    var parts = std.mem.splitScalar(u8, version, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        count += 1;
        if (part.len == 0 or (part.len > 1 and part[0] == '0')) return false;
        for (part) |byte| if (!std.ascii.isDigit(byte)) return false;
    }
    return count == 3;
}

test "closed references reject ranges latest and leading zero versions" {
    try std.testing.expect(packageRefValid("zig@0.16.0"));
    try std.testing.expect(!packageRefValid("zig@latest"));
    try std.testing.expect(!packageRefValid("zig@^0.16.0"));
    try std.testing.expect(!packageRefValid("zig@00.16.0"));
}
