const std = @import("std");
const toolchain = @import("toolchain.zig");

/// The selected policy ids: each resolved package's policies in package order, then the project's, each once.
pub fn compose(
    allocator: std.mem.Allocator,
    project: toolchain.Project,
    resolved: toolchain.Resolved,
) toolchain.Error![]const []const u8 {
    var policies: std.ArrayList([]const u8) = .empty;
    for (resolved.packages) |preset| {
        for (preset.policies) |policy| try appendUnique(allocator, &policies, policy);
    }
    for (project.policies) |policy| try appendUnique(allocator, &policies, policy);
    return policies.toOwnedSlice(allocator) catch return error.InvalidToolchain;
}

fn appendUnique(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), value: []const u8) toolchain.Error!void {
    for (list.items) |present| if (std.mem.eql(u8, present, value)) return;
    list.append(allocator, value) catch return error.InvalidToolchain;
}

test "composition orders the stable policy union by resolved package then project" {
    const presets = [_]toolchain.Preset{
        .{ .package = "base@1.0.0", .package_id = "base", .layer = .language, .extends = &.{}, .policies = &.{ "common@1", "base@1" } },
        .{ .package = "app@1.0.0", .package_id = "app", .layer = .framework, .extends = &.{}, .policies = &.{ "common@1", "app@1" } },
    };
    const packages = [_]*const toolchain.Preset{ &presets[0], &presets[1] };
    const composed = try compose(std.testing.allocator, .{ .presets = &.{}, .policies = &.{ "base@1", "project@1" } }, .{ .packages = &packages });
    defer std.testing.allocator.free(composed);
    const expected = [_][]const u8{ "common@1", "base@1", "app@1", "project@1" };
    try std.testing.expectEqualDeep(expected[0..], composed);
}
