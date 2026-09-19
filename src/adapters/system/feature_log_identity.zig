const std = @import("std");
const binding = @import("../../domain/feature_log_binding.zig");

/// Fresh independent log run identity; never successful workflow authority.
pub const Adapter = struct {
    io: std.Io,

    pub fn create(self: Adapter, allocator: std.mem.Allocator, feature: @import("../../domain/feature_identity.zig").FeatureId, policy: @import("../../domain/log_policy.zig").CompiledLoggingPolicy) !*binding.BindingOwner {
        var nonce: [16]u8 = undefined;
        try self.io.randomSecure(&nonce);
        const serialized = try std.json.Stringify.valueAlloc(allocator, policy, .{});
        defer allocator.free(serialized);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(serialized, &digest, .{});
        var run_buffer: [36]u8 = undefined;
        var policy_buffer: [71]u8 = undefined;
        const run = try std.fmt.bufPrint(&run_buffer, "RUN-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
        const policy_id = try std.fmt.bufPrint(&policy_buffer, "LOGPOL-{s}", .{std.fmt.bytesToHex(digest, .lower)});
        return binding.createValidated(allocator, .{
            .log_policy_id = .{ .bytes = policy_id },
            .binding_id = .{ .bytes = "LOGBIND-1" },
            .run_id = .{ .bytes = run },
            .feature_id = feature,
        });
    }
};
