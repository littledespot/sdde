const std = @import("std");

pub const max_provider_id_bytes: usize = 64;
pub const max_model_id_bytes: usize = 512;

pub const ProviderId = struct {
    bytes: []const u8,

    pub fn parse(raw: []const u8) ?ProviderId {
        if (!isLowerKebab(raw)) return null;
        return .{ .bytes = raw };
    }

    pub fn eql(left: ProviderId, right: ProviderId) bool {
        return std.mem.eql(u8, left.bytes, right.bytes);
    }
};

pub const ModelId = struct {
    bytes: []const u8,

    pub fn parse(raw: []const u8) ?ModelId {
        if (raw.len == 0 or raw.len > max_model_id_bytes or
            !std.unicode.utf8ValidateSlice(raw)) return null;
        return .{ .bytes = raw };
    }

    pub fn eql(left: ModelId, right: ModelId) bool {
        return std.mem.eql(u8, left.bytes, right.bytes);
    }
};

fn isLowerKebab(raw: []const u8) bool {
    if (raw.len == 0 or raw.len > max_provider_id_bytes or raw[0] == '-' or
        raw[raw.len - 1] == '-') return false;

    var previous_hyphen = false;
    for (raw) |byte| {
        const hyphen = byte == '-';
        if (!hyphen and !(byte >= 'a' and byte <= 'z') and
            !(byte >= '0' and byte <= '9')) return false;
        if (hyphen and previous_hyphen) return false;
        previous_hyphen = hyphen;
    }
    return true;
}

test "provider and model identities enforce their exact lexical bounds" {
    try std.testing.expect(ProviderId.parse("compiled-provider") != null);
    try std.testing.expect(ProviderId.parse("Compiled") == null);
    try std.testing.expect(ProviderId.parse("compiled--provider") == null);
    try std.testing.expect(ProviderId.parse("-compiled") == null);
    try std.testing.expect(ProviderId.parse("") == null);

    try std.testing.expect(ModelId.parse("model/version:1") != null);
    try std.testing.expect(ModelId.parse("") == null);
    try std.testing.expect(ModelId.parse(&.{0xff}) == null);

    const provider_at_limit = [_]u8{'a'} ** max_provider_id_bytes;
    const provider_over_limit = [_]u8{'a'} ** (max_provider_id_bytes + 1);
    try std.testing.expect(ProviderId.parse(&provider_at_limit) != null);
    try std.testing.expect(ProviderId.parse(&provider_over_limit) == null);
    const model_at_limit = [_]u8{'m'} ** max_model_id_bytes;
    const model_over_limit = [_]u8{'m'} ** (max_model_id_bytes + 1);
    try std.testing.expect(ModelId.parse(&model_at_limit) != null);
    try std.testing.expect(ModelId.parse(&model_over_limit) == null);
}
