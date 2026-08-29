pub const DataKey = enum {
    invocation_working_directory,
    exact_engine_config_file,
    raw_engine_config,
    engine_config,
    configured_root_path_policy_set,
    configured_root_candidate_set,
    configured_root_capability_set,
    bootstrap_root_registry_id,
    bootstrap_root_registry,
    bootstrap_root_registry_evidence,
};

pub const SideEffect = enum {
    none,
    filesystem_read,
};

pub const NodeKind = enum {
    action,
    orchestrator,
};

pub const NodeContract = struct {
    id: []const u8,
    kind: NodeKind,
    requires: []const DataKey,
    produces: []const DataKey,
    replaces: []const DataKey = &.{},
    invalidates: []const DataKey = &.{},
    side_effect: SideEffect,
};

pub const RuntimeStatus = enum {
    active,
    cancelled,
    deadline_exhausted,
};

pub const NodeRuntime = struct {
    context: ?*anyopaque = null,
    status_fn: *const fn (?*anyopaque) RuntimeStatus = alwaysActive,

    pub fn status(self: NodeRuntime) RuntimeStatus {
        return self.status_fn(self.context);
    }
};

pub const NodeDelta = struct {
    data_writes: []const DataKey = &.{},
    data_replacements: []const DataKey = &.{},
    data_invalidations: []const DataKey = &.{},

    pub fn successful(contract: NodeContract) NodeDelta {
        return .{
            .data_writes = contract.produces,
            .data_replacements = contract.replaces,
            .data_invalidations = contract.invalidates,
        };
    }
};

pub const DeltaError = error{
    MissingRequiredData,
    DataAlreadyPresent,
    ReplacementTargetMissing,
    InvalidationTargetMissing,
    UndeclaredWrite,
    MissingDeclaredWrite,
    DuplicateWrite,
    UndeclaredReplacement,
    MissingDeclaredReplacement,
    DuplicateReplacement,
    UndeclaredInvalidation,
    MissingDeclaredInvalidation,
    DuplicateInvalidation,
};

pub const PipelineEnvelope = struct {
    available: [data_key_count]bool,

    pub fn init(initial: []const DataKey) PipelineEnvelope {
        return .{ .available = keySetRuntime(initial) };
    }

    pub fn contains(self: PipelineEnvelope, key: DataKey) bool {
        return self.available[@intFromEnum(key)];
    }

    pub fn validateInvocation(
        self: PipelineEnvelope,
        contract: NodeContract,
    ) DeltaError!void {
        for (contract.requires) |required| {
            if (!self.contains(required)) return error.MissingRequiredData;
        }
    }

    pub fn apply(
        self: PipelineEnvelope,
        contract: NodeContract,
        delta: NodeDelta,
    ) DeltaError!PipelineEnvelope {
        try self.validateInvocation(contract);
        try validateExactKeys(
            contract.produces,
            delta.data_writes,
            error.UndeclaredWrite,
            error.MissingDeclaredWrite,
            error.DuplicateWrite,
        );
        try validateExactKeys(
            contract.replaces,
            delta.data_replacements,
            error.UndeclaredReplacement,
            error.MissingDeclaredReplacement,
            error.DuplicateReplacement,
        );
        try validateExactKeys(
            contract.invalidates,
            delta.data_invalidations,
            error.UndeclaredInvalidation,
            error.MissingDeclaredInvalidation,
            error.DuplicateInvalidation,
        );

        for (delta.data_writes) |key| {
            if (self.contains(key)) return error.DataAlreadyPresent;
        }
        for (delta.data_replacements) |key| {
            if (!self.contains(key)) return error.ReplacementTargetMissing;
        }
        for (delta.data_invalidations) |key| {
            if (!self.contains(key)) return error.InvalidationTargetMissing;
        }

        var next = self;
        for (delta.data_writes) |key| next.available[@intFromEnum(key)] = true;
        for (delta.data_replacements) |key| next.available[@intFromEnum(key)] = true;
        for (delta.data_invalidations) |key| next.available[@intFromEnum(key)] = false;
        return next;
    }
};

pub fn validateLinear(
    comptime initial: []const DataKey,
    comptime contracts: []const NodeContract,
) void {
    comptime var available = keySet(initial);

    inline for (contracts) |contract| {
        if (contract.kind != .action) {
            @compileError("linear child contract must describe an action");
        }
        inline for (contract.requires) |required| {
            if (!available[@intFromEnum(required)]) {
                @compileError("pipeline action requires an unavailable data key");
            }
        }
        inline for (contract.produces) |produced| {
            if (available[@intFromEnum(produced)]) {
                @compileError("pipeline action duplicates an existing data key");
            }
            available[@intFromEnum(produced)] = true;
        }
        inline for (contract.replaces) |replaced| {
            if (!available[@intFromEnum(replaced)]) {
                @compileError("pipeline action replaces an unavailable data key");
            }
        }
        inline for (contract.invalidates) |invalidated| {
            if (!available[@intFromEnum(invalidated)]) {
                @compileError("pipeline action invalidates an unavailable data key");
            }
            available[@intFromEnum(invalidated)] = false;
        }
    }
}

fn keySet(comptime keys: []const DataKey) [@typeInfo(DataKey).@"enum".fields.len]bool {
    var result = [_]bool{false} ** @typeInfo(DataKey).@"enum".fields.len;
    inline for (keys) |key| result[@intFromEnum(key)] = true;
    return result;
}

const data_key_count = @typeInfo(DataKey).@"enum".fields.len;

fn keySetRuntime(keys: []const DataKey) [data_key_count]bool {
    var result = [_]bool{false} ** data_key_count;
    for (keys) |key| result[@intFromEnum(key)] = true;
    return result;
}

fn validateExactKeys(
    declared: []const DataKey,
    actual: []const DataKey,
    undeclared_error: DeltaError,
    missing_error: DeltaError,
    duplicate_error: DeltaError,
) DeltaError!void {
    var seen = [_]bool{false} ** data_key_count;
    for (actual) |key| {
        const index = @intFromEnum(key);
        if (seen[index]) return duplicate_error;
        seen[index] = true;
        if (!containsKey(declared, key)) return undeclared_error;
    }
    for (declared) |key| {
        if (!seen[@intFromEnum(key)]) return missing_error;
    }
}

fn containsKey(keys: []const DataKey, expected: DataKey) bool {
    for (keys) |key| if (key == expected) return true;
    return false;
}

fn alwaysActive(_: ?*anyopaque) RuntimeStatus {
    return .active;
}

test "runner envelope applies only the exact declared delta" {
    const contract: NodeContract = .{
        .id = "test@1",
        .kind = .action,
        .requires = &.{.engine_config},
        .produces = &.{.configured_root_path_policy_set},
        .side_effect = .none,
    };
    const initial = PipelineEnvelope.init(&.{.engine_config});
    const next = try initial.apply(contract, NodeDelta.successful(contract));
    try std.testing.expect(next.contains(.configured_root_path_policy_set));
    try std.testing.expect(!initial.contains(.configured_root_path_policy_set));
}

test "runner envelope rejects missing undeclared and duplicate writes" {
    const contract: NodeContract = .{
        .id = "test@1",
        .kind = .action,
        .requires = &.{.engine_config},
        .produces = &.{.configured_root_path_policy_set},
        .side_effect = .none,
    };
    const envelope = PipelineEnvelope.init(&.{.engine_config});
    try std.testing.expectError(
        error.MissingDeclaredWrite,
        envelope.apply(contract, .{}),
    );
    try std.testing.expectError(
        error.UndeclaredWrite,
        envelope.apply(contract, .{ .data_writes = &.{.raw_engine_config} }),
    );
    try std.testing.expectError(
        error.DuplicateWrite,
        envelope.apply(contract, .{
            .data_writes = &.{
                .configured_root_path_policy_set,
                .configured_root_path_policy_set,
            },
        }),
    );
    const applied = try envelope.apply(contract, NodeDelta.successful(contract));
    try std.testing.expectError(
        error.DataAlreadyPresent,
        applied.apply(contract, NodeDelta.successful(contract)),
    );
}
const std = @import("std");
