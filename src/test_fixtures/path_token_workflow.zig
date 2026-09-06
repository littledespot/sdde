const std = @import("std");

/// Compose the existing test setup graphs. This is never a runtime fallback or
/// a required user workflow; unit/native/package tests share the same fixture.
pub fn yaml(allocator: std.mem.Allocator) ![]const u8 {
    const base = try prepared(allocator);
    defer allocator.free(base);
    const resources = try std.mem.replaceOwned(u8, allocator, base, "start: capture-project", "resources: { sample: sample.txt }\nstart: capture-project");
    defer allocator.free(resources);
    const next = try std.mem.replaceOwned(u8, allocator, resources, "use: build-superset-path-token-grammar@1, on: { ok: end.ok", "use: build-superset-path-token-grammar@1, on: { ok: scan-tokens");
    defer allocator.free(next);
    return std.mem.concat(allocator, u8, &.{ next, "  scan-tokens: { use: scan-path-tokens@1, with: { text: sample }, on: { ok: end.ok, failed: end.failed } }\n" });
}

pub fn prepared(allocator: std.mem.Allocator) ![]const u8 {
    const reference = @embedFile("reference-ingestion.workflow.yaml");
    const toolchain = @embedFile("toolchain.workflow.yaml");
    const start = try std.mem.replaceOwned(u8, allocator, reference, "start: normalize-feature", "start: capture-project");
    defer allocator.free(start);
    const next = try std.mem.replaceOwned(u8, allocator, start, "use: validate-reference-chunks@1\n    on: { ok: end.ok, failed: end.failed }", "use: validate-reference-chunks@1\n    on: { ok: compile-naming, failed: end.failed }");
    defer allocator.free(next);
    const steps = toolchain[(std.mem.indexOf(u8, toolchain, "steps:\n") orelse return error.InvalidFixture) + "steps:\n".len ..];
    const setup = try std.mem.replaceOwned(u8, allocator, steps, "ok: end.ok", "ok: normalize-feature");
    defer allocator.free(setup);
    return std.mem.concat(allocator, u8, &.{
        next, "\n", setup, "\n",
        "  compile-naming: { use: compile-naming-policy@1, on: { ok: build-grammar, failed: end.failed } }\n" ++
            "  build-grammar: { use: build-superset-path-token-grammar@1, on: { ok: end.ok, failed: end.failed } }\n",
    });
}
