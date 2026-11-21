//! Reconstruct current prompt schema only; observations never become authority.
const std = @import("std");
const format = @import("feature_log_format.zig");
const limits = @import("feature_log_limits.zig");
const debug = @import("request_debugger.zig");
pub const Error = std.mem.Allocator.Error || error{ InvalidDebugArchive, UnsupportedDebugDescriptionVersion };
const Body = struct {
    provenance: []const u8,
    direction: []const u8,
    encoding: []const u8,
    expected: usize,
    fragments: usize = 0,
    bytes: std.ArrayList(u8) = .empty,
};
pub const Archive = struct {
    allocator: std.mem.Allocator, // Session arena owns all retained strings/arrays.
    entries: std.ArrayList(Entry) = .empty,
    const Entry = struct { call: debug.Call, bodies: std.ArrayList(Body) = .empty, events: std.ArrayList(debug.Event) = .empty };

    pub fn ingest(self: *Archive, bytes: []const u8) Error!void {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        const heading = lines.next() orelse return error.InvalidDebugArchive;
        if (!std.mem.eql(u8, heading, std.mem.trimEnd(u8, format.prompt_heading, "\n"))) return error.InvalidDebugArchive;
        while (lines.next()) |line| {
            if (line.len == 0 and lines.peek() == null) break;
            // Interrupted final rows cannot be represented as a complete body.
            if (lines.peek() == null) break;
            const encoded = try std.mem.concat(self.allocator, u8, &.{ line, "\n" });
            format.validateEncodedRow(self.allocator, encoded, format.prompt_column_count) catch return error.InvalidDebugArchive;
            if (!std.mem.eql(u8, try cell(self.allocator, line, format.sharedColumn("schema_version")), limits.schema_version) or !std.mem.eql(u8, try cell(self.allocator, line, format.sharedColumn("column_schema_id")), limits.prompt_column_schema_id)) return error.InvalidDebugArchive;
            const row_kind = try cell(self.allocator, line, format.sharedColumn("record_kind"));
            if (std.mem.eql(u8, row_kind, "segment_header") or std.mem.eql(u8, row_kind, "segment_trailer")) continue;
            if (!std.mem.eql(u8, row_kind, "prompt")) return error.InvalidDebugArchive;
            if (!std.mem.eql(u8, try cell(self.allocator, line, format.promptColumn("body_class")), "complete_body")) continue;
            const call_id = try cell(self.allocator, line, format.promptColumn("call_id"));
            const run = try cell(self.allocator, line, format.sharedColumn("run_id"));
            const sequence = try rowSequence(line);
            if (std.meta.stringToEnum(@import("model_call_lineage.zig").Kind, try cell(self.allocator, line, format.promptColumn("call_kind"))) == null) return error.InvalidDebugArchive;
            var entry: *Entry = for (self.entries.items) |*entry| {
                if (std.mem.eql(u8, entry.call.id, call_id) and std.mem.eql(u8, entry.call.run, run)) break entry;
            } else added: {
                try self.entries.append(self.allocator, .{ .call = .{
                    .run = run,
                    .sequence = sequence,
                    .id = call_id,
                    .workflow = try cell(self.allocator, line, format.promptColumn("workflow_id")),
                    .action = try cell(self.allocator, line, format.promptColumn("action_id")),
                    .node = try cell(self.allocator, line, format.sharedColumn("node_id")),
                    .request_step = try cell(self.allocator, line, format.promptColumn("route_id")),
                    .slot = try cell(self.allocator, line, format.promptColumn("model_profile_id")),
                    .kind = try cell(self.allocator, line, format.promptColumn("call_kind")),
                    .original = try cell(self.allocator, line, format.promptColumn("original_call_id")),
                    .parent = try optionalCell(self.allocator, line, format.promptColumn("parent_call_id")),
                } });
                break :added &self.entries.items[self.entries.items.len - 1];
            };
            entry.call.sequence = @min(entry.call.sequence, sequence);
            if (!std.mem.eql(u8, entry.call.workflow, try cell(self.allocator, line, format.promptColumn("workflow_id"))) or !std.mem.eql(u8, entry.call.node, try cell(self.allocator, line, format.sharedColumn("node_id"))) or !std.mem.eql(u8, entry.call.action, try cell(self.allocator, line, format.promptColumn("action_id"))) or !std.mem.eql(u8, entry.call.original, try cell(self.allocator, line, format.promptColumn("original_call_id"))) or !debug.sameOptional(entry.call.parent, try optionalCell(self.allocator, line, format.promptColumn("parent_call_id")))) return error.InvalidDebugArchive;
            if (!std.mem.eql(u8, entry.call.kind, try cell(self.allocator, line, format.promptColumn("call_kind"))) or !std.mem.eql(u8, entry.call.slot, try cell(self.allocator, line, format.promptColumn("model_profile_id"))) or !std.mem.eql(u8, entry.call.request_step, try cell(self.allocator, line, format.promptColumn("route_id")))) return error.InvalidDebugArchive;
            const fragment = try cell(self.allocator, line, format.promptColumn("fragment_id"));
            var parts = std.mem.splitScalar(u8, fragment, '-');
            const operation = parts.next() orelse return error.InvalidDebugArchive;
            if (std.meta.stringToEnum(@import("llm_provider_operation.zig").ProviderOperationKind, operation) == null) return error.InvalidDebugArchive;
            const direction = parts.next() orelse return error.InvalidDebugArchive;
            const provenance = parts.next() orelse return error.InvalidDebugArchive;
            const encoding = parts.next() orelse return error.InvalidDebugArchive;
            const expected_call = try std.fmt.allocPrint(self.allocator, "{s}-{s}-{s}", .{ try cell(self.allocator, line, format.promptColumn("request_id")), operation, try cell(self.allocator, line, format.promptColumn("attempt")) });
            if (!std.mem.eql(u8, call_id, expected_call)) return error.InvalidDebugArchive;
            if (std.mem.eql(u8, direction, "request")) {
                if (!std.mem.eql(u8, provenance, "provider_body") and !std.mem.eql(u8, provenance, "request_description") and !std.mem.eql(u8, provenance, "source_snapshot")) return error.InvalidDebugArchive;
            } else if (std.mem.eql(u8, direction, "response")) {
                if (!std.mem.eql(u8, provenance, "provider_body") and !std.mem.eql(u8, provenance, "partial_provider_body") and !std.mem.eql(u8, provenance, "transport_outcome")) return error.InvalidDebugArchive;
            } else return error.InvalidDebugArchive;
            const offset = std.fmt.parseInt(usize, parts.next() orelse return error.InvalidDebugArchive, 10) catch return error.InvalidDebugArchive;
            if (parts.next() != null or !std.mem.eql(u8, direction, try cell(self.allocator, line, format.promptColumn("direction"))) or (!std.mem.eql(u8, encoding, "utf8") and !std.mem.eql(u8, encoding, "base64"))) return error.InvalidDebugArchive;
            const expected = std.fmt.parseInt(usize, try cell(self.allocator, line, format.promptColumn("body_bytes")), 10) catch return error.InvalidDebugArchive;
            const content = try cell(self.allocator, line, format.promptColumn("content"));
            const retained = std.fmt.parseInt(usize, try cell(self.allocator, line, format.promptColumn("retained_bytes")), 10) catch return error.InvalidDebugArchive;
            if (retained != content.len or content.len > limits.max_prompt_content_bytes or !std.mem.eql(u8, try cell(self.allocator, line, format.promptColumn("truncated")), "false")) return error.InvalidDebugArchive;
            const redacted = try cell(self.allocator, line, format.promptColumn("redacted"));
            if (!std.mem.eql(u8, redacted, "true") and !std.mem.eql(u8, redacted, "false")) return error.InvalidDebugArchive;
            if (std.mem.eql(u8, direction, "request")) entry.call.redacted = entry.call.redacted or std.mem.eql(u8, redacted, "true");
            const body: *Body = for (entry.bodies.items) |*body| {
                if (std.mem.eql(u8, body.direction, direction) and std.mem.eql(u8, body.provenance, provenance)) break body;
            } else added: {
                if (offset != 0) return error.InvalidDebugArchive;
                try entry.bodies.append(self.allocator, .{ .direction = direction, .provenance = provenance, .encoding = encoding, .expected = expected });
                break :added &entry.bodies.items[entry.bodies.items.len - 1];
            };
            if (body.expected != expected or !std.mem.eql(u8, body.encoding, encoding) or offset != body.bytes.items.len or offset > expected or content.len > expected - offset) return error.InvalidDebugArchive;
            if (body.fragments != 0 and offset == 0) return error.InvalidDebugArchive;
            try body.bytes.appendSlice(self.allocator, content);
            body.fragments += 1;
        }
    }

    pub fn calls(self: *Archive) Error![]debug.Call {
        const result = try self.allocator.alloc(debug.Call, self.entries.items.len);
        for (self.entries.items, result) |entry, *destination| {
            destination.* = entry.call;
            destination.events = entry.events.items;
            for (entry.bodies.items) |body| {
                const complete = body.expected == body.bytes.items.len;
                if (std.mem.eql(u8, body.direction, "request")) {
                    if (std.mem.eql(u8, body.provenance, "source_snapshot") and complete and std.mem.eql(u8, body.encoding, "utf8")) destination.source_snapshot = @import("request_source_snapshot.zig").Snapshot.decode(self.allocator, body.bytes.items) catch return error.InvalidDebugArchive;
                    if (std.mem.eql(u8, body.provenance, "request_description") and complete and std.mem.eql(u8, body.encoding, "utf8")) {
                        try requireCurrentDescription(self.allocator, body.bytes.items);
                        destination.description = debug.Description.decode(self.allocator, body.bytes.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidDebugArchive;
                    }
                    if (std.mem.eql(u8, body.provenance, "provider_body")) {
                        destination.request = body.bytes.items;
                        destination.request_complete = complete and std.mem.eql(u8, body.encoding, "utf8");
                    }
                } else if (std.mem.eql(u8, body.direction, "response")) {
                    if (std.mem.eql(u8, body.provenance, "transport_outcome")) destination.response_diagnostic = body.bytes.items;
                    // A diagnostic may accompany a partial prefix; preserve actual bytes.
                    if (destination.response == null or !std.mem.eql(u8, body.provenance, "transport_outcome")) {
                        destination.response = body.bytes.items;
                        destination.response_provenance = if (complete) body.provenance else "incomplete_capture";
                        destination.response_encoding = body.encoding;
                    }
                } else return error.InvalidDebugArchive;
            }
            if (destination.description) |description| {
                if (!std.mem.eql(u8, description.workflow_id, destination.workflow) or !std.mem.eql(u8, description.request_step, destination.request_step) or !std.mem.eql(u8, description.model_slot, destination.slot)) return error.InvalidDebugArchive;
            }
            if (destination.source_snapshot) |snapshot| {
                if (!snapshot.matches(destination.workflow, destination.node, destination.request_step) or !@import("model_request_kernel.zig").callActionBelongsTo(snapshot.caller.chain[snapshot.caller.chain.len - 1].target, destination.action)) return error.InvalidDebugArchive;
            }
        }
        try debug.orderCalls(result);
        return result;
    }

    pub fn ingestEvents(self: *Archive, bytes: []const u8) Error!void {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        if (!std.mem.eql(u8, lines.next() orelse return error.InvalidDebugArchive, std.mem.trimEnd(u8, format.event_heading, "\n"))) return error.InvalidDebugArchive;
        while (lines.next()) |line| {
            if (line.len == 0 or lines.peek() == null) break;
            const row = try std.mem.concat(self.allocator, u8, &.{ line, "\n" });
            format.validateEncodedRow(self.allocator, row, format.event_column_count) catch return error.InvalidDebugArchive;
            if (!std.mem.eql(u8, try cell(self.allocator, line, format.sharedColumn("schema_version")), limits.schema_version) or !std.mem.eql(u8, try cell(self.allocator, line, format.sharedColumn("column_schema_id")), limits.event_column_schema_id)) return error.InvalidDebugArchive;
            if (!std.mem.eql(u8, try cell(self.allocator, line, format.sharedColumn("record_kind")), "event")) continue;
            const correlation = (try optionalCell(self.allocator, line, format.eventColumn("correlation_id"))) orelse continue;
            const run = try cell(self.allocator, line, format.sharedColumn("run_id"));
            for (self.entries.items) |*entry| if (std.mem.eql(u8, entry.call.id, correlation) and std.mem.eql(u8, entry.call.run, run)) {
                try entry.events.append(self.allocator, .{ .node = try optionalCell(self.allocator, line, format.sharedColumn("node_id")), .kind = try cell(self.allocator, line, format.eventColumn("event_type")), .diagnostic = try optionalCell(self.allocator, line, format.eventColumn("diagnostic_code")), .outcome = try optionalCell(self.allocator, line, format.eventColumn("outcome")) });
            };
        }
    }
};

pub const SegmentOrder = struct { run: []const u8, first: u64, last: u64 };

/// Read recorded sequence bounds before ingesting fragmented bodies. Binding
/// names and segment ordinals do not order the entire run's stream.
pub fn segmentOrder(a: std.mem.Allocator, bytes: []const u8, events: bool) Error!?SegmentOrder {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const heading = if (events) format.event_heading else format.prompt_heading;
    if (!std.mem.eql(u8, lines.next() orelse return error.InvalidDebugArchive, std.mem.trimEnd(u8, heading, "\n"))) return error.InvalidDebugArchive;
    var result: ?SegmentOrder = null;
    while (lines.next()) |line| {
        if (line.len == 0 or lines.peek() == null) break;
        if (!std.mem.eql(u8, try cell(a, line, format.sharedColumn("record_kind")), if (events) "event" else "prompt")) continue;
        const run = try cell(a, line, format.sharedColumn("run_id"));
        const sequence = try rowSequence(line);
        if (result) |*order| {
            if (!std.mem.eql(u8, run, order.run) or sequence <= order.last) return error.InvalidDebugArchive;
            order.last = sequence;
        } else result = .{ .run = run, .first = sequence, .last = sequence };
    }
    return result;
}

fn rowSequence(line: []const u8) Error!u64 {
    const bytes = format.cellAt(line, format.sharedColumn("sequence")) orelse return error.InvalidDebugArchive;
    for (bytes) |byte| if (!std.ascii.isDigit(byte)) return error.InvalidDebugArchive;
    const sequence = std.fmt.parseInt(u64, bytes, 10) catch return error.InvalidDebugArchive;
    if (sequence == 0) return error.InvalidDebugArchive;
    return sequence;
}

pub fn optionalCell(a: std.mem.Allocator, line: []const u8, index: usize) Error!?[]const u8 {
    const raw = format.cellAt(line, index) orelse return error.InvalidDebugArchive;
    if (std.mem.eql(u8, raw, "\\N")) return null;
    var result: std.ArrayList(u8) = .empty;
    var escaped = false;
    for (raw) |byte| {
        if (escaped) {
            try result.append(a, switch (byte) {
                'n' => '\n',
                'r' => '\r',
                '\\', '|' => byte,
                else => return error.InvalidDebugArchive,
            });
            escaped = false;
        } else if (byte == '\\') {
            escaped = true;
        } else try result.append(a, byte);
    }
    if (escaped) return error.InvalidDebugArchive;
    return try result.toOwnedSlice(a);
}
fn cell(a: std.mem.Allocator, line: []const u8, index: usize) Error![]const u8 {
    return (try optionalCell(a, line, index)) orelse error.InvalidDebugArchive;
}

/// Version preflight refuses unsupported descriptions without interpreting
/// their fields. It is not a legacy reader and never supplies missing evidence.
fn requireCurrentDescription(a: std.mem.Allocator, bytes: []const u8) Error!void {
    var parsed = @import("strict_json.zig").parse(a, bytes, .{ .maximum_depth = 64 }, false, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidDebugArchive;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidDebugArchive;
    const version = parsed.value.object.get("version") orelse return error.InvalidDebugArchive;
    if (version != .string) return error.InvalidDebugArchive;
    const versions = std.meta.tags(@FieldType(debug.Description, "version"));
    comptime std.debug.assert(versions.len == 1);
    if (!std.mem.eql(u8, version.string, @tagName(versions[0]))) return error.UnsupportedDebugDescriptionVersion;
}
