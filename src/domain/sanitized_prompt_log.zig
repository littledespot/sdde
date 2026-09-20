const std = @import("std");
const limits = @import("feature_log_limits.zig");
const telemetry = @import("telemetry.zig");

pub const PromptDirection = enum { request, response };
pub const PromptBodyClass = enum { ordinary, reference_body, code_body, complete_body };
pub const CallAttribution = struct {
    workflow_id: telemetry.Identifier,
    action_id: telemetry.Identifier,
    call: @import("model_candidate_origin.zig").Origin,
    links: @import("model_call_lineage.zig").Links,
};

pub const SanitizedPromptFragment = struct {
    workflow_shortcode: telemetry.WorkflowShortcode,
    stage: ?telemetry.Stage = null,
    node_id: ?telemetry.Identifier = null,
    attempt: u32,
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
    attribution: ?CallAttribution = null,
    body_bytes: ?u64 = null,
};

pub const Error = error{InvalidSanitizedPromptFragment};

pub fn validate(fragment: SanitizedPromptFragment) Error!void {
    if (fragment.attempt == 0 or fragment.content.len != fragment.retained_bytes or
        fragment.content.len > limits.max_prompt_content_bytes or
        !std.unicode.utf8ValidateSlice(fragment.content)) return error.InvalidSanitizedPromptFragment;
    if (fragment.attribution) |attribution| {
        if (telemetry.Identifier.validate(attribution.workflow_id.bytes) == null or
            telemetry.Identifier.validate(attribution.action_id.bytes) == null or
            fragment.node_id == null or attribution.call.attempt.value != fragment.attempt or
            attribution.links.original.attempt.value == 0 or
            (attribution.links.kind == .initial) != (attribution.links.parent == null)) return error.InvalidSanitizedPromptFragment;
        if (attribution.links.kind == .initial and !std.meta.eql(attribution.call, attribution.links.original)) return error.InvalidSanitizedPromptFragment;
        if (attribution.links.parent) |parent| if (parent.attempt.value == 0 or std.meta.eql(attribution.call, parent)) return error.InvalidSanitizedPromptFragment;
    }
}

pub const ContentChunk = struct {
    index: usize,
    byte_offset: usize,
    content: []const u8,
};

/// Splits already-redacted content into bounded records without dropping bytes.
/// The caller retains the content and includes each chunk's index in its stable
/// fragment identity. Stream sequence and that identity preserve reconstruction.
pub const ContentChunks = struct {
    content: []const u8,
    offset: usize = 0,
    index: usize = 0,
    finished: bool = false,

    pub fn init(redacted_content: []const u8) Error!ContentChunks {
        if (!std.unicode.utf8ValidateSlice(redacted_content)) return error.InvalidSanitizedPromptFragment;
        return .{ .content = redacted_content };
    }

    pub fn next(self: *ContentChunks) ?ContentChunk {
        if (self.finished) return null;
        var end = self.offset + @min(self.content.len - self.offset, limits.max_prompt_content_bytes);
        while (end < self.content.len and self.content[end] & 0xc0 == 0x80) : (end -= 1) {}
        const result: ContentChunk = .{
            .index = self.index,
            .byte_offset = self.offset,
            .content = self.content[self.offset..end],
        };
        self.offset = end;
        self.index += 1;
        self.finished = end == self.content.len;
        return result;
    }
};

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
        if (source.attribution) |attribution| {
            destination.attribution.?.workflow_id.bytes = allocator.dupe(u8, attribution.workflow_id.bytes) catch return error.InvalidSanitizedPromptFragment;
            destination.attribution.?.action_id.bytes = allocator.dupe(u8, attribution.action_id.bytes) catch return error.InvalidSanitizedPromptFragment;
        }
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

test "prompt chunks retain complete content beyond batch and record boundaries" {
    const bytes = try std.testing.allocator.alloc(u8, limits.max_prompt_content_bytes * (max_fragments_per_batch + 1) + 17);
    defer std.testing.allocator.free(bytes);
    for (bytes, 0..) |*byte, index| byte.* = @intCast('a' + index % 26);
    var chunks = try ContentChunks.init(bytes);
    var reconstructed: std.ArrayList(u8) = .empty;
    defer reconstructed.deinit(std.testing.allocator);
    var count: usize = 0;
    while (chunks.next()) |chunk| {
        try std.testing.expectEqual(count, chunk.index);
        try std.testing.expectEqual(reconstructed.items.len, chunk.byte_offset);
        try std.testing.expect(chunk.content.len <= limits.max_prompt_content_bytes);
        try reconstructed.appendSlice(std.testing.allocator, chunk.content);
        count += 1;
    }
    try std.testing.expect(count > max_fragments_per_batch);
    try std.testing.expectEqualSlices(u8, bytes, reconstructed.items);
}

test "prompt chunks preserve UTF-8 scalars across every chunk boundary" {
    for ([_][]const u8{ "é", "世", "😀" }) |scalar| {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(std.testing.allocator);
        try bytes.appendNTimes(std.testing.allocator, 'x', limits.max_prompt_content_bytes - 1);
        try bytes.appendSlice(std.testing.allocator, scalar);
        try bytes.appendSlice(std.testing.allocator, "tail");
        var chunks = try ContentChunks.init(bytes.items);
        const first = chunks.next().?;
        try std.testing.expectEqual(limits.max_prompt_content_bytes - 1, first.content.len);
        try std.testing.expect(std.unicode.utf8ValidateSlice(first.content));
        const second = chunks.next().?;
        try std.testing.expectEqual(first.content.len, second.byte_offset);
        try std.testing.expectEqualSlices(u8, bytes.items[first.content.len..], second.content);
        try std.testing.expect(std.unicode.utf8ValidateSlice(second.content));
        try std.testing.expect(chunks.next() == null);
    }
}

test "empty prompt content remains observable and malformed UTF-8 rejects" {
    var chunks = try ContentChunks.init("");
    const empty = chunks.next().?;
    try std.testing.expectEqual(@as(usize, 0), empty.index);
    try std.testing.expectEqual(@as(usize, 0), empty.byte_offset);
    try std.testing.expectEqualSlices(u8, "", empty.content);
    try std.testing.expect(chunks.next() == null);
    try std.testing.expectError(error.InvalidSanitizedPromptFragment, ContentChunks.init("\xff"));
}
