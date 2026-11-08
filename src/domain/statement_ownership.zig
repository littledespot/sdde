//! ADR 0038 Decision 5: which statement records of a records batch their owner deletes
//! natively. One rule for every layer that needs it: response admission (the payload
//! coverage check and the text composition check, over the wire), unit validation and the
//! session (over typed records). A layer describes its batch and asks; the rule reads
//! claim and exact-value ordinals, never wording.
const std = @import("std");

/// A record kind's part in the rule. An owning record (a requirement) takes its claims
/// for every statement and is never deleted. An exclusive record (a rule, outcome,
/// assumption, non-goal or prohibition) takes its claims for later exclusive records and
/// is deleted when every claim it names is taken. Any other record plays no part.
pub const Role = enum { owning, exclusive, other };

/// One record as the rule sees it: the claims it names and the exact values it holds,
/// both by ordinal.
pub const Record = struct { role: Role, claims: []const i64, exact: []const i64 };

/// What a claim list entry that is no claim reads as: no claim ordinal is negative.
pub const no_claim: i64 = std.math.minInt(i64);

/// The exact value of a record whose text holds a value that can't be identified, such as
/// an ambiguous or unrecognizable one, text that is not a valid scalar, or an explicit
/// insertion. No other record holds it, so the record is never deleted, and the rule counts
/// it as holding no value for any other record.
pub fn unidentified(index: usize) i64 {
    // An index is far below the i64 range, so the sum stays negative and clear of `no_claim`.
    return no_claim + 1 + @as(i64, @intCast(index));
}

/// A batch held as data.
pub const Prepared = struct {
    records: []const Record,

    pub fn len(self: Prepared) usize {
        return self.records.len;
    }
    pub fn role(self: Prepared, index: usize) Role {
        return self.records[index].role;
    }
    pub fn claimCount(self: Prepared, index: usize) usize {
        return self.records[index].claims.len;
    }
    pub fn claim(self: Prepared, index: usize, position: usize) i64 {
        return self.records[index].claims[position];
    }
    pub fn exactCount(self: Prepared, index: usize) usize {
        return self.records[index].exact.len;
    }
    pub fn exact(self: Prepared, index: usize, position: usize) i64 {
        return self.records[index].exact[position];
    }
};

/// The rule over a batch type that provides `len`, `role`, `claimCount`, `claim`,
/// `exactCount` and `exact`. `removed` marks records already deleted; an index past its
/// end is present, so an empty slice means none was removed.
pub fn Rule(comptime Batch: type) type {
    comptime {
        for ([_][]const u8{ "len", "role", "claimCount", "claim", "exactCount", "exact" }) |name| {
            if (!@hasDecl(Batch, name)) @compileError("a statement batch provides " ++ name);
        }
    }
    return struct {
        fn present(removed: []const bool, index: usize) bool {
            return index >= removed.len or !removed[index];
        }

        fn names(batch: Batch, index: usize, wanted: i64) bool {
            for (0..batch.claimCount(index)) |position| if (batch.claim(index, position) == wanted) return true;
            return false;
        }

        fn holds(batch: Batch, index: usize, wanted: i64) bool {
            for (0..batch.exactCount(index)) |position| if (batch.exact(index, position) == wanted) return true;
            return false;
        }

        /// Whether the record at `index` carries its own `unidentified` value.
        fn marked(batch: Batch, index: usize) bool {
            return holds(batch, index, unidentified(index));
        }

        /// Whether `wanted` is taken for the exclusive record at `index`: a present owning
        /// record names it, or a present exclusive record before `index` does. A list entry
        /// that is no claim is never taken.
        pub fn taken(batch: Batch, removed: []const bool, index: usize, wanted: i64) bool {
            if (wanted == no_claim) return false;
            for (0..batch.len()) |position| {
                if (!present(removed, position) or !names(batch, position, wanted)) continue;
                switch (batch.role(position)) {
                    .owning => return true,
                    .exclusive => if (position < index) return true,
                    .other => {},
                }
            }
            return false;
        }

        /// Whether the record at `index` is exclusive, names claims, and has every one taken.
        pub fn whollyTaken(batch: Batch, removed: []const bool, index: usize) bool {
            if (batch.role(index) != .exclusive or batch.claimCount(index) == 0) return false;
            for (0..batch.claimCount(index)) |position| {
                if (!taken(batch, removed, index, batch.claim(index, position))) return false;
            }
            return true;
        }

        /// Whether another present record holds every exact value the record at `index`
        /// holds, so deleting it loses no exact value. A record that can't identify one of its
        /// values holds none for this purpose.
        pub fn exactHeldElsewhere(batch: Batch, removed: []const bool, index: usize) bool {
            for (0..batch.exactCount(index)) |position| {
                const wanted = batch.exact(index, position);
                for (0..batch.len()) |other| {
                    if (other != index and present(removed, other) and !marked(batch, other) and holds(batch, other, wanted)) break;
                } else return false;
            }
            return true;
        }

        /// The first present record the owner deletes: wholly taken, and no exact value
        /// is lost. Each delete is decided on the batch it leaves.
        pub fn first(batch: Batch, removed: []const bool) ?usize {
            for (0..batch.len()) |index| {
                if (present(removed, index) and whollyTaken(batch, removed, index) and exactHeldElsewhere(batch, removed, index)) return index;
            }
            return null;
        }

        /// Marks in `removed`, all false on entry and as long as the batch, every record
        /// the owner deletes in turn.
        pub fn sequence(batch: Batch, removed: []bool) void {
            std.debug.assert(removed.len == batch.len());
            while (first(batch, removed)) |index| removed[index] = true;
        }
    };
}

const Fixture = struct {
    fn requirement(claims: []const i64, exact: []const i64) Record {
        return .{ .role = .owning, .claims = claims, .exact = exact };
    }
    fn statement(claims: []const i64, exact: []const i64) Record {
        return .{ .role = .exclusive, .claims = claims, .exact = exact };
    }
    fn scenario(claims: []const i64) Record {
        return .{ .role = .other, .claims = claims, .exact = &.{} };
    }
    fn deleted(records: []const Record, buffer: []bool) []const bool {
        const removed = buffer[0..records.len];
        @memset(removed, false);
        Rule(Prepared).sequence(.{ .records = records }, removed);
        return removed;
    }
};

test "a statement whose every claim a requirement names is deleted, before or after it" {
    var buffer: [4]bool = undefined;
    const requirement_first = [_]Record{ Fixture.requirement(&.{3}, &.{}), Fixture.statement(&.{3}, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ false, true }, Fixture.deleted(&requirement_first, &buffer));
    const requirement_last = [_]Record{ Fixture.statement(&.{3}, &.{}), Fixture.requirement(&.{3}, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ true, false }, Fixture.deleted(&requirement_last, &buffer));
}

test "an earlier exclusive record takes its claims for a later one, never the reverse" {
    var buffer: [4]bool = undefined;
    const records = [_]Record{ Fixture.statement(&.{ 3, 4 }, &.{}), Fixture.statement(&.{3}, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ false, true }, Fixture.deleted(&records, &buffer));
}

test "a statement naming any untaken claim is kept, as is one naming none" {
    var buffer: [4]bool = undefined;
    const partly = [_]Record{ Fixture.requirement(&.{3}, &.{}), Fixture.statement(&.{ 3, 5 }, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&partly, &buffer));
    const unnamed = [_]Record{ Fixture.requirement(&.{3}, &.{}), Fixture.statement(&.{}, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&unnamed, &buffer));
}

test "requirements and scenarios are never deleted, and a scenario takes nothing" {
    var buffer: [4]bool = undefined;
    const records = [_]Record{ Fixture.requirement(&.{3}, &.{}), Fixture.requirement(&.{3}, &.{}), Fixture.scenario(&.{3}), Fixture.statement(&.{5}, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false, false, false }, Fixture.deleted(&records, &buffer));
    const scenario_named = [_]Record{ Fixture.scenario(&.{3}), Fixture.statement(&.{3}, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&scenario_named, &buffer));
}

test "a statement holding the only copy of an exact value is kept" {
    var buffer: [4]bool = undefined;
    const only = [_]Record{ Fixture.requirement(&.{3}, &.{}), Fixture.statement(&.{3}, &.{7}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&only, &buffer));
    const shared = [_]Record{ Fixture.requirement(&.{3}, &.{7}), Fixture.statement(&.{3}, &.{7}) };
    try std.testing.expectEqualSlices(bool, &.{ false, true }, Fixture.deleted(&shared, &buffer));
    const partly_held = [_]Record{ Fixture.requirement(&.{3}, &.{7}), Fixture.statement(&.{3}, &.{ 7, 9 }) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&partly_held, &buffer));
}

test "of two holders of the last exact copy the first goes and the last stays" {
    var buffer: [4]bool = undefined;
    const records = [_]Record{ Fixture.requirement(&.{3}, &.{}), Fixture.statement(&.{3}, &.{7}), Fixture.statement(&.{3}, &.{7}) };
    try std.testing.expectEqualSlices(bool, &.{ false, true, false }, Fixture.deleted(&records, &buffer));
}

test "a record with an unidentified value is kept and supplies no value" {
    var buffer: [4]bool = undefined;
    const held = [_]Record{ Fixture.requirement(&.{3}, &.{7}), Fixture.statement(&.{3}, &.{ 7, unidentified(1) }) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&held, &buffer));
    const holder = [_]Record{ Fixture.requirement(&.{3}, &.{unidentified(0)}), Fixture.statement(&.{3}, &.{7}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&holder, &buffer));
    const other = [_]Record{ Fixture.requirement(&.{3}, &.{7}), Fixture.statement(&.{3}, &.{unidentified(1)}), Fixture.statement(&.{3}, &.{7}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false, true }, Fixture.deleted(&other, &buffer));
    // A record with an unidentified part holds none of its other values for the rest.
    const partly = [_]Record{ Fixture.requirement(&.{3}, &.{ 7, unidentified(0) }), Fixture.statement(&.{3}, &.{7}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&partly, &buffer));
}

test "a list entry that is no claim is never taken, so its record is never deleted" {
    var buffer: [4]bool = undefined;
    const records = [_]Record{ Fixture.requirement(&.{no_claim}, &.{}), Fixture.statement(&.{no_claim}, &.{}) };
    try std.testing.expectEqualSlices(bool, &.{ false, false }, Fixture.deleted(&records, &buffer));
}

test "a removed record takes no claim and holds no exact value" {
    const records = [_]Record{ Fixture.requirement(&.{3}, &.{7}), Fixture.statement(&.{3}, &.{7}) };
    const Batch = Rule(Prepared);
    const batch: Prepared = .{ .records = &records };
    try std.testing.expect(Batch.taken(batch, &.{}, 1, 3));
    try std.testing.expect(!Batch.taken(batch, &.{true}, 1, 3));
    try std.testing.expect(Batch.exactHeldElsewhere(batch, &.{}, 1));
    try std.testing.expect(!Batch.exactHeldElsewhere(batch, &.{true}, 1));
    try std.testing.expectEqual(@as(?usize, 1), Batch.first(batch, &.{}));
    try std.testing.expectEqual(@as(?usize, null), Batch.first(batch, &.{ false, true }));
}
