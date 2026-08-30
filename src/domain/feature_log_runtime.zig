const std = @import("std");
const logging = @import("logging.zig");
const telemetry = @import("telemetry.zig");

pub const Stream = enum { event, prompt };
pub const PromptDirection = enum { request, response };
pub const PromptBodyClass = enum { ordinary, reference_body, code_body };
pub const FailureCode = enum {
    LOG_LOCK_TIMEOUT,
    LOG_SERIALIZATION_FAILURE,
    LOG_SINK_FAILURE,
    LOG_FLUSH_FAILURE,
    LOG_RELEASE_FAILURE,
    LOG_SEGMENT_LIMIT_EXHAUSTED,
};

pub const BindingCandidate = struct {
    log_policy_id: telemetry.Identifier,
    binding_id: telemetry.Identifier,
    run_id: telemetry.Identifier,
    feature_id: telemetry.Identifier,
};

pub const ValidatedFeatureLogBinding = opaque {
    pub fn logPolicyId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).log_policy_id;
    }
    pub fn bindingId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).binding_id;
    }
    pub fn runId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).run_id;
    }
    pub fn featureId(self: *const ValidatedFeatureLogBinding) telemetry.Identifier {
        return bindingStorage(self).feature_id;
    }
};

pub const BindingOwner = opaque {};
const BindingStorage = BindingCandidate;
const BindingOwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    binding: BindingStorage,
};

pub const BindingError = error{InvalidFeatureLogBinding};

pub fn createValidatedBinding(
    allocator: std.mem.Allocator,
    candidate: BindingCandidate,
) BindingError!*BindingOwner {
    if (!validPathIdentifier(candidate.log_policy_id) or !validPathIdentifier(candidate.binding_id) or
        !validPathIdentifier(candidate.run_id) or !validPathIdentifier(candidate.feature_id))
    {
        return error.InvalidFeatureLogBinding;
    }
    const owner = allocator.create(BindingOwnerStorage) catch return error.InvalidFeatureLogBinding;
    errdefer allocator.destroy(owner);
    owner.* = .{ .backing_allocator = allocator, .arena = .init(allocator), .binding = undefined };
    errdefer owner.arena.deinit();
    const arena = owner.arena.allocator();
    owner.binding = .{
        .log_policy_id = .{ .bytes = arena.dupe(u8, candidate.log_policy_id.bytes) catch return error.InvalidFeatureLogBinding },
        .binding_id = .{ .bytes = arena.dupe(u8, candidate.binding_id.bytes) catch return error.InvalidFeatureLogBinding },
        .run_id = .{ .bytes = arena.dupe(u8, candidate.run_id.bytes) catch return error.InvalidFeatureLogBinding },
        .feature_id = .{ .bytes = arena.dupe(u8, candidate.feature_id.bytes) catch return error.InvalidFeatureLogBinding },
    };
    return @ptrCast(owner);
}

fn validPathIdentifier(value: telemetry.Identifier) bool {
    return value.bytes.len != 0 and !std.mem.eql(u8, value.bytes, ".") and
        !std.mem.eql(u8, value.bytes, "..");
}

pub fn binding(owner: *const BindingOwner) *const ValidatedFeatureLogBinding {
    return @ptrCast(&bindingOwnerStorageConst(owner).binding);
}

pub fn deinitBindingOwner(owner: *BindingOwner) void {
    const storage = bindingOwnerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

pub const ClockReading = struct {
    occurred_at_utc: [20]u8,
    unix_ms: u64,
    monotonic_ms: u64,

    pub fn utc(self: *const ClockReading) []const u8 {
        return &self.occurred_at_utc;
    }
};

pub const StreamState = struct {
    segment_ordinal: u16,
    next_sequence: u64,
    segment_bytes: u64,
    segment_count: u8,
    total_segment_count: u8,
    records_since_flush: u8,
    last_flush_monotonic_ms: u64,
};

pub const StreamSeed = struct {
    next_segment_ordinal: u16,
    next_sequence: u64,
    total_segment_count: u8,
};

pub const Recovery = union(enum) {
    empty: StreamSeed,
    active: StreamState,
};

pub const PersistedEvidence = struct {
    segment_ordinal: u16,
    sequence: u64,
    bytes_written: usize,
    flushed: bool,
};

pub const BarrierOutcome = union(enum) {
    dropped,
    persisted: PersistedEvidence,
    blocked: FailureCode,
};

/// A value emitted by the separate prompt sanitization pipeline. F0002
/// validates the closed handoff but never receives or sanitizes a raw body.
pub const SanitizedPromptFragment = struct {
    workflow_shortcode: telemetry.WorkflowShortcode,
    stage: ?telemetry.Stage = null,
    node_id: ?telemetry.Identifier = null,
    attempt: u16,
    request_id: telemetry.Identifier,
    route_id: telemetry.Identifier,
    model_profile_id: telemetry.Identifier,
    fragment_id: telemetry.Identifier,
    direction: PromptDirection,
    body_class: PromptBodyClass,
    content: []const u8,
    retained_bytes: u16,
    truncated: bool,
    redacted: bool,
};

pub const max_prompt_fragments_per_batch: usize = 32;
pub const PromptBatchOwner = opaque {};
const PromptBatchOwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    fragments: []SanitizedPromptFragment,
};

pub fn createPromptBatch(
    backing_allocator: std.mem.Allocator,
    candidates: []const SanitizedPromptFragment,
) BindingError!*PromptBatchOwner {
    if (candidates.len == 0 or candidates.len > max_prompt_fragments_per_batch) return error.InvalidFeatureLogBinding;
    const owner = backing_allocator.create(PromptBatchOwnerStorage) catch return error.InvalidFeatureLogBinding;
    errdefer backing_allocator.destroy(owner);
    owner.* = .{ .backing_allocator = backing_allocator, .arena = .init(backing_allocator), .fragments = undefined };
    errdefer owner.arena.deinit();
    const allocator = owner.arena.allocator();
    const fragments = allocator.alloc(SanitizedPromptFragment, candidates.len) catch return error.InvalidFeatureLogBinding;
    for (fragments, candidates) |*destination, source| {
        if (source.fragment_id.bytes.len == 0) return error.InvalidFeatureLogBinding;
        destination.* = source;
        destination.request_id.bytes = allocator.dupe(u8, source.request_id.bytes) catch return error.InvalidFeatureLogBinding;
        destination.route_id.bytes = allocator.dupe(u8, source.route_id.bytes) catch return error.InvalidFeatureLogBinding;
        destination.model_profile_id.bytes = allocator.dupe(u8, source.model_profile_id.bytes) catch return error.InvalidFeatureLogBinding;
        destination.fragment_id.bytes = allocator.dupe(u8, source.fragment_id.bytes) catch return error.InvalidFeatureLogBinding;
        destination.content = allocator.dupe(u8, source.content) catch return error.InvalidFeatureLogBinding;
        if (source.node_id) |node_id| destination.node_id = .{ .bytes = allocator.dupe(u8, node_id.bytes) catch return error.InvalidFeatureLogBinding };
    }
    std.mem.sort(SanitizedPromptFragment, fragments, {}, promptFragmentLessThan);
    for (fragments[1..], fragments[0 .. fragments.len - 1]) |current, prior| {
        if (std.mem.eql(u8, current.fragment_id.bytes, prior.fragment_id.bytes)) return error.InvalidFeatureLogBinding;
    }
    owner.fragments = fragments;
    return @ptrCast(owner);
}

pub fn promptBatch(owner: *const PromptBatchOwner) []const SanitizedPromptFragment {
    return promptBatchStorageConst(owner).fragments;
}
pub fn deinitPromptBatch(owner: *PromptBatchOwner) void {
    const stored = promptBatchStorage(owner);
    const allocator = stored.backing_allocator;
    stored.arena.deinit();
    allocator.destroy(stored);
}
fn promptFragmentLessThan(_: void, left: SanitizedPromptFragment, right: SanitizedPromptFragment) bool {
    return std.mem.order(u8, left.fragment_id.bytes, right.fragment_id.bytes) == .lt;
}

pub const RetentionAuthorizationOwner = opaque {};
pub const AuthorizedRetention = struct { stream: Stream, cutoff_unix_ms: u64 };
const RetentionStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    current_feature_id: telemetry.Identifier,
    current_run_id: telemetry.Identifier,
    expected: BindingCandidate,
    stream: Stream,
    cutoff_unix_ms: u64,
    used: bool = false,
};

pub fn createRetentionAuthorization(
    allocator: std.mem.Allocator,
    policy: *const logging.CompiledLoggingPolicy,
    current: *const ValidatedFeatureLogBinding,
    historical: *const ValidatedFeatureLogBinding,
    stream: Stream,
    now_unix_ms: u64,
) BindingError!*RetentionAuthorizationOwner {
    if (policy.retention_days != logging.retention_days or
        !std.mem.eql(u8, current.featureId().bytes, historical.featureId().bytes) or
        std.mem.eql(u8, current.runId().bytes, historical.runId().bytes)) return error.InvalidFeatureLogBinding;
    const owner = allocator.create(RetentionStorage) catch return error.InvalidFeatureLogBinding;
    errdefer allocator.destroy(owner);
    owner.* = .{
        .backing_allocator = allocator,
        .arena = .init(allocator),
        .current_feature_id = undefined,
        .current_run_id = undefined,
        .expected = undefined,
        .stream = stream,
        .cutoff_unix_ms = now_unix_ms -| logging.retention_period_ms,
    };
    errdefer owner.arena.deinit();
    const owned = owner.arena.allocator();
    owner.current_feature_id = .{ .bytes = owned.dupe(u8, current.featureId().bytes) catch return error.InvalidFeatureLogBinding };
    owner.current_run_id = .{ .bytes = owned.dupe(u8, current.runId().bytes) catch return error.InvalidFeatureLogBinding };
    owner.expected = .{
        .log_policy_id = .{ .bytes = owned.dupe(u8, historical.logPolicyId().bytes) catch return error.InvalidFeatureLogBinding },
        .binding_id = .{ .bytes = owned.dupe(u8, historical.bindingId().bytes) catch return error.InvalidFeatureLogBinding },
        .run_id = .{ .bytes = owned.dupe(u8, historical.runId().bytes) catch return error.InvalidFeatureLogBinding },
        .feature_id = .{ .bytes = owned.dupe(u8, historical.featureId().bytes) catch return error.InvalidFeatureLogBinding },
    };
    return @ptrCast(owner);
}

pub fn consumeRetentionAuthorization(owner: *RetentionAuthorizationOwner, historical: *const ValidatedFeatureLogBinding) ?AuthorizedRetention {
    const stored = retentionStorage(owner);
    if (stored.used or !sameBinding(historical, stored.expected)) return null;
    stored.used = true;
    return .{ .stream = stored.stream, .cutoff_unix_ms = stored.cutoff_unix_ms };
}
pub fn retentionStream(
    owner: *const RetentionAuthorizationOwner,
    current: *const ValidatedFeatureLogBinding,
    historical: *const ValidatedFeatureLogBinding,
) ?Stream {
    const stored: *const RetentionStorage = @ptrCast(@alignCast(owner));
    if (stored.used or !sameBinding(historical, stored.expected) or
        !std.mem.eql(u8, current.featureId().bytes, stored.current_feature_id.bytes) or
        !std.mem.eql(u8, current.runId().bytes, stored.current_run_id.bytes)) return null;
    return stored.stream;
}
pub fn deinitRetentionAuthorization(owner: *RetentionAuthorizationOwner) void {
    const stored = retentionStorage(owner);
    const allocator = stored.backing_allocator;
    stored.arena.deinit();
    allocator.destroy(stored);
}

pub fn sameBinding(
    value: *const ValidatedFeatureLogBinding,
    candidate: BindingCandidate,
) bool {
    return std.mem.eql(u8, value.logPolicyId().bytes, candidate.log_policy_id.bytes) and
        std.mem.eql(u8, value.bindingId().bytes, candidate.binding_id.bytes) and
        std.mem.eql(u8, value.runId().bytes, candidate.run_id.bytes) and
        std.mem.eql(u8, value.featureId().bytes, candidate.feature_id.bytes);
}

fn bindingStorage(value: *const ValidatedFeatureLogBinding) *const BindingStorage {
    return @ptrCast(@alignCast(value));
}
fn bindingOwnerStorage(owner: *BindingOwner) *BindingOwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn bindingOwnerStorageConst(owner: *const BindingOwner) *const BindingOwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn promptBatchStorage(owner: *PromptBatchOwner) *PromptBatchOwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn promptBatchStorageConst(owner: *const PromptBatchOwner) *const PromptBatchOwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn retentionStorage(owner: *RetentionAuthorizationOwner) *RetentionStorage {
    return @ptrCast(@alignCast(owner));
}

test "validated feature log binding owns one immutable identity tuple" {
    const candidate: BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = telemetry.Identifier.validate("F0002").?,
    };
    const owner = try createValidatedBinding(std.testing.allocator, candidate);
    defer deinitBindingOwner(owner);
    try std.testing.expect(sameBinding(binding(owner), candidate));
}
