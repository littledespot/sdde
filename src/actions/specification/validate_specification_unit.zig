const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-specification-unit", .kind = .action, .requires = &.{ .specification_generation_session, .parsed_specification_unit, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_specification_unit}, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context, proposed: @import("../../domain/specification_candidate.zig").Candidate) @import("../../domain/specification_session.zig").Error!@import("../../domain/specification_candidate.zig").Result {
        const session = @import("../../domain/specification_session.zig");
        if (proposed.revision == 0 or !current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
        const result = try g.validate(allocator, self.validator, context, try session.unit(current.completed), proposed.response);
        return switch (result) {
            .valid => |checked| .{ .valid = .{ .unit = checked.unit, .response = checked.response, .origins = proposed.origins } },
            .invalid => |issue| .{ .invalid = .{ .owner = try session.owner(allocator, current), .revision = proposed.revision, .origin = proposed.origins.at(issue.field), .issue = issue } },
        };
    }
};
