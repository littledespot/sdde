//! Subject-keyed clarification refresh. This constructs a candidate registry;
//! neither a model need nor a loaded response authenticates an answer.
const std = @import("std");
const c = @import("clarification_inputs.zig");
pub const Error = c.Error || error{ AuthenticationRequired, ProtectedClarification, ClarificationLimitExceeded };
pub const Need = struct {
    stage: c.Stage,
    subject: c.Subject,
    authority: []const c.Authority,
    question: []const u8,
    why_required: []const u8,
    answer_schema: c.AnswerSchema,
};
pub const Needs = struct { feature: @import("feature_identity.zig").FeatureId, entries: []const Need };
pub const Result = union(enum) {
    ready: c.ValidatedState,
    blocked: enum { authentication_required, protected_clarification, limit_exceeded },
};

/// Caller arena owns new records; unchanged history continues to borrow input.
/// Missing prior subjects are retained, never inferred resolved from absence.
pub fn refresh(allocator: std.mem.Allocator, inputs: c.Inputs, needs: Needs) Error!c.ValidatedState {
    for (inputs.submissions) |submission| {
        if (submission.origin == .submitted and submission.answer != .none) return error.AuthenticationRequired;
    }
    const prior = try c.validate(.{ .value = inputs.state.value }, needs.feature);
    var state: c.State = prior.value orelse .{
        .schema = c.schema_version,
        .feature_id = needs.feature.bytes,
        .state_ordinal = 1,
        .revision = 1,
        .next_ordinal = .{ .spec = 1, .plan = 1, .tasks = 1 },
        .next_response_ordinal = 1,
        .records = &.{},
        .responses = &.{},
    };
    if (prior.value != null) {
        state.state_ordinal = std.math.add(u64, state.state_ordinal, 1) catch return error.ClarificationLimitExceeded;
        state.revision = std.math.add(u64, state.revision, 1) catch return error.ClarificationLimitExceeded;
    }
    var records: std.ArrayList(c.Record) = .empty;
    try records.appendSlice(allocator, state.records);
    const sorted = try allocator.dupe(Need, needs.entries);
    std.mem.sort(Need, sorted, {}, lessNeed);
    for (sorted, 0..) |need, index| {
        if (index > 0 and need.stage == sorted[index - 1].stage and c.sameSubject(need.subject, sorted[index - 1].subject)) return error.InvalidClarificationInput;
        var target: ?usize = null;
        for (records.items, 0..) |record, at| {
            const id = c.Id.parse(record.id).?;
            if (id.stage == need.stage and c.sameSubject(record.subject, need.subject)) {
                target = at;
                break;
            }
        }
        const id: c.Id = if (target) |at| blk: {
            const record = records.items[at];
            // A currently required protected subject cannot be reopened or
            // duplicated to evade missing authenticated applicability evidence.
            if (record.status == .resolved_by_user or record.status == .cancelled_by_user) return error.ProtectedClarification;
            for (inputs.protected_forms) |form| if (form.id.index() == c.Id.parse(record.id).?.index()) return error.ProtectedClarification;
            break :blk c.Id.parse(record.id).?;
        } else blk: {
            const next = switch (need.stage) {
                .spec => &state.next_ordinal.spec,
                .plan => &state.next_ordinal.plan,
                .tasks => &state.next_ordinal.tasks,
            };
            if (next.* > 99) return error.ClarificationLimitExceeded;
            const result: c.Id = .{ .stage = need.stage, .ordinal = next.* };
            next.* += 1;
            break :blk result;
        };
        const filename = id.filename();
        const record: c.Record = .{
            .id = if (target) |at| records.items[at].id else try allocator.dupe(u8, filename[0..3]),
            .revision = state.revision,
            .subject = need.subject,
            .authority = need.authority,
            .question = need.question,
            .why_required = need.why_required,
            .answer_schema = need.answer_schema,
            .status = .open,
            .response_id = null,
            .authority_resolution = null,
        };
        if (target) |at| records.items[at] = record else try records.append(allocator, record);
    }
    std.mem.sort(c.Record, records.items, {}, lessRecord);
    state.records = try records.toOwnedSlice(allocator);
    return c.validate(.{ .value = state }, needs.feature);
}

fn lessNeed(_: void, a: Need, b: Need) bool {
    if (a.stage != b.stage) return @intFromEnum(a.stage) < @intFromEnum(b.stage);
    inline for (.{ "requirement", "unit", "slot" }) |field| {
        const order = std.mem.order(u8, @field(a.subject, field), @field(b.subject, field));
        if (order != .eq) return order == .lt;
    }
    return false;
}
fn lessRecord(_: void, a: c.Record, b: c.Record) bool {
    return c.Id.parse(a.id).?.index() < c.Id.parse(b.id).?.index();
}
