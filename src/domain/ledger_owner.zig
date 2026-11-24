//! The chain of immutable owners behind a ledger (ADR 0012). Each owner holds one arena, one reference count, the
//! previous owner it keeps alive, and the ledger state it presents. A successor retains its predecessor; releasing
//! the last reference to an owner releases the predecessor in turn, and the first owner of a chain gives back what it
//! took when it was created.
const std = @import("std");

/// `Owner` is the opaque handle the ledger module exports. `Payload` is the ledger state one owner presents and
/// declares `releaseRoot`, which gives back what the chain's first owner took. `reference_exhausted` is the one error
/// the ledger module reports when a reference count cannot grow, so each ledger keeps its own error identity.
pub fn LedgerOwner(comptime Owner: type, comptime Payload: type, comptime reference_exhausted: anytype) type {
    const ReferenceExhausted = @TypeOf(reference_exhausted);
    return struct {
        pub const Storage = struct {
            backing_allocator: std.mem.Allocator,
            reference_count: usize,
            previous_owner: ?*Owner,
            arena: std.heap.ArenaAllocator,
            payload: Payload,
        };

        /// An owner whose storage and arena exist and whose state is not set. The caller aborts it on every path
        /// that does not seal it, and seals it only as the last fallible step.
        pub const Pending = struct {
            storage: *Storage,

            pub fn owner(self: Pending) *Owner {
                return @ptrCast(self.storage);
            }

            pub fn arena(self: Pending) std.mem.Allocator {
                return self.storage.arena.allocator();
            }

            /// Frees the arena, then the storage.
            pub fn abort(self: Pending) void {
                const allocator = self.storage.backing_allocator;
                self.storage.arena.deinit();
                allocator.destroy(self.storage);
            }

            pub fn sealInitial(self: Pending, state: Payload) *Owner {
                self.storage.payload = state;
                return self.owner();
            }

            /// Retains the predecessor, the one step that can fail, and only then links to it.
            pub fn sealSuccessor(self: Pending, previous: *Owner, state: Payload) ReferenceExhausted!*Owner {
                try retain(previous);
                self.storage.previous_owner = previous;
                self.storage.payload = state;
                return self.owner();
            }
        };

        pub fn beginInitial(allocator: std.mem.Allocator) std.mem.Allocator.Error!Pending {
            return begin(allocator);
        }

        /// The successor's storage comes from the allocator that made its predecessor.
        pub fn beginSuccessor(previous: *Owner) std.mem.Allocator.Error!Pending {
            return begin(storageOf(previous).backing_allocator);
        }

        fn begin(allocator: std.mem.Allocator) std.mem.Allocator.Error!Pending {
            const value = try allocator.create(Storage);
            value.* = .{
                .backing_allocator = allocator,
                .reference_count = 1,
                .previous_owner = null,
                .arena = .init(allocator),
                .payload = undefined,
            };
            return .{ .storage = value };
        }

        pub fn retain(owner: *Owner) ReferenceExhausted!void {
            const value = storageOf(owner);
            std.debug.assert(value.reference_count > 0);
            value.reference_count = std.math.add(usize, value.reference_count, 1) catch return reference_exhausted;
        }

        pub fn release(owner: *Owner) void {
            var next: ?*Owner = owner;
            while (next) |current| {
                const value = storageOf(current);
                std.debug.assert(value.reference_count > 0);
                value.reference_count -= 1;
                if (value.reference_count != 0) return;
                const previous = value.previous_owner;
                if (previous == null) Payload.releaseRoot(&value.payload);
                const allocator = value.backing_allocator;
                value.arena.deinit();
                allocator.destroy(value);
                next = previous;
            }
        }

        pub fn read(owner: *const Owner) *const Payload {
            return &storageConstOf(owner).payload;
        }

        pub fn previousOwner(owner: *const Owner) ?*Owner {
            return storageConstOf(owner).previous_owner;
        }

        fn storageOf(owner: *Owner) *Storage {
            return @ptrCast(@alignCast(owner));
        }

        fn storageConstOf(owner: *const Owner) *const Storage {
            return @ptrCast(@alignCast(owner));
        }
    };
}

const TestOwner = opaque {};
const OtherOwner = opaque {};

fn TestPayload(comptime O: type) type {
    return struct {
        owner: *O,
        root_releases: *usize,

        pub fn releaseRoot(self: *@This()) void {
            self.root_releases.* += 1;
        }
    };
}

const Chain = LedgerOwner(TestOwner, TestPayload(TestOwner), error.TestOwnerReferenceExhausted);
const OtherChain = LedgerOwner(OtherOwner, TestPayload(OtherOwner), error.OtherOwnerReferenceExhausted);

fn initialOwner(allocator: std.mem.Allocator, root_releases: *usize) std.mem.Allocator.Error!*TestOwner {
    const pending = try Chain.beginInitial(allocator);
    return pending.sealInitial(.{ .owner = pending.owner(), .root_releases = root_releases });
}

fn successorOwner(previous: *TestOwner, root_releases: *usize) !*TestOwner {
    const pending = try Chain.beginSuccessor(previous);
    errdefer pending.abort();
    _ = try pending.arena().create(u64);
    return pending.sealSuccessor(previous, .{ .owner = pending.owner(), .root_releases = root_releases });
}

test "a chain of owners frees every owner once and gives back the root once" {
    var root_releases: usize = 0;
    const initial = try initialOwner(std.testing.allocator, &root_releases);
    const first = try successorOwner(initial, &root_releases);
    const second = try successorOwner(first, &root_releases);
    try std.testing.expect(Chain.previousOwner(second) == first);
    try std.testing.expect(Chain.previousOwner(first) == initial);
    try std.testing.expect(Chain.previousOwner(initial) == null);
    try std.testing.expect(Chain.read(second).owner == second);
    // Each owner is kept alive by its holder and by its successor.
    Chain.release(initial);
    Chain.release(first);
    try std.testing.expectEqual(@as(usize, 0), root_releases);
    Chain.release(second);
    try std.testing.expectEqual(@as(usize, 1), root_releases);
}

test "a reference count that cannot grow is refused with the chain's own error and leaks nothing" {
    var root_releases: usize = 0;
    const initial = try initialOwner(std.testing.allocator, &root_releases);
    Chain.storageOf(initial).reference_count = std.math.maxInt(usize);
    try std.testing.expectError(error.TestOwnerReferenceExhausted, Chain.retain(initial));
    const pending = try Chain.beginSuccessor(initial);
    try std.testing.expectError(error.TestOwnerReferenceExhausted, pending.sealSuccessor(initial, .{ .owner = pending.owner(), .root_releases = &root_releases }));
    pending.abort();
    try std.testing.expectEqual(@as(usize, std.math.maxInt(usize)), Chain.storageOf(initial).reference_count);
    Chain.storageOf(initial).reference_count = 1;
    Chain.release(initial);
    try std.testing.expectEqual(@as(usize, 1), root_releases);
}

test "each instantiation reports its own error" {
    try std.testing.expect(Chain != OtherChain);
    var root_releases: usize = 0;
    const pending = try OtherChain.beginInitial(std.testing.allocator);
    const initial = pending.sealInitial(.{ .owner = pending.owner(), .root_releases = &root_releases });
    OtherChain.storageOf(initial).reference_count = std.math.maxInt(usize);
    try std.testing.expectError(error.OtherOwnerReferenceExhausted, OtherChain.retain(initial));
    OtherChain.storageOf(initial).reference_count = 1;
    OtherChain.release(initial);
    try std.testing.expectEqual(@as(usize, 1), root_releases);
}

fn everyAllocationFails(allocator: std.mem.Allocator) !void {
    var root_releases: usize = 0;
    const initial = try initialOwner(allocator, &root_releases);
    defer Chain.release(initial);
    const next = try successorOwner(initial, &root_releases);
    Chain.release(next);
}

test "an owner built over a failing allocator leaves nothing behind on any path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, everyAllocationFails, .{});
}
