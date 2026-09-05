const std = @import("std");
const c = @import("../domain/clarification_inputs.zig");
const forms = @import("../domain/clarification_form.zig");

pub fn record(id: []const u8) c.Record {
    return .{
        .id = id,
        .revision = 1,
        .subject = .{ .requirement = "FR-001", .unit = "primary", .slot = "appearance" },
        .authority = &.{.{ .kind = .reference, .ordinal = 1, .revision = 1 }},
        .question = "Which appearance is required?",
        .why_required = "The reference does not identify the intended appearance.",
        .answer_schema = .{ .bounded_business_text = 2000 },
        .status = .open,
        .response_id = null,
        .authority_resolution = null,
    };
}

pub fn state(records: []const c.Record) c.State {
    var result: c.State = .{
        .schema = c.schema_version,
        .feature_id = "Chosen/Café",
        .state_ordinal = 1,
        .revision = 1,
        .next_ordinal = .{ .spec = 1, .plan = 1, .tasks = 1 },
        .next_response_ordinal = 1,
        .records = records,
        .responses = &.{},
    };
    for (records) |item| switch (c.Id.parse(item.id).?.stage) {
        .spec => result.next_ordinal.spec += 1,
        .plan => result.next_ordinal.plan += 1,
        .tasks => result.next_ordinal.tasks += 1,
    };
    return result;
}

pub fn binding(value: c.State, item: c.Record) forms.Binding {
    return .{ .state_ordinal = value.state_ordinal, .state_revision = value.revision, .record_revision = item.revision, .status = item.status };
}

/// Caller arena owns this fixture and its captured serialization.
pub fn closed(allocator: std.mem.Allocator, id: []const u8, recorded: bool) !c.Captures {
    const records = try allocator.alloc(c.Record, 1);
    records[0] = record(id);
    var value = state(records);
    const bytes = try forms.render(allocator, records[0], binding(value, records[0]), .closed, "  Approved Café theme.  ");
    if (recorded) {
        const responses = try allocator.alloc(c.Response, 1);
        responses[0] = .{
            .id = 1,
            .clarification_id = id,
            .input_state_ordinal = 1,
            .input_state_revision = 1,
            .input_record_revision = 1,
            .submitted_form_bytes = bytes,
            .answer = .{ .business_text = "Approved Café theme." },
            .actor_id = "fixture-user",
            .authentication_evidence_id = "fixture-auth-1",
            .answered_at = "2026-09-05T00:00:00Z",
        };
        records[0].status = .resolved_by_user;
        records[0].revision = 2;
        records[0].response_id = 1;
        value.state_ordinal = 2;
        value.revision = 2;
        value.next_response_ordinal = 2;
        value.responses = responses;
    }
    const captures = try allocator.alloc(c.FormCapture, 1);
    captures[0] = .{ .id = c.Id.parse(id).?, .bytes = bytes };
    return .{ .state = try std.json.Stringify.valueAlloc(allocator, value, .{}), .forms = captures };
}
