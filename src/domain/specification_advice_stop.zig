//! Closed native transport shapes for stopping optional specification advice.
const pipeline = @import("pipeline.zig");

pub const Scope = enum {
    physical,
    protocol,
    physical_repair,
    protocol_repair,

    pub fn isProtocol(self: Scope) bool {
        return self == .protocol or self == .protocol_repair;
    }
    pub fn isRepair(self: Scope) bool {
        return self == .physical_repair or self == .protocol_repair;
    }
};

pub fn contract(comptime scope: Scope) pipeline.NodeContract {
    const base_requires = [_]pipeline.DataKey{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .packet_guidance };
    const transport_requires = if (scope.isProtocol()) [_]pipeline.DataKey{} else [_]pipeline.DataKey{.provider_invocation_validation_result};
    const repair_requires = if (scope.isRepair()) [_]pipeline.DataKey{.specification_support_repair} else [_]pipeline.DataKey{};
    return .{
        .id = switch (scope) {
            .physical => "stop-specification-advice",
            .protocol => "stop-specification-protocol-advice",
            .physical_repair => "stop-specification-repair-advice",
            .protocol_repair => "stop-specification-protocol-repair-advice",
        },
        .kind = .action,
        .requires = &(base_requires ++ transport_requires ++ repair_requires),
        .produces = &.{},
        .replaces = &.{.specification_support_review},
        .invalidates = if (scope.isRepair()) &.{.specification_support_repair} else &.{},
        .side_effect = .none,
    };
}
