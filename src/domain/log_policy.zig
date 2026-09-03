const std = @import("std");
const config = @import("config.zig");
const limits = @import("feature_log_limits.zig");
const telemetry = @import("telemetry.zig");

pub const AliasEvidence = enum { none, critical_to_fatal, warn_to_warning };

pub const CanonicalizedLevel = struct {
    threshold: telemetry.CanonicalLogLevel,
    alias_evidence: AliasEvidence,
    source: []const u8 = "",
};

pub const Error = error{InvalidLoggingPolicy};

pub fn canonicalizeConfiguredLevel(raw: []const u8) Error!CanonicalizedLevel {
    if (std.ascii.eqlIgnoreCase(raw, "fatal")) return canonicalizedLevel(raw, .fatal, .none);
    if (std.ascii.eqlIgnoreCase(raw, "critical")) return canonicalizedLevel(raw, .fatal, .critical_to_fatal);
    if (std.ascii.eqlIgnoreCase(raw, "error")) return canonicalizedLevel(raw, .error_level, .none);
    if (std.ascii.eqlIgnoreCase(raw, "warning")) return canonicalizedLevel(raw, .warning, .none);
    if (std.ascii.eqlIgnoreCase(raw, "warn")) return canonicalizedLevel(raw, .warning, .warn_to_warning);
    if (std.ascii.eqlIgnoreCase(raw, "info")) return canonicalizedLevel(raw, .info, .none);
    if (std.ascii.eqlIgnoreCase(raw, "debug")) return canonicalizedLevel(raw, .debug, .none);
    if (std.ascii.eqlIgnoreCase(raw, "trace")) return canonicalizedLevel(raw, .trace, .none);
    return error.InvalidLoggingPolicy;
}

fn canonicalizedLevel(raw: []const u8, threshold: telemetry.CanonicalLogLevel, evidence: AliasEvidence) CanonicalizedLevel {
    return .{ .threshold = threshold, .alias_evidence = evidence, .source = raw };
}

pub const CompiledLoggingPolicy = struct {
    level: CanonicalizedLevel,
    console: bool,
    prompt_capture: []const config.PromptCapture,
    timestamp_enabled: bool = true,
    file_enabled: bool = true,
    max_record_bytes: usize = limits.max_record_bytes,
    max_segment_bytes: usize = limits.max_segment_bytes,
    max_segments: u8 = limits.max_segments,
    retention_days: u8 = limits.retention_days,
    flush_at_or_above: telemetry.CanonicalLogLevel = .error_level,
    lower_level_flush_records: u8 = limits.lower_level_flush_records,
    lower_level_flush_interval_ms: u16 = limits.lower_level_flush_interval_ms,
    max_prompt_content_bytes: usize = limits.max_prompt_content_bytes,
    stream_lock_deadline_ms: u16 = limits.stream_lock_deadline_ms,
    stream_lock_attempt_count: u8 = limits.stream_lock_attempt_count,
};

pub const Owner = opaque {};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    policy: CompiledLoggingPolicy,
};

pub fn createValidated(
    allocator: std.mem.Allocator,
    logs: config.LogsConfig,
    canonicalized: CanonicalizedLevel,
) Error!*Owner {
    if (!std.mem.eql(u8, logs.level, canonicalized.source) or
        logs.promptCapture.len > @typeInfo(config.PromptCapture).@"enum".fields.len)
    {
        return error.InvalidLoggingPolicy;
    }
    var has_direction = false;
    for (logs.promptCapture, 0..) |selector, index| {
        if (selector == .request or selector == .response) has_direction = true;
        for (logs.promptCapture[0..index]) |previous| {
            if (selector == previous) return error.InvalidLoggingPolicy;
        }
    }
    if (logs.promptCapture.len != 0 and !has_direction) return error.InvalidLoggingPolicy;

    const owner = allocator.create(OwnerStorage) catch return error.InvalidLoggingPolicy;
    errdefer allocator.destroy(owner);
    owner.* = .{ .backing_allocator = allocator, .arena = .init(allocator), .policy = undefined };
    errdefer owner.arena.deinit();
    owner.policy = .{
        .level = .{
            .threshold = canonicalized.threshold,
            .alias_evidence = canonicalized.alias_evidence,
            .source = owner.arena.allocator().dupe(u8, canonicalized.source) catch return error.InvalidLoggingPolicy,
        },
        .console = logs.console,
        .prompt_capture = owner.arena.allocator().dupe(
            config.PromptCapture,
            logs.promptCapture,
        ) catch return error.InvalidLoggingPolicy,
    };
    return @ptrCast(owner);
}

pub fn policy(owner: *const Owner) *const CompiledLoggingPolicy {
    return &ownerStorageConst(owner).policy;
}

pub fn deinitOwner(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

pub fn isEmitted(policy_value: CompiledLoggingPolicy, level_value: telemetry.CanonicalLogLevel) bool {
    return level_value.rank() >= policy_value.level.threshold.rank();
}

pub fn transitionCompatible(current: CompiledLoggingPolicy, next: CompiledLoggingPolicy) bool {
    return current.timestamp_enabled == next.timestamp_enabled and
        current.file_enabled == next.file_enabled and
        current.max_record_bytes == next.max_record_bytes and
        current.max_segment_bytes == next.max_segment_bytes and
        current.max_segments == next.max_segments and
        current.retention_days == next.retention_days and
        current.flush_at_or_above == next.flush_at_or_above and
        current.lower_level_flush_records == next.lower_level_flush_records and
        current.lower_level_flush_interval_ms == next.lower_level_flush_interval_ms and
        current.max_prompt_content_bytes == next.max_prompt_content_bytes and
        current.stream_lock_deadline_ms == next.stream_lock_deadline_ms and
        current.stream_lock_attempt_count == next.stream_lock_attempt_count;
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

test "canonical level aliases have one owner and threshold comparison is exhaustive" {
    try std.testing.expectEqual(telemetry.CanonicalLogLevel.fatal, (try canonicalizeConfiguredLevel("CRITICAL")).threshold);
    try std.testing.expectEqual(AliasEvidence.warn_to_warning, (try canonicalizeConfiguredLevel("warn")).alias_evidence);
    try std.testing.expectError(error.InvalidLoggingPolicy, canonicalizeConfiguredLevel("verbose"));

    const levels = std.enums.values(telemetry.CanonicalLogLevel);
    for (levels) |configured| {
        const policy_value: CompiledLoggingPolicy = .{
            .level = .{ .threshold = configured, .alias_evidence = .none },
            .console = false,
            .prompt_capture = &.{},
        };
        for (levels) |event_level| {
            try std.testing.expectEqual(
                event_level.rank() >= configured.rank(),
                isEmitted(policy_value, event_level),
            );
        }
    }
}

test "policy transitions permit user choices but preserve hard logging contracts" {
    const current: CompiledLoggingPolicy = .{
        .level = .{ .threshold = .info, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var next = current;
    next.level.threshold = .debug;
    next.console = true;
    try std.testing.expect(transitionCompatible(current, next));
    next.max_segments -= 1;
    try std.testing.expect(!transitionCompatible(current, next));
}
