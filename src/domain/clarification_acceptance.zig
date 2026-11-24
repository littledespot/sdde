//! Acceptance of authenticated clarification answers (ADR 0025). A closed form that passed validation and whose invoking
//! account was authenticated becomes a response and resolves its record. Pure: this writes nothing, and the accepted
//! state stays in memory until the run publishes it.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const evidence = @import("actor_evidence.zig");
const feature = @import("feature_identity.zig");

/// A closed or cancelled form of this run's: not yet a response, and with an answer or a reason a user gave. A defer
/// stays open and takes no authentication (ADR 0025).
pub fn needsAuthentication(submission: c.Submission) bool {
    if (submission.origin != .submitted) return false;
    return switch (submission.requested_status) {
        .closed => switch (submission.answer) {
            .business_text, .selected_option, .selected_options => true,
            .none, .defer_reason, .cancel_reason => false,
        },
        .cancel => submission.answer == .cancel_reason,
        .open => false,
    };
}

/// The forms to authenticate, in the registry's order.
pub fn pending(allocator: std.mem.Allocator, inputs: c.Inputs) std.mem.Allocator.Error![]const c.Id {
    var ids: std.ArrayList(c.Id) = .empty;
    errdefer ids.deinit(allocator);
    for (inputs.submissions) |submission| if (needsAuthentication(submission)) try ids.append(allocator, submission.id);
    return ids.toOwnedSlice(allocator);
}

/// One closed form, its exact captured bytes and the evidence of the authentication that accepted it.
pub const Accepted = struct { id: c.Id, form_bytes: []const u8, evidence: evidence.Evidence };

/// Whether any of the forms the run accepted cancelled its record: the user's `cancel` ends the run `cancelled` (ADR 0025).
pub fn cancels(inputs: c.Inputs, accepted: []const c.Id) bool {
    const state = inputs.state.value orelse return false;
    for (accepted) |id| for (state.records) |record| {
        if (c.Id.parse(record.id).?.index() == id.index() and record.status == .cancelled_by_user) return true;
    };
    return false;
}

/// The inputs with every accepted form recorded: one response for each, and its record resolved or, for a cancel, cancelled
/// by the user, in a state one ordinal and one revision later, and the submission now a recorded one. The caller's arena
/// owns the result.
pub fn accept(allocator: std.mem.Allocator, inputs: c.Inputs, accepted: []const Accepted) c.Error!c.Inputs {
    if (accepted.len == 0) return inputs;
    const prior = inputs.state.value orelse return error.InvalidClarificationInput;
    if (prior.responses.len + accepted.len > c.max_responses) return error.InvalidClarificationInput;
    const selected = feature.FeatureId.parse(prior.feature_id) orelse return error.InvalidClarificationInput;
    const revision = std.math.add(u64, prior.revision, 1) catch return error.InvalidClarificationInput;
    const ordinal = std.math.add(u64, prior.state_ordinal, 1) catch return error.InvalidClarificationInput;
    const submissions = try allocator.dupe(c.Submission, inputs.submissions);
    const records = try allocator.dupe(c.Record, prior.records);
    const responses = try allocator.alloc(c.Response, prior.responses.len + accepted.len);
    @memcpy(responses[0..prior.responses.len], prior.responses);
    for (accepted, 0..) |item, offset| {
        const submission = for (submissions) |*candidate| {
            if (candidate.id.index() == item.id.index()) break candidate;
        } else return error.InvalidClarificationInput;
        if (!needsAuthentication(submission.*)) return error.InvalidClarificationInput;
        const record = for (records) |*candidate| {
            if (c.Id.parse(candidate.id).?.index() == item.id.index()) break candidate;
        } else return error.InvalidClarificationInput;
        if (record.status != .open) return error.InvalidClarificationInput;
        var buffer: [24]u8 = undefined;
        const response_id = prior.next_response_ordinal + offset;
        responses[prior.responses.len + offset] = .{
            .id = response_id,
            .clarification_id = record.id,
            .input_state_ordinal = prior.state_ordinal,
            .input_state_revision = prior.revision,
            .input_record_revision = record.revision,
            .submitted_form_bytes = item.form_bytes,
            .answer = submission.answer,
            .actor_id = item.evidence.actor_id,
            .authentication_evidence_id = try allocator.dupe(u8, evidence.idText(&buffer, item.evidence.ordinal)),
            .answered_at = item.evidence.occurred_at,
        };
        record.status = if (submission.requested_status == .cancel) .cancelled_by_user else .resolved_by_user;
        record.response_id = response_id;
        record.revision = revision;
        submission.origin = .recorded;
    }
    var state = prior;
    state.state_ordinal = ordinal;
    state.revision = revision;
    state.next_response_ordinal = prior.next_response_ordinal + accepted.len;
    state.records = records;
    state.responses = responses;
    return .{ .state = try c.validate(.{ .value = state }, selected), .submissions = submissions, .protected_forms = inputs.protected_forms };
}
