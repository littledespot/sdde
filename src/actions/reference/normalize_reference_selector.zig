const std = @import("std");
const selector = @import("../../domain/reference_selector.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    normalizer: unicode.Normalizer,
    pub const contract: pipeline.NodeContract = .{
        .id = "normalize-reference-selector@1",
        .kind = .action,
        .requires = &.{.specify_invocation},
        .produces = &.{.normalized_reference_selector},
        .side_effect = .none,
    };

    pub fn execute(self: Action, allocator: std.mem.Allocator, invocation: selector.Invocation) unicode.Error!selector.NormalizedCandidate {
        const nfc = try self.normalizer.nfc(allocator, invocation.raw_reference, selector.max_bytes);
        defer allocator.free(nfc);
        for (nfc) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        var normalized: std.Io.Writer.Allocating = .init(allocator);
        errdefer normalized.deinit();
        var components = std.mem.splitScalar(u8, nfc, '/');
        var first = true;
        while (components.next()) |component| {
            if (std.mem.eql(u8, component, ".")) continue;
            if (!first) normalized.writer.writeByte('/') catch return error.OutOfMemory;
            normalized.writer.writeAll(component) catch return error.OutOfMemory;
            first = false;
        }
        return .{ .bytes = normalized.toOwnedSlice() catch return error.OutOfMemory };
    }
};
