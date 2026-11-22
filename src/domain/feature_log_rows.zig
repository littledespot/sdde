const std = @import("std");
const binding_module = @import("feature_log_binding.zig");
const format = @import("feature_log_format.zig");
const event_registry = @import("log_event_registry.zig");
const prompt_log = @import("sanitized_prompt_log.zig");
const stream = @import("feature_log_stream.zig");
const telemetry = @import("telemetry.zig");

// The pure steps that turn a fact or a prompt fragment into the bytes of one row, and a segment's control records into
// theirs. Every error here is a serialization failure to the routines.

pub fn validateEvent(fact: telemetry.TelemetryFact) error{InvalidLogEventFact}!event_registry.EventDefinition {
    return event_registry.validateFact(fact) catch error.InvalidLogEventFact;
}

pub fn validatePrompt(fragment: prompt_log.SanitizedPromptFragment) error{InvalidPromptLogFragment}!void {
    prompt_log.validate(fragment) catch return error.InvalidPromptLogFragment;
}

pub fn buildEvent(
    event_id_buffer: *[32]u8,
    binding: *const binding_module.ValidatedFeatureLogBinding,
    state: stream.StreamState,
    reading: *const stream.ClockReading,
    attributed: telemetry.WorkflowTelemetryFact,
) error{InvalidLogEvent}!format.EventRecord {
    const event_id = format.eventId(event_id_buffer, state.next_sequence) orelse return error.InvalidLogEvent;
    return .{
        .log_policy_id = binding.logPolicyId(),
        .binding_id = binding.bindingId(),
        .segment_ordinal = state.segment_ordinal,
        .workflow_shortcode = attributed.workflow_shortcode,
        .event_id = event_id,
        .sequence = state.next_sequence,
        .occurred_at_utc = reading.utc(),
        .monotonic_offset = reading.monotonic_ms,
        .run_id = binding.runId(),
        .feature_id = binding.featureId(),
        .fact = attributed.fact,
    };
}

pub fn buildPrompt(
    event_id_buffer: *[32]u8,
    binding: *const binding_module.ValidatedFeatureLogBinding,
    state: stream.StreamState,
    reading: *const stream.ClockReading,
    fragment: prompt_log.SanitizedPromptFragment,
) error{InvalidPromptLogRecord}!format.PromptRecord {
    const event_id = format.eventId(event_id_buffer, state.next_sequence) orelse return error.InvalidPromptLogRecord;
    return .{
        .log_policy_id = binding.logPolicyId(),
        .binding_id = binding.bindingId(),
        .segment_ordinal = state.segment_ordinal,
        .event_id = event_id,
        .sequence = state.next_sequence,
        .occurred_at_utc = reading.utc(),
        .monotonic_offset = reading.monotonic_ms,
        .run_id = binding.runId(),
        .feature_id = binding.featureId(),
        .fragment = fragment,
    };
}

pub fn serializeEvent(allocator: std.mem.Allocator, record: format.EventRecord) error{LogSerializationFailure}![]u8 {
    return format.serializeEvent(allocator, record) catch error.LogSerializationFailure;
}

pub fn serializePrompt(allocator: std.mem.Allocator, record: format.PromptRecord) error{LogSerializationFailure}![]u8 {
    return format.serializePrompt(allocator, record) catch error.LogSerializationFailure;
}

pub fn controlRecord(
    kind: format.ControlKind,
    binding: *const binding_module.ValidatedFeatureLogBinding,
    segment_ordinal: u16,
    final_sequence: ?u64,
    occurred_at_utc: []const u8,
) format.ControlRecord {
    return .{
        .kind = kind,
        .log_policy_id = binding.logPolicyId(),
        .binding_id = binding.bindingId(),
        .segment_ordinal = segment_ordinal,
        .final_sequence = final_sequence,
        .occurred_at_utc = occurred_at_utc,
        .run_id = binding.runId(),
        .feature_id = binding.featureId(),
    };
}

pub fn serializeControl(
    allocator: std.mem.Allocator,
    stream_kind: stream.Stream,
    kind: format.ControlKind,
    binding: *const binding_module.ValidatedFeatureLogBinding,
    segment_ordinal: u16,
    final_sequence: ?u64,
    occurred_at_utc: []const u8,
) error{LogSerializationFailure}![]u8 {
    return format.serializeControl(allocator, stream_kind, controlRecord(kind, binding, segment_ordinal, final_sequence, occurred_at_utc)) catch error.LogSerializationFailure;
}

pub fn measureControl(
    stream_kind: stream.Stream,
    kind: format.ControlKind,
    binding: *const binding_module.ValidatedFeatureLogBinding,
    segment_ordinal: u16,
    final_sequence: ?u64,
    occurred_at_utc: []const u8,
) error{LogSerializationFailure}!usize {
    return format.controlLength(stream_kind, controlRecord(kind, binding, segment_ordinal, final_sequence, occurred_at_utc)) catch error.LogSerializationFailure;
}

/// One row for a stream. The tag is the stream, so a row cannot meet the other stream's state or heading.
pub const Row = union(stream.Stream) {
    event: struct {
        attributed: telemetry.WorkflowTelemetryFact,
        definition: event_registry.EventDefinition,
    },
    prompt: prompt_log.SanitizedPromptFragment,
};

/// Build the row against the stream's state and serialise it into `allocator`'s memory. The event id the record borrows
/// is consumed by the serialiser, so its buffer lives only here.
pub fn render(
    allocator: std.mem.Allocator,
    binding: *const binding_module.ValidatedFeatureLogBinding,
    state: stream.StreamState,
    reading: *const stream.ClockReading,
    row: Row,
) error{LogSerializationFailure}![]u8 {
    var event_id_buffer: [32]u8 = undefined;
    switch (row) {
        .event => |event| {
            const record = buildEvent(&event_id_buffer, binding, state, reading, event.attributed) catch return error.LogSerializationFailure;
            return serializeEvent(allocator, record);
        },
        .prompt => |fragment| {
            const record = buildPrompt(&event_id_buffer, binding, state, reading, fragment) catch return error.LogSerializationFailure;
            return serializePrompt(allocator, record);
        },
    }
}

/// The level and event type that decide whether a row forces a flush (26-security.md): an event carries its own, a
/// prompt fragment is a debug-level `model.prompt_fragment`.
pub fn flushKey(row: Row) struct { level: telemetry.CanonicalLogLevel, event_type: telemetry.EventType } {
    return switch (row) {
        .event => |event| .{ .level = event.definition.level, .event_type = telemetry.eventOf(event.attributed.fact) },
        .prompt => .{ .level = .debug, .event_type = .model_prompt_fragment },
    };
}
