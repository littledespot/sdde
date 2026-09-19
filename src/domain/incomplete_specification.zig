//! Pending specification data. This projection exposes current business evidence
//! without asserting that required decisions are resolved or saving execution.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const snapshot = @import("reference_snapshot.zig");
const state = @import("specification_state.zig");
pub const State = struct {
    schema: []const u8,
    feature: @import("feature_identity.zig").FeatureId,
    revision: u64,
    stage: enum { spec_clarification_pending } = .spec_clarification_pending,
    reference: snapshot.Snapshot,
    id_ledger: @import("specification_identity.zig").Ledger,
    clarification: struct { state_ordinal: u64, revision: u64 },
    open_clarifications: []const c.Id,
};
pub const Error = state.Error || c.Error || error{InvalidIncompleteSpecification};

pub fn build(a: std.mem.Allocator, prior: state.Prior, reference: snapshot.Snapshot, clarifications: c.ValidatedState, contracts: ?state.ContractSource) Error!State {
    const value = clarifications.value orelse return error.InvalidIncompleteSpecification;
    const feature = reference.inputs.corpus.feature_id;
    _ = try c.validate(.{ .value = value }, feature);
    var open: std.ArrayList(c.Id) = .empty;
    for (value.records) |record| {
        const id = c.Id.parse(record.id) orelse return error.InvalidIncompleteSpecification;
        if (id.stage == .spec and record.status == .open) try open.append(a, id);
    }
    const result: State = .{
        .schema = state.schema,
        .feature = feature,
        .revision = try state.nextRevision(prior),
        .reference = reference,
        .id_ledger = prior.ledger(),
        .clarification = .{ .state_ordinal = value.state_ordinal, .revision = value.revision },
        .open_clarifications = try open.toOwnedSlice(a),
    };
    try validate(a, result, feature, contracts);
    return result;
}

pub fn validate(a: std.mem.Allocator, value: State, feature: @import("feature_identity.zig").FeatureId, contracts: ?state.ContractSource) Error!void {
    if (!std.mem.eql(u8, value.schema, state.schema) or value.revision == 0 or
        !std.mem.eql(u8, value.feature.bytes, feature.bytes) or
        !std.mem.eql(u8, value.reference.inputs.corpus.feature_id.bytes, feature.bytes) or
        value.clarification.state_ordinal == 0 or value.clarification.revision == 0 or
        value.open_clarifications.len == 0 or value.open_clarifications.len > 99) return error.InvalidIncompleteSpecification;
    var previous: u8 = 0;
    for (value.open_clarifications) |id| {
        if (id.stage != .spec or id.ordinal <= previous or id.ordinal > 99) return error.InvalidIncompleteSpecification;
        previous = id.ordinal;
    }
    for (value.id_ledger.next) |next| if (next == 0) return error.InvalidIncompleteSpecification;
    try state.validateReference(a, value.reference, contracts);
}

pub fn bindClarifications(value: State, clarifications: c.ValidatedState) Error!c.State {
    const current = clarifications.value orelse return error.InvalidIncompleteSpecification;
    _ = try c.validate(.{ .value = current }, value.feature);
    if (current.state_ordinal != value.clarification.state_ordinal or current.revision != value.clarification.revision) return error.InvalidIncompleteSpecification;
    var index: usize = 0;
    for (current.records) |record| {
        const id = c.Id.parse(record.id) orelse return error.InvalidIncompleteSpecification;
        if (id.stage != .spec or record.status != .open) continue;
        if (index >= value.open_clarifications.len or !std.meta.eql(id, value.open_clarifications[index])) return error.InvalidIncompleteSpecification;
        index += 1;
    }
    if (index != value.open_clarifications.len or index == 0) return error.InvalidIncompleteSpecification;
    return current;
}
