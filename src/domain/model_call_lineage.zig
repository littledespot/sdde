//! Execution-local log links. These observations grant no retry or repair authority.
const std = @import("std");
pub const Origin = @import("model_candidate_origin.zig").Origin;
pub const Kind = enum { initial, retry, repair, context_followup };
pub const Source = union(enum) { none, response: Origin, assembled_candidate };
pub const Links = struct { kind: Kind, original: Origin, parent: ?Origin, source: Source };
pub const Error = std.mem.Allocator.Error || error{
    ZeroModelAttempt,
    ExplicitRetryKind,
    DuplicateModelCall,
    UnexpectedModelCallSource,
    MissingModelCallSource,
    UnknownModelCallSource,
    NonIncreasingModelAttempt,
};
pub const Rejection = enum { zero_attempt, explicit_retry, duplicate_call, unexpected_source, missing_source, unknown_source, non_increasing_attempt };
pub fn rejection(cause: Error) ?Rejection {
    return switch (cause) {
        error.OutOfMemory => null,
        error.ZeroModelAttempt => .zero_attempt,
        error.ExplicitRetryKind => .explicit_retry,
        error.DuplicateModelCall => .duplicate_call,
        error.UnexpectedModelCallSource => .unexpected_source,
        error.MissingModelCallSource => .missing_source,
        error.UnknownModelCallSource => .unknown_source,
        error.NonIncreasingModelAttempt => .non_increasing_attempt,
    };
}

/// Both capture and prompt validation consume this one closed link contract.
pub fn valid(call: Origin, links: Links) bool {
    if (call.attempt.value == 0 or links.original.attempt.value == 0) return false;
    return switch (links.source) {
        .none => links.kind == .initial and links.parent == null and std.meta.eql(call, links.original),
        .assembled_candidate => links.kind == .repair and links.parent == null and std.meta.eql(call, links.original),
        .response => |parent| links.kind != .initial and links.parent != null and
            parent.attempt.value != 0 and !std.meta.eql(call, parent) and std.meta.eql(parent, links.parent.?),
    };
}

pub fn callId(buffer: []u8, call: Origin) error{NoSpaceLeft}![]const u8 {
    return std.fmt.bufPrint(buffer, "request-{d}-{s}-{d}", .{ call.request.value, @tagName(call.kind), call.attempt.value });
}

pub const History = struct {
    entries: std.ArrayList(Entry) = .empty,
    const Entry = struct { call: Origin, links: Links };

    pub fn deinit(self: *History, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn observe(self: *History, allocator: std.mem.Allocator, call: Origin, kind: Kind, source: Source) Error!Links {
        if (call.attempt.value == 0) return error.ZeroModelAttempt;
        if (kind == .retry) return error.ExplicitRetryKind;
        switch (source) {
            .none => if (kind != .initial) return error.MissingModelCallSource,
            .response => if (kind == .initial) return error.UnexpectedModelCallSource,
            .assembled_candidate => if (kind != .repair) return error.UnexpectedModelCallSource,
        }
        var previous: ?Entry = null;
        var parent: ?Entry = null;
        for (self.entries.items) |entry| {
            if (std.meta.eql(entry.call, call)) return error.DuplicateModelCall;
            if (source == .response and std.meta.eql(entry.call, source.response)) {
                parent = entry;
            }
            if (entry.call.request.value == call.request.value and entry.call.kind == call.kind) previous = entry;
        }
        if (source == .response and parent == null) return error.UnknownModelCallSource;
        const links: Links = if (previous) |prior| linked: {
            if (prior.call.attempt.value >= call.attempt.value) return error.NonIncreasingModelAttempt;
            break :linked .{ .kind = .retry, .original = prior.links.original, .parent = prior.call, .source = .{ .response = prior.call } };
        } else if (parent) |prior| .{ .kind = kind, .original = prior.links.original, .parent = prior.call, .source = source } else .{ .kind = kind, .original = call, .parent = null, .source = source };
        try self.entries.append(allocator, .{ .call = call, .links = links });
        return links;
    }
};
