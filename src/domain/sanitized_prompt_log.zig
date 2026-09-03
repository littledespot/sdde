const std = @import("std");
const limits = @import("feature_log_limits.zig");
const telemetry = @import("telemetry.zig");

pub const PromptDirection = enum { request, response };
pub const PromptBodyClass = enum { ordinary, reference_body, code_body };

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

pub const Error = error{InvalidSanitizedPromptFragment};

pub fn validate(fragment: SanitizedPromptFragment) Error!void {
    if (fragment.attempt == 0 or fragment.content.len != fragment.retained_bytes or
        fragment.content.len > limits.max_prompt_content_bytes or
        !std.unicode.utf8ValidateSlice(fragment.content)) return error.InvalidSanitizedPromptFragment;
}

pub const max_fragments_per_batch: usize = 32;
pub const BatchOwner = opaque {};
const BatchOwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    fragments: []SanitizedPromptFragment,
};

pub fn createBatch(
    backing_allocator: std.mem.Allocator,
    candidates: []const SanitizedPromptFragment,
) Error!*BatchOwner {
    if (candidates.len == 0 or candidates.len > max_fragments_per_batch) return error.InvalidSanitizedPromptFragment;
    const owner = backing_allocator.create(BatchOwnerStorage) catch return error.InvalidSanitizedPromptFragment;
    errdefer backing_allocator.destroy(owner);
    owner.* = .{ .backing_allocator = backing_allocator, .arena = .init(backing_allocator), .fragments = undefined };
    errdefer owner.arena.deinit();
    const allocator = owner.arena.allocator();
    const owned_fragments = allocator.alloc(SanitizedPromptFragment, candidates.len) catch return error.InvalidSanitizedPromptFragment;
    for (owned_fragments, candidates) |*destination, source| {
        if (source.fragment_id.bytes.len == 0) return error.InvalidSanitizedPromptFragment;
        destination.* = source;
        destination.request_id.bytes = allocator.dupe(u8, source.request_id.bytes) catch return error.InvalidSanitizedPromptFragment;
        destination.route_id.bytes = allocator.dupe(u8, source.route_id.bytes) catch return error.InvalidSanitizedPromptFragment;
        destination.model_profile_id.bytes = allocator.dupe(u8, source.model_profile_id.bytes) catch return error.InvalidSanitizedPromptFragment;
        destination.fragment_id.bytes = allocator.dupe(u8, source.fragment_id.bytes) catch return error.InvalidSanitizedPromptFragment;
        destination.content = allocator.dupe(u8, source.content) catch return error.InvalidSanitizedPromptFragment;
        if (source.node_id) |node_id| destination.node_id = .{ .bytes = allocator.dupe(u8, node_id.bytes) catch return error.InvalidSanitizedPromptFragment };
    }
    std.mem.sort(SanitizedPromptFragment, owned_fragments, {}, lessThan);
    for (owned_fragments[1..], owned_fragments[0 .. owned_fragments.len - 1]) |current, prior| {
        if (std.mem.eql(u8, current.fragment_id.bytes, prior.fragment_id.bytes)) return error.InvalidSanitizedPromptFragment;
    }
    owner.fragments = owned_fragments;
    return @ptrCast(owner);
}

pub fn batch(owner: *const BatchOwner) []const SanitizedPromptFragment {
    return storageConst(owner).fragments;
}

pub fn deinitBatch(owner: *BatchOwner) void {
    const stored = storage(owner);
    const allocator = stored.backing_allocator;
    stored.arena.deinit();
    allocator.destroy(stored);
}

fn lessThan(_: void, left: SanitizedPromptFragment, right: SanitizedPromptFragment) bool {
    return std.mem.order(u8, left.fragment_id.bytes, right.fragment_id.bytes) == .lt;
}

fn storage(owner: *BatchOwner) *BatchOwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn storageConst(owner: *const BatchOwner) *const BatchOwnerStorage {
    return @ptrCast(@alignCast(owner));
}
