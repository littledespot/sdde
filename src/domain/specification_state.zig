//! Complete canonical Specify publication. This is accepted artifact data,
//! never a saved runner, model response, checkpoint or continuation.
const std = @import("std");
const spec = @import("specification.zig");
const reference = @import("reference_snapshot.zig");
const clarification = @import("clarification_inputs.zig");
const ids = @import("specification_identity.zig");
pub const schema = "specification-state/v25";
pub const max_bytes = 64 * 1024 * 1024;
pub const State = struct {
    schema: []const u8,
    feature: @import("feature_identity.zig").FeatureId,
    revision: u64,
    stage: enum { specified },
    reference: reference.Snapshot,
    brief: spec.Brief,
    content: spec.IdentifiedContent,
    id_ledger: ids.Ledger,
    coverage: @import("specification_coverage.zig").Coverage,
    clarification: struct { state_ordinal: u64, revision: u64 },
    /// The captured principle registry, which the next run's capture reads as its
    /// prior registry. Spec doesn't assess principles.
    principle_registry: @import("principle_registry.zig").Registry,
};
pub const Prior = struct {
    captured: ?[]const u8,
    value: union(enum) { absent, specified: State, pending: @import("incomplete_specification.zig").State } = .absent,

    pub fn specified(self: Prior) ?State {
        return switch (self.value) {
            .specified => |value| value,
            .absent, .pending => null,
        };
    }
    pub fn ledger(self: Prior) ids.Ledger {
        return switch (self.value) {
            .absent => .{},
            .specified => |value| value.id_ledger,
            .pending => |value| value.id_ledger,
        };
    }
};
pub const Error = @import("reference_extraction_contract.zig").Error || error{InvalidSpecificationState};
pub const ContractSource = @import("../ports/workflow_contract_source.zig").Source;

pub fn parse(allocator: std.mem.Allocator, bytes: ?[]const u8, feature: @import("feature_identity.zig").FeatureId, contracts: ?ContractSource) Error!Prior {
    const input = bytes orelse return .{ .captured = null };
    const raw = @import("strict_json.zig").decode(std.json.Value, allocator, input, .{ .maximum_bytes = max_bytes, .maximum_depth = 64 }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
    if (raw != .object) return error.InvalidSpecificationState;
    const tag = raw.object.get("stage") orelse return error.InvalidSpecificationState;
    if (tag != .string) return error.InvalidSpecificationState;
    const Stage = enum { specified, spec_clarification_pending };
    switch (std.meta.stringToEnum(Stage, tag.string) orelse return error.InvalidSpecificationState) {
        .specified => {
            const current = @import("strict_json.zig").decode(State, allocator, input, .{ .maximum_bytes = max_bytes, .maximum_depth = 64 }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
            try validate(allocator, current, feature, contracts);
            return .{ .captured = input, .value = .{ .specified = current } };
        },
        .spec_clarification_pending => {
            const draft = @import("incomplete_specification.zig");
            const current = @import("strict_json.zig").decode(draft.State, allocator, input, .{ .maximum_bytes = max_bytes, .maximum_depth = 64 }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
            draft.validate(allocator, current, feature, contracts) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE => error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE,
                else => error.InvalidSpecificationState,
            };
            return .{ .captured = input, .value = .{ .pending = current } };
        },
    }
}

pub fn validateReference(allocator: std.mem.Allocator, value: reference.Snapshot, contracts: ?ContractSource) Error!void {
    const binding = value.extraction_contract orelse return error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE;
    const source = contracts orelse return error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE;
    try @import("reference_extraction_contract.zig").validate(allocator, binding, source.resolve(binding.workflow_id), value.inputs.chunks.partition);
    reference.validate(allocator, value) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
}

pub fn validate(allocator: std.mem.Allocator, state: State, feature: @import("feature_identity.zig").FeatureId, contracts: ?ContractSource) Error!void {
    try validateReference(allocator, state.reference, contracts);
    if (!std.mem.eql(u8, state.schema, schema) or state.revision == 0 or
        !std.mem.eql(u8, state.feature.bytes, feature.bytes) or
        !std.mem.eql(u8, state.reference.inputs.corpus.feature_id.bytes, feature.bytes) or
        state.clarification.state_ordinal == 0 or state.clarification.revision == 0 or
        !state.reference.inputs.corpus.state_id.eql(state.reference.extraction.state_id) or
        state.reference.conflicts.len != 0) return error.InvalidSpecificationState;
    var entity_count: usize = 0;
    for (state.content.records) |record| if (record.proposal.content == .entity) {
        entity_count += 1;
    };
    if (!spec.entityMembershipSatisfied(state.content.entities.disposition, entity_count)) return error.InvalidSpecificationState;
    @import("principle_registry.zig").validate(state.principle_registry) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
    validateAssociations(allocator, state) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
    var largest: [std.meta.tags(spec.Kind).len]u32 = @splat(0);
    for (spec.required_record_families) |kind| if (!spec.hasRecords(state.content, kind)) return error.InvalidSpecificationState;
    for (state.content.records, 0..) |record, position| {
        const index = @intFromEnum(record.id.kind);
        if (record.id.kind != std.meta.activeTag(record.proposal.content) or record.id.ordinal <= largest[index]) return error.InvalidSpecificationState;
        largest[index] = record.id.ordinal;
        // An edge case links to an acceptance criterion it may link to; no other record links.
        if (!@import("scenario_link.zig").validStored(state.content.records, position)) return error.InvalidSpecificationState;
    }
    for (state.id_ledger.next, largest) |next, used| if (next == 0 or next <= used) return error.InvalidSpecificationState;
}

pub fn nextRevision(prior: Prior) Error!u64 {
    const previous = switch (prior.value) {
        .absent => return 1,
        .specified => |value| value.revision,
        .pending => |value| value.revision,
    };
    return std.math.add(u64, previous, 1) catch error.InvalidSpecificationState;
}

pub fn checkClarifications(state: clarification.ValidatedState) Error!clarification.State {
    const value = state.value orelse return error.InvalidSpecificationState;
    for (value.records) |record| {
        const id = clarification.Id.parse(record.id) orelse return error.InvalidSpecificationState;
        if (id.stage == .spec and record.status == .open) return error.InvalidSpecificationState;
    }
    return value;
}

fn validateAssociations(backing: std.mem.Allocator, state: State) !void {
    var scratch: std.heap.ArenaAllocator = .init(backing);
    defer scratch.deinit();
    const allocator = scratch.allocator();
    const records = try @import("reference_support.zig").snapshot(allocator, state.reference);
    try @import("specification_provenance.zig").validateStored(allocator, state.reference.inputs, .{ .records = state.reference.passive_records, .occurrences = state.reference.passive_occurrences }, records, state.brief, state.content);
    // ADR 0048: the stored title is the one the captured sources yield.
    try @import("specification_title.zig").validateStored(allocator, state.reference.inputs, state.content.display_name);
    const coverage = @import("specification_coverage.zig");
    const checked = try coverage.checkRecords(allocator, records, state.brief, state.content);
    if (checked != .valid) return error.InvalidSpecificationState;
    const canonical = @import("canonical_json.zig");
    if (!std.mem.eql(u8, try canonical.encode(coverage.Coverage, allocator, checked.valid), try canonical.encode(coverage.Coverage, allocator, state.coverage))) return error.InvalidSpecificationState;
}
