const std = @import("std");

pub const WorkflowId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const WorkflowStepId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowStepId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const WorkflowParameterId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowParameterId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const WorkflowResourceId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?WorkflowResourceId {
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

pub const ParameterValue = union(enum) {
    boolean: bool,
    integer: i64,
    string: []const u8,
};

pub const ParameterBinding = struct {
    id: WorkflowParameterId,
    value: ParameterValue,
};

pub const ResourceDeclaration = struct {
    id: WorkflowResourceId,
    name: []const u8,
};

pub const TransitionTarget = union(enum) {
    step: WorkflowStepId,
    terminal: OutcomeTag,
};

pub const OutcomeTransition = struct {
    outcome: OutcomeTag,
    target: TransitionTarget,
};

pub const DeclarativeStep = struct {
    id: WorkflowStepId,
    operation_id: RegisteredRef,
    parameters: []const ParameterBinding,
    outcomes: []const OutcomeTransition,
};

pub const Transition = struct {
    from: WorkflowStepId,
    outcome: OutcomeTag,
    target: TransitionTarget,
};

test "workflow identifiers and operation references are exact" {
    try std.testing.expect(WorkflowId.parse("custom-flow") != null);
    try std.testing.expect(WorkflowStepId.parse("generate") != null);
    try std.testing.expect(WorkflowResourceId.parse("result-schema") != null);
    try std.testing.expect(WorkflowId.parse("Custom") == null);
    try std.testing.expect(RegisteredRef.parse("model.generate@1") != null);
    try std.testing.expect(RegisteredRef.parse("model.generate@01") == null);
}
