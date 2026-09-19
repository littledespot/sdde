//! Complete canonical Specify publication. This is accepted artifact data,
//! never a saved runner, model response, checkpoint or continuation.
const std = @import("std");
const spec = @import("specification.zig");
const reference = @import("reference_snapshot.zig");
const authority = @import("required_authority.zig");
const clarification = @import("clarification_inputs.zig");
const ids = @import("specification_identity.zig");
pub const schema = "specification-state/v2";
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
    principle_assessment: @import("principle_assessment.zig").Canonical,
    review: struct {
        candidate_revision: u64,
        seeds: []const authority.Seed,
        evidence: []const authority.Evidence,
        candidates: []const authority.Candidate,
        observations: authority.Observations,
        result: authority.Result,
    },
};
pub const Prior = struct { captured: ?[]const u8, state: ?State };
pub const Error = @import("reference_extraction_contract.zig").Error || error{InvalidSpecificationState};
pub const ContractSource = @import("../ports/workflow_contract_source.zig").Source;

pub fn parse(allocator: std.mem.Allocator, bytes: ?[]const u8, feature: @import("feature_identity.zig").FeatureId, contracts: ?ContractSource) Error!Prior {
    const input = bytes orelse return .{ .captured = null, .state = null };
    const state = @import("strict_json.zig").decode(State, allocator, input, .{ .maximum_bytes = max_bytes, .maximum_depth = 64 }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
    try validate(allocator, state, feature, contracts);
    return .{ .captured = input, .state = state };
}

pub fn validate(allocator: std.mem.Allocator, state: State, feature: @import("feature_identity.zig").FeatureId, contracts: ?ContractSource) Error!void {
    const binding = state.reference.extraction_contract orelse return error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE;
    const source = contracts orelse return error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE;
    try @import("reference_extraction_contract.zig").validate(allocator, binding, source.resolve(binding.workflow_id), state.reference.inputs.chunks.partition);
    reference.validate(allocator, state.reference) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
    if (!std.mem.eql(u8, state.schema, schema) or state.revision == 0 or
        !std.mem.eql(u8, state.feature.bytes, feature.bytes) or
        !std.mem.eql(u8, state.reference.inputs.corpus.feature_id.bytes, feature.bytes) or
        !std.mem.eql(u8, state.review.result.feature.bytes, feature.bytes) or
        state.review.result.continuation != .all_resolved or
        state.clarification.state_ordinal == 0 or state.clarification.revision == 0 or
        !state.reference.inputs.corpus.state_id.eql(state.reference.extraction.state_id) or
        state.reference.conflicts.len != 0) return error.InvalidSpecificationState;
    validateAssociations(allocator, state) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationState;
    var largest: [std.meta.tags(spec.Kind).len]u32 = @splat(0);
    for (spec.required_record_families) |kind| if (!spec.hasRecords(state.content, kind)) return error.InvalidSpecificationState;
    for (state.content.records) |record| {
        const index = @intFromEnum(record.id.kind);
        if (record.id.kind != std.meta.activeTag(record.proposal.content) or record.id.ordinal <= largest[index]) return error.InvalidSpecificationState;
        largest[index] = record.id.ordinal;
    }
    for (state.id_ledger.next, largest) |next, used| if (next == 0 or next <= used) return error.InvalidSpecificationState;
}

pub fn nextRevision(prior: Prior) Error!u64 {
    return if (prior.state) |state| std.math.add(u64, state.revision, 1) catch error.InvalidSpecificationState else 1;
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
    try @import("specification_provenance.zig").validateStored(allocator, state.reference.inputs, records, state.brief, state.content);
    const coverage = @import("specification_coverage.zig");
    const checked = try coverage.checkRecords(allocator, records, state.brief, state.content);
    if (checked != .valid) return error.InvalidSpecificationState;
    const canonical = @import("canonical_json.zig");
    if (!std.mem.eql(u8, try canonical.encode(coverage.Coverage, allocator, checked.valid), try canonical.encode(coverage.Coverage, allocator, state.coverage))) return error.InvalidSpecificationState;
    if (state.review.candidate_revision == 0) return error.InvalidSpecificationState;
    var inputs = try @import("specification_authority.zig").projectRecords(allocator, state.feature, records, state.content, state.brief);
    inputs.revision = state.review.candidate_revision;
    inputs.seeds = state.review.seeds;
    inputs.evidence = state.review.evidence;
    inputs.candidates = state.review.candidates;
    try @import("specification_support.zig").Source.validateStored(allocator, inputs, state.reference.inputs);
    try @import("principle_assessment.zig").validateStored(allocator, inputs, state.reference.inputs, state.principle_assessment);
    if (!try authority.validate(allocator, inputs, state.review.observations, state.review.result)) return error.InvalidSpecificationState;
}
