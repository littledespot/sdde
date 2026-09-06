const std = @import("std");
pub fn yaml(allocator: std.mem.Allocator) ![]const u8 {
    const base = try @import("reference_text_workflow.zig").yaml(allocator);
    defer allocator.free(base);
    const next = try std.mem.replaceOwned(u8, allocator, base, "use: validate-reference-passive-literals, on: { ok: end.ok", "use: validate-reference-passive-literals, on: { ok: extract-facts");
    defer allocator.free(next);
    return std.mem.concat(allocator, u8, &.{
        next,
        "  extract-facts: { use: extract-structured-reference-facts, on: { ok: identify-candidates, failed: end.failed } }\n" ++
            "  identify-candidates: { use: assign-structured-token-candidate-identities, on: { ok: end.ok, failed: end.failed } }\n",
    });
}
