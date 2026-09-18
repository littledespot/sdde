const std = @import("std");
const r = @import("../domain/principle_registry.zig");
const policy = @import("../domain/principle_policy.zig");
pub const selection: policy.Row = .{ .stage = .spec, .environment = null, .fileKind = null, .categories = &.{ .core, .custom } };
pub fn registry(a: std.mem.Allocator, prose: ?[]const u8) !r.Registry {
    const count: usize = if (prose != null) 2 else 1;
    const entries = try a.alloc(r.Entry, count);
    if (prose) |bytes| entries[0] = .{ .kind = .semantic_markdown, .descriptor = .{ .path = "core.md", .raw_path = "core.md", .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = 2 }, .size = bytes.len, .modified_ns = 0, .changed_ns = 0 } } } };
    entries[count - 1] = .{ .kind = .mechanical_toolchain_layer_excluded, .descriptor = .{ .path = "toolchain.yaml", .raw_path = "toolchain.yaml", .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = 3 }, .size = 20, .modified_ns = 0, .changed_ns = 0 } } } };
    const captures = try a.alloc(r.Capture, if (prose != null) 1 else 0);
    if (prose) |bytes| captures[0] = .{ .entry = 1, .bytes = bytes };
    return r.build(a, .{ .inventory = .{ .root = .{ .path = "principles", .identity = .{ .filesystem_id = 1, .file_id = 1 } }, .entries = entries, .source_bytes = if (prose) |bytes| bytes.len else 0 }, .sources = captures }, .{ .hints = &.{.{ .basename = "core.md", .category = .core }}, .selections = &.{selection} }, null);
}
pub fn emptyAssessment(a: std.mem.Allocator, inputs: @import("../domain/required_authority.zig").Inputs) !@import("../domain/principle_assessment.zig").Canonical {
    const policy_registry = try registry(a, null);
    const assessment = @import("../domain/principle_assessment.zig");
    return assessment.canonical(a, try assessment.project(a, .{ .business = try assessment.businessInput(a, inputs), .registry = policy_registry, .selection = try r.select(a, policy_registry, .{ .stage = .spec, .environment = null, .fileKind = null }) }));
}
