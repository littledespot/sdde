const std = @import("std");
const reference = @import("reference_selector.zig");
const path_policy = @import("configured_path_policy.zig");

pub const maximum_id_bytes = 255;
pub const maximum_folded_bytes = reference.max_bytes * 4;
pub const Error = std.mem.Allocator.Error || error{ InvalidFeatureNamingPolicy, InvalidFeatureId };

pub const NamingPolicy = struct {
    version: enum { unicode17_ascii_v1 },
    maximum_length: u8,

    pub fn init(maximum: i64) ?NamingPolicy {
        if (maximum < 1 or maximum > maximum_id_bytes) return null;
        return .{ .version = .unicode17_ascii_v1, .maximum_length = @intCast(maximum) };
    }
};

pub const FeatureId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?FeatureId {
        path_policy.validateComponent(maximum_id_bytes, bytes, .ascii) catch return null;
        if (bytes[0] == '-' or bytes[bytes.len - 1] == '-') return null;
        var hyphen = false;
        for (bytes) |byte| {
            if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '-') return null;
            if (byte == '-' and hyphen) return null;
            hyphen = byte == '-';
        }
        return .{ .bytes = bytes };
    }
};

/// Prospective name and its exact source/policy, not ownership or availability.
/// The selector is borrowed; the derived ID is caller-owned until publication.
pub const FeatureIdentitySeed = struct {
    reference_selector: reference.RelativeSelector,
    naming_policy: NamingPolicy,
    feature_id: FeatureId,
};

pub fn fromFolded(allocator: std.mem.Allocator, folded: []const u8, policy: NamingPolicy) Error!FeatureId {
    if (policy.maximum_length == 0) return error.InvalidFeatureNamingPolicy;
    if (folded.len > maximum_folded_bytes or !std.unicode.utf8ValidateSlice(folded)) return error.InvalidFeatureId;
    var buffer: [maximum_id_bytes]u8 = undefined;
    var length: usize = 0;
    var separator = false;
    for (folded) |byte| {
        if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte)) {
            separator = length > 0;
            continue;
        }
        // Truncation may not leave a trailing hyphen.
        if (length + @intFromBool(separator) >= policy.maximum_length) break;
        if (separator) {
            buffer[length] = '-';
            length += 1;
        }
        buffer[length] = byte;
        length += 1;
        separator = false;
    }
    const id = FeatureId.parse(buffer[0..length]) orelse return error.InvalidFeatureId;
    return .{ .bytes = try allocator.dupe(u8, id.bytes) };
}
