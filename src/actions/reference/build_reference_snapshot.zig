const pipeline = @import("../../domain/pipeline.zig");
const snapshot = @import("../../domain/reference_snapshot.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-snapshot", .kind = .action, .requires = &.{ .reference_directory, .citable_reference_inputs, .accounted_reference_extraction, .accounted_reference_reconciliation, .reference_passive_literals }, .produces = &.{.reference_snapshot}, .side_effect = .none };
    pub fn execute(_: Action, allocator: @import("std").mem.Allocator, authority: @import("../../domain/workflow_compilation.zig").SemanticAuthority, directory: @import("../../domain/reference_ingestion.zig").RelativePath, inputs: @import("../../domain/reference_evidence.zig").Inputs, extracted: @import("../../domain/reference_extraction.zig").Accounted, reconciled: @import("../../domain/reference_reconciliation.zig").Accounted, registry: @import("../../domain/passive_literals.zig").Registry) (snapshot.Error || @import("../../domain/reference_extraction_contract.zig").Error)!snapshot.Snapshot {
        const binding = try @import("../../domain/reference_extraction_contract.zig").capture(allocator, authority, inputs.chunks.partition);
        return snapshot.build(directory, inputs, extracted, reconciled, registry, binding);
    }
};
