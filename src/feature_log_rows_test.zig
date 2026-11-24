const std = @import("std");
const feature_identity = @import("domain/feature_identity.zig");
const format = @import("domain/feature_log_format.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const log_rows = @import("domain/feature_log_rows.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const prompt_log = @import("domain/sanitized_prompt_log.zig");
const telemetry = @import("domain/telemetry.zig");

const reading: log_stream.ClockReading = .{ .occurred_at_utc = "2026-08-30T10:15:30Z".*, .unix_ms = 1_788_087_330_000, .monotonic_ms = 1001 };

fn stateAt(next_sequence: u64) log_stream.StreamState {
    return .{ .segment_ordinal = 2, .next_sequence = next_sequence, .segment_bytes = 500, .segment_count = 2, .total_segment_count = 2, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
}

fn candidate() log_binding.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = feature_identity.FeatureId.parse("F0002").?,
    };
}

fn fragment() !prompt_log.SanitizedPromptFragment {
    return .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .attempt = 1,
        .request_id = telemetry.Identifier.validate("REQ-1").?,
        .route_id = telemetry.Identifier.validate("ROUTE-1").?,
        .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
        .fragment_id = telemetry.Identifier.validate("FRAG-1").?,
        .direction = .response,
        .body_class = .code_body,
        .content = "sanitized",
        .retained_bytes = 9,
        .truncated = false,
        .redacted = true,
    };
}

fn eventRow() !log_rows.Row {
    const fact: telemetry.TelemetryFact = .{ .run_completed = .{ .outcome = .completed } };
    return .{ .event = .{
        .attributed = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = fact },
        .definition = try log_rows.validateEvent(fact),
    } };
}

fn rowFor(stream: log_stream.Stream) !log_rows.Row {
    return switch (stream) {
        .event => try eventRow(),
        .prompt => .{ .prompt = try fragment() },
    };
}

test "an event fact validates to its registry definition, and a fact only the prompt stream carries does not" {
    const definition = try log_rows.validateEvent(.{ .run_completed = .{ .outcome = .completed } });
    try std.testing.expectEqual(@as(@TypeOf(definition.sensitivity), .public_metadata), definition.sensitivity);
    try std.testing.expectError(error.InvalidLogEventFact, log_rows.validateEvent(.{ .model_prompt_fragment = .{} }));
}

test "a prompt fragment validates when its retained bytes are its content, and not otherwise" {
    var valid = try fragment();
    try log_rows.validatePrompt(valid);
    valid.retained_bytes = 3;
    try std.testing.expectError(error.InvalidPromptLogFragment, log_rows.validatePrompt(valid));
}

test "a row renders as one line of its own stream against the state's sequence, and no state at sequence zero renders one" {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const binding = log_binding.binding(owner);
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        const row = try rowFor(stream);
        const bytes = try log_rows.render(std.testing.allocator, binding, stateAt(7), &reading, row);
        defer std.testing.allocator.free(bytes);
        try std.testing.expect(bytes[bytes.len - 1] == '\n');
        const line = bytes[0 .. bytes.len - 1];
        try std.testing.expect(std.mem.indexOfScalar(u8, line, '\n') == null);
        try std.testing.expectEqualStrings(@tagName(stream), format.cellAt(line, format.sharedColumn("record_kind")).?);
        try std.testing.expectEqualStrings("7", format.cellAt(line, format.sharedColumn("sequence")).?);
        // The event id is derived from the sequence, and sequence zero names none.
        try std.testing.expectError(error.LogSerializationFailure, log_rows.render(std.testing.allocator, binding, stateAt(0), &reading, row));
    }
}

test "a row forces a flush at the level and type it carries: an event its own, a prompt fragment a debug fragment event" {
    const event = log_rows.flushKey(try eventRow());
    const definition = try log_rows.validateEvent(.{ .run_completed = .{ .outcome = .completed } });
    try std.testing.expectEqual(definition.level, event.level);
    try std.testing.expectEqual(telemetry.EventType.run_completed, event.event_type);
    const prompt = log_rows.flushKey(.{ .prompt = try fragment() });
    try std.testing.expectEqual(telemetry.CanonicalLogLevel.debug, prompt.level);
    try std.testing.expectEqual(telemetry.EventType.model_prompt_fragment, prompt.event_type);
}

test "a control record's measured length is its serialized length, in either stream, and a trailer needs its final sequence" {
    const owner = try log_binding.createValidated(std.testing.allocator, candidate());
    defer log_binding.deinitOwner(owner);
    const binding = log_binding.binding(owner);
    const utc: []const u8 = &reading.occurred_at_utc;
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        for ([_]struct { kind: format.ControlKind, final: ?u64 }{
            .{ .kind = .segment_header, .final = null },
            .{ .kind = .segment_trailer, .final = 4 },
        }) |case| {
            const bytes = try log_rows.serializeControl(std.testing.allocator, stream, case.kind, binding, 2, case.final, utc);
            defer std.testing.allocator.free(bytes);
            try std.testing.expectEqual(bytes.len, try log_rows.measureControl(stream, case.kind, binding, 2, case.final, utc));
            const line = bytes[0 .. bytes.len - 1];
            try std.testing.expectEqualStrings(@tagName(case.kind), format.cellAt(line, format.sharedColumn("record_kind")).?);
        }
        try std.testing.expectError(error.LogSerializationFailure, log_rows.serializeControl(std.testing.allocator, stream, .segment_trailer, binding, 2, null, utc));
    }
}
