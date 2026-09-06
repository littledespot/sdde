const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const spec = @import("../../domain/specification.zig");
const projection = @import("../../domain/specification_projection.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "project-specification-document",
        .kind = .action,
        .requires = &.{ .identified_specification_content, .required_authority_inputs, .accounted_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .specification_coverage, .required_authority_gate },
        .produces = &.{.specification_document},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, context: @import("../../domain/specification_provenance.zig").Context, content: spec.IdentifiedContent, authority: @import("../../domain/required_authority.zig").Inputs) projection.Error!spec.CapturedDocument {
        if (authority.projection != .specification or authority.specification == null or authority.brief == null or
            !std.mem.eql(u8, authority.feature.bytes, context.inputs.corpus.feature_id.bytes) or
            !try spec.sameContent(allocator, authority.specification.?, content)) return error.InvalidSpecification;
        return projection.project(allocator, context, content);
    }
};
