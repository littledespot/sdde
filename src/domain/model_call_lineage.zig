//! Execution-local log links. These observations grant no retry or repair authority.
const std = @import("std");
pub const Origin = @import("model_candidate_origin.zig").Origin;
pub const Kind = enum { initial, retry, repair, context_followup };
pub const Links = struct { kind: Kind, original: Origin, parent: ?Origin };
pub const Error = std.mem.Allocator.Error || error{InvalidModelCallLineage};

pub fn callId(buffer: []u8, call: Origin) error{NoSpaceLeft}![]const u8 {
    return std.fmt.bufPrint(buffer, "request-{d}-{s}-{d}", .{ call.request.value, @tagName(call.kind), call.attempt.value });
}

pub const History = struct {
    entries: std.ArrayList(Entry) = .empty,
    const Entry = struct { call: Origin, links: Links };

    pub fn deinit(self: *History, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn observe(self: *History, allocator: std.mem.Allocator, call: Origin, kind: Kind, source: ?Origin) Error!Links {
        if (call.attempt.value == 0 or kind == .retry) return error.InvalidModelCallLineage;
        var previous: ?Entry = null;
        var parent: ?Entry = null;
        for (self.entries.items) |entry| {
            if (std.meta.eql(entry.call, call)) return error.InvalidModelCallLineage;
            if (source) |origin| if (std.meta.eql(entry.call, origin)) {
                parent = entry;
            };
            if (entry.call.request.value == call.request.value and entry.call.kind == call.kind) previous = entry;
        }
        if ((kind == .repair or kind == .context_followup) != (source != null) or (source != null and parent == null)) return error.InvalidModelCallLineage;
        const links: Links = if (previous) |prior| linked: {
            if (prior.call.attempt.value >= call.attempt.value) return error.InvalidModelCallLineage;
            break :linked .{ .kind = .retry, .original = prior.links.original, .parent = prior.call };
        } else if (parent) |prior| .{ .kind = kind, .original = prior.links.original, .parent = prior.call } else .{ .kind = .initial, .original = call, .parent = null };
        try self.entries.append(allocator, .{ .call = call, .links = links });
        return links;
    }
};
