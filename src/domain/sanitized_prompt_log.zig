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
            !@import("model_call_lineage.zig").valid(attribution.call, attribution.links)) return error.InvalidSanitizedPromptFragment;
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

test "prompt chunks retain complete content across many record boundaries" {
    // Chunking has no count ceiling: complete content is never tail-truncated.
    const minimum_chunks = 33;
    const bytes = try std.testing.allocator.alloc(u8, limits.max_prompt_content_bytes * minimum_chunks + 17);
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
    try std.testing.expect(count > minimum_chunks);
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
