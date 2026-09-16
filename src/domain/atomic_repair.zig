//! Shared immutable repair authorization and compare-and-swap contract.
//! Domain validators select typed targets/rules; workflow graphs own repetition.
const std = @import("std");
const identity = @import("model_request_identity.zig");
const Origin = @import("model_candidate_origin.zig").Origin;

/// Execution-local merge facts, published only with the resulting candidate.
/// A changed value and a new revision do not establish validation acceptance.
pub const Merge = struct {
    authorization: identity.RepairAuthorizationId,
    owner: identity.ImmutableUnitOwnerId,
    operation: enum { replace, insert, delete },
    revision_before: u64,
    revision_after: u64,
    changed: bool,
    origin: ?Origin,

    pub fn copy(self: Merge, a: std.mem.Allocator) strict.Error!Merge {
        const bytes = try std.json.Stringify.valueAlloc(a, self, .{});
        defer a.free(bytes);
        return strict.decode(Merge, a, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
    }
};
const packets = @import("model_input_packet.zig");
const json = @import("model_candidate_json.zig");
const strict = @import("strict_json.zig");

/// Execution-local dependency binding, never persisted freshness authority.
pub const Snapshot = struct { bytes: [32]u8 };
pub fn snapshot(comptime T: type, a: std.mem.Allocator, value: T) std.mem.Allocator.Error!Snapshot {
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    defer a.free(bytes);
    var result: Snapshot = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &result.bytes, .{});
    return result;
}

pub fn Contract(comptime Target: type, comptime Replacement: type, comptime Dependencies: type, comptime Rule: type) type {
    return struct {
        pub const Error = packets.Error || strict.Error || error{InvalidAtomicRepair};
        pub const Authorization = struct {
            id: identity.RepairAuthorizationId,
            owner: identity.ImmutableUnitOwnerId,
            revision: u64,
            target: Target,
            operation: union(enum) { replace: Replacement, insert: std.meta.Tag(Replacement), delete: Replacement },
            rule: Rule,
            dependencies: Dependencies,
        };

        pub fn authorize(a: std.mem.Allocator, owner: identity.ImmutableUnitOwnerId, revision: u64, target: Target, expected: Replacement, dependencies: Dependencies, rule: Rule) Error!Authorization {
            return authorizeOperation(a, owner, revision, target, .{ .replace = expected }, dependencies, rule);
        }
        pub fn authorizeInsert(a: std.mem.Allocator, owner: identity.ImmutableUnitOwnerId, revision: u64, target: Target, kind: std.meta.Tag(Replacement), dependencies: Dependencies, rule: Rule) Error!Authorization {
            return authorizeOperation(a, owner, revision, target, .{ .insert = kind }, dependencies, rule);
        }
        pub fn authorizeDelete(a: std.mem.Allocator, owner: identity.ImmutableUnitOwnerId, revision: u64, target: Target, expected: Replacement, dependencies: Dependencies, rule: Rule) Error!Authorization {
            return authorizeOperation(a, owner, revision, target, .{ .delete = expected }, dependencies, rule);
        }
        fn authorizeOperation(a: std.mem.Allocator, owner: identity.ImmutableUnitOwnerId, revision: u64, target: Target, operation: @FieldType(Authorization, "operation"), dependencies: Dependencies, rule: Rule) Error!Authorization {
            if (revision == 0) return error.InvalidAtomicRepair;
            try identity.validateUnitOwner(owner);
            const bytes = try std.json.Stringify.valueAlloc(a, .{ owner, revision, target, operation, dependencies, rule }, .{});
            defer a.free(bytes);
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
            // Snapshot borrowed candidate/evidence slices before any later merge.
            const value: Authorization = .{ .id = .{ .bytes = &std.fmt.bytesToHex(digest, .lower) }, .owner = owner, .revision = revision, .target = target, .operation = operation, .dependencies = dependencies, .rule = rule };
            const encoded = try std.json.Stringify.valueAlloc(a, value, .{});
            defer a.free(encoded);
            return strict.decode(Authorization, a, encoded, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
        }

        pub fn checkDependencies(a: std.mem.Allocator, authorization: Authorization, current: Dependencies) Error!void {
            if (!try eql(Dependencies, a, authorization.dependencies, current)) return error.InvalidAtomicRepair;
        }

        pub fn packet(a: std.mem.Allocator, authorization: Authorization, base: *const packets.Packet, definition: @import("model_result_schema.zig").DefinitionId) Error!*packets.Packet {
            if (!identity.unitOwnerEql(authorization.owner, base.unit())) return error.InvalidAtomicRepair;
            var arena: std.heap.ArenaAllocator = .init(a);
            defer arena.deinit();
            const scratch = arena.allocator();
            const limits: strict.Limits = .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth };
            const input = try strict.decode(std.json.Value, scratch, base.body(), limits);
            if (authorization.operation == .delete) return error.InvalidAtomicRepair;
            const facts = .{ .operation = std.meta.activeTag(authorization.operation), .target = if (@hasDecl(Target, "guidance")) authorization.target.guidance() else authorization.target, .rule = if (@hasDecl(Rule, "guidance")) authorization.rule.guidance() else authorization.rule };
            var repair = try strict.decode(std.json.Value, scratch, try json.encode(@TypeOf(facts), scratch, facts), limits);
            // Only optional presentation fields are omitted. Evidence, old values
            // and the native authorization retain their complete contracts.
            omitAbsent(repair.object.getPtr("target").?);
            omitAbsent(repair.object.getPtr("rule").?);
            if (authorization.operation == .replace) {
                const current_value = try strict.decode(std.json.Value, scratch, try json.encodeSelected(Replacement, scratch, authorization.operation.replace), limits);
                try repair.object.put(scratch, "current_value", current_value);
            }
            const body = try std.json.Stringify.valueAlloc(scratch, .{ .input = input, .repair = repair }, .{});
            return packets.create(a, body, base.unit(), .{ .atomic_repair = authorization.id }, definition);
        }

        pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
            return json.decodeSelected(Replacement, a, try checkRequest(authorization, input), bytes);
        }

        /// Retained authorization binds both default and domain-selected decoders.
        pub fn checkRequest(authorization: Authorization, input: *const packets.Packet) Error!std.meta.Tag(Replacement) {
            if (!identity.unitOwnerEql(authorization.owner, input.unit()) or input.purpose() != .atomic_repair or
                !std.mem.eql(u8, authorization.id.bytes, input.purpose().atomic_repair.bytes)) return error.InvalidAtomicRepair;
            return switch (authorization.operation) {
                .replace => |value| std.meta.activeTag(value),
                .insert => |kind| kind,
                .delete => return error.InvalidAtomicRepair,
            };
        }

        /// Exact native old-value equality shared by authorization and merge.
        pub fn equal(a: std.mem.Allocator, left: Replacement, right: Replacement) std.mem.Allocator.Error!bool {
            return eql(Replacement, a, left, right);
        }
        fn changed(a: std.mem.Allocator, authorization: Authorization, replacement: ?Replacement) Error!bool {
            return switch (authorization.operation) {
                .replace => |expected| !try equal(a, expected, replacement orelse return error.InvalidAtomicRepair),
                .insert, .delete => true,
            };
        }
        /// Merged data outlives the released repair request/result owner.
        pub fn copyReplacement(a: std.mem.Allocator, value: Replacement) Error!Replacement {
            const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
            defer a.free(bytes);
            return strict.decode(Replacement, a, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
        }

        fn eql(comptime T: type, a: std.mem.Allocator, left: T, right: T) std.mem.Allocator.Error!bool {
            const l = try std.json.Stringify.valueAlloc(a, left, .{});
            defer a.free(l);
            const r = try std.json.Stringify.valueAlloc(a, right, .{});
            defer a.free(r);
            return std.mem.eql(u8, l, r);
        }

        /// Validate the exact authorized old value before the domain applies the
        /// replacement. Semantic acceptance still requires the original validators.
        pub fn checkMerge(a: std.mem.Allocator, owner: identity.ImmutableUnitOwnerId, revision: u64, current: ?Replacement, dependencies: Dependencies, authorization: Authorization, replacement: ?Replacement, origin: ?Origin) Error!Merge {
            try checkDependencies(a, authorization, dependencies);
            if (!identity.unitOwnerEql(owner, authorization.owner) or revision != authorization.revision) return error.InvalidAtomicRepair;
            switch (authorization.operation) {
                .replace => |expected| {
                    const value = replacement orelse return error.InvalidAtomicRepair;
                    if (std.meta.activeTag(value) != std.meta.activeTag(expected) or !try equal(a, current orelse return error.InvalidAtomicRepair, expected)) return error.InvalidAtomicRepair;
                },
                .insert => |kind| if (current != null or replacement == null or std.meta.activeTag(replacement.?) != kind) return error.InvalidAtomicRepair,
                .delete => |expected| if (replacement != null or !try equal(a, current orelse return error.InvalidAtomicRepair, expected)) return error.InvalidAtomicRepair,
            }
            return (Merge{
                .authorization = authorization.id,
                .owner = owner,
                .operation = switch (authorization.operation) {
                    .replace => .replace,
                    .insert => .insert,
                    .delete => .delete,
                },
                .revision_before = revision,
                .revision_after = std.math.add(u64, revision, 1) catch return error.InvalidAtomicRepair,
                .changed = try changed(a, authorization, replacement),
                .origin = origin,
            }).copy(a);
        }
    };
}

fn omitAbsent(value: *std.json.Value) void {
    if (value.* != .object) return;
    var index: usize = 0;
    while (index < value.object.count()) {
        if (value.object.values()[index] == .null) {
            value.object.orderedRemoveAt(index);
        } else index += 1;
    }
}
