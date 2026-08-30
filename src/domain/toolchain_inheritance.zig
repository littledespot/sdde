const std = @import("std");
const toolchain = @import("toolchain.zig");
const schema = @import("toolchain_schema.zig");

pub fn validateCompleteRegistry(allocator: std.mem.Allocator, registry: toolchain.Registry) toolchain.Error!void {
    for (registry.presets) |preset| {
        const selected = [_][]const u8{preset.package};
        const resolved = try resolve(allocator, .{ .presets = &selected, .policies = &.{} }, registry);
        allocator.free(resolved.packages);
    }
}

pub fn resolve(
    allocator: std.mem.Allocator,
    project: toolchain.Project,
    registry: toolchain.Registry,
) toolchain.Error!toolchain.Resolved {
    var ordered: std.ArrayList(*const toolchain.Preset) = .empty;
    errdefer ordered.deinit(allocator);
    const selected = allocator.alloc(u8, registry.presets.len) catch return error.InvalidToolchain;
    defer allocator.free(selected);
    @memset(selected, 0);
    for (project.presets) |reference| try markSelected(registry, reference, selected);
    for (registry.presets, 0..) |left, index| {
        if (selected[index] == 0) continue;
        for (registry.presets[index + 1 ..], index + 1..) |right, right_index| {
            if (selected[right_index] != 0 and std.mem.eql(u8, left.package_id, right.package_id) and
                !std.mem.eql(u8, left.package, right.package)) return error.InvalidToolchain;
        }
    }
    const emitted = allocator.alloc(bool, registry.presets.len) catch return error.InvalidToolchain;
    defer allocator.free(emitted);
    @memset(emitted, false);
    while (true) {
        var next: ?usize = null;
        for (registry.presets, 0..) |preset, index| {
            if (selected[index] == 0 or emitted[index] or !dependenciesEmitted(registry, preset, emitted)) continue;
            if (next == null or schema.lessPreset({}, preset, registry.presets[next.?])) next = index;
        }
        const index = next orelse break;
        emitted[index] = true;
        ordered.append(allocator, &registry.presets[index]) catch return error.InvalidToolchain;
    }
    var selected_count: usize = 0;
    for (selected) |state| if (state != 0) {
        selected_count += 1;
    };
    if (ordered.items.len != selected_count) return error.InvalidToolchain;
    return .{ .packages = ordered.toOwnedSlice(allocator) catch return error.InvalidToolchain };
}

fn markSelected(registry: toolchain.Registry, reference: []const u8, states: []u8) toolchain.Error!void {
    const index = findPreset(registry, reference) orelse return error.InvalidToolchain;
    if (states[index] == 1) return error.InvalidToolchain;
    if (states[index] == 2) return;
    states[index] = 1;
    for (registry.presets[index].extends) |dependency| try markSelected(registry, dependency, states);
    states[index] = 2;
}

fn dependenciesEmitted(registry: toolchain.Registry, preset: toolchain.Preset, emitted: []const bool) bool {
    for (preset.extends) |dependency| {
        const index = findPreset(registry, dependency) orelse return false;
        if (!emitted[index]) return false;
    }
    return true;
}

fn findPreset(registry: toolchain.Registry, reference: []const u8) ?usize {
    for (registry.presets, 0..) |preset, index| if (std.mem.eql(u8, preset.package, reference)) return index;
    return null;
}

test "inheritance is dependency first" {
    const presets = [_]toolchain.Preset{
        .{ .package = "base@1.0.0", .package_id = "base", .layer = .language, .extends = &.{}, .policies = &.{"project.zig@1"} },
        .{ .package = "app@1.0.0", .package_id = "app", .layer = .framework, .extends = &.{"base@1.0.0"}, .policies = &.{} },
    };
    const resolved = try resolve(std.testing.allocator, .{ .presets = &.{"app@1.0.0"}, .policies = &.{} }, .{ .presets = &presets });
    defer std.testing.allocator.free(resolved.packages);
    try std.testing.expectEqualStrings("base@1.0.0", resolved.packages[0].package);
}

test "inheritance rejects cycles and conflicting package versions" {
    const cyclic = [_]toolchain.Preset{
        .{ .package = "a@1.0.0", .package_id = "a", .layer = .language, .extends = &.{"b@1.0.0"}, .policies = &.{} },
        .{ .package = "b@1.0.0", .package_id = "b", .layer = .runtime, .extends = &.{"a@1.0.0"}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, resolve(std.testing.allocator, .{ .presets = &.{"a@1.0.0"}, .policies = &.{} }, .{ .presets = &cyclic }));
    const conflicting = [_]toolchain.Preset{
        .{ .package = "a@1.0.0", .package_id = "a", .layer = .language, .extends = &.{}, .policies = &.{} },
        .{ .package = "a@2.0.0", .package_id = "a", .layer = .language, .extends = &.{}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, resolve(std.testing.allocator, .{ .presets = &.{ "a@1.0.0", "a@2.0.0" }, .policies = &.{} }, .{ .presets = &conflicting }));
}

test "complete registry rejects invalid unselected closures" {
    const missing = [_]toolchain.Preset{
        .{ .package = "selected@1.0.0", .package_id = "selected", .layer = .language, .extends = &.{}, .policies = &.{} },
        .{ .package = "unused@1.0.0", .package_id = "unused", .layer = .runtime, .extends = &.{"absent@1.0.0"}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, validateCompleteRegistry(std.testing.allocator, .{ .presets = &missing }));

    const cycle = [_]toolchain.Preset{
        .{ .package = "selected@1.0.0", .package_id = "selected", .layer = .language, .extends = &.{}, .policies = &.{} },
        .{ .package = "unused-a@1.0.0", .package_id = "unused-a", .layer = .runtime, .extends = &.{"unused-b@1.0.0"}, .policies = &.{} },
        .{ .package = "unused-b@1.0.0", .package_id = "unused-b", .layer = .framework, .extends = &.{"unused-a@1.0.0"}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, validateCompleteRegistry(std.testing.allocator, .{ .presets = &cycle }));
}
