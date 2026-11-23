const std = @import("std");
const evidence = @import("../domain/actor_evidence.zig");

/// Parsing uses a caller-owned arena, including partial allocations on failure. A document that is not the registry's
/// closed contract is an `InvalidActorEvidence`; the parser decides nothing else about it.
pub const Parser = struct {
    parse_fn: *const fn (std.mem.Allocator, []const u8) evidence.Error!evidence.Registry,
    pub fn parse(self: Parser, allocator: std.mem.Allocator, bytes: []const u8) evidence.Error!evidence.Registry {
        return self.parse_fn(allocator, bytes);
    }
};
