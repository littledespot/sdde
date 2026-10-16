//! Subject-keyed clarification refresh. This constructs a candidate registry;
//! neither a model need nor a loaded response authenticates an answer.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const wire = @import("model_text_wire.zig");
pub const Error = c.Error || error{ AuthenticationRequired, ProtectedClarification, ClarificationLimitExceeded };
pub const Need = struct {
    stage: c.Stage,
    subject: c.Subject,
    authority: []const c.Authority,
    question: []const u8,
    why_required: []const u8,
    answer_schema: c.AnswerSchema,
};
pub const Needs = struct { feature: @import("feature_identity.zig").FeatureId, original_sources: []const wire.SourceText, entries: []const Need };
/// Execution-local source-aware state. Only State itself is persisted; a fresh
/// invocation must revalidate its questions against its current captured corpus.
pub const Ready = struct {
    state: c.ValidatedState,
    original_sources: []const wire.SourceText,
    pub fn validate(self: Ready, a: std.mem.Allocator) c.Error!c.ValidatedState {
        const current = self.state.value orelse return error.InvalidClarificationInput;
        const selected = @import("feature_identity.zig").FeatureId.parse(current.feature_id) orelse return error.InvalidClarificationInput;
        const state = try c.validate(.{ .value = current }, selected);
        try c.validateQuestions(a, state, self.original_sources);
        return state;
    }
    pub fn validateFor(self: Ready, a: std.mem.Allocator, inputs: @import("reference_evidence.zig").Inputs) c.Error!c.ValidatedState {
        const current = self.state.value orelse return error.InvalidClarificationInput;
        if (!std.mem.eql(u8, current.feature_id, inputs.corpus.feature_id.bytes) or !inputs.corpus.state_id.eql(inputs.chunks.state_id) or
            self.original_sources.len != inputs.corpus.sources.len) return error.InvalidClarificationInput;
        for (self.original_sources, inputs.corpus.sources) |retained, source| {
            if (!std.meta.eql(retained.source_id, source.id) or !std.mem.eql(u8, retained.bytes, source.bytes)) return error.InvalidClarificationInput;
        }
        return self.validate(a);
    }
};
/// Native corpus projection; no candidate or stored question supplies witnesses.
pub fn originalSources(a: std.mem.Allocator, inputs: @import("reference_evidence.zig").Inputs) c.Error![]const wire.SourceText {
    if (!inputs.corpus.state_id.eql(inputs.chunks.state_id)) return error.InvalidClarificationInput;
    const sources = try a.alloc(wire.SourceText, inputs.corpus.sources.len);
    errdefer a.free(sources);
    for (inputs.corpus.sources, sources) |source, *target| target.* = .{ .source_id = source.id, .bytes = source.bytes };
    if (!wire.validSources(sources)) return error.InvalidClarificationInput;
    return sources;
}
pub const Result = union(enum) {
    ready: Ready,
    blocked: enum { authentication_required, protected_clarification, limit_exceeded },
};

pub const Progress = enum { ready, needs_user, blocked };

pub fn progress(result: Result) Progress {
    if (result != .ready) return .blocked;
    const state = result.ready.state.value orelse return .blocked;
    for (state.records) |record| if (record.status == .open) return .needs_user;
    return .ready;
}

/// Caller arena owns new records; unchanged history continues to borrow input.
/// Missing prior subjects are retained, never inferred resolved from absence.
pub fn refresh(allocator: std.mem.Allocator, inputs: c.Inputs, needs: Needs) Error!Ready {
    for (inputs.submissions) |submission| {
        if (submission.origin == .submitted and submission.answer != .none) return error.AuthenticationRequired;
    }
    const prior = try c.validate(.{ .value = inputs.state.value }, needs.feature);
    try c.validateQuestions(allocator, prior, needs.original_sources);
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
    const ready: Ready = .{ .state = try c.validate(.{ .value = state }, needs.feature), .original_sources = needs.original_sources };
    _ = try ready.validate(allocator);
    return ready;
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
