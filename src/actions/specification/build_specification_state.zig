const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const state = @import("../../domain/specification_state.zig");
const authority = @import("../../domain/required_authority.zig");
const snapshot = @import("../../domain/reference_snapshot.zig");
const coverage = @import("../../domain/specification_coverage.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-specification-state",
        .kind = .action,
        .requires = &.{ .prior_specification_state, .reference_snapshot, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .identified_specification_content, .specification_id_ledger, .specification_coverage, .required_authority_inputs, .required_authority_observations, .required_authority_result, .required_authority_gate, .refreshed_clarification_state, .validated_specification_rendering },
        .produces = &.{.specification_publication_state},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, prior: state.Prior, reference: snapshot.Snapshot, context: @import("../../domain/specification_provenance.zig").Context, content: @import("../../domain/specification.zig").IdentifiedContent, ledger: @import("../../domain/specification_identity.zig").Ledger, accounted: coverage.Coverage, inputs: authority.Inputs, observations: authority.Observations, result: authority.Result, clarifications: @import("../../domain/clarification_refresh.zig").Result, rendering_valid: bool) !state.State {
        if (!rendering_valid or clarifications != .ready or inputs.brief == null or inputs.specification == null or
            !reference.inputs.corpus.state_id.eql(context.inputs.corpus.state_id) or
            !try @import("../../domain/specification.zig").sameContent(allocator, content, inputs.specification.?) or
            !try authority.validate(allocator, inputs, observations, result)) return error.InvalidSpecificationState;
        const clarification = try state.checkClarifications(clarifications.ready);
        const expected = try coverage.validate(allocator, context.references, inputs.brief.?, content);
        const canonical = @import("../../domain/canonical_json.zig");
        if (!std.mem.eql(u8, try canonical.encode(coverage.Coverage, allocator, expected), try canonical.encode(coverage.Coverage, allocator, accounted))) return error.InvalidSpecificationState;
        const value: state.State = .{
            .schema = state.schema,
            .feature = inputs.feature,
            .revision = try state.nextRevision(prior),
            .stage = .specified,
            .reference = reference,
            .brief = inputs.brief.?,
            .content = content,
            .id_ledger = ledger,
            .coverage = accounted,
            .clarification = .{ .state_ordinal = clarification.state_ordinal, .revision = clarification.revision },
            .review = .{ .seeds = inputs.seeds, .evidence = inputs.evidence, .candidates = inputs.candidates, .observations = observations, .result = result },
        };
        try state.validate(allocator, value, inputs.feature);
        return value;
    }
};
