//! Shared immutable replacement authorization and compare-and-swap contract.
//! Domain validators select typed targets/rules; workflow graphs own repetition.
const std = @import("std");
const identity = @import("model_request_identity.zig");
const packets = @import("model_input_packet.zig");
const json = @import("model_candidate_json.zig");
const strict = @import("strict_json.zig");

pub fn Contract(comptime Target: type, comptime Replacement: type, comptime Rule: type) type {
    return struct {
        pub const Error = packets.Error || strict.Error || error{InvalidAtomicRepair};
        pub const Authorization = struct {
            id: identity.RepairAuthorizationId,
            owner: identity.ImmutableUnitOwnerId,
            revision: u64,
            target: Target,
            expected: Replacement,
            rule: Rule,
        };

        pub fn authorize(a: std.mem.Allocator, owner: identity.ImmutableUnitOwnerId, revision: u64, target: Target, expected: Replacement, rule: Rule) Error!Authorization {
            if (revision == 0) return error.InvalidAtomicRepair;
            try identity.validateUnitOwner(owner);
            const bytes = try std.json.Stringify.valueAlloc(a, .{ owner, revision, target, expected, rule }, .{});
            defer a.free(bytes);
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
            return .{ .id = .{ .bytes = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)) }, .owner = owner, .revision = revision, .target = target, .expected = expected, .rule = rule };
        }

        pub fn packet(a: std.mem.Allocator, authorization: Authorization, base: *const packets.Packet, definition: @import("model_result_schema.zig").DefinitionId) Error!*packets.Packet {
            if (!identity.unitOwnerEql(authorization.owner, base.unit())) return error.InvalidAtomicRepair;
            var arena: std.heap.ArenaAllocator = .init(a);
            defer arena.deinit();
            const scratch = arena.allocator();
            const limits: strict.Limits = .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth };
            const input = try strict.decode(std.json.Value, scratch, base.body(), limits);
            const expected = try strict.decode(std.json.Value, scratch, try json.encodeSelected(Replacement, scratch, authorization.expected), limits);
            const facts = .{ .target = authorization.target, .rule = authorization.rule };
            var repair = try strict.decode(std.json.Value, scratch, try json.encode(@TypeOf(facts), scratch, facts), limits);
            try repair.object.put(scratch, "expected", expected);
            const body = try std.json.Stringify.valueAlloc(scratch, .{ .input = input, .repair = repair }, .{});
            return packets.create(a, body, base.unit(), .{ .atomic_repair = authorization.id }, definition);
        }

        pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
            if (!identity.unitOwnerEql(authorization.owner, input.unit()) or input.purpose() != .atomic_repair or
                !std.mem.eql(u8, authorization.id.bytes, input.purpose().atomic_repair.bytes)) return error.InvalidAtomicRepair;
            return json.decodeSelected(Replacement, a, std.meta.activeTag(authorization.expected), bytes);
        }

        /// Validate the exact authorized old value before the domain applies the
        /// replacement. Semantic acceptance still requires the original validators.
        pub fn checkMerge(a: std.mem.Allocator, owner: identity.ImmutableUnitOwnerId, revision: u64, current: Replacement, authorization: Authorization, replacement: Replacement) Error!u64 {
            if (!identity.unitOwnerEql(owner, authorization.owner) or revision != authorization.revision or
                std.meta.activeTag(replacement) != std.meta.activeTag(authorization.expected)) return error.InvalidAtomicRepair;
            const old = try std.json.Stringify.valueAlloc(a, current, .{});
            defer a.free(old);
            const expected = try std.json.Stringify.valueAlloc(a, authorization.expected, .{});
            defer a.free(expected);
            if (!std.mem.eql(u8, old, expected)) return error.InvalidAtomicRepair;
            return std.math.add(u64, revision, 1) catch error.InvalidAtomicRepair;
        }
    };
}
