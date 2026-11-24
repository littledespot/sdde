const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
const refresh = @import("../../domain/clarification_refresh.zig");
const projection = @import("../../domain/specification_projection.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-specification-clarification-need",
        .kind = .action,
        .requires = &.{ .validated_specification_unit, .relative_feature_directory, .accounted_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals },
        .produces = &.{.clarification_needs},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, feature: @import("../../domain/feature_identity.zig").FeatureId, context: @import("../../domain/specification_provenance.zig").Context, checked: g.Checked) projection.Error!refresh.Needs {
        if (checked.response != .clarification or !std.mem.eql(u8, feature.bytes, context.inputs.corpus.feature_id.bytes)) return error.InvalidSpecification;
        // A records need names the family it is about, and the subject does not use it: the model's pick differs from one run to the next.
        if (checked.unit == .records and checked.response.clarification.record_kind == null) return error.InvalidSpecification;
        const question = try projection.scalar(allocator, context, checked.response.clarification.question);
        const entries = (try @import("../../domain/specification_provenance.zig").items(context)).entries;
        const citation_ids = checked.response.clarification.question.provenance.citation_ids;
        const prepared = @import("../../domain/clarification_preparation.zig").prepare(allocator, question.bytes, switch (checked.response.clarification.reason) {
            .missing => "Required business information is missing; answer only the decision in the question.",
            .ambiguous => "More than one business interpretation remains; identify the intended choice.",
            .conflicting => "Business sources conflict; identify which requirement governs and why.",
        }, entries, .{ .citation_ids = citation_ids }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecification;
        // A records need is about the text of the claims its bound signal holds, which the engine bound and the model
        // did not pick. The other units have one need each in a specification, so their unit names them.
        const sources = switch (checked.unit) {
            .records => @import("../../domain/clarification_subject.zig").fromCitations(allocator, context.inputs.corpus.sources, entries, citation_ids) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecification,
            .brief, .primary_user_story, .entities => &[_]@import("../../domain/clarification_inputs.zig").SourceSpan{},
        };
        const needs = try allocator.alloc(refresh.Need, 1);
        const authority = try allocator.dupe(@import("../../domain/clarification_inputs.zig").Authority, &.{.{ .reference = context.inputs.corpus.state_id }});
        needs[0] = .{
            .stage = .spec,
            .subject = .{ .requirement = "specification", .unit = @tagName(checked.unit), .slot = "content", .sources = sources },
            .authority = authority,
            .question = prepared.question,
            .why_required = prepared.why_required,
            .answer_schema = .{ .bounded_business_text = @import("../../domain/clarification_inputs.zig").max_text_bytes },
        };
        return .{ .feature = feature, .original_sources = refresh.originalSources(allocator, context.inputs) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecification, .entries = needs };
    }
};
