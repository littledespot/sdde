const std = @import("std");

pub const WorkflowId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const WorkflowNodeId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowNodeId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const WorkflowParameterId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowParameterId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const RegisteredRef = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?RegisteredRef {
        if (bytes.len < 3 or bytes.len > 128) return null;
        const at = std.mem.lastIndexOfScalar(u8, bytes, '@') orelse return null;
        if (at == 0 or at + 1 == bytes.len or bytes[0] < 'a' or bytes[0] > 'z' or bytes[at + 1] == '0') return null;
        var separator = false;
        for (bytes[0..at], 0..) |byte, index| {
            const current_separator = byte == '.' or byte == '-';
            if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or current_separator) or
                (current_separator and (index == 0 or separator))) return null;
            separator = current_separator;
        }
        if (separator) return null;
        for (bytes[at + 1 ..]) |byte| if (!std.ascii.isDigit(byte)) return null;
        return .{ .bytes = bytes };
    }
};

fn validLocalId(bytes: []const u8) bool {
    if (bytes.len == 0 or bytes.len > 64 or bytes[0] < 'a' or bytes[0] > 'z') return false;
    var hyphen = false;
    for (bytes, 0..) |byte, index| {
        if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or byte == '-') or
            (byte == '-' and (index == 0 or hyphen))) return false;
        hyphen = byte == '-';
    }
    return !hyphen;
}

pub const OutcomeTag = enum { ok, needs_user, invalid, blocked, failed, cancelled };
pub const ParameterKind = enum { boolean, integer, @"enum", registered_id };
pub const ParameterValue = union(ParameterKind) {
    boolean: bool,
    integer: i64,
    @"enum": WorkflowNodeId,
    registered_id: RegisteredRef,
};
pub const ParameterBinding = struct { id: WorkflowParameterId, value: ParameterValue };
pub const DeclarativeNode = struct {
    id: WorkflowNodeId,
    contract_id: RegisteredRef,
    parameters: []const ParameterBinding,
};
pub const TransitionTarget = union(enum) { node: WorkflowNodeId, terminal: OutcomeTag };
pub const Transition = struct {
    from: WorkflowNodeId,
    outcome: OutcomeTag,
    target: TransitionTarget,
};
test "workflow and registered identifiers are exact" {
    try std.testing.expect(WorkflowId.parse("custom-flow") != null);
    try std.testing.expect(WorkflowId.parse("Custom") == null);
    try std.testing.expect(RegisteredRef.parse("core.noop@1") != null);
    try std.testing.expect(RegisteredRef.parse("core.noop@01") == null);
    try std.testing.expect(RegisteredRef.parse("core.noop@999999999999999999999999999999") != null);
}
