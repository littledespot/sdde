//! Diagnostic workload attribution from closed native request identities.
//! These categories measure consumption; they create no workflow authority or
//! assertion about the semantic stage that first lost a source obligation.
const std = @import("std");
const identity = @import("../../../src/domain/model_request_identity.zig");
pub const OwnerKind = std.meta.Tag(identity.ImmutableUnitOwnerId);
pub const Purpose = identity.RequestPurposeKind;
pub const Stage = enum { extraction_grouping, generation, review, repair, clarification, other };
const ProviderUsage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage;

/// Consumption attributed to one stage. A send without reported usage leaves the stage's
/// actual totals unknown; its known totals still count what was reported.
pub const Resources = struct {
    stage: Stage,
    physical_sends: u64 = 0,
    known_actual_tokens: u64 = 0,
    known_input_tokens: u64 = 0,
    known_output_tokens: u64 = 0,
    actual_tokens: ?u64 = 0,
    actual_input_tokens: ?u64 = 0,
    actual_output_tokens: ?u64 = 0,
    usage_complete: bool = true,
    send_share: ?f64 = null,
    /// Denominator covers known consumption only when usage is incomplete.
    known_accounted_token_share: ?f64 = null,
    actual_token_share: ?f64 = null,
};

/// One zeroed entry per stage, indexed by the stage.
pub fn empty(a: std.mem.Allocator) ![]Resources {
    const result = try a.alloc(Resources, std.meta.tags(Stage).len);
    for (std.meta.tags(Stage), result) |stage, *value| value.* = .{ .stage = stage };
    return result;
}

/// Adds one physical send of a request with this purpose and owner.
pub fn add(result: []Resources, purpose: Purpose, owner: OwnerKind, usage: ?ProviderUsage) error{ AccountingOverflow, CaptureMismatch }!void {
    const value = &result[@intFromEnum(classify(purpose, owner))];
    value.physical_sends = std.math.add(u64, value.physical_sends, 1) catch return error.AccountingOverflow;
    if (usage) |reported| {
        if (ProviderUsage.init(reported.input_tokens, reported.output_tokens, reported.total_tokens) == null) return error.CaptureMismatch;
        value.known_actual_tokens = std.math.add(u64, value.known_actual_tokens, reported.total_tokens) catch return error.AccountingOverflow;
        value.known_input_tokens = std.math.add(u64, value.known_input_tokens, reported.input_tokens) catch return error.AccountingOverflow;
        value.known_output_tokens = std.math.add(u64, value.known_output_tokens, reported.output_tokens) catch return error.AccountingOverflow;
    } else value.usage_complete = false;
    actualize(value);
}

/// Adds another tally of the same stage, such as another run's.
pub fn merge(target: *Resources, item: Resources) error{AccountingOverflow}!void {
    target.physical_sends = std.math.add(u64, target.physical_sends, item.physical_sends) catch return error.AccountingOverflow;
    target.known_actual_tokens = std.math.add(u64, target.known_actual_tokens, item.known_actual_tokens) catch return error.AccountingOverflow;
    target.known_input_tokens = std.math.add(u64, target.known_input_tokens, item.known_input_tokens) catch return error.AccountingOverflow;
    target.known_output_tokens = std.math.add(u64, target.known_output_tokens, item.known_output_tokens) catch return error.AccountingOverflow;
    target.usage_complete = target.usage_complete and item.usage_complete;
    actualize(target);
}

/// Actual totals are the known totals only while every send's usage is known.
fn actualize(value: *Resources) void {
    value.actual_tokens = if (value.usage_complete) value.known_actual_tokens else null;
    value.actual_input_tokens = if (value.usage_complete) value.known_input_tokens else null;
    value.actual_output_tokens = if (value.usage_complete) value.known_output_tokens else null;
}

/// Each stage's share of all sends and tokens. One stage of unknown usage makes every
/// actual token share unknown.
pub fn share(values: []Resources) error{AccountingOverflow}!void {
    var sends: u64 = 0;
    var tokens: u64 = 0;
    var usage_complete = true;
    for (values) |value| {
        sends = std.math.add(u64, sends, value.physical_sends) catch return error.AccountingOverflow;
        tokens = std.math.add(u64, tokens, value.known_actual_tokens) catch return error.AccountingOverflow;
        usage_complete = usage_complete and value.usage_complete;
    }
    for (values) |*value| {
        value.send_share = if (sends != 0) @as(f64, @floatFromInt(value.physical_sends)) / @as(f64, @floatFromInt(sends)) else null;
        value.known_accounted_token_share = if (tokens != 0) @as(f64, @floatFromInt(value.known_actual_tokens)) / @as(f64, @floatFromInt(tokens)) else null;
        value.actual_token_share = if (usage_complete) value.known_accounted_token_share else null;
    }
}

pub fn classify(purpose: Purpose, owner: OwnerKind) Stage {
    return switch (purpose) {
        .atomic_repair => .repair,
        .semantic_review => .review,
        .clarification_resolution => .clarification,
        .context_followup => .other,
        .initial_generation => switch (owner) {
            .reference_chunk, .reference_global => .extraction_grouping,
            .specification_unit => .generation,
            .semantic_review => .review,
            .workflow_step, .plan_unit, .task_cluster, .implementation_operation => .other,
        },
    };
}

test "stage tallies keep known usage, hide unknown actual totals and reject inconsistent usage" {
    const a = std.testing.allocator;
    const tally = try empty(a);
    defer a.free(tally);
    try add(tally, .initial_generation, .specification_unit, ProviderUsage.init(4, 3, 7).?);
    try add(tally, .atomic_repair, .specification_unit, ProviderUsage.init(2, 1, 3).?);
    const generation = &tally[@intFromEnum(Stage.generation)];
    try std.testing.expectEqual(@as(?u64, 7), generation.actual_tokens);
    try std.testing.expectEqual(@as(?u64, 4), generation.actual_input_tokens);
    try share(tally);
    try std.testing.expectEqual(@as(?f64, 0.5), generation.send_share);
    try std.testing.expectEqual(@as(?f64, 0.7), generation.actual_token_share);
    // A send without usage keeps the known totals and hides the actual ones, and with
    // them every stage's actual token share.
    try add(tally, .initial_generation, .specification_unit, null);
    try share(tally);
    try std.testing.expectEqual(@as(u64, 2), generation.physical_sends);
    try std.testing.expectEqual(@as(u64, 7), generation.known_actual_tokens);
    try std.testing.expectEqual(@as(?u64, null), generation.actual_tokens);
    try std.testing.expectEqual(@as(?f64, null), tally[@intFromEnum(Stage.repair)].actual_token_share);
    // Merging another tally of the stage keeps one unknown send unknown.
    var combined: Resources = .{ .stage = .repair };
    try merge(&combined, tally[@intFromEnum(Stage.repair)]);
    try std.testing.expectEqual(@as(?u64, 3), combined.actual_tokens);
    try merge(&combined, .{ .stage = .repair, .physical_sends = 1, .usage_complete = false });
    try std.testing.expectEqual(@as(u64, 2), combined.physical_sends);
    try std.testing.expectEqual(@as(u64, 3), combined.known_actual_tokens);
    try std.testing.expectEqual(@as(?u64, null), combined.actual_tokens);
    // Usage whose total isn't its input plus output, and counts that overflow, reject.
    try std.testing.expectError(error.CaptureMismatch, add(tally, .semantic_review, .semantic_review, .{ .input_tokens = 1, .output_tokens = 1, .total_tokens = 3 }));
    tally[@intFromEnum(Stage.review)].physical_sends = std.math.maxInt(u64);
    try std.testing.expectError(error.AccountingOverflow, add(tally, .semantic_review, .semantic_review, null));
    try std.testing.expectError(error.AccountingOverflow, merge(&combined, .{ .stage = .repair, .physical_sends = std.math.maxInt(u64) }));
    // No sends, no shares.
    const idle = try empty(a);
    defer a.free(idle);
    try share(idle);
    try std.testing.expectEqual(@as(?f64, null), idle[0].send_share);
}

test "baseline stage attribution uses native purpose and owner without operation names" {
    for (std.meta.tags(OwnerKind)) |owner| {
        try std.testing.expectEqual(Stage.repair, classify(.atomic_repair, owner));
        try std.testing.expectEqual(Stage.review, classify(.semantic_review, owner));
        try std.testing.expectEqual(Stage.clarification, classify(.clarification_resolution, owner));
        try std.testing.expectEqual(Stage.other, classify(.context_followup, owner));
        const expected: Stage = switch (owner) {
            .reference_chunk, .reference_global => .extraction_grouping,
            .specification_unit => .generation,
            .semantic_review => .review,
            .workflow_step, .plan_unit, .task_cluster, .implementation_operation => .other,
        };
        try std.testing.expectEqual(expected, classify(.initial_generation, owner));
    }
}
