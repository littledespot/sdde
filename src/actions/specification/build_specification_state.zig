const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const state = @import("../../domain/specification_state.zig");
const snapshot = @import("../../domain/reference_snapshot.zig");
const coverage = @import("../../domain/specification_coverage.zig");
pub const Action = struct {
    contracts: ?state.ContractSource = null,
    pub const contract: pipeline.NodeContract = .{
        .id = "build-specification-state",
        .kind = .action,
        .requires = &.{ .prior_specification_state, .reference_snapshot, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_generation_session, .identified_specification_content, .specification_id_ledger, .specification_coverage, .principle_registry, .refreshed_clarification_state, .validated_specification_rendering },
        .produces = &.{.specification_publication_state},
        .side_effect = .none,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, prior: state.Prior, reference: snapshot.Snapshot, context: @import("../../domain/specification_provenance.zig").Context, brief: @import("../../domain/specification.zig").Brief, content: @import("../../domain/specification.zig").IdentifiedContent, ledger: @import("../../domain/specification_identity.zig").Ledger, accounted: coverage.Coverage, principles: @import("../../domain/principle_registry.zig").Registry, clarifications: @import("../../domain/clarification_refresh.zig").Result, rendering_valid: bool) !state.State {
        if (!rendering_valid or clarifications != .ready or !reference.inputs.corpus.state_id.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationState;
        const clarification = try state.checkClarifications(try clarifications.ready.validateFor(allocator, context.inputs));
        const expected = try coverage.validate(allocator, context.references, brief, content);
        const canonical = @import("../../domain/canonical_json.zig");
        if (!std.mem.eql(u8, try canonical.encode(coverage.Coverage, allocator, expected), try canonical.encode(coverage.Coverage, allocator, accounted))) return error.InvalidSpecificationState;
        const feature = context.inputs.corpus.feature_id;
        const value: state.State = .{
            .schema = state.schema,
            .feature = feature,
            .revision = try state.nextRevision(prior),
            .stage = .specified,
            .reference = reference,
            .brief = brief,
            .content = content,
            .id_ledger = ledger,
            .coverage = accounted,
            .clarification = .{ .state_ordinal = clarification.state_ordinal, .revision = clarification.revision },
            .principle_registry = principles,
        };
        try state.validate(allocator, value, feature, self.contracts);
        return value;
    }
};
