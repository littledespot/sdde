const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const spec = @import("../../domain/specification.zig");
const projection = @import("../../domain/specification_projection.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "project-specification-document",
        .kind = .action,
        .requires = &.{ .identified_specification_content, .accounted_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .specification_coverage },
        .produces = &.{.specification_document},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, context: @import("../../domain/specification_provenance.zig").Context, content: spec.IdentifiedContent) projection.Error!spec.CapturedDocument {
        return projection.project(allocator, context, content);
    }
};
