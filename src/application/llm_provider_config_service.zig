const std = @import("std");
const llm_provider_config = @import("../domain/llm_provider_config.zig");

pub const LLMProviderConfigService = struct {
    allocator: std.mem.Allocator,
    raw: llm_provider_config.Raw,

    pub fn init(
        allocator: std.mem.Allocator,
        raw: llm_provider_config.Raw,
    ) LLMProviderConfigService {
        return .{ .allocator = allocator, .raw = raw };
    }

    pub fn bytes(self: *const LLMProviderConfigService) []const u8 {
        return self.raw.bytes;
    }

    pub fn deinit(self: *LLMProviderConfigService) void {
        self.raw.deinit(self.allocator);
        self.* = undefined;
    }
};

test "owns one immutable capture without parsing or rereading" {
    const allocator = std.testing.allocator;
    var service = LLMProviderConfigService.init(allocator, .{
        .bytes = try allocator.dupe(u8, "{\"providers\":[]}"),
    });
    defer service.deinit();
    const first = service.bytes();
    const second = service.bytes();
    try std.testing.expect(first.ptr == second.ptr);
    try std.testing.expectEqualStrings("{\"providers\":[]}", first);
}
