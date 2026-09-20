//! Diagnostic source identities. Structural selectors survive YAML formatting;
//! source bytes are observations, never executable workflow authority.
const std = @import("std");
pub const Entry = struct {
    subgraph: ?[]const u8,
    id: []const u8,
    kind: enum { operation, subgraph },
    target: []const u8,
    declaration: []const u8,
};
pub const Document = struct { path: []const u8, content: []const u8 };

pub fn cloneChain(a: std.mem.Allocator, source: []const Entry) std.mem.Allocator.Error![]const Entry {
    const result = try a.dupe(Entry, source);
    for (result) |*entry| {
        if (entry.subgraph) |scope| entry.subgraph = try a.dupe(u8, scope);
        entry.id = try a.dupe(u8, entry.id);
        entry.target = try a.dupe(u8, entry.target);
        entry.declaration = try a.dupe(u8, entry.declaration);
    }
    return result;
}
pub fn sameChain(a: []const Entry, b: []const Entry) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if ((left.subgraph == null) != (right.subgraph == null)) return false;
        if (left.subgraph) |scope| if (!std.mem.eql(u8, scope, right.subgraph.?)) return false;
        if (left.kind != right.kind or !std.mem.eql(u8, left.id, right.id) or !std.mem.eql(u8, left.target, right.target) or !std.mem.eql(u8, left.declaration, right.declaration)) return false;
    }
    return true;
}
