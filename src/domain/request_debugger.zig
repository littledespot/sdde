//! Closed diagnostic data. None of these values may enter a workflow envelope.
const std = @import("std");
const strict = @import("strict_json.zig");
pub const Description = @import("model_request_description.zig").Description;
pub const Mode = enum { exact, modified };
pub const Edit = struct { content: []const @import("llm_provider_operation.zig").ModelVisibleContent, schema: []const u8 };
pub const ReplayInput = struct {
    call: u32,
    mode: Mode,
    edit: ?Edit = null,

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) strict.Error!ReplayInput {
        const value = try strict.decode(ReplayInput, a, bytes, .{ .maximum_depth = 64 });
        if ((value.mode == .modified) != (value.edit != null)) return error.InvalidJsonDocument;
        return value;
    }
};
pub const Validation = struct {
    extraction: enum { unavailable, valid, invalid } = .unavailable,
    json: enum { unavailable, valid, invalid } = .unavailable,
    schema: enum { unavailable, valid, invalid } = .unavailable,
    normalization: @import("model_envelope.zig").Normalization = .none,
    model_text: ?[]const u8 = null,
    parsed: ?std.json.Value = null,
    reason: ?[]const u8 = null,
    path: ?[]const u8 = null,
    expected: ?[]const u8 = null,
    received: ?[]const u8 = null,
    input_tokens: ?u64 = null,
    output_tokens: ?u64 = null,
    latency_ms: ?u32 = null,
};
pub const RequestRecord = struct {
    version: enum { @"request-replay/v4" } = .@"request-replay/v4",
    id: []const u8,
    run: []const u8,
    sequence: u64,
    parent_run: []const u8,
    parent_call: []const u8,
    original_run: []const u8,
    original_call: []const u8,
    node: []const u8,
    mode: Mode,
    description: Description,
    source_snapshot: ?@import("request_source_snapshot.zig").Snapshot = null,
    source_overrides: bool = false,
    body: []const u8,
};
pub const ResponseRecord = struct {
    version: enum { @"response-replay/v1" } = .@"response-replay/v1",
    id: []const u8,
    outcome: enum { received, partial, transport_failed, cancelled },
    status: ?u16 = null,
    body: ?[]const u8 = null,
    encoding: enum { utf8, base64 } = .utf8,
    redacted: bool = false,
    diagnostic: ?[]const u8 = null,
};
pub const Call = struct {
    run: []const u8,
    // First captured prompt-row sequence, or persisted replay dispatch sequence.
    sequence: u64,
    execution_order: u64 = 0,
    id: []const u8,
    workflow: []const u8,
    action: []const u8,
    node: []const u8,
    request_step: []const u8,
    slot: []const u8,
    kind: []const u8,
    original: []const u8,
    original_run: ?[]const u8 = null,
    parent: ?[]const u8,
    parent_run: ?[]const u8 = null,
    description: ?Description = null,
    source_snapshot: ?@import("request_source_snapshot.zig").Snapshot = null,
    source_overrides: bool = false,
    request: ?[]const u8 = null,
    response: ?[]const u8 = null,
    response_provenance: ?[]const u8 = null,
    response_status: ?u16 = null,
    response_diagnostic: ?[]const u8 = null,
    request_complete: bool = false,
    redacted: bool = false,
    response_encoding: []const u8 = "utf8",
    validation: Validation = .{},
    events: []const Event = &.{},
    replay: ?Mode = null,
};
pub const Event = struct { node: ?[]const u8, kind: []const u8, diagnostic: ?[]const u8, outcome: ?[]const u8 };

pub const ReplayIdentity = struct {
    id: []const u8,
    run: @import("telemetry.zig").Identifier,
    sequence: u64,
};

/// Independent runs are grouped, never compared as one causal timeline.
/// Within a run, log sequence is authoritative; IDs and filenames are not.
pub fn orderCalls(calls: []Call) error{InvalidDebugArchive}!void {
    std.mem.sort(Call, calls, {}, struct {
        fn less(_: void, a: Call, b: Call) bool {
            if ((a.replay != null) != (b.replay != null)) return a.replay == null;
            const run_order = std.mem.order(u8, a.run, b.run);
            return if (run_order == .eq) a.sequence < b.sequence else run_order == .lt;
        }
    }.less);
    var previous: ?Call = null;
    for (calls) |*call| {
        if (call.sequence == 0) return error.InvalidDebugArchive;
        call.execution_order = 1;
        if (previous) |last| {
            if (std.mem.eql(u8, last.run, call.run)) {
                if (last.sequence >= call.sequence) return error.InvalidDebugArchive;
                call.execution_order = last.execution_order + 1;
            }
        }
        // A rejected replay can reserve a dispatch sequence without saving a
        // record. Keep subsequent replay numbers stable across reopening.
        if (call.replay != null) call.execution_order = call.sequence;
        previous = call.*;
    }
}

pub fn sameOptional(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?, b.?);
}
