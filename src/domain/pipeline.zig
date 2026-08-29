pub const DataKey = enum {
    invocation_working_directory,
    exact_engine_config,
    raw_engine_config,
    engine_config,
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
