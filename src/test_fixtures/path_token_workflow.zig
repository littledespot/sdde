const std = @import("std");

/// Compose the existing test setup graphs. This is never a runtime fallback or
/// a required user workflow; unit/native/package tests share the same fixture.
pub fn yaml(allocator: std.mem.Allocator) ![]const u8 {
    const base = try prepared(allocator);
    defer allocator.free(base);
    const resources = try std.mem.replaceOwned(u8, allocator, base, "start: toolchain", "resources: { sample: sample.txt }\nstart: toolchain");
    defer allocator.free(resources);
    const next = try std.mem.replaceOwned(u8, allocator, resources, "use: prepare-reference-tokens, on: { ok: end.ok", "use: prepare-reference-tokens, on: { ok: scan-tokens");
    defer allocator.free(next);
    return std.mem.concat(allocator, u8, &.{ next, "  scan-tokens: { use: scan-path-tokens, with: { text: sample }, on: { ok: end.ok, failed: end.failed } }\n" });
}

/// The toolchain, input, reference evidence and reference token stages with the separate naming-policy
/// step between the last two: every reference product a downstream step reads.
pub fn prepared(allocator: std.mem.Allocator) ![]const u8 {
    const reference = @embedFile("reference-ingestion.workflow.yaml");
    const toolchain = @embedFile("toolchain.workflow.yaml");
    const start = try std.mem.replaceOwned(u8, allocator, reference, "start: inputs", "start: toolchain");
    defer allocator.free(start);
    const next = try std.mem.replaceOwned(u8, allocator, start, "use: prepare-reference-evidence\n    on: { ok: end.ok, failed: end.failed }", "use: prepare-reference-evidence\n    on: { ok: compile-naming, failed: end.failed }");
    defer allocator.free(next);
    const steps = toolchain[(std.mem.indexOf(u8, toolchain, "steps:\n") orelse return error.InvalidFixture) + "steps:\n".len ..];
    const setup = try std.mem.replaceOwned(u8, allocator, steps, "ok: end.ok", "ok: inputs");
    defer allocator.free(setup);
    return std.mem.concat(allocator, u8, &.{
        next, "\n", setup, "\n",
        "  compile-naming: { use: compile-naming-policy, on: { ok: tokens, failed: end.failed } }\n" ++
            "  tokens: { use: prepare-reference-tokens, on: { ok: end.ok, failed: end.failed } }\n",
    });
}
