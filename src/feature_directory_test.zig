const std = @import("std");
const feature = @import("domain/feature_directory.zig");
const identity = @import("domain/feature_identity.zig");
const normalize = @import("actions/specify/normalize_feature_directory.zig");
const validate = @import("actions/specify/validate_feature_directory.zig");
const normalizer: @import("ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = @import("unicode_normalization").nfc };
const configured: feature.Roots = .{ .specs = "requirements/current", .archive = "requirements/current/archive" };

test "feature input is lossless config-root-relative and independent of reference input" {
    for ([_][]const u8{ "one", "unrelated/日本語" }) |reference| {
        const candidate = try (normalize.Action{ .normalizer = normalizer }).execute(std.testing.allocator, .{ .raw_feature = "./Cafe\u{301}\\日本語", .raw_reference = reference });
        defer std.testing.allocator.free(candidate.bytes);
        const result = try (validate.Action{ .roots = configured }).execute(std.testing.allocator, candidate);
        defer std.testing.allocator.free(result.project_relative_path);
        try std.testing.expectEqualStrings("Café/日本語", result.feature_id.bytes);
        try std.testing.expectEqualStrings("requirements/current/Café/日本語", result.project_relative_path);
    }
}

test "feature resolution has no hardcoded or stripped specs prefix" {
    for ([_][]const u8{ "specs", "requirements/current" }) |root| {
        const result = try feature.validate(std.testing.allocator, .{ .bytes = "specs/hello-world" }, .{ .specs = root, .archive = "elsewhere/archive" });
        defer std.testing.allocator.free(result.project_relative_path);
        const expected = try std.mem.concat(std.testing.allocator, u8, &.{ root, "/specs/hello-world" });
        defer std.testing.allocator.free(expected);
        try std.testing.expectEqualStrings(expected, result.project_relative_path);
    }
}

test "feature path safety rejects escape aliases invalid components and archive descendants" {
    for ([_][]const u8{
        "",         ".",            "../outside",               "/absolute", "C:\\outside", "a//b", "a/",      "a/../b",
        "a/%2e%2e", "a/%252f",      "a/CON",                    "a/b.",      "a/b ",        "a/b?", "a/\x00b", "a/\u{85}b",
        "archive",  "ARCHIVE/item", "archive/child/grandchild", "\xff",
    }) |path| {
        try std.testing.expectError(error.InvalidFeatureDirectory, feature.validate(std.testing.allocator, .{ .bytes = path }, configured));
    }
    try std.testing.expectError(error.InvalidFeatureDirectory, (validate.Action{}).execute(std.testing.allocator, .{ .bytes = "hello" }));
    const sibling = try feature.validate(std.testing.allocator, .{ .bytes = "archive-copy" }, configured);
    defer std.testing.allocator.free(sibling.project_relative_path);
    const oversized = [_]u8{'a'} ** 256;
    try std.testing.expect(identity.FeatureId.parse(&oversized) == null);
    try std.testing.expect(identity.FeatureId.parse("Case/Café/日本語") != null);
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    const candidate = try (normalize.Action{ .normalizer = normalizer }).execute(allocator, .{ .raw_feature = "./Cafe\u{301}/notes", .raw_reference = "independent" });
    defer allocator.free(candidate.bytes);
    const result = try feature.validate(allocator, candidate, configured);
    defer allocator.free(result.project_relative_path);
    try std.testing.expectEqualStrings("requirements/current/Café/notes", result.project_relative_path);
}

test "feature normalization and resolution release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "feature inspection is a narrow read capability not a reference or model capability" {
    const binding = @import("application/workflow_operation_binding.zig");
    const runners = @import("application/feature_directory_workflow.zig");
    const inspection = comptime binding.inspect(runners.Inspect, &.{});
    try std.testing.expect(inspection.valid and inspection.feature_read and !inspection.reference_read and !inspection.model_provider);
    const validation = comptime binding.inspect(runners.Validate, &.{});
    try std.testing.expect(validation.valid and !validation.feature_read and !validation.reference_read);
}
