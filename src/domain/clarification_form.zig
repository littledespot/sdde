const std = @import("std");
const clarification = @import("clarification_inputs.zig");

pub const answer_start = "<!-- sdd:answer:start -->\n";
pub const answer_end = "\n<!-- sdd:answer:end -->\n";
pub const Binding = struct { state_ordinal: u64, state_revision: u64, record_revision: u64, status: clarification.EngineStatus };
pub const Template = struct {
    before_status: []const u8,
    before_answer: []const u8,
    after_answer: []const u8 = answer_end,
};

/// Sole renderer for engine-owned form regions; parsing compares these exact
/// regions and imports only the requested status and bounded answer.
pub fn template(allocator: std.mem.Allocator, record: clarification.Record, binding: Binding) clarification.Error!Template {
    const id = clarification.Id.parse(record.id) orelse return error.InvalidClarificationInput;
    var allowed: std.Io.Writer.Allocating = .init(allocator);
    defer allowed.deinit();
    switch (record.answer_schema) {
        .bounded_business_text => |maximum| allowed.writer.print("Enter at most {d} UTF-8 bytes.", .{maximum}) catch return error.OutOfMemory,
        .select_one => |options| {
            allowed.writer.writeAll("Enter one option key.") catch return error.OutOfMemory;
            try writeOptions(&allowed.writer, options);
        },
        .select_many => |many| {
            allowed.writer.print("Enter {d} to {d} option keys, one per line.", .{ many.minimum, many.maximum }) catch return error.OutOfMemory;
            try writeOptions(&allowed.writer, many.options);
        },
    }
    const before_status = try std.fmt.allocPrint(allocator, "---\nschemaVersion: clarification-form/v1\nclarificationId: {s}\nstage: {s}\nclarificationStateId: clarification-state-{d}\nclarificationStateRevision: {d}\nrecordRevision: {d}\nengineStatus: {s}\nrequestedStatus: ", .{ record.id, @tagName(id.stage), binding.state_ordinal, binding.state_revision, binding.record_revision, @tagName(binding.status) });
    errdefer allocator.free(before_status);
    const before_answer = try std.fmt.allocPrint(allocator, "\nanswerKind: {s}\n---\n\n# {s} — {s} clarification\n\n## Question (engine-owned)\n\n{s}\n\n## Why this is required (engine-owned)\n\n{s}\n\n## Allowed answer (engine-owned)\n\n{s}\nChange requestedStatus to closed to answer, or use open with defer: <reason> or cancel with cancel: <reason>.\n\n## Answer (user-editable)\n\n{s}", .{ @tagName(record.answer_schema), record.id, switch (id.stage) {
        .spec => "Specification",
        .plan => "Planning",
        .tasks => "Tasks",
    }, record.question, record.why_required, allowed.written(), answer_start });
    return .{ .before_status = before_status, .before_answer = before_answer };
}

fn writeOptions(writer: *std.Io.Writer, options: []const clarification.Option) clarification.Error!void {
    for (options) |option| writer.print("\n- {s}: {s}", .{ option.key, option.label }) catch return error.OutOfMemory;
}

pub fn render(allocator: std.mem.Allocator, record: clarification.Record, binding: Binding, status: clarification.RequestedStatus, answer: []const u8) clarification.Error![]u8 {
    const regions = try template(allocator, record, binding);
    defer allocator.free(regions.before_status);
    defer allocator.free(regions.before_answer);
    return std.mem.concat(allocator, u8, &.{ regions.before_status, @tagName(status), regions.before_answer, answer, regions.after_answer });
}

pub fn renderAuthorityAudit(allocator: std.mem.Allocator, record: clarification.Record, state: clarification.State) clarification.Error![]u8 {
    return std.fmt.allocPrint(allocator, "---\nschemaVersion: clarification-audit/v1\nclarificationId: {s}\nclarificationStateId: clarification-state-{d}\nclarificationStateRevision: {d}\nrecordRevision: {d}\nengineStatus: resolved_by_authority\n---\n\n# {s} — Resolved clarification\n\n## Question (engine-owned)\n\n{s}\n\n## Resolution (engine-owned)\n\n{s}\n", .{ record.id, state.state_ordinal, state.revision, record.revision, record.id, record.question, record.authority_resolution orelse return error.InvalidClarificationInput });
}
