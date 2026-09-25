const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
const refresh = @import("../../domain/clarification_refresh.zig");
const projection = @import("../../domain/specification_projection.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-specification-clarification-need",
        .kind = .action,
        .requires = &.{ .validated_specification_unit, .relative_feature_directory, .accounted_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain },
        .produces = &.{.clarification_needs},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_identity.zig").FeatureId, context: @import("../../domain/specification_provenance.zig").Context, checked: g.Checked) projection.Error!refresh.Needs {
        if (checked.response != .clarification or !std.mem.eql(u8, feature.bytes, context.inputs.corpus.feature_id.bytes)) return error.InvalidSpecification;
        const question = try projection.scalar(allocator, context, checked.response.clarification.question);
        const prepared = @import("../../domain/clarification_preparation.zig").prepare(allocator, question.bytes, switch (checked.response.clarification.reason) {
            .missing => "Required business information is missing; answer only the decision in the question.",
            .ambiguous => "More than one business interpretation remains; identify the intended choice.",
            .conflicting => "Business sources conflict; identify which requirement governs and why.",
        }, (try @import("../../domain/specification_provenance.zig").items(context)).entries, .{ .citation_ids = checked.response.clarification.question.provenance.citation_ids }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecification;
        const needs = try allocator.alloc(refresh.Need, 1);
        const authority = try allocator.dupe(@import("../../domain/clarification_inputs.zig").Authority, &.{.{ .reference = context.inputs.corpus.state_id }});
        needs[0] = .{
            .stage = .spec,
            .subject = .{ .requirement = "specification", .unit = switch (checked.unit) {
                .records => @tagName(checked.response.clarification.record_kind orelse return error.InvalidSpecification),
                else => @tagName(checked.unit),
            }, .slot = "content" },
            .authority = authority,
            .question = prepared.question,
            .why_required = prepared.why_required,
            .answer_schema = .{ .bounded_business_text = @import("../../domain/clarification_inputs.zig").max_text_bytes },
        };
        return .{ .feature = feature, .entries = needs };
    }
};
