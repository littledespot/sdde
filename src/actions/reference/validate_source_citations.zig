const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const citations = @import("../../domain/source_citations.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-source-citations@1",
        .kind = .action,
        .requires = &.{ .citable_reference_inputs, .reference_citation_proposals },
        .produces = &.{.validated_source_citations},
        .side_effect = .none,
    };

    /// Structural citation proof only; this does not prove semantic support.
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: evidence.Inputs, proposals: evidence.CitationProposals) evidence.Error!evidence.ValidatedCitations {
        return citations.validate(allocator, inputs, proposals);
    }
};
