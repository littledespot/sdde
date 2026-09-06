const std = @import("std");
/// Shared test composition, never a runtime asset or a required extra workflow.
pub fn yaml(allocator: std.mem.Allocator) ![]const u8 {
    const base = try @import("path_token_workflow.zig").prepared(allocator);
    defer allocator.free(base);
    const next = try std.mem.replaceOwned(u8, allocator, base, "use: build-superset-path-token-grammar@1, on: { ok: end.ok", "use: build-superset-path-token-grammar@1, on: { ok: scan-literals");
    defer allocator.free(next);
    return std.mem.concat(allocator, u8, &.{
        next,
        "  scan-literals: { use: scan-reference-passive-literals@1, on: { ok: assign-literals, failed: end.failed } }\n" ++
            "  assign-literals: { use: assign-passive-literal-identities@1, on: { ok: validate-literals, failed: end.failed } }\n" ++
            "  validate-literals: { use: validate-reference-passive-literals@1, on: { ok: end.ok, failed: end.failed } }\n",
    });
}
