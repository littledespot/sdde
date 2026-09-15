//! Structural authority gaps projected into the existing clarification lifecycle.
const std = @import("std");
const a = @import("required_authority.zig");
const c = @import("clarification_inputs.zig");
const refresh = @import("clarification_refresh.zig");
pub fn build(allocator: std.mem.Allocator, inputs: a.Inputs, observations: a.Observations, result: a.Result) a.Error!refresh.Needs {
    if (try a.validate(allocator, inputs, observations, result)) return error.InvalidRequiredAuthority;
    var needs: std.ArrayList(refresh.Need) = .empty;
    for (result.entries) |entry| {
        const gap: a.Gap = switch (entry.outcome) {
            .clarification_required => |value| value,
            .upstream_rework_required => |value| .{ .owner = value.owner, .reason = value.reason },
            .administrative_block => return error.InvalidRequiredAuthority,
            .resolved_exactly_one, .resolved_explicit_not_applicable, .resolved_explicit_exception => continue,
        };
        const registered = a.policy(entry.requirement) orelse return error.InvalidRequiredAuthority;
        if (registered.owner != gap.owner or entry.input_authorities.len == 0) return error.InvalidRequiredAuthority;
        // Wording, finding order and execution revision never identify a form.
        const subject = try subjectFor(allocator, entry.requirement);
        var details: std.ArrayList(u8) = .empty;
        for (inputs.evidence) |evidence| {
            if (!std.meta.eql(evidence.requirement, entry.requirement) or evidence.finding == .supported) continue;
            if (evidence.review) |review| {
                if (!c.validText(review.detail, c.max_text_bytes)) return error.InvalidRequiredAuthority;
                if (details.items.len != 0) try details.appendSlice(allocator, "\n");
                try details.appendSlice(allocator, review.detail);
            }
        }
        if (details.items.len > c.max_text_bytes) return error.InvalidRequiredAuthority;
        try needs.append(allocator, .{
            .stage = gap.owner,
            .subject = subject,
            .authority = entry.input_authorities,
            .question = if (details.items.len != 0) try details.toOwnedSlice(allocator) else "What decision or source information resolves this requirement?",
            .why_required = switch (gap.reason) {
                .missing => "Required source information is missing.",
                .ambiguous => "The source leaves more than one interpretation.",
                .conflicting, .multiple_non_equivalent => "The sources disagree; an authoritative decision is required.",
                .stale => "The earlier decision no longer applies to the current inputs.",
                .unsupported => "The available sources do not establish the required behavior.",
                .unregistered_ownership_or_policy => return error.InvalidRequiredAuthority,
            },
            .answer_schema = .{ .bounded_business_text = c.max_text_bytes },
        });
    }
    if (needs.items.len == 0) return error.InvalidRequiredAuthority;
    return .{ .feature = inputs.feature, .entries = try needs.toOwnedSlice(allocator) };
}
pub fn subjectFor(allocator: std.mem.Allocator, id: a.Id) a.Error!c.Subject {
    if (a.policy(id) == null) return error.InvalidRequiredAuthority;
    return .{
        .requirement = try std.fmt.allocPrint(allocator, "{s}@{d}", .{ @tagName(id.kind), id.contract_version }),
        .unit = switch (id.unit) {
            .feature => "feature",
            .record => |record| try std.fmt.allocPrint(allocator, "{s}.{d}", .{ @tagName(record.kind), record.ordinal }),
            inline .signal, .conflict, .token, .decision => |value, tag| try std.fmt.allocPrint(allocator, "{s}.{d}", .{ @tagName(tag), value.ordinal }),
        },
        .slot = if (id.member == 0) @tagName(id.slot) else try std.fmt.allocPrint(allocator, "{s}.{d}", .{ @tagName(id.slot), id.member }),
    };
}
