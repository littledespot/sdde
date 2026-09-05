const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const forms = @import("../../domain/clarification_form.zig");
const parser_port = @import("../../ports/clarification_input_parser.zig");

pub const Action = struct {
    parser: parser_port.FormParser,
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-clarification-forms@1",
        .kind = .action,
        .requires = &.{ .raw_clarification_inputs, .validated_clarification_state },
        .produces = &.{.clarification_inputs},
        .side_effect = .none,
    };
    /// The runner owns the scratch arena and all borrowed state/capture inputs.
    pub fn execute(self: Action, allocator: std.mem.Allocator, state: clarification.ValidatedState, captured: clarification.Captures) clarification.Error!clarification.Inputs {
        const registry = state.value orelse {
            if (captured.forms.len != 0) return error.InvalidClarificationInput;
            return .{ .state = state, .submissions = &.{}, .protected_forms = &.{} };
        };
        if (captured.forms.len != registry.records.len) return error.InvalidClarificationInput;
        var submissions: std.ArrayList(clarification.Submission) = .empty;
        errdefer submissions.deinit(allocator);
        var protected: std.ArrayList(clarification.FormCapture) = .empty;
        errdefer protected.deinit(allocator);
        for (registry.records, captured.forms) |record, capture| {
            const id = clarification.Id.parse(record.id).?;
            if (capture.id.index() != id.index()) return error.InvalidClarificationInput;
            var binding: forms.Binding = .{ .state_ordinal = registry.state_ordinal, .state_revision = registry.revision, .record_revision = record.revision, .status = record.status };
            if (record.status == .resolved_by_authority) {
                const expected = try forms.renderAuthorityAudit(allocator, record, registry);
                defer allocator.free(expected);
                if (!std.mem.eql(u8, expected, capture.bytes)) return error.InvalidClarificationInput;
                continue;
            }
            const response = if (record.response_id) |response_id| clarification.findResponse(registry, response_id).? else null;
            if (response) |saved| {
                if (!std.mem.eql(u8, saved.submitted_form_bytes, capture.bytes)) return error.InvalidClarificationInput;
                binding = .{ .state_ordinal = saved.input_state_ordinal, .state_revision = saved.input_state_revision, .record_revision = saved.input_record_revision, .status = .open };
            }
            const submitted = try self.parser.parse(allocator, capture.bytes, record, binding);
            if (response) |saved| {
                if (!sameAnswer(saved.answer, submitted.answer) or
                    (record.status == .resolved_by_user and submitted.requested_status != .closed) or
                    (record.status == .cancelled_by_user and submitted.requested_status != .cancel)) return error.InvalidClarificationInput;
            }
            if (submitted.requested_status == .closed) try protected.append(allocator, capture);
            try submissions.append(allocator, .{
                .id = id,
                .subject = record.subject,
                .authority = record.authority,
                .requested_status = submitted.requested_status,
                .answer = submitted.answer,
                .origin = if (response != null) .recorded else .submitted,
            });
        }
        const owned = try submissions.toOwnedSlice(allocator);
        errdefer allocator.free(owned);
        return .{ .state = state, .submissions = owned, .protected_forms = try protected.toOwnedSlice(allocator) };
    }
};

fn sameAnswer(left: clarification.Answer, right: clarification.Answer) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .none => true,
        .business_text => |text| std.mem.eql(u8, text, right.business_text),
        .selected_option => |key| std.mem.eql(u8, key, right.selected_option),
        .defer_reason => |reason| std.mem.eql(u8, reason, right.defer_reason),
        .cancel_reason => |reason| std.mem.eql(u8, reason, right.cancel_reason),
        .selected_options => |keys| blk: {
            if (keys.len != right.selected_options.len) break :blk false;
            for (keys, right.selected_options) |a, b| if (!std.mem.eql(u8, a, b)) break :blk false;
            break :blk true;
        },
    };
}
