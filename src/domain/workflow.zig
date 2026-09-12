const std = @import("std");
pub const max_local_id_bytes = 64;

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

/// One current operation contract. Version suffixes are not aliases.
pub const OperationId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?OperationId {
        return if (bytes.len <= 128 and validRegisteredName(bytes)) .{ .bytes = bytes } else null;
    }
};

pub const RegisteredRef = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?RegisteredRef {
        if (bytes.len < 3 or bytes.len > 128) return null;
        const at = std.mem.lastIndexOfScalar(u8, bytes, '@') orelse return null;
        if (at + 1 == bytes.len or !validRegisteredName(bytes[0..at]) or bytes[at + 1] == '0') return null;
        for (bytes[at + 1 ..]) |byte| if (!std.ascii.isDigit(byte)) return null;
        return .{ .bytes = bytes };
    }
};

fn validRegisteredName(bytes: []const u8) bool {
    if (bytes.len == 0 or !std.ascii.isLower(bytes[0])) return false;
    var separator = false;
    for (bytes) |byte| {
        const current_separator = byte == '.' or byte == '-';
        if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or current_separator) or
            (current_separator and separator)) return false;
        separator = current_separator;
    }
    return !separator;
}

fn validLocalId(bytes: []const u8) bool {
    if (bytes.len == 0 or bytes.len > max_local_id_bytes or bytes[0] < 'a' or bytes[0] > 'z') return false;
    var hyphen = false;
    for (bytes, 0..) |byte, index| {
        if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or byte == '-') or
            (byte == '-' and (index == 0 or hyphen))) return false;
        hyphen = byte == '-';
    }
    return !hyphen;
}

/// `more` is successful bounded progress, never a workflow terminal state.
pub const OutcomeTag = enum { ok, more, needs_user, invalid, blocked, failed, cancelled };

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
    operation_id: OperationId,
    parameters: []const ParameterBinding,
    outcomes: []const OutcomeTransition,
};

pub const Transition = struct {
    from: WorkflowStepId,
    outcome: OutcomeTag,
    target: TransitionTarget,
};

test "workflow identifiers operation IDs and policy references are distinct and exact" {
    try std.testing.expect(WorkflowId.parse("custom-flow") != null);
    try std.testing.expect(WorkflowStepId.parse("generate") != null);
    try std.testing.expect(WorkflowResourceId.parse("result-schema") != null);
    try std.testing.expect(WorkflowId.parse("Custom") == null);
    for ([_][]const u8{ "a", "invoke-model", "core.empty-invocation", "model.generate", "a" ** 128 }) |value| {
        try std.testing.expect(OperationId.parse(value) != null);
        try std.testing.expect(RegisteredRef.parse(value) == null);
    }
    for ([_][]const u8{ "", "InvokeModel", "1model", ".model", "model.", "model-", "model..generate", "model.-generate", "model--generate", "model/generate", "model generate", "model\n", "modél", "a" ** 129, "invoke-model@1", "model.generate@2", "model.generate@01", "model.generate@latest" }) |value| {
        try std.testing.expect(OperationId.parse(value) == null);
    }
    try std.testing.expect(RegisteredRef.parse("core.safe@1") != null);
    try std.testing.expect(RegisteredRef.parse("core.safe@01") == null);
}
