//! Test-only completion of a session's scenarios phase (ADR 0038 Decision 3): the scenarios of every
//! group with a slot, written as the engine binds a model's answer to its slots, so a session
//! whose records are all admitted completes its records unit. The answers are derived from the slot
//! numbers (or a value the test supplies), never hand-written wording.
const std = @import("std");
const g = @import("../domain/specification_generation.zig");
const session = @import("../domain/specification_session.zig");
const request = @import("../domain/scenario_request.zig");
const provenance = @import("../domain/specification_provenance.zig");
const text = @import("reference_text.zig");

/// A scenarios answer holding one scenario for each of `numbers`, in that order. Each part of a
/// scenario carries its own name and its number, so a part that lands in another field is seen.
pub fn answer(a: std.mem.Allocator, numbers: []const u32) ![]const u8 {
    return tagged(a, "", numbers);
}

/// The same answer with `tag` in every part, so two groups never write equal criteria (equal
/// criteria of different groups block as competing records).
fn tagged(a: std.mem.Allocator, tag: []const u8, numbers: []const u32) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    try out.writer.writeAll("{\"scenarios\":[");
    for (numbers, 0..) |number, index| {
        if (index != 0) try out.writer.writeAll(",");
        try out.writer.print("{{\"number\":{d},\"given\":\"MOCK Given {s}{d}.\",\"when\":\"MOCK When {s}{d}.\",\"then\":\"MOCK Then {s}{d}.\"}}", .{ number, tag, number, tag, number, tag, number });
    }
    try out.writer.writeAll("]}");
    return out.written();
}

/// The session once every group's scenarios are admitted and the batches merge. A session outside
/// the scenarios phase is returned as it is.
pub fn complete(a: std.mem.Allocator, current: session.Session, context: provenance.Context) !session.Session {
    return finish(a, current, context, null);
}

/// The same, with every scenario's given, when and then written as `value` (the wording a test's
/// exact-value expectations rely on). Only a group with a single slot can take it: equal criteria
/// naming different claims are competing records.
pub fn completeWith(a: std.mem.Allocator, current: session.Session, context: provenance.Context, value: @import("../domain/specification.zig").BusinessValue) !session.Session {
    return finish(a, current, context, value);
}

fn finish(a: std.mem.Allocator, current: session.Session, context: provenance.Context, value: ?@import("../domain/specification.zig").BusinessValue) !session.Session {
    if (!session.scenarioPhase(current)) return current;
    var next = current;
    while (next.scenario_cursor < session.scenarioPopulation(next)) {
        const plan = try session.scenarioPlan(a, next);
        const bound = (try session.currentBinding(a, next, context)).records;
        const criteria = if (value) |supplied| supplied: {
            // Slots after the first add their place, so equal criteria never name different claims.
            const Segment = @import("../domain/typed_text.zig").BusinessSegment;
            const written = try a.alloc(@import("../domain/specification.zig").Values(.model).RecordProposal, plan.count());
            for (written, 0..) |*criterion, index| {
                const own: @import("../domain/specification.zig").BusinessValue = if (index == 0) supplied else .{ .segments = try std.mem.concat(a, Segment, &.{ supplied.segments, &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, " ({d})", .{index + 1}) } }} }) };
                criterion.* = try g.batchRecord(a, bound, .{ .acceptance_criterion = .{ .given = own, .when = own, .then = own } }, try a.dupe(@import("../domain/reference_reconciliation.zig").ClaimId, &.{plan.slot(index).claim}));
            }
            break :supplied written;
        } else numbered: {
            const numbers = try a.alloc(u32, plan.count());
            for (numbers, 1..) |*number, ordinal| number.* = @intCast(ordinal);
            const tag = try std.fmt.allocPrint(a, "g{d}-", .{plan.group.ordinal});
            break :numbered try request.parse(a, try tagged(a, tag, numbers), plan, bound);
        };
        const checked = try session.admit(a, next, context, (try g.validate(a, text.validator, context, .records, .{ .content = .{ .records = criteria } })).valid);
        if (try session.checkConsistency(a, next, context, checked, null) != null) return error.InvalidScenarioFixture;
        next = try session.appendScenarios(a, next, checked);
    }
    return session.completeScenarios(a, next);
}
