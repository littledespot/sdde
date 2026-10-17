//! User-approved live-test cost policy. Production model selection is separate.
const std = @import("std");
const identity = @import("../../src/domain/llm_provider_identity.zig");
const config = @import("../../src/domain/config.zig");

pub const Error = error{DisallowedTestModel};

// Only the exact user-selected small-model tuple is permitted; every other
// provider/model pair fails closed. This list supplies no default selection.
pub fn require(provider: identity.ProviderId, model: identity.ModelId) Error!void {
    const allowed = [_]struct { provider: []const u8, model: []const u8 }{
        .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" },
    };
    for (allowed) |entry| if (std.mem.eql(u8, provider.bytes, entry.provider) and std.mem.eql(u8, model.bytes, entry.model)) return;
    return error.DisallowedTestModel;
}

pub fn requireConfiguredSlots(models: *const config.ModelsConfig) Error!void {
    for (models.slots.map.values()) |slot| {
        try require(identity.ProviderId.parse(slot.provider) orelse return error.DisallowedTestModel, identity.ModelId.parse(slot.model) orelse return error.DisallowedTestModel);
    }
}

test "live test cost policy permits only the explicit Bedrock GPT-OSS-20B tuple" {
    try require(.{ .bytes = "aws-bedrock" }, .{ .bytes = "openai.gpt-oss-20b-1:0" });
    for ([_]struct { provider: []const u8, model: []const u8 }{
        .{ .provider = "aws-bedrock", .model = "au.anthropic.claude-sonnet-5-5" },
        .{ .provider = "aws-bedrock", .model = "global.anthropic.claude-sonnet-5-5" },
        .{ .provider = "openai", .model = "gpt-6-sol" },
        .{ .provider = "openai", .model = "gpt-6.1-sol" },
        .{ .provider = "aws-bedrock", .model = "au.anthropic.claude-haiku-5-5" },
        .{ .provider = "openai", .model = "gpt-6-luna" },
        .{ .provider = "openai", .model = "global.openai.gpt-6-luna" },
        .{ .provider = "aws-bedrock", .model = "openai.gpt-6-luna" },
        .{ .provider = "aws-bedrock", .model = "us.openai.gpt-6-luna" },
        .{ .provider = "aws-bedrock", .model = "global.openai.gpt-6-luna" },
        .{ .provider = "openai", .model = "openai.gpt-oss-20b-1:0" },
        .{ .provider = "aws-bedrock", .model = "gpt-oss-20b" },
        .{ .provider = "aws-bedrock", .model = "global.openai.gpt-oss-20b-1:0" },
        .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-120b-1:0" },
        .{ .provider = "aws-bedrock", .model = "anthropic.claude-3-5-haiku-20241022-v1:0" },
        .{ .provider = "openai", .model = "gpt-6-luna-unknown-alias" },
        .{ .provider = "aws-bedrock", .model = "gpt-6-luna" },
        .{ .provider = "unknown", .model = "openai.gpt-oss-20b-1:0" },
    }) |entry| try std.testing.expectError(error.DisallowedTestModel, require(.{ .bytes = entry.provider }, .{ .bytes = entry.model }));
}

test "live workflow cost preflight checks every configured model slot" {
    var models: config.ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(std.testing.allocator);
    try models.slots.map.put(std.testing.allocator, "generation", .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0" });
    try requireConfiguredSlots(&models);
    try models.slots.map.put(std.testing.allocator, "repair", .{ .provider = "openai", .model = "gpt-6-sol" });
    try std.testing.expectError(error.DisallowedTestModel, requireConfiguredSlots(&models));
    models.slots.map.getPtr("repair").?.model = "openai.gpt-oss-20b-1:0";
    try std.testing.expectError(error.DisallowedTestModel, requireConfiguredSlots(&models));
    models.slots.map.getPtr("repair").?.provider = "aws-bedrock";
    try requireConfiguredSlots(&models);
}
