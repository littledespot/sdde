//! The actor-evidence registry (ADR 0025): who authenticated each accepted clarification answer. An entry holds the public
//! provider, account, assurance level, run and trusted time of one authentication, and no credential, digest or form byte.
//! The registry is execution-local until the run publishes it with the responses it joins.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const feature = @import("feature_identity.zig");
const canonical_json = @import("canonical_json.zig");

pub const schema_version = "actor-evidence-registry/v1";
pub const max_entries = c.max_responses;
pub const max_bytes = 2 * 1024 * 1024;
/// The document, its entries and one entry.
pub const max_depth = 3;
/// `UnsupportedActorName` is an account name outside the token syntax: it is rejected, never widened to fit.
pub const Error = std.mem.Allocator.Error || error{ InvalidActorEvidence, UnsupportedActorName };
pub const EncodeError = Error || canonical_json.Error;

pub const Provider = enum { os_account };
pub const Assurance = enum { invoking_account };
pub const EventKind = enum { clarification_response };

pub const Evidence = struct {
    ordinal: u64,
    event_kind: EventKind,
    provider: Provider,
    actor_id: []const u8,
    assurance: Assurance,
    run_id: []const u8,
    occurred_at: []const u8,
};

/// Append-only: a later revision holds every earlier entry unchanged. Revision 0 is the empty registry; each run that
/// authenticates at least one form appends all of its entries in one revision.
pub const Registry = struct {
    schema: []const u8,
    feature_id: []const u8,
    revision: u64,
    next_ordinal: u64,
    entries: []const Evidence,
};

/// What the authentication port reports for one lease: the account, the run it was observed in and the trusted time.
pub const Observation = struct {
    provider: Provider,
    actor_id: []const u8,
    assurance: Assurance,
    run_id: []const u8,
    occurred_at: [20]u8,
};

pub fn empty(selected: feature.FeatureId) Registry {
    return .{ .schema = schema_version, .feature_id = selected.bytes, .revision = 0, .next_ordinal = 1, .entries = &.{} };
}

/// The text of an evidence ID, which a response carries as its `authentication_evidence_id`. The buffer always fits it:
/// `AE-` and at most 20 digits of a `u64` are 23 bytes.
pub fn idText(buffer: *[24]u8, ordinal: u64) []const u8 {
    return std.fmt.bufPrint(buffer, "AE-{d}", .{ordinal}) catch unreachable;
}

pub fn parseId(bytes: []const u8) ?u64 {
    if (bytes.len < 4 or !std.mem.startsWith(u8, bytes, "AE-")) return null;
    const digits = bytes[3..];
    if (digits.len > 1 and digits[0] == '0') return null;
    for (digits) |digit| if (!std.ascii.isDigit(digit)) return null;
    const ordinal = std.fmt.parseInt(u64, digits, 10) catch return null;
    if (ordinal == 0 or ordinal > max_entries) return null;
    return ordinal;
}

pub fn validActor(bytes: []const u8) bool {
    return c.validToken(bytes);
}

/// A UTC reading (`2026-11-23T08:15:00Z`) in range, by the one check the feature log makes; the trusted clock owns its value.
pub fn validUtc(bytes: []const u8) bool {
    return @import("feature_log_format.zig").validUtcTimestamp(bytes);
}

pub fn validate(registry: Registry, selected: feature.FeatureId) Error!void {
    if (!std.mem.eql(u8, registry.schema, schema_version) or !std.mem.eql(u8, registry.feature_id, selected.bytes) or
        registry.entries.len > max_entries or registry.next_ordinal != registry.entries.len + 1 or
        (registry.entries.len == 0) != (registry.revision == 0) or registry.revision > registry.entries.len) return error.InvalidActorEvidence;
    for (registry.entries, 1..) |entry, ordinal| {
        if (entry.ordinal != ordinal or !validActor(entry.actor_id) or !c.validToken(entry.run_id) or !validUtc(entry.occurred_at)) return error.InvalidActorEvidence;
    }
}

fn sameEvidence(left: Evidence, right: Evidence) bool {
    return left.ordinal == right.ordinal and left.event_kind == right.event_kind and left.provider == right.provider and
        left.assurance == right.assurance and std.mem.eql(u8, left.actor_id, right.actor_id) and
        std.mem.eql(u8, left.run_id, right.run_id) and std.mem.eql(u8, left.occurred_at, right.occurred_at);
}

/// A later registry keeps every earlier entry unchanged and advances its revision exactly when it appends.
pub fn validateAppend(prior: Registry, next: Registry) Error!void {
    if (!std.mem.eql(u8, prior.feature_id, next.feature_id) or next.entries.len < prior.entries.len) return error.InvalidActorEvidence;
    for (prior.entries, next.entries[0..prior.entries.len]) |before, after| if (!sameEvidence(before, after)) return error.InvalidActorEvidence;
    const appended = next.entries.len > prior.entries.len;
    if (next.revision != prior.revision + @intFromBool(appended)) return error.InvalidActorEvidence;
}

/// Every response names an entry of the registry that holds the same account and time, and no two responses share one.
/// An entry no response names is tolerated: a run that failed after its registry was written leaves one, and the next run
/// authenticates its forms again.
pub fn validateJoin(registry: Registry, state: c.State) Error!void {
    for (state.responses, 0..) |response, index| {
        const ordinal = parseId(response.authentication_evidence_id) orelse return error.InvalidActorEvidence;
        if (ordinal > registry.entries.len) return error.InvalidActorEvidence;
        const entry = registry.entries[ordinal - 1];
        if (entry.event_kind != .clarification_response or !std.mem.eql(u8, response.actor_id, entry.actor_id) or
            !std.mem.eql(u8, response.answered_at, entry.occurred_at)) return error.InvalidActorEvidence;
        for (state.responses[0..index]) |other| {
            if (std.mem.eql(u8, other.authentication_evidence_id, response.authentication_evidence_id)) return error.InvalidActorEvidence;
        }
    }
}

pub const Recorded = struct {
    registry: Registry,
    /// The entries this call appended, in order.
    appended: []const Evidence,
};

/// Appends one entry for each observation, in order, in one new revision. The caller's arena owns the result.
pub fn record(allocator: std.mem.Allocator, prior: Registry, observations: []const Observation) Error!Recorded {
    if (observations.len == 0) return .{ .registry = prior, .appended = &.{} };
    const total = prior.entries.len + observations.len;
    if (total > max_entries) return error.InvalidActorEvidence;
    const entries = try allocator.alloc(Evidence, total);
    @memcpy(entries[0..prior.entries.len], prior.entries);
    for (observations, entries[prior.entries.len..], prior.next_ordinal..) |observation, *entry, ordinal| {
        if (!validActor(observation.actor_id)) return error.UnsupportedActorName;
        entry.* = .{
            .ordinal = ordinal,
            .event_kind = .clarification_response,
            .provider = observation.provider,
            .actor_id = try allocator.dupe(u8, observation.actor_id),
            .assurance = observation.assurance,
            .run_id = try allocator.dupe(u8, observation.run_id),
            .occurred_at = try allocator.dupe(u8, &observation.occurred_at),
        };
    }
    const next: Registry = .{
        .schema = schema_version,
        .feature_id = prior.feature_id,
        .revision = prior.revision + 1,
        .next_ordinal = prior.next_ordinal + observations.len,
        .entries = entries,
    };
    const selected = feature.FeatureId.parse(prior.feature_id) orelse return error.InvalidActorEvidence;
    try validate(next, selected);
    try validateAppend(prior, next);
    return .{ .registry = next, .appended = entries[prior.entries.len..] };
}

pub fn encode(allocator: std.mem.Allocator, registry: Registry) EncodeError![]const u8 {
    const bytes = try canonical_json.encode(Registry, allocator, registry);
    if (bytes.len > max_bytes) return error.InvalidActorEvidence;
    return bytes;
}
