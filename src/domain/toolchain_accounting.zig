const std = @import("std");
const toolchain = @import("toolchain.zig");

pub fn validateCaptureBudget(project: toolchain.Capture, presets: []const toolchain.Entry) toolchain.Error!void {
    if (project.bytes.len > toolchain.max_document_bytes or presets.len > toolchain.max_presets) {
        return error.InvalidToolchain;
    }
    var total: u64 = project.bytes.len;
    for (presets) |preset| {
        if (preset.size > toolchain.max_document_bytes) return error.InvalidToolchain;
        total = std.math.add(u64, total, preset.size) catch return error.InvalidToolchain;
        if (total > toolchain.max_total_bytes) return error.InvalidToolchain;
    }
}

test "capture budget includes project and every preset exactly once" {
    const one_mebibyte = try std.testing.allocator.alloc(u8, toolchain.max_document_bytes);
    defer std.testing.allocator.free(one_mebibyte);
    const project: toolchain.Capture = .{ .name = toolchain.project_filename, .bytes = one_mebibyte };
    var presets: [16]toolchain.Entry = undefined;
    for (&presets, 0..) |*preset, index| preset.* = .{
        .name = "preset",
        .size = toolchain.max_document_bytes,
        .identity = .{ .filesystem_id = 1, .file_id = index + 1 },
    };
    try validateCaptureBudget(project, presets[0..15]);
    try std.testing.expectError(error.InvalidToolchain, validateCaptureBudget(project, &presets));
}
