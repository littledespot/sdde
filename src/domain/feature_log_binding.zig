const std = @import("std");
const telemetry = @import("telemetry.zig");

pub const BindingCandidate = struct {
    log_policy_id: telemetry.Identifier,
    binding_id: telemetry.Identifier,
    run_id: telemetry.Identifier,
    feature_id: telemetry.Identifier,
};

pub const ValidatedFeatureLogBinding = opaque {
    pub fn logPolicyId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).log_policy_id;
    }
    pub fn bindingId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).binding_id;
    }
    pub fn runId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).run_id;
    }
    pub fn featureId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).feature_id;
    }
};

pub const BindingOwner = opaque {};
const BindingStorage = BindingCandidate;
const BindingOwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    binding: BindingStorage,
};

pub const Error = error{InvalidFeatureLogBinding};

pub fn createValidated(
    allocator: std.mem.Allocator,
    candidate: BindingCandidate,
) Error!*BindingOwner {
    if (!validPathIdentifier(candidate.log_policy_id) or !validPathIdentifier(candidate.binding_id) or
        !validPathIdentifier(candidate.run_id) or !validPathIdentifier(candidate.feature_id))
    {
        return error.InvalidFeatureLogBinding;
    }
    const owner = allocator.create(BindingOwnerStorage) catch return error.InvalidFeatureLogBinding;
    errdefer allocator.destroy(owner);
    owner.* = .{ .backing_allocator = allocator, .arena = .init(allocator), .binding = undefined };
    errdefer owner.arena.deinit();
    const arena = owner.arena.allocator();
    owner.binding = .{
        .log_policy_id = .{ .bytes = arena.dupe(u8, candidate.log_policy_id.bytes) catch return error.InvalidFeatureLogBinding },
        .binding_id = .{ .bytes = arena.dupe(u8, candidate.binding_id.bytes) catch return error.InvalidFeatureLogBinding },
        .run_id = .{ .bytes = arena.dupe(u8, candidate.run_id.bytes) catch return error.InvalidFeatureLogBinding },
        .feature_id = .{ .bytes = arena.dupe(u8, candidate.feature_id.bytes) catch return error.InvalidFeatureLogBinding },
    };
    return @ptrCast(owner);
}

pub fn binding(owner: *const BindingOwner) *const ValidatedFeatureLogBinding {
    return @ptrCast(&bindingOwnerStorageConst(owner).binding);
}

pub fn deinitOwner(owner: *BindingOwner) void {
    const storage = bindingOwnerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

pub fn sameBinding(value: *const ValidatedFeatureLogBinding, candidate: BindingCandidate) bool {
    return std.mem.eql(u8, value.logPolicyId().bytes, candidate.log_policy_id.bytes) and
        std.mem.eql(u8, value.bindingId().bytes, candidate.binding_id.bytes) and
        std.mem.eql(u8, value.runId().bytes, candidate.run_id.bytes) and
        std.mem.eql(u8, value.featureId().bytes, candidate.feature_id.bytes);
}

fn validPathIdentifier(value: telemetry.Identifier) bool {
    return value.bytes.len != 0 and !std.mem.eql(u8, value.bytes, ".") and
        !std.mem.eql(u8, value.bytes, "..");
}

fn bindingStorage(value: *const ValidatedFeatureLogBinding) *const BindingStorage {
    return @ptrCast(@alignCast(value));
}
fn bindingOwnerStorage(owner: *BindingOwner) *BindingOwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn bindingOwnerStorageConst(owner: *const BindingOwner) *const BindingOwnerStorage {
    return @ptrCast(@alignCast(owner));
}

test "validated feature log binding owns one immutable identity tuple" {
    const candidate: BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = telemetry.Identifier.validate("F0002").?,
    };
    const owner = try createValidated(std.testing.allocator, candidate);
    defer deinitOwner(owner);
    try std.testing.expect(sameBinding(binding(owner), candidate));
}
