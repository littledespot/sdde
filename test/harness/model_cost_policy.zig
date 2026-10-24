//! User-approved live-test cost policy. Production model selection is separate.
const std = @import("std");
const identity = @import("../../src/domain/llm_provider_identity.zig");
const config = @import("../../src/domain/config.zig");

pub const Error = error{DisallowedTestModel};

/// What a live request is for. Rubric grading keeps its own recorded model
/// decision (design/harness/acceptance.md), so a model approved only for
/// workflow generation never becomes a judge.
pub const Use = enum { generation, judge };

pub const Permitted = struct { provider: []const u8, model: []const u8, uses: []const Use };

// Only the exact user-selected tuples are permitted for their approved uses; every
// other provider/model/use fails closed. This list supplies no default selection.
pub const permitted = [_]Permitted{
    .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0", .uses = &.{ .generation, .judge } },
    // ADR 0029: Claude Haiku 5.5 through the AU geo profile, for generation only. Bedrock
    // offers it in ap-southeast-2 only through a profile, which may route to ap-southeast-4
    // (user decision, 24 October 2026).
    .{ .provider = "aws-bedrock", .model = "au.anthropic.claude-haiku-5-5", .uses = &.{.generation} },
    // ADR 0028: Claude Haiku 5.5 through the Anthropic Messages API, for generation
    // only (user direction, 22 October 2026: "update the providers to connect to claude").
    .{ .provider = "anthropic", .model = "claude-haiku-5-5", .uses = &.{.generation} },
};

pub fn require(use: Use, provider: identity.ProviderId, model: identity.ModelId) Error!void {
    for (permitted) |entry| {
        if (std.mem.eql(u8, provider.bytes, entry.provider) and std.mem.eql(u8, model.bytes, entry.model) and
            std.mem.indexOfScalar(Use, entry.uses, use) != null) return;
    }
    return error.DisallowedTestModel;
}

pub fn requireConfiguredSlots(models: *const config.ModelsConfig) Error!void {
    for (models.slots.map.values()) |slot| {
        try require(.generation, identity.ProviderId.parse(slot.provider) orelse return error.DisallowedTestModel, identity.ModelId.parse(slot.model) orelse return error.DisallowedTestModel);
    }
}

fn isPermitted(use: Use, provider: []const u8, model: []const u8) bool {
    for (permitted) |entry| {
        if (std.mem.eql(u8, provider, entry.provider) and std.mem.eql(u8, model, entry.model) and std.mem.indexOfScalar(Use, entry.uses, use) != null) return true;
    }
    return false;
}

test "live test cost policy accepts each permitted tuple for exactly its approved uses" {
    for (permitted) |entry| for (std.enums.values(Use)) |use| {
        if (std.mem.indexOfScalar(Use, entry.uses, use) != null) {
            try require(use, .{ .bytes = entry.provider }, .{ .bytes = entry.model });
        } else {
            // Approval for one use never extends to another, such as judging.
            try std.testing.expectError(error.DisallowedTestModel, require(use, .{ .bytes = entry.provider }, .{ .bytes = entry.model }));
        }
    };
}

test "live test cost policy rejects altered identities and cross-provider pairings" {
    var buffer: [512]u8 = undefined;
    for (permitted) |entry| for (std.enums.values(Use)) |use| {
        // Aliases, regional prefixes and suffixes of a permitted model are other models.
        inline for (.{ "{s}-unlisted", "us.{s}", "global.{s}" }) |pattern| {
            const model = try std.fmt.bufPrint(&buffer, pattern, .{entry.model});
            if (!isPermitted(use, entry.provider, model)) try std.testing.expectError(error.DisallowedTestModel, require(use, .{ .bytes = entry.provider }, .{ .bytes = model }));
        }
        const provider = try std.fmt.bufPrint(&buffer, "{s}-unlisted", .{entry.provider});
        try std.testing.expectError(error.DisallowedTestModel, require(use, .{ .bytes = provider }, .{ .bytes = entry.model }));
        // A model permitted through one provider is not permitted through another.
        for (permitted) |other| if (!isPermitted(use, other.provider, entry.model)) {
            try std.testing.expectError(error.DisallowedTestModel, require(use, .{ .bytes = other.provider }, .{ .bytes = entry.model }));
        };
    };
}

test "live workflow cost preflight checks every configured model slot for generation" {
    var models: config.ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(std.testing.allocator);
    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |name| std.testing.allocator.free(name);
        names.deinit(std.testing.allocator);
    }
    // One slot per tuple permitted for generation passes together.
    for (permitted, 0..) |entry, index| if (std.mem.indexOfScalar(Use, entry.uses, .generation) != null) {
        const name = try std.fmt.allocPrint(std.testing.allocator, "slot-{d}", .{index});
        try names.append(std.testing.allocator, name);
        try models.slots.map.put(std.testing.allocator, name, .{ .provider = entry.provider, .model = entry.model });
    };
    try std.testing.expect(models.slots.map.count() != 0);
    try requireConfiguredSlots(&models);
    // Any one disallowed slot rejects the whole configuration.
    const first = permitted[0];
    var buffer: [512]u8 = undefined;
    try models.slots.map.put(std.testing.allocator, "unlisted", .{ .provider = first.provider, .model = try std.fmt.bufPrint(&buffer, "{s}-unlisted", .{first.model}) });
    try std.testing.expectError(error.DisallowedTestModel, requireConfiguredSlots(&models));
    _ = models.slots.map.orderedRemove("unlisted");
    try requireConfiguredSlots(&models);
    // A tuple approved only for judging cannot generate.
    for (permitted) |entry| if (std.mem.indexOfScalar(Use, entry.uses, .generation) == null) {
        try models.slots.map.put(std.testing.allocator, "judge-only", .{ .provider = entry.provider, .model = entry.model });
        try std.testing.expectError(error.DisallowedTestModel, requireConfiguredSlots(&models));
        _ = models.slots.map.orderedRemove("judge-only");
    };
}
